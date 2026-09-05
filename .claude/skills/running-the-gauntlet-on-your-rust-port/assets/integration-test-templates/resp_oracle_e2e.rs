//! resp_oracle_e2e.rs — paste-ready RESP-class oracle test template.
//!
//! Copy into `crates/<port>-e2e/tests/<command_family>_oracle_e2e.rs`.

use std::process::{Child, Command, Stdio};
use std::time::Duration;

const SUBJECT_IDENTITY_LABEL: &str = "<port>";        // e.g. "frankenredis"
const REFERENCE_IDENTITY_LABEL: &str = "redis-oracle";

/// Drive a RESP transcript through both engines (reference redis-server + the
/// port's binary) on distinct ports; assert byte-identical wire output (after
/// canonicalization of RESP3 unordered collections).
fn scenario(transcript: &str, label: &str) {
    assert_ne!(SUBJECT_IDENTITY_LABEL, REFERENCE_IDENTITY_LABEL,
        "EngineIdentity self-comparison violation");

    let ref_port = 16379_u16;
    let port_port = 16380_u16;

    // Start reference redis-server (assumes pinned version on PATH).
    let mut ref_srv = Command::new("redis-server")
        .args(&[
            "--port", &ref_port.to_string(),
            "--bind", "127.0.0.1",
            "--daemonize", "no",
            "--save", "",
            "--appendonly", "no",
            "--logfile", "",
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn reference redis-server");

    let mut port_srv = Command::new(std::env::var("PORT_BIN").unwrap_or_else(|_|
        "target/release-perf/franken-redis-server".into()))
        .args(&["--port", &port_port.to_string(), "--bind", "127.0.0.1"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn port redis-server");

    std::thread::sleep(Duration::from_secs(1));

    let ref_out = drive_transcript(ref_port, transcript);
    let port_out = drive_transcript(port_port, transcript);

    let _ = ref_srv.kill();
    let _ = port_srv.kill();

    let ref_canon = canonicalize_resp(&ref_out);
    let port_canon = canonicalize_resp(&port_out);

    assert_eq!(ref_canon, port_canon,
        "{label}: RESP divergence after canonicalization\n  ref:  {ref_canon}\n  port: {port_canon}");
}

fn drive_transcript(port: u16, transcript: &str) -> Vec<u8> {
    use std::io::{Read, Write};
    use std::net::TcpStream;
    let mut s = TcpStream::connect(("127.0.0.1", port)).expect("connect");
    s.write_all(transcript.as_bytes()).expect("write");
    s.set_read_timeout(Some(Duration::from_secs(3))).ok();
    let mut buf = Vec::new();
    let _ = s.read_to_end(&mut buf);
    buf
}

/// Canonicalize RESP output: parse RESP3, sort Sets, sort Map keys, keep
/// Lists/Arrays/Streams ordered.
fn canonicalize_resp(raw: &[u8]) -> String {
    // ... per pattern:35-NORMALIZED-VALUE (RespValue 14-variant comparator) ...
    // Stub for the template; the port-side implementation lives in
    // crates/<port>-harness/src/resp_canonicalizer.rs.
    String::from_utf8_lossy(raw).into()
}

// ===== Per-command-family tests — fill these in =====

#[test]
fn get_set_basic() {
    scenario(
        "*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$3\r\nbar\r\n*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n",
        "get_set_basic",
    );
}

#[test]
fn hash_unordered_sets() {
    scenario(
        "*4\r\n$4\r\nHSET\r\n$1\r\nh\r\n$1\r\na\r\n$1\r\n1\r\n*4\r\n$4\r\nHSET\r\n$1\r\nh\r\n$1\r\nb\r\n$1\r\n2\r\n*2\r\n$5\r\nHKEYS\r\n$1\r\nh\r\n",
        "hash_unordered_sets",
    );
}
