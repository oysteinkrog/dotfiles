# Threat Model

[SECURITY.md](SECURITY.md) names three risk classes informally. This file applies a STRIDE-style structured threat model. Use during quarterly security audits and before any release that bumps `doctor_contract_version`.

STRIDE: **S**poofing, **T**ampering, **R**epudiation, **I**nformation disclosure, **D**enial of service, **E**levation of privilege.

---

## Threat catalog

### Spoofing

| Threat | Vector | Mitigation | Test |
|--------|--------|------------|------|
| Forged actions.jsonl line | Malicious local user crafts an `actions.jsonl` line with `before_hash` matching their planted backup | Strict undo verifies `before_hash == sha256(live_file)` AND backup must exist AND backup's hash must match | [ADVERSARIAL-REVIEW.md § B.1](ADVERSARIAL-REVIEW.md) |
| Forged trust-anchor signature | Attacker compromises bundled signing key | Trust anchor is bundled at build time; key rotation policy in OPS-RUNBOOK | Build-time signature verification |
| Spoofed tool version | Attacker swaps `<tool>` binary mid-session | Doctor's per-run record captures `tool_version`; mismatch surfaces as a finding | Drift detection on `version_changed` |

### Tampering

| Threat | Vector | Mitigation | Test |
|--------|--------|------------|------|
| Live file mutated between detect and fix (TOCTOU) | Concurrent agent edits | `mutate()` re-reads live file IMMEDIATELY before backup; before_hash captures the read state | [ADVERSARIAL-REVIEW.md § A.3](ADVERSARIAL-REVIEW.md) |
| Backup tampered with after backup write | Attacker modifies `<run-dir>/backups/` files | Backup mode 0400; run-dir mode 0500 after run; backup's hash recorded in `actions.jsonl` (immutable) | mode-check on undo |
| Trust manifest swapped | Build-time injection | Trust anchor public key bundled with manifest; both signed | (build-time defense) |
| Symlink in `write_scopes` resolved to escape scope | Planted `.beads/inner -> /etc/passwd` | `mutate()` canonicalizes path before scope check | [ADVERSARIAL-REVIEW.md § A.1](ADVERSARIAL-REVIEW.md) |
| Doctor's own source code tampered with | Attacker patches `mutate()` | Outside doctor's threat model; defense at build/release layer | (build-time defense) |

### Repudiation

| Threat | Vector | Mitigation | Test |
|--------|--------|------------|------|
| User claims doctor mutated something it didn't | Disputed change | `actions.jsonl` is the audit trail; before/after hashes for every mutation | Inspect actions.jsonl |
| Agent claims a finding wasn't surfaced | Disputed missing finding | `report.json` is per-run snapshot; `--explain` expands evidence | Replay via report.json |
| Runtime panic with no postmortem | Unrecoverable crash | Stderr captured to `<run-dir>/stderr.log`; panics caught at runtime; surfaced as `panics_caught` metric | Test panic path |

### Information disclosure

| Threat | Vector | Mitigation | Test |
|--------|--------|------------|------|
| Credentials leaked into `report.json` | Finding evidence captures raw bytes | `redact_secrets()` regex set on JSON serializer; bypass for backups (which are byte-identical by design but mode 0400 inside chmod 0500 dir) | Token-corpus regression test |
| Credentials leaked into `actions.jsonl` | Operation captures content | Only `path`, `op`, hashes recorded — never content | Schema audit |
| Credentials leaked via stderr log | Diagnostic output captures content | Log redaction also in stderr writer | Token-corpus regression test |
| Credentials leaked via `--explain` | Expanded evidence reads file content | Explain only emits hashes + structured paths; never reads file content for evidence | Audit `--explain` code path |
| Backups committed to git | `.doctor/` not in `.gitignore` | Doctor adds `.doctor/` on first run via `mutate()` | Pre-commit hook checks |
| Run-id reveals timing patterns | Attacker correlates run-ids to user activity | Run-id is `sha256(target_sha + iso8601_seconds)[:6]`; irreversibly hashed | (info leakage minimal) |

### Denial of service

