# VERIFICATION-FIRST — Live-Evidence Verification Protocol for Volatile Facts

The FrankenSQLite bibles + this skill's mining extracts encode an enormous amount of **evergreen methodology** (the keep-gate rules, the kernel axioms, the operator library, the 30-line `scenario()` template). They also encode an enormous amount of **volatile reference state** — facts that were true when the bible was written and may or may not be true when the agent applies the skill to your project today.

The methodology survives version bumps. The volatile facts don't.

This file is the discipline for distinguishing the two and the protocol for verifying volatile facts before staking a release claim on them.

---

## Core Rule

**Do not stake a release claim on a volatile fact UNTIL it has been verified against live primary sources AND logged in `<workspace>/provider_audit_log.md`.**

Equivalently: every artifact emitted by the gauntlet must be sourced from one of:

1. **Evergreen kernel** — patterns / axioms / templates that hold across versions. Cite by section number (e.g., "by K-4 from KERNEL.md").
2. **Live-verified volatile fact** — verified against a live primary source AT THIS RUN's start, with the verification log entry attached to the artifact.

If neither applies, the artifact is **a guess** and must be flagged as such (`provenance: unverified` in the envelope).

The pattern is the same as the saas-billing skill's `VERIFICATION-FIRST.md`, adapted for the gauntlet's reference-version-sensitive surface.

---

## Evergreen vs. Volatile Classification

### Evergreen (use from memory; no live verification needed)

These survive across reference versions, SDK reorganizations, and methodology evolution. They're what this skill exists to teach.

- The 12 K-N axioms in [KERNEL.md](KERNEL.md).
- The 19 operator glyphs in [OPERATORS.md](OPERATORS.md).
- The 10 winning optimization patterns from [remediation/REMEDIATION-PATTERNS.md](../remediation/REMEDIATION-PATTERNS.md).
- The 30-line `scenario()` template (subject vs. oracle parity).
- The 6 timing constants (`WARMUP_ITERS=2, MIN_ITERS=3, MAX_ITERS=10, TARGET_DURATION=5s`).
- The 6 weighted scenario categories (`ReadSingle 0.35, ReadAggregate 0.15, ...`).
- The `release-perf` profile recipe (`opt-level=3, lto="thin", codegen-units=1, debug="line-tables-only", strip=false`).
- The `truncate_score` 6-decimal-place rule.
- The Differential V2 envelope `artifact_id = SHA-256(canonical JSON excluding run_id)`.
- The `EngineIdentity::{Subject,Oracle}` discriminator.
- The MismatchClassification 5 classes (Order / TypeAffinity / NullHandling / FloatingPoint / FalsePositive vs. TrueDivergence).
- The keep-gate rules (10 of them, [KEEP-GATE-RULES.md](KEEP-GATE-RULES.md)).
- The 8 retry-condition predicate forms ([RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md)).
- The negative-ledger discipline (60-day mining + project-class failure terms).
- The 16-phase loop structure.
- The convergence rule (≥10 rounds, ≥2 clean, every hypothesis resolved).
- The proof-pack 19 required fields.
- The bench-history pass-over-pass thresholds (primary −3%, geomean −5%, per-category −10%, p90 −15%, throughput −5%).

### Volatile (must verify live per project class)

These drift between reference versions. They're surface details, cardinality floors, tolerances, RNG seed contracts, dispatch tables, command lists, PRAGMA lists, type-system rules, etc.

| Volatile fact class | Project class scope | Drift cadence | Verify against |
|---|---|---|---|
| Reference version surface details (PRAGMA list, COMMAND list, opcode set, dispatch table) | All | Per-version | Live binary introspection (e.g., `sqlite3 -cmd '.pragma list'`) |
| Per-class boundary counts | All (per [taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md)) | Per-version | Source-level grep + boundary enumeration |
| Cardinality floors for fixture corpus | All | Per-major-version | Generate fresh corpus; record cardinality |
| ULP tolerances per operator | Numerical-Python + ML-System | Per-version | Live `gradcheck`/`numpy.testing.assert_array_almost_equal` calibration |
| RNG seed contract | Numerical-Python + ML-System | Per-major-version | Live seed-fixture re-derivation |
| Per-class crash-boundary protocol enumeration | All | Per-major-version | Live source-level enumeration + cross-check with reference's recovery code |
| Fault VFS taxonomy applicability | SQL-class | Per-version | Live VFS introspection |
| Reference binary's identity strings | All | Per-build | Live oracle-preflight-doctor query |
| Reference's `__all__` / exported symbol list | Numerical-Python + ML-System | Per-version | Live `python -c "import <module>; print(<module>.__all__)"` |
| Reference's webhook / event taxonomy | HTTP-Protocol | Per-version | Live API call to reference framework |
| Reference's default config (e.g., journal_mode, RESP version, dtype default) | All | Per-version | Live preflight check |

