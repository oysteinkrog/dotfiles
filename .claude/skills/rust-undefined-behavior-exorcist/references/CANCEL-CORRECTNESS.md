# Cancel Correctness — Concurrency Soundness As A Peer UB Lane To Memory UB

Some projects (notably `asupersync`) treat cancel-correctness as a memory-safety-grade obligation: any blocking-syscall boundary that lacks `cx: &Cx` is logged as CRITICAL.

This file documents the cancel-correctness lane and how the skill audits it.

Anchor: cass Q-103 — asupersync SOCKS5 connector lacked `cx`, was uncancellable. Fixed by threading `cx: &Cx` through all 12 public HttpClient methods + 5 `check_cx(cx)?` calls at DNS / connect / TLS / redirect / proxy boundaries.

---

## What is cancel-correctness?

A function is **cancel-correct** if, given a cancellation signal `Cx`, it stops doing work and returns `Cancelled` within a bounded time (typically the syscall granularity, ~milliseconds).

A function is **cancel-incorrect** if cancellation has no effect — the function continues to completion or blocks indefinitely on a syscall.

Why this matters for UB exorcism: in a structured-concurrency runtime, a leaked / uncancellable task is the equivalent of a memory leak — resources (FDs, sockets, allocations) live longer than the task's logical scope, breaking the runtime's invariants. The user's vocabulary treats this as a soundness violation.

---

## The cancel-correctness checklist

Every `pub fn` (or `pub async fn`) that performs at least one blocking operation must:

- [ ] Take `cx: &Cx` (or equivalent cancellation token) as a parameter
- [ ] Call `check_cx(cx)?` (or equivalent) at every blocking-syscall boundary:
  - DNS resolution
  - TCP connect
  - TLS handshake
  - HTTP redirect (each hop)
  - Proxy connect (each layer)
  - File open / read / write
  - mmap / munmap
  - Process spawn / wait
  - Lock acquisition (if long-blocking)
  - sleep / time wait
- [ ] Document the cancellation semantics in rustdoc
- [ ] Return `Err(ClientError::Cancelled)` (or equivalent) cleanly — don't `panic!`, don't leak

---

## Audit pattern

In Phase 2 (static sweep), the audit runs:

```bash
# Step 1: Find every pub fn that performs blocking syscalls
ast-grep -p 'pub fn $NAME($$$) { $$$ TcpStream::connect $$$ }'
ast-grep -p 'pub fn $NAME($$$) { $$$ std::fs::File::open $$$ }'
# ... etc for each blocking primitive

# Step 2: For each, check if it takes a cx parameter
ast-grep -p 'pub fn $NAME($$$, cx: &Cx, $$$) { $$$ }'
# Diff the two sets → functions that block but don't take cx
```

Any `pub fn` that blocks without `cx` is `LIKELY-UB` in cancel-correctness terms.

---

## The remediation pattern

Mined verbatim from Q-103. Before:

```rust
pub fn connect_via_socks5(&self, addr: SocketAddr) -> io::Result<Conn> {
    let proxy_conn = TcpStream::connect(self.proxy)?;
    perform_socks5_handshake(&proxy_conn, addr)?;
    Ok(Conn::new(proxy_conn))
}
```

After:

```rust
pub fn connect_via_socks5(&self, cx: &Cx, addr: SocketAddr) -> Result<Conn, ClientError> {
    check_cx(cx)?;                                    // pre-DNS
    let proxy_addr = resolve_dns(self.proxy, cx)?;    // DNS itself is async; takes cx
    check_cx(cx)?;                                    // pre-connect
    let proxy_conn = tcp_connect(proxy_addr, cx)?;    // connect takes cx
    check_cx(cx)?;                                    // pre-handshake
    perform_socks5_handshake(&proxy_conn, addr, cx)?; // handshake takes cx
    check_cx(cx)?;                                    // post-handshake
    Ok(Conn::new(proxy_conn))
}
```

Every syscall boundary has a `check_cx(cx)?`. The `?` operator short-circuits to `ClientError::Cancelled` if the Cx is set.

---

## The 12-method sweep

For HttpClient specifically (Q-103), all 12 public methods needed `cx`:

