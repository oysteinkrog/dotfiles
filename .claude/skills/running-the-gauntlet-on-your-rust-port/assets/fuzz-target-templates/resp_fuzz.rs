//! resp_fuzz.rs — paste-ready RESP-class differential-fuzz target.
//!
//! Copy into `fuzz/fuzz_targets/fuzz_resp_oracle.rs` after running
//!   `cargo +nightly fuzz init`
//!   `cargo +nightly fuzz add fuzz_resp_oracle`
//!
//! fuzz/Cargo.toml dependencies:
//!   libfuzzer-sys = "0.4"
//!   arbitrary     = { version = "1", features = ["derive"] }
//!   <your-port>   = { path = "../" }
//!
//! Vendored reference: `vendor/redis-7.2.4-bin/redis-server` (per
//! ORACLE-TOOLCHAIN §6) running on a per-input UNIX socket.
//!
//! Pairs with: assets/integration-test-templates/resp_oracle_e2e.rs.

#![no_main]

use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;

// ===== Structure-aware input — narrow to a valid RESP command sequence =====
//
// Generated commands stay within a small command vocabulary so the fuzzer
// spends its energy on semantic edges (TTL races, type collisions, integer
// overflow) rather than RESP-frame parsing (which is exercised by the
// `fuzz_resp_parser` raw-byte target, not here).

#[derive(Arbitrary, Debug, Clone)]
pub struct DiffScript {
    pub commands: Vec<Cmd>,
}

#[derive(Arbitrary, Debug, Clone)]
pub enum Cmd {
    Set     { key: KeyIdx, value: Vec<u8> },
    Get     { key: KeyIdx },
    Del     { key: KeyIdx },
    Exists  { key: KeyIdx },
    Incr    { key: KeyIdx },
    Decr    { key: KeyIdx },
    Append  { key: KeyIdx, value: Vec<u8> },
    Strlen  { key: KeyIdx },
    Expire  { key: KeyIdx, seconds: u8 },
    LPush   { key: KeyIdx, value: Vec<u8> },
    RPush   { key: KeyIdx, value: Vec<u8> },
    LRange  { key: KeyIdx, start: i8, stop: i8 },
    LLen    { key: KeyIdx },
    SAdd    { key: KeyIdx, member: Vec<u8> },
    SMembers{ key: KeyIdx },
    SCard   { key: KeyIdx },
    HSet    { key: KeyIdx, field: Vec<u8>, value: Vec<u8> },
    HGet    { key: KeyIdx, field: Vec<u8> },
    HDel    { key: KeyIdx, field: Vec<u8> },
}

/// Key namespace bounded to 8 keys so collisions are likely and
/// type-confusion (WRONGTYPE) edges actually get exercised.
#[derive(Arbitrary, Debug, Clone, Copy)]
pub struct KeyIdx(pub u8);

impl KeyIdx {
    fn render(&self) -> String { format!("k{}", self.0 % 8) }
}

// ===== Differential driver =====
//
// Both engines start fresh per fuzz iteration. The reference is a
// vendored `redis-server` spawned on a fresh UNIX socket; the subject is
// the port. Any RESP-value-tree divergence (per the collection-semantics
// comparator from ORACLE-TOOLCHAIN §6) is a bug.

fuzz_target!(|script: DiffScript| {
    // EngineIdentity guard: subject != oracle (asserted at harness setup,
    // not per-call — see ORACLE-TOOLCHAIN §4).

    // Bound the input size so libfuzzer doesn't generate million-command
    // sequences that timeout. Tune per workload.
    if script.commands.len() > 64 { return; }

    let mut subject = match SubjectClient::spawn() { Ok(c) => c, Err(_) => return };
    let mut reference = match ReferenceClient::spawn() { Ok(c) => c, Err(_) => return };

    for cmd in &script.commands {
        let args = render_cmd(cmd);
        let sub_resp = subject.send(&args);
        let ref_resp = reference.send(&args);
        if !resp_equal(&sub_resp, &ref_resp) {
            // PANIC: libfuzzer saves the input as a crash.
            // Triage via the mismatch-minimizer in ORACLE-TOOLCHAIN §12.
            panic!(
                "DIFFERENTIAL DIVERGENCE\n  cmd: {args:?}\n  subject: {sub_resp:?}\n  reference: {ref_resp:?}"
            );
        }
    }
});