Per [PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md), each class has its own volatile-fact menu.

---

## Verification Checklist Per Project Class

### SQL-class (frankensqlite, sqlmodel_rust)

```bash
# Reference binary version
sqlite3 --version

# PRAGMA list (volatile across SQLite 3.X versions)
sqlite3 -cmd '.pragma list' < /dev/null > <workspace>/verification/sqlite_pragma_list.txt

# Opcode list (volatile; new opcodes added each version)
sqlite3 -cmd '.help' < /dev/null | grep -i opcode || \
  python3 -c "import sqlite3; conn = sqlite3.connect(':memory:'); cur = conn.cursor(); cur.execute('EXPLAIN SELECT 1'); print([row[1] for row in cur.fetchall()])"

# WAL frame format (volatile across major versions)
sqlite3 -cmd '.dbconfig' < /dev/null

# Identity strings — must match docs/contracts/<reference>_version_contract.toml
sqlite3 -version | head -1
```

Log each finding to `<workspace>/provider_audit_log.md` per the schema below.

### RESP-class (frankenredis)

```bash
# Server version + protocol negotiation
redis-cli HELLO 3

# COMMAND COUNT (volatile; e.g., 7.2.5 vs 7.4.0 differ by ~10 commands)
redis-cli COMMAND COUNT
redis-cli COMMAND LIST | wc -l

# Module-loaded list (changes with version)
redis-cli MODULE LIST

# Default config snapshot
redis-cli CONFIG GET '*' > <workspace>/verification/redis_config.txt

# Persistence file format check
redis-cli CONFIG GET save
redis-cli CONFIG GET appendonly
```

### Numerical-Python-class (franken_numpy, frankenpandas, frankenscipy, franken_networkx)

```bash
# NumPy version + SIMD flags
python3 -c "import numpy; print(numpy.__version__); print(numpy.show_config())"

# numpy.__all__ (volatile; new APIs added per minor version)
python3 -c "import numpy; print(sorted(numpy.__all__))" > <workspace>/verification/numpy_all.txt

# BLAS thread count
python3 -c "import numpy; print(numpy.show_runtime())"

# RNG state policy (volatile across major versions)
python3 -c "from numpy.random import Generator, PCG64DXSM; g = Generator(PCG64DXSM(seed=42)); print(g.bit_generator.state)"
```

### ML-System-class (frankentorch, frankenjax, franken_whisper)

```bash
# PyTorch version + CUDA/cuDNN/driver
python3 -c "import torch; print(torch.__version__, torch.version.cuda, torch.backends.cudnn.version())"

# Dispatch table (volatile per release)
python3 -c "import torch; print(len(torch._C._get_all_operator_overloads()))"

# Determinism flags (some flags change semantics across versions)
python3 -c "import torch; torch.use_deterministic_algorithms(True); print(torch.are_deterministic_algorithms_enabled())"

# Per-op ULP tolerance baseline (run gradcheck on a representative op)
python3 -c "
import torch
x = torch.randn(8, requires_grad=True, dtype=torch.float64)
torch.autograd.gradcheck(lambda t: t.sin(), (x,))
print('gradcheck baseline: PASS')
"
```

### HTTP-Protocol-class (fastapi_rust, fastmcp_rust)

```bash
# Reference framework version
python3 -c "import fastapi; print(fastapi.__version__)"

# OpenAPI schema generation (changes with version)
python3 -c "
from fastapi import FastAPI
app = FastAPI()
print(len(app.openapi()['paths']) if hasattr(app, 'openapi') else 'no openapi')
"

# Pydantic version (load-bearing; v1 vs v2 differs substantially)
python3 -c "import pydantic; print(pydantic.VERSION)"

# MCP protocol version (FastMCP-specific; volatile across protocol revisions)
python3 -c "from mcp import __version__; print(__version__)"
```

