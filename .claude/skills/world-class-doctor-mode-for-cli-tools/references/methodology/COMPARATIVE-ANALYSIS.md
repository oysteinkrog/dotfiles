# Comparative Analysis — Industry Doctors vs. This Methodology

Many CLIs ship a `doctor` subcommand. Most are good; few are *agent-ergonomic*. This file compares the major industry doctors against the methodology in this skill, identifies where each excels and where each falls short, and credits influences.

The point isn't to disparage other tools — they pioneered the pattern; this methodology stands on their shoulders. The point is to identify what's distinctive about the methodology so a reviewer can articulate why this skill is worth applying.

---

## `cargo doctor` (proposed; doesn't yet exist as `cargo` subcommand)

**Status:** there's no official `cargo doctor`. There IS `cargo verify-project` and `cargo check`. Neither is a comprehensive doctor.

**Closest analogs:**
- `cargo verify-project` — checks Cargo.toml is well-formed.
- `cargo check` — type-checks but doesn't compile.
- `cargo update` — updates dependencies (mutating, no backup).

**What's missing vs. this methodology:**
- No chokepoint discipline (each cargo subcommand mutates ad-hoc).
- No undo (rolling back a `cargo update` requires git; not byte-for-byte for the lockfile family).
- No `--robot` mode.

**Lift opportunity:** building `cargo doctor` per this methodology would be Pattern 14 (build-system doctor). High value because Rust projects accumulate `target/` corruption, lockfile drift, registry stale, and toolchain skew.

---

## `npm doctor`

**Status:** exists; runs since npm v6.

**What it does:**
- Checks Node.js version against npm's compatibility matrix.
- Verifies the registry is reachable.
- Checks the npm cache is intact.
- Validates user permissions on global directories.

**Strengths:**
- Multi-aspect check; not single-purpose.
- Reasonable error messages.
- Long-established convention.

**Where this methodology adds value:**
- `npm doctor` doesn't `--fix`. The methodology adds the fix layer.
- `npm doctor` doesn't have `--json`. The methodology adds the agent-facing schema.
- `npm doctor` has no per-run artifacts. The methodology adds the audit trail.
- `npm doctor` doesn't refuse-with-redirect. Its errors are informational only.

**Lift:** an `npm doctor v2` per this methodology would track lockfile drift, package.json/lockfile schema mismatches, dependency phantoms, and npm cache integrity.

---

## `brew doctor`

**Status:** exists; the gold standard for "verify install integrity" across the Homebrew community.

**What it does:**
- Checks PATH ordering.
- Checks for outdated formulae.
- Identifies "unbrewed" files in `/usr/local/`.
- Verifies symlinks aren't broken.
- Many other heuristic checks accumulated over a decade.

**Strengths:**
- Very mature. Coverage of common breakages is excellent.
- Good error messages with paste-ready remediation commands.
- Beloved by the community.

