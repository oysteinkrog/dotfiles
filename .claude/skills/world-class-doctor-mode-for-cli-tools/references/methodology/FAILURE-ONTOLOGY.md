# Failure Ontology — Taxonomic Classification of FMs

The failure-mode catalog in [recipes/failure_mode_catalog.md](../recipes/failure_mode_catalog.md) is organized by subsystem (state_files, configs, schemas, ...). This file goes orthogonal: classifies every FM by its **kind** of failure, regardless of subsystem.

The ontology helps Phase 1 archaeologists ensure coverage across kinds (a project with 30 FMs all in one kind is suspiciously narrow); helps Phase 6 scoring weight by kind (some kinds are systematically more dangerous than others); helps Phase 9 fixture-author build adversarial pairs across kinds.

---

## The seven kinds

### Kind A — Drift

Two stores disagree about the same fact. One must be authoritative; the other is stale.

**Examples:**
- `fm-state-files-jsonl-tombstone-drift`: DB tombstones table vs. JSONL rows.
- `fm-vendor-drift-resource-deleted-remotely`: local cache vs. remote vendor state.
- `fm-configs-mcp-drift`: `.mcp.canonical.json` vs. `.mcp.json`.
- `fm-state-files-db-family-partial-presence`: `.db` vs. `.db-wal` vs. `.db-shm`.

**Detection signature:** read both, compare, emit a finding citing the difference.
**Fixer signature:** rewrite the non-authoritative side from authority. Authority must be configurable (which is which).
**Severity range:** P1 (manageable) to P0 (data loss imminent).

---

### Kind B — Corruption

A single store has been mangled — bytes are inconsistent with its own schema, contract, or invariants.

**Examples:**
- `fm-state-files-jsonl-malformed`: a JSONL line is missing a field or has invalid UTF-8.
- `fm-schemas-db-version-mismatch`: schema_version doesn't match the binary's compiled-against version.
- `fm-state-files-db-integrity`: `pragma integrity_check` returns non-OK.
- `fm-configs-toml-parse-error`: the config file doesn't parse.

**Detection signature:** parse / verify / check; if fails, emit finding with file:line:col.
**Fixer signature:** depends. Some are auto-fixable from a known-good source (e.g., regenerate completion script). Most require intent (refuse + manual remediation).
**Severity range:** P1 to P0 (depending on whether auto-fixable).

---

### Kind C — Orphan

A reference exists but its target doesn't (or vice-versa).

**Examples:**
- `fm-concurrency-primitives-stale-doctor-lock`: lockfile references PID that's not alive.
- `fm-userland-state-shell-rc-broken-source`: `~/.zshrc` sources a file that doesn't exist.
- `fm-plugins-missing-dir`: plugin manifest references a directory that's gone.
- `fm-external-artifacts-orphaned-extra-file`: a file matching our naming pattern exists but is not in the manifest.

