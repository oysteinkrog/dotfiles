# Cookbook — Doctor Patterns for Common Project Shapes

The phase loop is universal but the *shape* of the doctor differs by project archetype. This cookbook names fifteen recurring shapes, the variations in failure-mode partition each one implies, and the per-shape adjustments to the standard surface.

For each pattern: scope, additional failure-mode classes, surface variations, and a one-paragraph application note.

---

## Pattern 1 — Single-binary state-owning CLI (the baseline)

**Examples.** `br`, `xf`, `cm`, `cass`.
**Scope.** One binary, owns a `.<tool>/` directory in the project, persists state across invocations.
**Failure-mode classes.** All standard subsystems (state_files, configs, schemas, caches, concurrency_primitives, userland_state).
**Surface.** The canonical surface from [CLI-SURFACE.md](CLI-SURFACE.md).
**Note.** This is the default. The rest of the cookbook is variations on it.

---

## Pattern 2 — Multi-binary toolkit (single shared state)

**Examples.** `br` + `bv` (both touch `.beads/`); `cargo` + `cargo-deny` + `cargo-audit`.
**Scope.** Multiple binaries sharing one state surface.
**Failure-mode classes.** Standard + cross-binary version skew (one binary is at v1.2, another at v1.0).
**Surface.** Each binary gets its own `<binary> doctor` subcommand. They share `mutate()` (in a common library) and write to the same `.doctor/runs/<run-id>/` directory. The `capabilities --json` of each binary cross-references siblings via a `siblings: ["bv"]` field.
**Note.** One scorecard per binary, but the workspace tracks all of them; the aggregate score is the binary-weighted average. See [recipes/multi-binary-toolkit.md](../recipes/multi-binary-toolkit.md).

---

## Pattern 3 — Single-binary stateless CLI (config-only)

**Examples.** `dcg` (the destructive-command guard reads patterns from a config), `de-slopify` (text transformer with config).
**Scope.** One binary, no persistent state across invocations beyond config files.
**Failure-mode classes.** configs, schemas (config schema versioning), permissions. NOT state_files, caches, concurrency_primitives.
**Surface.** Standard surface, but `--fix` mostly addresses config drift / config schema migration. `undo` is still mandatory.
**Note.** The `mutate()` chokepoint and backup invariants apply unchanged. The fixture suite is smaller (5–10 fixtures typical, vs. 30+ for state-owning tools).

---

## Pattern 4 — Daemon / long-running process CLI

**Examples.** `wrangler dev`, `ntm` (terminal multiplexer), `mcp-agent-mail` (MCP server), Cloudflare Workers local dev.
**Scope.** CLI starts a daemon; the daemon owns sockets, ports, listeners, watchdog timers.
**Failure-mode classes.** Standard + sockets + listeners + port conflicts + watchdog state + shared-memory cleanup.
**Surface.** Adds:
- `<tool> doctor health --watch` (NDJSON stream of liveness; analogous to `caam robot watch`).
- `<tool> doctor --running` (variant detector that probes the running daemon if any).
- `--strict-isolation` on `--fix` (don't touch a running daemon's live state; only quarantine the socket / pidfile).
**Note.** Concurrency-safety is more important here: the doctor must never `--fix` a workspace whose daemon is alive (refuse with exit 4, suggest `<tool> stop` first). The detector probes daemon liveness via socket-connect (offline-only — no network) and treats a non-responsive socket as a P0 finding. See [recipes/daemon-cli.md](../recipes/daemon-cli.md).

---

## Pattern 5 — Installer / provisioner CLI