fn render_cmd(c: &Cmd) -> Vec<Vec<u8>> {
    use Cmd::*;
    let s = |x: &str| x.as_bytes().to_vec();
    let k = |k: &KeyIdx| k.render().into_bytes();
    let bound = |v: &Vec<u8>| v.iter().take(64).copied().collect();
    match c {
        Set { key, value }              => vec![s("SET"),    k(key), bound(value)],
        Get { key }                     => vec![s("GET"),    k(key)],
        Del { key }                     => vec![s("DEL"),    k(key)],
        Exists { key }                  => vec![s("EXISTS"), k(key)],
        Incr { key }                    => vec![s("INCR"),   k(key)],
        Decr { key }                    => vec![s("DECR"),   k(key)],
        Append { key, value }           => vec![s("APPEND"), k(key), bound(value)],
        Strlen { key }                  => vec![s("STRLEN"), k(key)],
        Expire { key, seconds }         => vec![s("EXPIRE"), k(key), seconds.to_string().into_bytes()],
        LPush { key, value }            => vec![s("LPUSH"),  k(key), bound(value)],
        RPush { key, value }            => vec![s("RPUSH"),  k(key), bound(value)],
        LRange { key, start, stop }     => vec![s("LRANGE"), k(key), start.to_string().into_bytes(), stop.to_string().into_bytes()],
        LLen { key }                    => vec![s("LLEN"),   k(key)],
        SAdd { key, member }            => vec![s("SADD"),   k(key), bound(member)],
        SMembers { key }                => vec![s("SMEMBERS"), k(key)],
        SCard { key }                   => vec![s("SCARD"),  k(key)],
        HSet { key, field, value }      => vec![s("HSET"),   k(key), bound(field), bound(value)],
        HGet { key, field }             => vec![s("HGET"),   k(key), bound(field)],
        HDel { key, field }             => vec![s("HDEL"),   k(key), bound(field)],
    }
}

// ===== Stub clients & comparator =====
//
// In a real port, replace these with the actual subject + vendored-redis
// subprocess client; the collection-semantics-aware `resp_equal` is the
// 14-variant comparator from ORACLE-TOOLCHAIN §6.

#[derive(Debug, Clone)]
pub enum RespValue {
    SimpleString(Vec<u8>),
    Error(Vec<u8>),
    Integer(i64),
    BulkString(Option<Vec<u8>>),
    Array(Option<Vec<RespValue>>),
    Null,
    Boolean(bool),
    Double(f64),
    Map(Vec<(RespValue, RespValue)>),
    Set(Vec<RespValue>),
}

fn resp_equal(a: &RespValue, b: &RespValue) -> bool {
    use RespValue::*;
    match (a, b) {
        (Set(x), Set(y)) => {
            let mut xs: Vec<&RespValue> = x.iter().collect();
            let mut ys: Vec<&RespValue> = y.iter().collect();
            xs.sort_by_key(|v| format!("{v:?}"));
            ys.sort_by_key(|v| format!("{v:?}"));
            xs.len() == ys.len() && xs.iter().zip(ys.iter()).all(|(p, q)| resp_equal(p, q))
        }
        // Maps unordered; Arrays ordered; both-error = agreement (regardless of message).
        (Error(_), Error(_)) => true,
        (Double(x), Double(y)) => (x - y).abs() < 1e-12,
        // Fallback: structural equality via Debug (stub).
        _ => format!("{a:?}") == format!("{b:?}"),
    }
}

struct SubjectClient;
impl SubjectClient {
    fn spawn() -> Result<Self, ()> { Ok(Self) }
    fn send(&mut self, _args: &[Vec<u8>]) -> RespValue { RespValue::Null }
}

struct ReferenceClient;
impl ReferenceClient {
    fn spawn() -> Result<Self, ()> { Ok(Self) }
    fn send(&mut self, _args: &[Vec<u8>]) -> RespValue { RespValue::Null }
}