---

## The `provider_audit_log.md` Schema

Every verification produces an entry in `<workspace>/provider_audit_log.md`. The file is **append-only**; entries are never overwritten or deleted (historical trail is part of the proof).

```markdown
## Verification: <name>
- checked_at: 2026-05-22T19:14:00Z
- environment: gauntlet_workspace
- scope: read_only_reference_introspection
- redaction: counts_only_no_payloads
- project_class: SQL-class
- reference: sqlite-3.52.0
- finding:
  - <structured finding — count, list, version string, etc.>
- expected (per docs/contracts/<reference>_version_contract.toml):
  - <value from the contract>
- actual (live reference introspection):
  - <value from the live query>
- delta:
  - ✓ match | ✗ drift (severity: <high | medium | low>)
- next_action:
  - <if delta: file as Phase 12 remediation OR halt with oracle_preflight=red>
  - <if match: log and continue>
- repro_command:
  - <one-line shell invocation that reproduces this finding>
```

The artifact IS the audit. If a verification result is not in `<workspace>/provider_audit_log.md`, the verification didn't happen.

The contents of `provider_audit_log.md` are read by:
- `scripts/oracle-preflight-doctor.sh` (verifies expected matches actual; exits non-zero on drift)
- `subagents/final-report-author.md` (cites verification log in `FINAL_GAUNTLET_REPORT.md § Verification Trail`)
- `subagents/certification-bundler.md` (includes the log in the strict-conformant-release.v1 bundle as `certification_bundle/verification_log.md`)

---

## Primary Source Hierarchy

Use sources in this priority order:

1. **Live read-only introspection of the pinned reference binary/library AT THIS RUN'S TIME** — most authoritative.
2. **Reference source code at the pinned commit SHA** — authoritative for build-time facts (e.g., opcode enum members).
3. **Reference's published release notes / changelog for the pinned version** — authoritative for behavioral semantics declared by the project.
4. **This skill's evergreen kernel + operator library** — authoritative for methodology.

Avoid relying on:

- The FrankenSQLite bibles' specific cardinality / count / threshold numbers (these were point-in-time; some still hold, some have drifted).
- Stale agent memory of "I think SQLite has N PRAGMAs".
- Third-party tutorials more than 6 months old.
- Mining-extract numbers from MINING-1/2/3 without live re-verification (the *patterns* in the mining extracts are evergreen; the *numbers* are point-in-time).
- "I read this in the SQLite docs" without a current URL + pinned version.

---

## Mandatory Verification Triggers

Verify live whenever the gauntlet depends on:

1. **Reference binary version + identity strings** — preflight every run.
2. **Per-class surface enumeration** (PRAGMA list, COMMAND list, opcode list, `__all__` list) — at Phase 1 recon and Phase 7 surface parity.
3. **Per-class crash-boundary count** — at Phase 6 conformance harness; if the count differs from [taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md)'s tabulated count, update the contract and re-derive affected lanes.
4. **Per-op ULP tolerance** (Numerical-Python + ML-System classes only) — at Phase 6 metamorphic; recalibrate via `gradcheck` against the live reference.
5. **RNG seed contract** — at Phase 4 golden capture; if the seed contract differs, the golden artifacts must be regenerated.
6. **FaultKind applicability** — at Phase 6 fault-injector authoring; some fault categories don't apply to all reference versions (e.g., `PowerCut` simulates older I/O stacks).
7. **Default config of the reference binary** (journal_mode, RESP version, dtype, ...) — at Phase 5 perf harness; bench results stake claims on the default config matching.
8. **Cardinality floors of fixture corpora** — at Phase 4 golden capture; the floor is what `oracle_preflight_doctor.rs` checks; a drift means the corpus needs regeneration.
9. **Module-loaded list** (RESP-class; Numerical-Python-class) — at Phase 3 oracle wiring; ensures the reference's module set matches what the subject expects.

---

## Diagnostic Discipline (security rules)

These apply EVERY verification run. Violations are P1 incidents.