| Threat | Vector | Mitigation | Test |
|--------|--------|------------|------|
| Disk-fill via repeated runs | Attacker triggers many `--fix` invocations | Each run stays in its own dir; `gc` removes old runs (operator-initiated) | Disk pressure test |
| Slow detector wedges health budget | Attacker plants pathological state | Health budget < 200ms enforced; per-detector timeout 1s; over-budget detector skipped with finding | Timing test |
| Pathologically deep symlink chain | ELOOP errors | Linux kernel limit (40) catches; doctor handles ELOOP gracefully | Symlink-chain test |
| Pathologically large state file | Detector tries to read 10GB | Detector reads via streaming; stat-only checks for size > N | Size-bound test |
| Lock starvation | Attacker holds lock indefinitely | Lock TTL (5 min default); `force_release` only with explicit user authorization | Lock-TTL test |
| Concurrent doctor flood | N agents try `--fix` simultaneously | Lock serializes; only one wins per second | [ADVERSARIAL-REVIEW.md § C.1](ADVERSARIAL-REVIEW.md) |

### Elevation of privilege

| Threat | Vector | Mitigation | Test |
|--------|--------|------------|------|
| Doctor escalates to root via setuid | (Out of scope; doctors are not setuid) | N/A | N/A |
| Doctor's `--fix` causes unintended state change in privileged area | `write_scopes` includes `/etc/` | `write_scopes` MUST NOT include root-owned paths | Scope audit |
| Path-traversal via `--only` | `--only "../../etc/passwd"` | Argument parser refuses non-`fm-…` IDs; runtime no-op for unknown IDs | [ADVERSARIAL-REVIEW.md § A.2](ADVERSARIAL-REVIEW.md) |
| Op-injection via Op enum | Custom Op variant smuggled in | Op enum closed; `mutate()` exhaustive match | Enum coverage |
| `--force` bypasses lock | `--force` flag implementation | `--force` requires `--yes` AND specific documented exception | [ADVERSARIAL-REVIEW.md § F.3](ADVERSARIAL-REVIEW.md) |

---

## Per-pattern threat differences

| Pattern | Most-relevant STRIDE | Notes |
|---------|----------------------|-------|
| 4 (daemon) | DoS (port flooding); Spoofing (PID reuse) | Daemon-specific in [recipes/daemon-cli.md](../recipes/daemon-cli.md) |
| 5/11 (installer) | Tampering (binary swap); Spoofing (forged signature) | Heaviest STRIDE surface; trust anchor is the root |
| 9 (distributed) | Information disclosure (credentials in vendor calls); Spoofing (vendor MITM) | TLS is project's responsibility; doctor inherits it |
| 13 (forensic) | Tampering (forensic snapshot poisoning); Repudiation | Read-only nature reduces surface; snapshot integrity is everything |
| 15 (compliance) | Information disclosure (regulated data in reports); Repudiation (audit trail integrity) | The audit log IS the protection |

---

## Out-of-scope threats

The doctor's threat model assumes:

- The host OS is trusted (kernel not rooted; libc not replaced).
- Build-time supply chain is the project's responsibility (signing keys, toolchain integrity, dependency provenance).
- The user's terminal session is trusted (no keylogger; no screenshare).
- Other processes running as the same user are trusted (per Unix model; no fine-grained sandboxing).
- Network protocol-level attacks (TLS MITM with a forged CA in the user's trust store) are out of scope.

For projects subject to compliance regimes that require defense beyond these assumptions, additional layers (e.g., FIPS-validated cryptography, privileged-process isolation, hardware-backed key storage) are project-level concerns NOT addressed by the doctor.

---

## Quarterly threat-model review

Per [OPS-RUNBOOK.md § Quarterly](OPS-RUNBOOK.md):

1. Review this catalog. Are any threats now obsolete (mitigation absorbed)? Move to "Resolved threats" section (NEVER delete per AGENTS.md).
2. Are there new threats not in the catalog? Add with mitigation + test reference.
3. For each entry, run the linked adversarial-review test or threat-specific check.
4. File P1 beads for any failure.

Threats accumulate; mitigations accumulate; the catalog is the project's institutional security knowledge.

---

## Resolved threats (historical)

(Empty initially; entries appear here as threats are resolved by methodology evolution.)

---

## How this differs from SECURITY.md

| File | Audience | Purpose |
|------|----------|---------|
| [SECURITY.md](SECURITY.md) | Implementers | What to build (defenses, redaction, mode 0600) |
| THREAT-MODEL.md (this file) | Reviewers, auditors | What attacks are addressed (the contract that defenses imply) |
| [ADVERSARIAL-REVIEW.md](ADVERSARIAL-REVIEW.md) | Phase-7 reviewers | Concrete test scenarios for each threat |

The three files form a triangle: SECURITY.md is the implementation; THREAT-MODEL.md is the spec; ADVERSARIAL-REVIEW.md is the verification.