**Where this methodology adds value:**
- `brew doctor` is read-only. No `--fix`.
- No `--json` (output is human-formatted; agents must parse prose).
- No backups (if there were a `--fix`, the verbatim-backup invariant doesn't exist).
- Reflective discovery is informal (the docs are the contract; not a `capabilities --json`).

**Influence on this methodology:**
- The "many heuristic checks" approach is what Phase 1 archaeology systematizes.
- The "paste-ready remediation in errors" practice → [Q-016](QUOTE-BANK.md) and Axiom 10.
- The "unbrewed files" detection (orphan files outside the manifest) → [recipes/installer.md § fm-external-artifacts-orphaned-extra-file](../recipes/installer.md).

---

## `rustup doctor` / `rustup check`

**Status:** `rustup check` exists. Verifies installed toolchains against currently-pinned versions.

**What it does:**
- Compares installed toolchain version against rust-toolchain.toml.
- Reports if updates are available.
- Verifies signature on the rustup binary itself.

**Strengths:**
- Bundled trust anchor for verifying its own binary.
- Crisp scope (just toolchain version state).

**Where this methodology adds value:**
- Limited surface (only toolchain). The methodology covers all subsystems.
- `rustup check` doesn't `--fix` (rustup update is a separate command).
- No per-run artifacts.

**Influence on this methodology:**
- The bundled-trust-anchor pattern → [recipes/installer.md trust manifest](../recipes/installer.md).

---

## `kubectl get componentstatuses` / `kubectl cluster-info dump`

**Status:** `componentstatuses` deprecated; `cluster-info dump` is the Kubernetes-equivalent diagnostic surface.

**What it does:**
- Exports cluster state to disk.
- Highly verbose; designed for support engineers.

**Strengths:**
- Comprehensive state capture.
- Structured output (JSON / YAML).

**Where this methodology adds value:**
- Kubernetes' surface is forensic-only (Pattern 13). No `--fix`. The methodology covers fix patterns.
- Output is unstructured for agent consumption (verbose dumps, not findings-with-remediation).
- Every kubectl command is online; no offline-default mode.

**Lift:** a `kubectl doctor` per Pattern 8 (wrapper for a tool you don't own) + Pattern 13 (forensic) could surface common cluster issues with structured findings.

---

## `git fsck`

**Status:** built-in; runs since Git v1.0.

**What it does:**
- Verifies object integrity (blob hashes, tree references).
- Reports dangling objects.
- Identifies missing objects.

**Strengths:**
- Foundational; used by every git operation.
- Clear failure modes (corrupted vs. missing vs. dangling).

**Where this methodology adds value:**
- `git fsck` reports issues but doesn't `--fix` corrupted objects.
- No per-run artifacts (issues exist in stderr only).
- No reflective discovery.

**Influence on this methodology:**
- The "verify object integrity at runtime" pattern → state_files subsystem detectors.

---

## `psql -c "VACUUM (VERBOSE, ANALYZE)"` / `mysqlcheck`

**Status:** built-in; vendor-provided maintenance tools.

**What they do:**
- Verify table integrity.
- Reclaim space.
- Update query planner statistics.

**Strengths:**
- Deeply integrated with the storage engine.

**Where this methodology adds value:**
- These are mutating by default; no `--dry-run` for VACUUM (autovacuum is global config).
- No `--json` mode (output is human-formatted).
- No undo (vacuum changes are permanent).

For a `<tool> doctor` that wraps these tools (Pattern 8), the methodology adds: structured output, dry-run plan, and refuse-with-redirect when the user might not want a vacuum (e.g., during peak load).

---

## `dnf check` / `apt list --upgradable`

**Status:** package-manager built-ins.

**What they do:**
- List packages with available updates.
- Check for broken dependencies.

**Strengths:**
- Universal across distros.
- Fast.

**Where this methodology adds value:**
- These are read-only by default; the user must invoke `update` separately. The methodology's `<tool> doctor --fix` integrates the diagnose + remediate cycle into one flag.
- No per-run audit (which packages were checked, when, with what result).

---

## `flutter doctor`

**Status:** exists; widely used in Flutter ecosystem.

**What it does:**
- Checks for installed SDKs (Flutter, Dart, Android, iOS).
- Verifies signing configuration.
- Lists connected devices.
- Reports environment-level issues.

**Strengths:**
- Probably the most user-friendly diagnostic surface in mainstream tooling.
- Great use of color, emoji, and progressive disclosure.
- Multi-aspect coverage from a single command.

**Where this methodology adds value:**
- `flutter doctor` is heavily TTY-oriented. JSON mode is limited.
- Doesn't have a chokepoint or backup invariant for the few mutations it offers.
- No reflective `capabilities --json`.

**Influence on this methodology:**
- The "many aspects in one command" UX → the `--robot-triage` mega-command.

---

## `op` (1Password CLI) `health` and similar SaaS-vendor doctors

**Status:** vendor-specific.

**What they do:**
- Verify auth state with vendor.
- Probe vendor health.

**Strengths:**
- Tight integration with vendor APIs.
- Often async-friendly.

**Where this methodology adds value:**
- These usually `--online` by default; the methodology's offline-by-default protects CI / sandboxes.
- Often single-purpose (just auth); the methodology covers all subsystems.

---

## What's distinctive about this methodology

After comparing, the methodology's distinctive contributions:

| Aspect | Industry tools | This methodology |
|--------|----------------|---------------------|
| **Diagnostic surface** | Common (everyone has one) | Universal — exit codes, JSON, robot-docs |
| **Fix layer** | Rare (most are read-only) | Universal via `mutate()` chokepoint |
| **Backups** | Almost never | Mandatory verbatim per Axiom 2 |
| **Undo** | Almost never (git only) | Mandatory byte-for-byte per Axiom 3 |
| **Idempotence** | Often broken | Verified per Axiom 4 + verify-idempotence.sh |
| **Crash-recovery** | Often broken | Verified per Axiom 5 + verify-crash-recovery.sh |
| **Concurrency safety** | Almost never | Verified per Axiom 6 + verify-concurrency.sh |
| **Reflective discovery** | Rare (none have full capabilities --json) | Required per Axiom 11 |
| **Offline by default** | Rare | Required per Axiom 12 |
| **Per-run artifacts** | Almost never | Required per Axiom 13 |
| **Fixture suite** | Sometimes | Required per Axiom 15 |
| **Pass cadence** | Ad-hoc | Quarterly per OPS-RUNBOOK |
| **Multi-agent etiquette** | Not addressed | First-class per ETIQUETTE.md |
| **Threat model** | Implicit | Explicit per THREAT-MODEL.md |
| **Methodology evolution** | None | Pass-N → pass-N+1 per Axiom 16 |

Every row that differs is a load-bearing contribution. None are individually novel; the synthesis is.

---

## When industry tools are better

This methodology adds rigor; industry tools add accumulated wisdom.

- **Heuristic coverage.** `brew doctor` has accumulated 10+ years of "weird thing X means user did Y". A fresh `brew doctor` per this methodology would START with less coverage.
- **Idiomatic UX.** `flutter doctor`'s color-coded output is genuinely beautiful for human readers.
- **Single-purpose performance.** `git fsck` is faster than a methodology-wrapped equivalent because it has direct access to git internals.

The methodology's contribution is the discipline; the industry's contribution is the pattern library. Combine both: apply the methodology AND borrow the pattern library.

---

## Citation discipline

When proposing a Cookbook pattern or a recipe based on an industry tool:

1. Cite the original tool as the source.
2. Note what the methodology adds.
3. Note where the original tool got it right.

This file is the citation backbone. Add to it when you study a new industry doctor.

---

## Future analyses to add

- `pip check` and pip's `--report` mode.
- `gem list --installed`.
- `composer diagnose` (PHP).
- `gradle dependencies --offline`.
- `terraform validate` + `terraform plan` (the dry-run ancestor).
- `ansible-playbook --check` (industry-leading dry-run).
- `kubectl --dry-run=server`.
- `helm lint`.

Each of these informs a Cookbook pattern or refines an existing axiom. The library grows.
