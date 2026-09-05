# Recipe — Daemon / Long-Running Process CLI

Shape: the CLI starts a long-running background process (a daemon) that owns sockets, ports, watchdog timers, and possibly shared memory. Examples: `wrangler dev`, `ntm`, `mcp-agent-mail`, `wezterm mux`, `ghostty` server, language servers, `lsp-bridge`, dev-server commands.

---

## The dual-life problem

A daemon CLI has two life states:

- **Daemon-running.** Sockets open, port bound, watchdog ticking, shared memory mapped.
- **Daemon-stopped.** State files at rest; lock files possibly stale; sockets/pipes possibly orphaned.

The doctor must distinguish these and behave correctly for each. Mutating the workspace while the daemon is alive is a guaranteed corruption path.

---

## The `--running` axis

Add a third axis to the CLI surface (alongside `--fix` and `--online`):

```text
<tool> doctor                        # Auto-detect; refuse to --fix while running.
<tool> doctor --running              # Probe the live daemon; report its state.
<tool> doctor --offline-only         # Force-treat as if daemon-stopped (CI mode).
<tool> doctor --strict-isolation     # On --fix, refuse if daemon is alive.
```

The detector layer probes daemon liveness via:

1. **Pidfile check.** Read `<state-dir>/<tool>.pid`; if PID is alive (`kill -0 $pid`), daemon is running.
2. **Socket check (offline).** `connect()` to the daemon's Unix socket with a 100ms timeout. Connect-success = daemon alive. Connect-refused = stopped. Connect-timeout = wedged.
3. **Port check (offline).** If daemon binds a TCP port locally, `connect()` to `127.0.0.1:<port>` (still offline; loopback isn't network).

If the daemon is alive, `--fix` refuses by default with exit 4 and a finding suggesting `<tool> stop && <tool> doctor --fix && <tool> start`. The user can override with `--force` (requires `--yes`) — but the override is documented narrowly; most fixers refuse even with `--force`.

---

## Failure-mode classes specific to daemons

### `daemon_state` subsystem

```
fm-daemon-state-pidfile-stale
  detector: read pidfile; if PID is dead, P1.
  fixer: quarantine the pidfile (mutate via Op::Rename).

fm-daemon-state-pidfile-pid-mismatch
  detector: pidfile says PID 1234; process 1234 is alive but is a different
            program (check /proc/<pid>/cmdline). P0.
  fixer: refuse — could be PID reuse; user investigates.

fm-daemon-state-pidfile-pid-belongs-to-other-tool
  detector: pidfile PID belongs to <tool> but a different version (check
            /proc/<pid>/exe). P1.
  fixer: refuse — ambiguous; manual remediation.

fm-daemon-state-socket-orphaned
  detector: socket file exists; connect() fails with ENOENT/ECONNREFUSED.
            P1.
  fixer: quarantine the socket file via mutate.

fm-daemon-state-socket-wedged
  detector: connect() succeeds but no protocol response within 1s. P0.
  fixer: refuse — daemon may be doing legitimate slow work; user investigates
         (or runs `<tool> kill` then doctor again).

fm-daemon-state-watchdog-stalled
  detector: shared memory shows last watchdog tick > 30s ago, daemon claims
            running. P0.
  fixer: refuse — likely deadlock; manual `<tool> kill` then `<tool> start`.

fm-daemon-state-port-conflict
  detector: pidfile shows daemon should be on port N; port N is bound by
            a different PID. P0.
  fixer: refuse — port-conflict resolution is the user's call.
```

### `shared_memory` subsystem (when applicable)

```
fm-shared-memory-orphaned-segment
  detector: shmat probes; if a segment exists with our key but no daemon
            owner, P2.
  fixer: detect-only — shmctl rm requires elevated privileges and is too
         destructive for the doctor to do automatically. Manual remediation:
         `ipcrm shm <key>`.
```

---

## Live-state reading detectors (`--running` mode)

When the daemon IS alive, the doctor can ask it questions via the protocol:

```rust
// pseudocode
fn detect_live_daemon_health(repo: &Path, args: &Args) -> Option<Finding> {
    if !args.running { return None; }
    let socket = repo.join(".<tool>/socket");
    let mut stream = std::os::unix::net::UnixStream::connect(&socket).ok()?;
    stream.set_read_timeout(Some(Duration::from_secs(1))).ok()?;
    write_json_request(&mut stream, json!({"command": "health"}));
    let response: Value = read_json_response(&mut stream)?;
    if response.get("status").and_then(|s| s.as_str()) != Some("healthy") {
        return Some(Finding {
            id: "fm-daemon-live-unhealthy",
            severity: "P0",
            evidence: response,
            ...
        });
    }
    None
}
```

The protocol detector reads from the daemon, never writes. Live-state mutation requires explicit user-issued daemon commands (`<tool> reload`, `<tool> restart`); the doctor never reaches into the daemon's process.

---

## Streaming health (`watch`)

For continuous-monitoring use cases (CI dashboards, on-call):

```text
<tool> doctor health --watch
```

Emits NDJSON one event per second to stdout. Each event has the same schema as `<tool> doctor health` output. The agent / dashboard consumes the stream until ctrl-C.

```jsonc
{"ts":"2026-05-06T14:23:07Z","status":"ok","findings":0,"daemon_alive":true,"watchdog_age_ms":143}
{"ts":"2026-05-06T14:23:08Z","status":"ok","findings":0,"daemon_alive":true,"watchdog_age_ms":1142}
{"ts":"2026-05-06T14:23:09Z","status":"warn","findings":1,"daemon_alive":true,"watchdog_age_ms":2143}
```

`--watch` honors `--online`, `--no-color`, etc. Per Axiom 8, output is one JSON-line per row, no headers.

---

## Concurrency: doctor + daemon coexistence

The doctor's lock (`.doctor/.doctor.lock`) is **distinct** from the daemon's lock (`.<tool>/<tool>.pid` or similar). Both locks serialize against themselves:

- Two doctors: one wins via `.doctor.lock`, the other refuses with exit 5.
- Two daemons: project's existing daemon-spawn code already handles this.
- Doctor + daemon: the doctor reads the daemon's pidfile to detect liveness, but doesn't try to acquire the daemon's lock. They're independent.

The exception: `<tool> doctor --fix --strict-isolation` refuses if the daemon is alive (detected via pidfile + socket connect). The user runs `<tool> stop`, then doctor, then `<tool> start`.

---

## Common pitfalls

- **`kill -9` from inside the doctor.** Never. The doctor never signals other processes. If a daemon is wedged, the doctor describes it; the user (or a separate `<tool> kill` command) sends the signal.
- **Reading the daemon's state file while it's writing.** Read-snapshots via the protocol (`<tool> dump-state` over the socket), not direct file reads. If the protocol is unavailable, the detector emits `findings_only_running` to indicate it's degraded.
- **Doctor's atomic-write tempfile lands in a directory the daemon also writes to.** The daemon's writer races with the doctor's rename. Solution: doctor's tempfile lives in a *subdirectory* of the daemon's state dir that the daemon never touches (e.g., `.<tool>/state/.doctor.tmp.<pid>`).
- **Socket-permission drift.** `chmod 0700 ~/.<tool>/socket` (private to user). The doctor checks; if mode is more permissive, P1 fixer chmods via mutate.
- **Long-running `--watch` leaks fds on ctrl-C.** Wrap `--watch` in signal handlers; close socket cleanly. If the doctor's own cleanup leaves orphaned fds, that's a P1 finding for the doctor itself.