**Examples.** `installer-workmanship` skill output, `acfs` (agentic-coding-flywheel-setup), fleet-provisioning installer CLIs.
**Scope.** CLI installs other tools; doctor verifies the install integrity post-hoc.
**Failure-mode classes.** external_artifacts (installed binaries' checksums), permissions (files installed with wrong mode), hooks (shell rc files modified), userland_state (XDG dirs).
**Surface.** Adds:
- `<tool> doctor verify-install` — a privileged subcommand that checks every installed artifact's checksum against the signed manifest. Always offline-first; signature verification uses bundled keys.
- `<tool> doctor reinstall <artifact>` — re-fetches and re-installs one artifact. Routes through `mutate()` with backup of the existing file.
**Note.** The installer's manifest is the source-of-truth for what should be installed. The doctor's `capabilities::write_scopes` includes `~/.local/bin/<tool>`, `/usr/local/bin/<tool>`, `~/.<tool>/`. See [recipes/installer.md](../recipes/installer.md).

---

## Pattern 6 — TUI-first CLI with non-interactive subset

**Examples.** `bv` (graph triage TUI; `--robot-*` flags expose CLI mode), `frankentui` apps.
**Scope.** Primary UX is a TUI; the agent surface is a separate `--robot-*` mode.
**Failure-mode classes.** Standard + TUI-state files (rendering caches, persisted layouts).
**Surface.** `<tool> doctor` ALWAYS runs in non-interactive mode (per Axiom 7); never launches the TUI. The TUI's own state files are detected/repaired by detectors with subsystem `tui_state`.
**Note.** The bare `<tool>` (with no args) launching a TUI is the shape AGENTS.md § bv warns against — agent invocations must use `--robot-*`. Doctor never has this problem because `<tool> doctor` is by-construction non-interactive.

---

## Pattern 7 — AI-coding-agent CLI (`<tool> agent doctor`)

**Examples.** `caam` (manages multi-account agent sessions), `ntm` (orchestrates agent swarms), `cass` (mines agent sessions), `cm` (procedural memory for agents).
**Scope.** CLI's primary purpose is to support AI coding agents; doctor's primary user is also an AI coding agent (recursive).
**Failure-mode classes.** Standard + agent-session state (session files, memory caches, account credentials), rate-limit state, prompt-cache state.
**Surface.** Adds:
- `<tool> doctor session-integrity <session-id>` — verifies a captured session is replayable.
- `<tool> doctor account-health [--online]` — vendor-API check (gated).
- `<tool> doctor cache-warmth` — verifies prompt-cache primers are valid and not stale.
**Note.** This is the meta-pattern: the user's agents use `<tool>` to coordinate, and `<tool> doctor` keeps that coordination layer healthy. The doctor's robot-docs explicitly addresses an *agent* reader (not a human).

---

## Pattern 8 — Doctor for a tool you don't own (proposed `<external> doctor`)

**Examples.** Proposing `cargo doctor`, `kubectl doctor`, `rustup doctor` (already exists, but informs the pattern).
**Scope.** The CLI is a third-party tool; you can't modify its source. The "doctor" is a wrapper.
**Failure-mode classes.** Whatever the third-party tool's state surface is, observed externally.
**Surface.** Wrapper CLI: `<wrapper> <external-tool>-doctor` or a bash-script doctor that orchestrates `<external-tool> --version`, queries config files, etc.
**Note.** No `mutate()` chokepoint inside the third-party tool's process — but the wrapper's own `mutate()` is still load-bearing for any config it rewrites. Skip Phase 8's "demote related skill" because there's no upstream skill to demote. Useful for surfacing the upstream tool's actual remediation playbook in agent-ergonomic form.

---

## Pattern 9 — Doctor for a distributed CLI (vendor-API client)

**Examples.** `wrangler` (Cloudflare), `vercel` CLI, `gh` (GitHub), `gcloud`, `aws`.
**Scope.** CLI talks to a remote service; "health" includes both local config and vendor-side state.
**Failure-mode classes.** Standard + auth_state (token expiry, scope drift), vendor_drift (local cache vs. remote reality), rate_limits.
**Surface.** Adds extensive `--online` paths:
- `<tool> doctor auth-status [--online]` — token validity (offline check via JWT exp; online check via vendor API).
- `<tool> doctor vendor-sync [--online]` — pulls remote config and diffs against local cache.
- `<tool> doctor rate-limit-budget [--online]` — current rate-limit window state.
**Note.** Online detectors emit `findings_only_offline` when network is unavailable. Vendor failures (5xx) are findings, not crashes. See [recipes/distributed-cli.md](../recipes/distributed-cli.md).

---

## Pattern 10 — Absorb-playbook (manual repair → automated fixer)

**Examples.** `fixing-beads-problems` → `br doctor`, `system-performance-remediation` → `pt doctor`, `path-rationalization` → `pr doctor`.
**Scope.** A manual playbook skill exists. Mode `absorb-playbook` converts each playbook step into a (detector, fixer, fixture) tuple.
**Failure-mode classes.** Whatever the playbook addresses.
**Surface.** Standard. The novel part is Phase 8: update the source playbook's SKILL.md to demote it to a fallback.
**Note.** Per AGENTS.md no-delete, the original playbook content stays — relabeled as fallback, not removed. Detail in [ABSORB-PLAYBOOK.md](ABSORB-PLAYBOOK.md).

---

## Pattern 11 — Doctor for an installer-bootstrap chain

**Examples.** `installer-workmanship` skill output produces install scripts that need their own doctor; `dsr` (Doodlestein Self-Releaser) for fallback releases.
**Scope.** A bootstrap script (typically `curl | bash`) installs a tool; `<tool> doctor verify-bootstrap` checks the install came from the right source with the right signature.
**Failure-mode classes.** external_artifacts + signature verification + supply-chain attestation.
**Surface.** Adds:
- `<tool> doctor verify-bootstrap` — checksum + signature validation against the bundled trust anchor.
- `<tool> doctor reinstall-from-bundle` — re-extracts the bundled binary and replaces the installed one (via `mutate()` with backup).
**Note.** The trust anchor (public key) is baked into the binary at build time. The doctor never fetches keys from the network. Online verification (against a release-server signature) is opt-in via `--online` and `--verify-online`.

---

## Pattern 12 — Doctor for a skill itself (meta-doctor)

**Examples.** This skill's *own* doctor — `world-class-doctor-mode-for-cli-tools/scripts/validate-skill.sh`.
**Scope.** The skill is the "tool"; the workspace contains SKILL.md, references/, scripts/, assets/, subagents/. A meta-doctor validates the skill's internal consistency.
**Failure-mode classes.**
- Broken cross-references (links from SKILL.md to a missing reference file)
- QUOTE-BANK ID drift (a referenced `Q-NNN` doesn't exist)
- CORPUS path rot (a cited `/dp/...` source no longer exists locally)
- Frontmatter regressions (SKILL.md's `description` exceeds the budget; `name` doesn't match the directory)
- Subagent file naming drift (a referenced subagent doesn't exist)
- Script executability (a referenced script isn't `+x`)
**Surface.** `world-class-doctor-mode-for-cli-tools/scripts/validate-skill.sh <skill-dir>`.
**Note.** This is the recursive pattern — the skill that builds doctors *has* a doctor. Captured in [META-DOCTOR.md](META-DOCTOR.md).

---

## Pattern 13 — Read-only / forensic doctor (post-mortem mode)

**Examples.** Production incidents where the project's state is broken AND the user cannot afford a write. The doctor diagnoses without `--fix` ever being available; instead it produces a structured forensic report.

**Scope.** A fork of Pattern 1 where every fixer is replaced by `manual_remediations`. The runtime explicitly rejects `--fix` with a hard error.

**Failure-mode classes.** All standard subsystems, but with the specific addition of `forensic_evidence` outputs: byte-level diffs, hash-trees, timestamps of all modifications since a reference SHA.

**Surface variations:**
- `<tool> doctor freeze` — captures the entire workspace state to a `.doctor/frozen/<id>/` directory (no mutation; just `cp -a` snapshot of the current state).
- `<tool> doctor compare-frozen <id-a> <id-b>` — diffs two snapshots.
- `<tool> doctor --fix` — refuses with exit 4 and a finding `manual: this tool is forensic-only`.

**Note.** Useful for compliance-bound projects (SOC 2, HIPAA) where ANY automated fix would violate change-control. The doctor's value is structured-evidence-extraction.

**When to apply:** the user has a regulatory requirement that every state change goes through a documented change-management process. Doctor's `--fix` is incompatible with that process; forensic-only is.

---

## Pattern 14 — Build-system doctor

**Examples.** `cargo doctor` (proposed for cargo workspaces), `npm doctor` (exists; could be expanded with this methodology), `gradle doctor` (proposed), `pip check` extension.

**Scope.** The CLI is a build tool. State lives in lock files, dependency caches, target/build directories. The doctor verifies that the build state is consistent.

**Failure-mode classes.**
- `lockfile_drift` — Cargo.lock vs. Cargo.toml; package-lock.json vs. package.json.
- `cache_corruption` — target/release artifact references a removed dep; .cargo/registry corrupted.
- `dependency_phantom` — listed in Cargo.toml as a dep but not used (or vice versa, listed in code but not declared).
- `version_skew_workspace` — workspace member crates at incompatible versions.
- `feature_flag_inconsistency` — a feature is on in dev but off in CI.

**Surface variations:**
- `<tool> doctor verify-lockfile` — compare lockfile to manifest; report drift.
- `<tool> doctor detect-phantom-deps` — static analysis of imports vs. declarations.
- `<tool> doctor cache-integrity` — verify dep cache hashes against lockfile.

**Fixers (mostly safe to auto-run):**
- Regenerate lockfile (cargo update).
- Vacuum cache.
- Reinstall deps from lockfile.

**Why it's a separate pattern:** lockfile-and-cache discipline is its own world. The detectors / fixers are well-known and cleanly auto-fixable.

---

## Pattern 15 — Compliance / audit doctor

**Examples.** A doctor whose output is consumed by a compliance auditor (internal or external). For SOC 2, HIPAA, PCI, GDPR, or similar regimes.

**Scope.** Combines Pattern 13 (read-only / forensic) with extensive `--audit-export` capabilities.

**Failure-mode classes.**
- `audit_log_gap` — `actions.jsonl` from a prior run is missing from the audit trail.
- `permission_drift` — a credential file's mode changed since the last audit.
- `crypto_key_age` — keys older than the policy max.
- `unencrypted_pii` — file contents matching PII regex outside the encrypted-blob region.
- `access_control_drift` — the project's RBAC declarations vs. running config.

**Surface variations:**
- `<tool> doctor audit-export --since <date> --to <file.csv>` — emits all findings + actions in a CSV the auditor can ingest.
- `<tool> doctor compliance --regime soc2-type-ii` — runs the regime-specific detector suite.
- All findings include `regime: ["soc2", "hipaa"]` arrays so the auditor can filter.

**Note.** Most compliance doctors don't have a `--fix` mode at all. They detect, structure, and export. Remediation is the project owner's responsibility under change control.

**Cite:** [SECURITY.md § Compliance considerations](SECURITY.md) — the existing skill already addresses some of this; Pattern 15 is the dedicated escalation.

---

## Choosing the right pattern

When applying this skill to a new project, the archaeologist's first task (after reading SKILL.md and AGENTS.md) is to classify the project against this cookbook:

1. Does the project produce one binary or several? → Pattern 1 vs 2.
2. Does it persist state, or is it config-only? → Pattern 1 vs 3.
3. Does it run a daemon? → Pattern 4.
4. Does it install other tools? → Pattern 5.
5. Is it a TUI primarily? → Pattern 6.
6. Does it support AI agents? → Pattern 7.
7. Is the target tool out of our control? → Pattern 8.
8. Does it talk to a remote service? → Pattern 9.
9. Is there a manual playbook to absorb? → Pattern 10.
10. Is the install pipeline curl-pipe-bash? → Pattern 11.
11. Are we doctoring a *skill*? → Pattern 12.

Most real projects match 1–3 patterns simultaneously (e.g., `caam` is Patterns 2, 5, 7, 9 — a multi-binary AI-agent installer that talks to vendor APIs). Apply the per-pattern adjustments additively; the canonical surface is the union, with conflicts resolved by Phase 3's synthesizer.