1. **Do NOT inspect reference binaries that require secrets without strict scoping.** Most gauntlet references are open binaries (sqlite3, redis-server, etc.) — no secret needed. But if the reference is a hosted API (some HTTP-Protocol-class references), apply the saas-billing skill's secret-handling discipline.
2. **Do NOT put secrets in shell arguments.** Use env-var loading inside the verification process, not `--token X` on the command line.
3. **Redact identifiers unless the identifier IS the finding.** Counts and key sets are usually enough. If a per-fixture ID is needed, store in a restricted artifact.
4. **Sample vs. full-scan must be labeled.** A `--limit 100` recent sample is NOT a population proof. Label the artifact entry with `sample_size: 100` or `full_scan: true (paginated)`.
5. **Live re-verification cadence** — at Phase 0 (preflight), Phase 2 (contract pinning), Phase 4 (golden), Phase 9 (baseline). Add per-mode cadence:
   - `gauntlet-full`: every Phase 0 + Phase 9 (per round if iterating).
   - `audit-only`: Phase 0 + Phase 9 once.
   - `compliance-pass`: every Phase 0 + Phase 9; treat the verification log as the auditor evidence.
   - `migration`: every Phase 0 + every Phase 6 lane re-run.

---

## When to Back Off vs. Proceed with a Documented Assumption

If a verification fails (live reference state contradicts the contract / a mined-from-bible fact):

| Severity | Example | Response |
|---|---|---|
| **Critical** | Reference identity string doesn't match contract; reference version differs from pinned | HALT. Oracle preflight is red. Surface to the user. Do not proceed. |
| **High** | A required PRAGMA from the contract is missing in the live reference (means the reference version is wrong) | HALT. Re-verify the binary; if confirmed missing, recommend `migration` mode. |
| **Medium** | A new PRAGMA / COMMAND / opcode exists in the live reference but is not in the contract | Add to contract; rebalance FeatureUniverse weights; continue (this is the normal `incremental-rebase` flow). |
| **Low** | A help-text format changed; a non-load-bearing string output differs | Log in `provider_audit_log.md` with severity:low; continue. |

When in doubt: **do not finalize the claim**. Surface to the user with the exact verification finding + the proposed next step.

The escalation language for high-severity drifts:

```
HALT (verification failure):
- expected: <from contract>
- actual: <live finding>
- delta severity: high
- proposed next step: switch to `migration` mode against <reference>-<new_version>
- rationale: <one paragraph>

Do you want to:
(a) switch to migration mode now,
(b) re-pin the contract to the live version and continue (NOT RECOMMENDED if any artifact has already shipped),
(c) escalate to the human reviewer?
```

---

## Verification artifacts that go in the certification bundle

For `gauntlet-full` and `compliance-pass` modes, the verification log feeds `certification_bundle/`:

- `certification_bundle/verification_log.md` — full append-only log from this run.
- `certification_bundle/verification_summary.json` — machine-readable summary (count by severity, drift list).
- `certification_bundle/reference_identity_proof.txt` — `<reference> --version` output captured at run start.
- `certification_bundle/contract_hash.txt` — SHA-256 of `docs/contracts/<reference>_version_contract.toml` at certification time.

The auditor reads the verification summary first; details follow.

---

## Concrete Examples

### Example 1: SQLite 3.52 → 3.53 PRAGMA list drift

```bash
# Pinned in contract: sqlite-3.52.0 with PRAGMA list of 56 entries
# At run time:
sqlite3 -cmd '.pragma list' < /dev/null | wc -l
# → 58

# Log entry:
cat >> <workspace>/provider_audit_log.md <<EOF
## Verification: sqlite-pragma-list
- checked_at: 2026-05-22T19:14:00Z
- environment: gauntlet_workspace
- scope: read_only_reference_introspection
- redaction: counts_only_no_payloads
- project_class: SQL-class
- reference: sqlite-3.52.0 (per contract)
- finding:
  - live PRAGMA count: 58
  - delta from contract (56): +2
- expected: 56
- actual: 58
- delta:
  - ✗ drift (severity: medium)
- next_action:
  - identify the 2 new PRAGMAs; if entitlement-affecting, add to FeatureUniverse and rebalance weights; otherwise log as out-of-scope-for-pinned-version.
- repro_command:
  - sqlite3 -cmd '.pragma list' < /dev/null
EOF
```

Resolution: identify the 2 new PRAGMAs via diff. They're `PRAGMA secure_delete` (already in contract — false positive — was on alias) and `PRAGMA query_only` (new in 3.53). Switch to `migration` mode if 3.53 is the intent; otherwise pin the binary at 3.52.