**Detection signature:** follow the reference; if target missing, emit finding.
**Fixer signature:** quarantine the orphan reference (don't auto-create the target — that would be intent-bearing).
**Severity range:** P2 (cosmetic) to P1 (blocks tool startup).

---

### Kind D — Permission

File mode, ownership, or ACL is wrong.

**Examples:**
- `fm-permissions-credential-too-permissive`: 0644 on a credentials file (should be 0600).
- `fm-permissions-binary-not-executable`: 0644 on a script that should be 0755.
- `fm-permissions-install-as-root-running-as-user`: file is root-owned but the user can write.

**Detection signature:** stat; compare against expected.
**Fixer signature:** chmod via `mutate(... Op::Chmod)`. Always idempotent. Always reversible.
**Severity range:** P3 (cosmetic) to P1 (security risk).

---

### Kind E — Liveness

A long-lived state (lock, socket, daemon) outlived its owner.

**Examples:**
- `fm-daemon-state-pidfile-stale`: pidfile present, PID dead.
- `fm-daemon-state-socket-orphaned`: socket file present, no listener.
- `fm-daemon-state-watchdog-stalled`: shared memory shows watchdog tick > 30s ago.
- `fm-concurrency-primitives-stale-doctor-lock` (also Kind C — overlaps).

**Detection signature:** liveness probe (`kill(pid, 0)`, `connect()`, watchdog timestamp).
**Fixer signature:** quarantine the stale resource via `Op::Rename`.
**Severity range:** P1 to P0 (when blocks normal operation).

---

### Kind F — Skew

A version or schema has drifted between two components that must agree.

**Examples:**
- `fm-multi-binary-version-skew`: `br` is 0.4.7, `bv` is 0.4.5.
- `fm-schemas-db-version-mismatch`: same as Kind B's example, but emphasizing the cross-component nature.
- `fm-vendor-drift-region-mismatch`: local config says us-east-1, vendor account is eu-west-1.

**Detection signature:** read both versions; compare against compatibility matrix.
**Fixer signature:** usually refuse; manual remediation pointing at upgrade path.
**Severity range:** P1 to P0 (when versions silently mis-write).

---

### Kind G — Configuration

A user-controlled config file is in a state we can detect but not safely auto-fix.

**Examples:**
- `fm-configs-mcp-drift` (also Kind A — overlaps).
- `fm-userland-state-shell-rc-broken-source` (also Kind C).
- `fm-secrets-token-expired`: vendor token expired.
- `fm-network-anthropic-api-key-missing`: env var not set.

**Detection signature:** evaluate the config against a known-good policy.
**Fixer signature:** REFUSE. Configuration is intent-bearing; manual_remediation only.
**Severity range:** P3 (informational) to P0 (security or correctness).

---

## The kinds × subsystems matrix

A healthy doctor's FM coverage hits both axes:

|               | state_files | configs | schemas | caches | sockets | hooks | plugins | secrets | permissions | external | concurrency | network | userland |
|---------------|-------------|---------|---------|--------|---------|-------|---------|---------|-------------|----------|-------------|---------|----------|
| **Drift**     | ✓           | ✓       | ✓       | ✓      |         |       | ✓       |         |             |          |             | ✓       |          |
| **Corruption**| ✓           | ✓       | ✓       | ✓      |         |       |         |         |             | ✓        |             |         |          |
| **Orphan**    | ✓           | ✓       |         | ✓      | ✓       | ✓     | ✓       |         |             | ✓        | ✓           |         | ✓        |
| **Permission**|             |         |         |        |         | ✓     |         | ✓       | ✓           |          |             |         | ✓        |
| **Liveness**  | ✓           |         |         |        | ✓       |       |         |         |             |          | ✓           | ✓       |          |
| **Skew**      |             | ✓       | ✓       |        |         |       | ✓       |         |             | ✓        |             | ✓       |          |
| **Configuration**|          | ✓       |         |        |         |       |         | ✓       |             |          |             | ✓       | ✓        |

If a project's FM coverage is concentrated in only one or two kinds (rows), the doctor is incomplete. The archaeologist should ask "where are the Drift FMs?" "where are the Liveness FMs?" — even if the answer is "n/a for this project type", the question forces explicit thinking.

---

## Per-kind treatment patterns

| Kind | Default fixer behavior | Default severity floor | Auto-fix rate (typical) |
|------|------------------------|------------------------|-------------------------|
| Drift | Rewrite from authority | P2 | 80%+ |
| Corruption | Refuse OR auto-rebuild | P1 | 30–70% |
| Orphan | Quarantine | P2 | 90%+ |
| Permission | Chmod | P2 | 95%+ |
| Liveness | Quarantine | P1 | 90%+ |
| Skew | Refuse + remediation | P1 | < 10% (manual) |
| Configuration | Refuse | P3 | < 10% (manual) |

The auto-fix rate per kind is approximate. Drift, Permission, and Liveness are the high-yield kinds. Configuration and Skew are mostly detect-only.

---

## Cross-kind interactions

Some interactions deserve combinatorial fixtures (`tests/doctor_fixtures/pairs/`):

- **Drift × Liveness**: a stale lockfile (Liveness) AND tombstone drift (Drift) — fixing tombstone drift requires the lock; refuse with redirect to fix lockfile first.
- **Skew × Drift**: schema_version mismatch (Skew) AND DB-JSONL drift (Drift) — refuse drift fix until skew is resolved.
- **Permission × Configuration**: too-permissive credentials (Permission) AND token expired (Configuration) — fix permission first (auto), then surface token expiry (manual).

---

## When a kind is missing

If a project's FM inventory has zero entries for a kind that conceptually applies:

1. Re-mine cass for that kind's signature phrases.
2. Re-grep the bug tracker for that kind's symptoms.
3. Check if the project genuinely has no instances (unusual but possible).

A typical state-owning CLI has FMs across ALL seven kinds. A config-only CLI typically lacks Liveness FMs. A read-only CLI lacks Configuration and Skew.

---

## How this differs from per-subsystem catalog

[recipes/failure_mode_catalog.md](../recipes/failure_mode_catalog.md) organizes FMs by what part of the system they're IN.

This file organizes by what the failure IS.

Both organizations are useful: the catalog is the implementer's reference (give me all the state_files FMs); the ontology is the auditor's reference (do we have Drift covered everywhere?).

Phase 1 archaeology should consult both.