| Method | Blocking surface |
|---|---|
| `get` | DNS, connect, TLS, redirect |
| `post` | DNS, connect, TLS, redirect, body write |
| `put` | same as post |
| `delete` | same as get |
| `head` | same as get |
| `patch` | same as post |
| `request` | depends on Method |
| `connect_via_proxy` | DNS, connect (×2 for proxy + target) |
| `connect_via_socks5` | DNS, connect, SOCKS5 handshake |
| `set_proxy` | none (config; cx unnecessary) — but added for consistency |
| `set_timeout` | none |
| `inner` | none |

The 12-method audit is the **shape-sweep** of the cancel-correctness lane — find one missing `cx`, sweep the whole `pub fn` surface.

---

## The `check_cx` helper

```rust
fn check_cx(cx: &Cx) -> Result<(), ClientError> {
    if cx.is_cancelled() {
        Err(ClientError::Cancelled)
    } else {
        Ok(())
    }
}
```

Cheap (one atomic load). Call before every blocking syscall, no exceptions.

---

## Cancel-correctness vs async drop

Cancel-correctness applies to *functions*. [UB-TAXONOMY.md §17 Async drop hazards](UB-TAXONOMY.md) applies to *types*. They compose:

- Cancel-correctness: `pub fn foo(cx: &Cx, ...) -> Result<...>` aborts on cancellation
- Async drop: `impl Drop for ConnHandle` doesn't block (doesn't call `block_on`)

A connection's lifecycle uses both:
1. `connect(cx, ...)` is cancel-correct → returns either a `Conn` or `Cancelled`
2. `Conn::Drop` doesn't block → closes the FD synchronously, releases other resources via deferred channels

---

## CI integration

Phase 12 `UB_RUNBOOK.md` can include a cancel-correctness CI job using the
shipped `scripts/cancel-correctness-audit.sh` (covers ~20 blocking primitives;
the `--cx-type` flag points it at the project's actual cancellation handle
type):

```yaml
cancel-correctness:
  steps:
    - run: |
        scripts/cancel-correctness-audit.sh src/ --cx-type Cx > /tmp/cancel-audit.txt
        # Violation lines have a unique `// contains: <primitive>` suffix.
        # Framing/heading lines never include that substring.
        if grep -q ' // contains: ' /tmp/cancel-audit.txt; then
          echo "::error::Cancel-correctness violation:"
          cat /tmp/cancel-audit.txt
          exit 1
        fi
```

Override `--cx-type` if the project's cancellation handle isn't called `Cx`
(common alternatives: `CancelToken`, `ShutdownSignal`).  Add `--output <file>`
to also persist the report to the audit workspace.

---

## When cancel-correctness is NOT a UB lane

Some projects don't have structured concurrency:
- Synchronous CLI tools where `Ctrl-C` aborts the process unceremoniously
- Stateless web handlers where each request is its own short-lived context
- `sync` Rust code (non-async) where the OS thread is the cancellation unit

For these, cancel-correctness is a feature request, not a soundness obligation.

The skill's Phase 0 partition reads the project's archetype + the presence of a `Cx` type. If absent, this lane is a no-op.

---

## Tooling proposal

`scripts/cancel-correctness-audit.sh`:

```bash
#!/usr/bin/env bash
# Find pub fn signatures with blocking calls but no cx parameter.
set -euo pipefail
SOURCE="${1:?source dir required}"
ast-grep -p 'pub fn $NAME($$$) -> $RET { $$$ TcpStream::connect $$$ }' "$SOURCE" \
  | grep -v 'cx: &Cx' \
  > /tmp/blocking-no-cx.txt
# ... repeat for each blocking primitive ...
echo "Cancel-correctness candidates:"
cat /tmp/blocking-no-cx.txt
```

---

## Cross-references

- cass Q-103 — verbatim source
- [HIDDEN-BARRIERS.md §HB-3](HIDDEN-BARRIERS.md#hb-3-missing-cx-cx-on-a-sync-syscall-function) — pattern catalog entry
- [UB-TAXONOMY.md §17 Async drop hazards](UB-TAXONOMY.md) — adjacent concern
- [PROJECT-TYPES.md §P6 Async runtime](PROJECT-TYPES.md) — archetype priors