### Example 2: Redis 7.2.5 → 7.4.0 COMMAND COUNT drift

```bash
# Contract: redis-7.2.5 with COMMAND COUNT = 241
redis-cli COMMAND COUNT
# → 247

# Log entry:
cat >> <workspace>/provider_audit_log.md <<EOF
## Verification: redis-command-count
- checked_at: 2026-05-22T19:14:00Z
- project_class: RESP-class
- reference: redis-7.2.5 (per contract)
- finding:
  - live COMMAND COUNT: 247
  - new commands: <list from comm -13 <(redis-cli COMMAND LIST | sort) <previous-pinned-list>>
- delta: ✗ drift (severity: medium)
- next_action:
  - if testing against 7.4.0: switch to migration mode and add the 6 new commands to FeatureUniverse
  - if intent is 7.2.5: re-install the correct binary version
EOF
```

### Example 3: PyTorch 2.X dispatch table drift

```bash
# Contract: torch-2.5.0 with dispatch overload count = N
python3 -c "import torch; print(len(torch._C._get_all_operator_overloads()))"
# → returns N+12

# Log entry: similar shape; severity medium; next_action: enumerate the 12 new overloads and assess per-op ULP impact.
```

### Example 4: Live RNG seed contract verification

```bash
# Contract: PCG64DXSM seed 42 → first 4 u64s = [a, b, c, d]
python3 -c "
from numpy.random import Generator, PCG64DXSM
g = Generator(PCG64DXSM(seed=42))
print(g.integers(low=0, high=2**63, size=4).tolist())
"
# Compare to contract's hash; if differs → ✗ drift severity:critical (because golden artifacts depend on this).
```

---

## Class-specific gotchas

- **SQL-class:** PRAGMA aliases are common (e.g., `synchronous` and `sync` may resolve to same setting in some versions). Count by canonical name, not by surface text.
- **RESP-class:** `COMMAND INFO` returns arity/flags/etc.; a change in flags (without a change in command count) is still surface drift.
- **Numerical-Python-class:** `__all__` is the source of truth, not module attribute enumeration (which catches private helpers).
- **ML-System-class:** Determinism flags interact (`torch.use_deterministic_algorithms` + `CUBLAS_WORKSPACE_CONFIG` env var). Verify both.
- **HTTP-Protocol-class:** Pydantic v1 vs v2 changes the schema-generation output substantially; pin Pydantic version in the contract.

---

## Verification cadence by mode

| Mode | Verification cadence |
|---|---|
| `gauntlet-full` | Phase 0 + Phase 2 + Phase 4 + Phase 9 (per round if iterating) + Phase 15 (re-verify before soak) |
| `audit-only` | Phase 0 + Phase 9 once |
| `harden-pillar` | Phase 0 + Phase 9 once on the affected pillar |
| `add-feature` | Phase 0 + Phase 2 (the rebalance step touches the contract) |
| `incremental-rebase` | Phase 0 only (assumes the rebase didn't move the reference) |
| `compliance-pass` | Phase 0 + Phase 9; verification log IS the auditor deliverable |
| `red-team` | Phase 0 only (the adversarial run doesn't change verification) |
| `migration` | Phase 0 + Phase 2 + every Phase 6 affected lane |
| `cass-mine-only` | Phase 0 only |
| `quick-smoke` | Phase 0 only (CI budget) |

See [MODE-ROUTER.md](MODE-ROUTER.md) for the mode definitions and [PHASES.md](../PHASES.md) for what each phase produces.

---

## When verification is impossible

Sometimes the live reference binary cannot be reached (offline run, sandbox without network, etc.). The fallback:

1. Note the inability in `provider_audit_log.md` with `severity: blocker`.
2. Proceed using the LAST KNOWN GOOD verification entry (which must exist; otherwise halt).
3. Stamp every emitted artifact with `provenance: assumed_from_<previous_verification_timestamp>`.
4. Surface to the user at the end: "Verification was skipped this run; X artifacts inherit provenance from the prior verification at TIMESTAMP. Recommend re-running with live access before any release decision."

A run with stale verification is **explicitly documented**, never silent. K-3 (negative evidence first-class) requires logging the blocker; K-2 (honesty in the harness) requires stamping artifacts with their provenance.

See [CASS-MINING.md § When cass is unavailable](CASS-MINING.md) for the analogous fallback for the negative-ledger mining step.
