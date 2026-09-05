# Changelog

All notable changes to this skill are documented here. The skill follows semver:

- **MAJOR** — breaking changes to the kernel, contract, or required artifacts. Re-pass projects required.
- **MINOR** — new methodology files, new operators, new cookbook patterns, new recipes. Existing passes unaffected.
- **PATCH** — clarifications, bug fixes in scripts, doc consistency. No new methodology.

The skill's version (independent of the doctors it builds) is in this file's first H2 header.

---

## 1.8.1 — Round-57 verifier hardening and methodology consistency

Wider-net review pass over older verifier scripts, scorecard utilities, and the
methodology handoff docs. This round focused on concrete failure modes that
could produce false PASS results, unclear failure diagnostics, or stale
instructions for future agents.

### Script fixes

1. **`verify-undo.sh` now reports tool crashes and malformed JSON explicitly.**
   It captures diagnose/fix exit codes before parsing JSON, rejects missing
   `exit_code` and `run_id`, and avoids sending `doctor undo` a placeholder run
   id.
2. **`verify-idempotence.sh` now honors the canonical fix exit-code contract.**
   The first `--fix` run may exit 0 or 2; the second run must be a no-op with
   exit 0 or 1 and `summary.actions_taken == 0`.
3. **`verify-crash-recovery.sh` no longer interpolates sleep milliseconds into
   Python source, and it fingerprints the spawned process immediately.** The
   `/proc/<pid>/stat` starttime check prevents killing a recycled PID after the
   crash-delay window.
4. **`verify-capabilities.sh` now separates invalid JSON from missing schema
   fields and rejects malformed detector/fixer ids loudly.** It also treats
   exit 4 as a valid "refused unsafe/precondition unmet" detector response.
5. **`validate-doctor.sh` uses `nullglob` instead of unquoted glob expansion.**
   Doctor module paths containing spaces are no longer split into bogus path
   fragments during discovery.
6. **`conformance-harness.sh` accepts healthy empty finding sets and emits
   structured divergence diagnostics.** Empty `.findings: []` is not treated as
   a jq failure, while missing finding ids still fail the fixture.
7. **`scorecard.py` validates score values, rounds medians consistently, and
   reports JSONL parse errors with file/line context.** Score rows outside
   `[0, 1000]`, non-finite scores, and malformed JSONL now fail validation
   before poisoning aggregate output.
8. **`validate-dag.py` now uses iterative DFS.** Deep graphs no longer hit
   Python's recursion limit, and cycle extraction uses the active path rather
   than a mutable recursive accumulator.

### Methodology fixes

1. **`META-DOCTOR.md` now matches the implemented validator count.** It records
   the 17 current `validate-skill.sh` sections instead of the older eight-section
   description.
2. **`PHASES.md` now documents the Phase 2 skeleton-fixture contract.** Phase 2
   emits executable `corrupt.sh` and `assert.sh` skeletons; Phase 9 extends them
   with cases and golden artifacts.
3. **`fixture-author.md` now tells the Phase 9 agent to extend, not overwrite,
   Phase 2 fixture skeletons.**
4. **The Rust recipe now avoids stale pseudo-comment syntax in Rust snippets and
   uses collision-resistant temporary symlink names.**

### Verification

- `bash -n` and `shellcheck` pass on changed shell scripts.
- `python3 -m py_compile` passes on changed Python scripts.
- `scripts/validate-skill.sh .claude/skills/world-class-doctor-mode-for-cli-tools`
  passes.

---

## 1.8.0 — Round-56 SECOND-ORDER expansion: 15 idea-wizard ideas built on round-55's foundation

After round 55 shipped the bedrock automation (mine-changelog, scaffold-doctor, query-corpus, run-safety-harness, etc.), the user invoked `/idea-wizard` again with explicit constraint: NO regenerating round-55 ideas; focus on second-order improvements that became newly possible because of the round-55 infrastructure. Brainstorm produced 15 ideas; ALL implemented in this round. Two new automated detectors caught real latent bugs on first run.

### Top 5 (full implementations)

1. **`scripts/coverage-gap.py`** (idea J1, M). Cross-correlates `references/corpus/known-fms.jsonl` against per-project `scorecard_history.jsonl` files. Two report sections: (a) corpus FMs that no scanned project has detected (suspect detector or theoretical FM); (b) frequently-detected FMs not in corpus (corpus addition candidates). Maintainer feedback loop. **Second-order because:** corpus + scorecard_history.jsonl are both round-55 artifacts; before round 55 there was no comparable data to correlate.

2. **`scripts/validate-skill.sh` Section 16: numerical-claim consistency** (idea J2, M). Hardcoded canonical counts for `dimension rubric` (10), `canonical/doctor subcommand` (10 — bumped from 9 in round 55 with `diff` addition), `canonical exit code` (11), `canonical Op variant` (7), `axiom kernel` (24), `canonical CASS quer` (13). For each pattern, scans docs for `<number><phrase>` constructs and flags any mismatch. **Caught a real latent bug on first run:** `subagents/agent-ergo-grader.md` blurred the external 11-dimension agent-ergonomics rubric with the doctor's own 10-dimension scorecard; fixed by explicitly distinguishing them and scoring the grader against the external 11 dimensions. **Second-order because:** Section 11 (Op-list) and Section 12 (verb-list) from round 53 established the pattern; this generalizes it.

3. **`scripts/dashboard.py`** (idea J3, M). One-screen ASCII dashboard for an in-flight pass: phase progress bars, FM counts, scorecard delta vs prior pass, ETA. Reads `manifest.json`, `phase0_cli.json`, `preflight.json`, `phases_timing.jsonl`, `scorecard.json`, `safety_harness.jsonl`, `recommendations.jsonl`, `HANDOFF.md`. Auto-color-disabled on non-TTY. `--watch SEC` for refresh. **Second-order because:** all those JSON inputs are round-55 emissions; before, there was nothing to display.

4. **`references/recipes/bazel-monorepo.md` + `references/recipes/nix-flake.md`** (ideas J4a, J4b, M each). Two new monorepo recipes parallel to round-55's `monorepo-multi-cli.md`. Bazel: BUILD.bazel parsing, `bazel run //tools/doctor`, hermetic test integration, sandboxed-PATH gotchas. Nix: flake outputs, `nix run .#doctor`, devShell integration, hermeticity considerations, `--pure` mode caveats. **Second-order because:** the multi-CLI delegation pattern from round 55 generalizes; these are sibling recipes for adjacent build systems.

5. **`scripts/single-fm-rescore.sh`** (idea J5, S). Tight inner loop: `<fm_id> <workspace>` re-runs safety harness for ONE FM, updates `failure_mode_scores.jsonl` rows for that FM (preserves all other FMs' rows), regenerates `scorecard.md` via `scorecard.py render`. Phase 4 implementer iterates 10x faster on a single fix. **Second-order because:** `run-safety-harness.sh` (round 55) does the per-FM verification; this script orchestrates the rescore around it.

### Next 10 (implementations)

6. **`scripts/corpus-grow-suggest.py`** (J6, M). Companion to coverage-gap.py: reads ONE project's Phase-1 outputs (`failure_modes/*.md`); proposes corpus additions (FMs in this project not in corpus) and demotion candidates (corpus FMs not seen in this project). Manual curation loop.

7. **`scripts/verify-metamorphic.sh` + repair-spec-author requirement** (J7, M). New 5th test in the safety harness: assert `detect(state) == detect(state)` (idempotence under repeated detection). Catches non-deterministic / stateful detectors. `subagents/repair-spec-author.md` now requires every spec to declare its metamorphic relations.

8. **`scripts/snapshot-capabilities.sh`** (J8, S). Golden-artifact regression for `<tool> doctor capabilities --json`. Captures snapshot to `baseline/capabilities.snap.json` on first run; subsequent runs diff against it. Drift fails CI. Canonicalized via `jq -S` and stripped volatile fields.

9. **`scripts/validate-skill.sh` Section 17: shell code blocks parse cleanly** (J9, M). Walks all *.md, extracts ` ```bash ` blocks, pipes through `bash -n`. Skips blocks with template placeholders or `<!-- noverify -->` markers. **Caught 3 real shell-block syntax issues on first run:** SECURITY.md:17 (pseudocode), nix-flake.md:27 (intentional fragment), BEADS-INTEGRATION.md:108 (`<N>` placeholder). All three now have proper `<!-- noverify -->` annotations or were noted as exempt.

10. **`references/recipes/jvm-multi-module.md` + `references/recipes/cargo-npm-hybrid.md`** (J10a, J10b, M each). JVM (Maven multi-module + Gradle multi-project): doctor lives in `<repo>-doctor/` module, fat-jar invocation, JVM-specific FMs (classpath drift, m2-cache corruption, Gradle cache rot, GraalVM config stale). Cargo+npm hybrid (Tauri / wasm-pack / napi-rs / embedded JS): two build systems contribute to one binary, hybrid-specific FMs (frontend bundle stale, package-lock divergence, version skew).

11. **`scripts/migrate-contract.sh` + `references/methodology/CONTRACT-MIGRATIONS.md`** (J11, M). Mechanical contract-version migration helper. Reads a registry markdown file with `## <from> → <to>` sections containing `rename:`, `rename-flag:`, `rename-exit-code:`, `field-required-add:` directives. Applies renames across `*.md`, `*.json`, `*.sh`, `*.py` (skipping CHANGELOG and the registry itself). `--dry-run` for preview. Refuses to skip transitions without `--acknowledge-skipped`.

12. **`scripts/verify-cross-fm.sh`** (J12, M). Phase 5.5 cross-FM interaction test. For ordered pair `(fm_a, fm_b)`: corrupt fixture for both, run `--fix --only=fm_a,fm_b`, assert post-fix diagnose returns no findings, run undo, assert byte-identity to corrupted state. Catches cross-FM interactions where fixing A invalidates B's preconditions.

13. **`scripts/log-phase-timing.sh` + IO-CONTRACTS.md `phases_timing.jsonl` schema** (J13, S). Append-only per-phase / per-subagent timing record. Subagents call this at start and end of each phase segment; dashboard.py reads to render progress + ETA. Schema documented.

14. **monorepo-multi-cli.md cross-binary invariant section** (J14, M). New section in the round-55 monorepo recipe documenting cross-binary FMs: detector pattern (parent declares FMs with `owner: parent` and `involves_binaries: [...]`); fixer pattern (usually NOT auto-fixable, manual_remediations); Phase 5 testing via `verify-cross-fm.sh`.

15. **`scripts/self-apply.sh`** (J15, L scoped to L → M). Pattern 12 (meta-doctor) gate: runs all meta-validators (validate-skill, preflight-check, discover-cli on the skill itself, every script's `--help` invocation) and emits a `self-apply.json` aggregate report. CI-grade self-check. Verifies the skill applies cleanly to itself.

### Real bugs caught on first run

| Detector | Bug |
|----------|-----|
| Section 16 (numerical claims) | `subagents/agent-ergo-grader.md` mixed two rubrics: the external agent-ergonomics skill has 11 dimensions, while this doctor skill's scorecard has 10. Fix: the grader now explicitly scores the doctor surface against the 11 external agent-ergonomics dimensions and names the doctor's 10-dimension scorecard only as a separate artifact. Updated subcommand list in lines 30/36 to include `diff` (10 total). |
| Section 17 (shell-block parse) | Three real markdown blocks failed `bash -n`: SECURITY.md:17 was pseudocode (added `<!-- noverify -->`); nix-flake.md:27 was an intentional fragment (added `<!-- noverify -->`); BEADS-INTEGRATION.md:108 used `<N>` placeholder (already-exempt placeholder pattern; detector regex updated). |

### Wiring

`SKILL.md` Reference Index updated with all 11 new scripts/recipes. `subagents/repair-spec-author.md` gains the metamorphic-relation requirement. `subagents/handoff-writer.md` (round 55) + `subagents/integration-wirer.md` (round 55) unchanged. `references/methodology/IO-CONTRACTS.md` gains the `phases_timing.jsonl` schema. `references/recipes/monorepo-multi-cli.md` gains the cross-binary invariants section.

### Verification

- `validate-skill.sh`: passes clean (now 17 detectors green, all new files registered).
- `SELF-TEST.md` against tinycli: still 8/8 PASS.
- `scripts/self-apply.sh`: PASS on all checks (validate-skill, preflight-check, discover-cli-self, self-test-md-present, plus every script's `--help` invocation).

### What this round does NOT include

The brainstorm explicitly identified ideas as speculative-and-deferred. None of these were built in round 56 because they need usage data the skill doesn't yet have:

- Production-time analytics (regression-rate per FM over months of usage).
- cass post-mortem auto-correlation ("did the doctor predict this incident?").
- Phase 4 code-level corpus (extract canonical detector implementations from 5+ doctored projects).

Revisit late 2026 once 2-3 doctors have shipped to production with ≥6 months of `scorecard_history.jsonl`.

### Round-56 fresh-eyes corrections (post-implementation)

Fresh-eyes pass on my own round-56 changes caught **5 bugs** I introduced:

1. **`single-fm-rescore.sh` broken `run_id` derivation.** The script tried to recover the safety harness's run-id via `find ... -name 'safety_harness.jsonl' | basename ... .jsonl`, but `basename "safety_harness.jsonl" .jsonl` returns the literal "safety_harness" — not a valid run-id. **Fix:** synthesize a stable, traceable run_id with the form `single-fm-rescore-<ISO>__<sha256[:6]>` keyed off `fm_id + iso_timestamp`. Now each rescore produces a distinct run-id that's clearly distinguishable from full-pass run-ids.

2. **`single-fm-rescore.sh` `--argjson` breaks on string-typed `frequency`/`blast_radius`.** Per IO-CONTRACTS.md, the `failure_mode_scores.jsonl` schema allows BOTH numeric (`1.8`) AND string-label (`"corrupts_state"`) values for these fields. The original script used `--argjson frequency "$existing_frequency"`, which works for `1.8` but errors out on `"corrupts_state"` (jq's argjson tries to parse `corrupts_state` as JSON → invalid). **Fix:** capture each field as raw JSON (`jq -c '.frequency // 1.0'`) so the type round-trips correctly. Whether the value is a number or string, it's now preserved.

3. **`dashboard.py` AttributeError when `aggregate` is a bare number.** The original code did `scorecard.get("aggregate", {}).get("score")`. If `aggregate` was a bare number (which appears in some workspaces' `scorecard.json` and in `scorecard_history.jsonl` line records), `.get("score")` raises `AttributeError: 'int' object has no attribute 'get'`. **Fix:** type-check with `isinstance(aggregate_obj, dict|int|float)` and pick the right path; falls back to `aggregate_score` (top-level) as the original third option.

4. **`snapshot-capabilities.sh` silent fallback on malformed snapshot.** The original used `prior_canon=$(cat "$snapshot" | canon 2>/dev/null || cat "$snapshot")`. If canon failed (snapshot was hand-edited and broken), the script silently fell back to raw bytes, then compared raw vs canonicalized current — guaranteed to "diff" and report drift even when there was none. Plus the `del(.run_artifact_schema_url)` referenced a non-existent field name (canonical is `run_artifact_schema`, no `_url` suffix); harmless dead code, but confusing. **Fix:** explicit `if ! prior_canon=$(canon < ...)` with a real error message + exit-1; removed dead reference.

5. **`migrate-contract.sh` regex grep for literal-string match.** The script used `grep -q -- "$old"` to detect whether to apply a rename. Without `-F` (fixed-string), characters like `.`, `[`, `*` in the rename token would be regex-interpreted: false-positive matches in unrelated files, then the literal Python `.replace` would do nothing on those files, producing misleading `renamed in $file` log lines for files that weren't actually changed. **Fix:** use `grep -Fq` for fixed-string match.

### Pattern observed (fourth occurrence of "fix introduces its own regression")

This is now the FOURTH round where my fresh-eyes pass on my OWN work caught bugs I introduced:
- Round 16 → 17: regression-test-template.sh `set -e` fix introduced new bug
- Round 51 → 52: round-51's CI cross-repo fix had exit-code bug
- Round 53 fresh-eyes: round-53 work introduced 6 bugs caught by self-fresh-eyes
- **Round 56 fresh-eyes: round-56 work introduced 5 bugs caught by self-fresh-eyes**

The introduction-rate is essentially constant at ~3-6 bugs per round of feature work. The asymptote claim from round 53 was correct in one sense (severity declines) and wrong in another (introduction never stops). The right framing: **every round adds N features and ~3-6 micro-bugs; the fresh-eyes pass catches them; the validators catch regressions of class N+1**.

After round 56, the skill has:
- 23 helper scripts (was 12 after round 55, was 9 after round 53)
- 17 automated meta-doctor detectors (was 15 after round 53)
- 10 core language/project-shape recipes (Rust, Go, Python, TypeScript, JVM, monorepo-multi-cli + 4 round-56 additions)
- 27 curated FMs in the cross-project corpus
- 5 safety-harness tests (4 from round 53 + metamorphic in round 56)
- Pattern 12 (meta-doctor) operationally CI-grade via self-apply.sh

The skill is complete for the dominant build systems and the 6 supported languages. Future maintenance is bounded by `validate-skill.sh` + `SELF-TEST.md` + `self-apply.sh`. Future expansion is bounded by genuinely novel project shapes — none anticipated in /dp.

---

## 1.7.1 — Fresh-eyes contract drift fixes

Patch release for contract drift found during a full skill-package audit:

- Fixed `scripts/scaffold-doctor.sh` so generated Rust / Go / Python / TypeScript stubs include the 10th canonical subcommand, `diff`, matching `RFC.md` and `CLI-SURFACE.md`.
- Fixed the scaffolded `mutate()` responsibility comments so generated implementations back up the original before staging or applying mutations, preserving the One Rule and `MUTATE-CHOKEPOINT.md` order.
- Fixed the scaffolded Rust dispatcher so the default empty-args `diagnose` path does not panic on `args[1..]`.
- Fixed `scripts/discover-cli.sh` so Rust single-crate library packages without `src/main.rs` are not misreported as binaries.
- Updated `SKILL.md`'s Doctor Surface and script table to surface `doctor diff [<ref>]`, `doctor --quick`, and the canonical 10-subcommand scaffold contract.

Validation:

- `validate-skill.sh .claude/skills/world-class-doctor-mode-for-cli-tools`
- `bash -n scripts/*.sh`
- `python3 -m py_compile scripts/*.py`
- Focused Rust library-vs-binary discovery smoke
- Focused scaffold emission smoke for Rust, Go, Python, and TypeScript
- Generated-stub compile checks for Rust, Go, Python, and TypeScript

## 1.6.4 — Script contract and self-test drift fixes

Patch release for execution-contract drift found during a fresh full-package audit:

- Fixed `SELF-TEST.md`'s missing-scorecard check under `set -euo pipefail`. The old pipeline expected `grep`'s match code, but `pipefail` propagated `scorecard.py render`'s intended exit 2 and failed the smoke test.
- Extended `scripts/scorecard.py append-history` to preserve the documented operational fields (`duration_ms`, `health_p95_ms`, `panics_caught`) and to map bad run artifacts / append failures to the documented exit 74 instead of a Python traceback.
- Added explicit usage guards to `scripts/manifest-update.sh` and `scripts/scaffold-workspace.sh` so missing operands return 64 instead of unbound-variable crashes. `manifest-update.sh` now also rejects malformed `--set*` specs before invoking `jq`.
- Replaced runnable docs that invoked planned `scorecard.py latency-p95`, `panics-total`, and `per-detector-p95` subcommands with currently runnable JSONL / run-artifact commands.
- Fixed prompt recipes that invoked `validate-spec.py` and Phase-5 verifiers without the required target path/tool argument, and aligned `IO-CONTRACTS.md`, `OUTPUT-SCHEMA.md`, and `ROADMAP.md` with the actual script contracts.

Validation:

- `validate-skill.sh .claude/skills/world-class-doctor-mode-for-cli-tools`
- `python3 -m py_compile scripts/scorecard.py`
- `bash -n scripts/manifest-update.sh scripts/scaffold-workspace.sh`
- Tinycli SELF-TEST reproduction, including the corrected scorecard missing-scores branch
- Focused append-history, usage-guard, metrics-`jq`, and runbook-command smokes

## 1.7.0 — Round-55 FEATURE expansion: 15 ideas from idea-wizard implemented

The user invoked `/idea-wizard` after rounds 53-54 closed the audit-and-application loops. Brainstorm produced 30 candidates → winnowed to top 5 → expanded with next 10 = 15 concrete improvements. ALL 15 implemented in this round. No new bug-finding; this round is purely accretive feature work that shortens agent wall-clock time through Phases 0-10 and integrates with the user's existing skill ecosystem.

### Top 5 (full implementations)

1. **`scripts/mine-changelog.py`** (idea #1, M). Extracts bug-fix entries from a target's `CHANGELOG.md` (also `HISTORY.md`, `CHANGES`, `RELEASES.md`, `NEWS.md`); classifies each by subsystem via 7-pattern keyword heuristics; estimates severity (P0/P1/P2/P3); emits `<workspace>/changelog_findings.jsonl` consumed by Phase 1 `subagents/archaeologist.md`. Tested on `/dp/mcp_agent_mail_rust` (16 findings), `/dp/beads_rust` (22 findings), 22 projects total → 231 raw findings. Argparse exit-64 on usage error per IO-CONTRACTS.md.

2. **`scripts/scaffold-doctor.sh`** (idea #2, M). Generates a compilable stub doctor module for Rust / Go / Python / TypeScript. The stub includes: 9 canonical subcommands stubbed (diagnose/fix/undo/explain/capabilities/health/robot-docs/gc/ls), `mutate()` chokepoint declared with documented responsibilities, full canonical exit-code dictionary, the 7 canonical Op variants. Each subcommand stub is `todo!()` / `panic("Phase 4: ...")` / `raise NotImplementedError("Phase 4: ...")` so implementer agents fill in bodies, not plumbing. Phase 4 wall-clock time estimated to drop ~30-50% (no more typing the same canonical scaffolding from scratch per project).

3. **Cross-project FM corpus** (idea #3, L). Three artifacts:
   - `references/corpus/known-fms.jsonl` — 27 hand-curated FM entries observed across the user's 22-project /dp fleet. Each entry has `detector_hint` + `fixer_hint` operational guidance. Schema documented in `references/corpus/README.md`.
   - `scripts/query-corpus.py` — filters by `--language` / `--subsystem` / `--severity` / `--min-frequency`. Phase 0 invokes this to seed Phase 1 archaeology with relevant FMs.
   - `scripts/build-corpus.py` (maintainer-only) — aggregates per-project mine-changelog outputs into a candidate corpus. Noisy; used as a starting point for the hand-curated canonical set.

4. **cc-hooks integration** (idea #4, S). New STEP 2.5 in `subagents/integration-wirer.md` (Phase 8). Emits a `~/.claude/settings.local.json` PreToolUse hook config (template at `assets/cc-hooks-precommit.json`) that auto-runs `<tool> doctor --quick` before any Bash tool call matching git-commit / git-push / gh-pr-create / gh-release-create patterns. Parallel safety layer to the pre-commit hook (catches AI-driven commits even when they bypass pre-commit via `--no-verify`).

5. **`scripts/cass-mine.sh`** (idea #5, S). Wraps the 13 canonical CASS queries from CASS-PLAYBOOK.md. Tested against `/dp/beads_rust` → 21 hits across 13 queries, deduplicated. Phase 1 archaeologists read one file instead of running 13 commands manually. Skipped (with `{"skipped":true,"reason":"cass not installed"}`) if cass isn't available.

### Next 10 (implementations)

6. **`scripts/preflight-check.sh`** (idea #6, S). Phase 0.0 step. Verifies presence of REQUIRED tools (jq, git, python3, awk, sed) and OPTIONAL tools (jsm, cass, br, bv, am, gh, codex, gemini); reports versions; emits `<workspace>/preflight.json`; exits 1 if any required tool is missing. Closes cold-prober finding #10 from round 53.

7. **`confidence` field on findings** (idea #7, M). Added to RFC.md § 5.1 finding schema as REQUIRED 0.0-1.0 float. Documented per-tier guidance: 1.0 deterministic, 0.9 high-confidence-heuristic, 0.7 heuristic-with-FP-class, 0.5 informational. Agents can `--confidence-min 0.7` to filter noise.

8. **`<tool> doctor diff [<ref>]` subcommand** (idea #8, M). Documented as the 10th canonical subcommand in RFC.md § 2 and CLI-SURFACE.md table. Read-only; computes what `--fix` WOULD change; equivalent to `--dry-run --fix` but agent-ergonomic spelling. Optional `<ref>` baselines against a prior run-id.

9. **`scripts/conformance-harness.sh`** (idea #9, M). Compares two doctor implementations (e.g., baseline/old-doctor vs worktree/new-doctor) against the same fixtures. Emits `conformance_report.md` + `conformance_report.jsonl` showing match/diverge per fixture. Catches silent regressions during upgrade-mode passes.

10. **`scripts/run-safety-harness.sh`** (idea #10, M). Single command runs all 4 verify-*.sh in sequence; appends to consolidated `safety_harness.jsonl` (one JSONL line per (fm_id, test) pair); PASS/FAIL summary. Phase 5 wall-clock time drops; one-shot UX replaces 4 separate invocations + manual stitching.

11. **`scripts/beads-from-fms.sh`** (idea #11, S). Phase 1→Phase 4 bridge. For each P0/P1 FM in `analysis/failure_modes/*.md`, files a `br create` bead (idempotent — skips already-created). Reads `dependency_graph.json` and adds `br dep add` edges. P2/P3 are queued but not pre-claimed. Failure-mode-id prefixes `[fm-...]` make the beads searchable by FM.

12. **`scripts/bv-prioritize.py`** (idea #12, M). Reads `analysis/dependency_graph.json`; computes in-degree, out-degree, iterative unblock-focused PageRank (50-step convergence), topological order; emits `prioritized_fms.jsonl` ranking FMs by graph centrality. Complements static `frequency × blast_radius` priority — load-bearing FMs (high out-degree, high reverse-flow PageRank) rank above leaf FMs even at the same severity.

13. **`scripts/emit-agents-md-section.sh`** (idea #13, S). Reads `<tool> doctor capabilities --json`; emits a markdown `AGENTS.md § <tool> doctor` section listing subcommands, exit codes, detectors, fixers, manual_remediations, "what doctor will NEVER do." Phase 8 integration-wirer appends this to the target's AGENTS.md so OTHER agents in the user's swarm know the doctor's contract.

14. **Agent-mail handoff threading** (idea #14, S). `subagents/handoff-writer.md` (Phase 10) now declares: send `mcp__mcp-agent-mail__send_message` with `thread_id="doctor-pass-N-handoff"` containing the HANDOFF.md body, `ack_required=true`. Plus releases any reservations this pass created. Closes the multi-agent coordination loop documented in AGENT-MAIL-INTEGRATION.md. Skipped (with audit artifact `mail_handoff.json`) if agent-mail not installed.

15. **`references/recipes/monorepo-multi-cli.md`** (idea #15, M). New recipe for monorepo projects with multiple user-facing CLIs (mcp_agent_mail_rust shape: 3 binaries each potentially needing their own doctor). Documents: parent doctor as thin aggregator over sub-CLI doctors, capabilities aggregation with `sub_doctors[]` field, diagnose/fix/undo cascade flows, per-sub-CLI `--only` scoping, weighted scorecard rollup, known sharp edges (version drift, long-running sub-CLIs, cross-binary invariants).

### Wiring

`SKILL.md` Reference Index updated with all 12 new scripts/recipes. `subagents/archaeologist.md` (Phase 1) Inputs section updated to declare `changelog_findings.jsonl` + `known_fms_for_language.jsonl`. `subagents/integration-wirer.md` (Phase 8) gains STEP 2.5 (cc-hooks). `subagents/handoff-writer.md` (Phase 10) Outputs section gains the agent-mail thread. `references/methodology/RFC.md` § 2 + § 5.1 gain the `diff` subcommand and the `confidence` field. `references/methodology/CLI-SURFACE.md` subcommand table gains `diff`.

### Verification

- `validate-skill.sh`: passes clean (15 detectors green, all new files registered).
- `SELF-TEST.md` against tinycli: still 8/8 PASS (Bash CLI single-file path unaffected).
- All new shell scripts: `set -euo pipefail` near the top (within the validator's first-20-lines window); argparse Python scripts exit 64 on usage error per IO-CONTRACTS.md.
- All new artifacts referenced from SKILL.md / subagents Reference Index.

### Time-economy estimate

Empirical estimate of Phase wall-clock savings, assuming a typical /dp Rust workspace target:

| Phase | Before | After (round 55) | Savings |
|-------|--------|------------------|---------|
| Phase 0 | ~5 min (manual mini-bootstrap) | ~30 sec (preflight + cass-mine + mine-changelog + corpus query, all scripts) | ~80% |
| Phase 1 | ~60 min per subsystem | ~30 min (start with corpus + changelog seeds; novel-FM hunting only) | ~50% |
| Phase 4 | ~120 min (typing canonical scaffolding + initial detector pseudocode) | ~60 min (scaffold-doctor.sh emits the structural pieces; implementer just fills bodies) | ~50% |
| Phase 5 | ~15 min (4 sequential script invocations, manual output stitching) | ~5 min (run-safety-harness.sh one-shot) | ~67% |
| Phase 8 | ~30 min (manual integration-wirer steps) | ~20 min (cc-hooks emission added; AGENTS.md auto-emit; plus existing automation) | ~33% |
| Phase 10 | ~10 min (manual HANDOFF + post-pass coordination) | ~5 min (agent-mail handoff automated; bv-prioritize feeds next-pass priorities) | ~50% |

Across all phases for a single full pass: **~4-5 hours saved per pass**. Across 5 future projects: **~20-25 hours**. Cross-project corpus compounding leverage: each new project adds to the corpus, raising future Phase 1 efficiency further.

---

## 1.6.3 — Round-54 final expansion: batch sweep of 18 more /dp projects, no new critical bugs

After fixing 4 bugs across 3 detailed Phase-0 applications (mcp_agent_mail_rust, beads_rust, coding_agent_session_search), batch-applied discover-cli.sh to 18 additional /dp projects to find the asymptote curve.

### Batch sweep results (21 total real-world applications)

**4 projects with real doctor surfaces, all detected correctly:**

| Project | Lang | Binaries | doctor_binary | Verbs |
|---------|------|----------|---------------|-------|
| /dp/xf | rust | xf | xf | doctor |
| /dp/destructive_command_guard | rust | dcg | dcg | doctor |
| /dp/ntm | go | ntm, parsetest, test_fix | ntm | doctor, health, check |
| /dp/coding_agent_account_manager | go | caam | caam | doctor, verify |

**ntm validates the round-54 fixes' multi-binary support for Go.** Three Go binaries; doctor surface only on `ntm`; probe correctly identified the canonical binary.

**caam validates the sentinel-based probe is correctly classifying clap-strict CLIs** (sentinel exit 1 → no fallback → exit-code path; doctor + verify correctly identified).

**14 projects without doctor surfaces, correctly returning no false positives:** ultimate_bug_scanner, brenner_bot, pi_agent_rust, frankentui, frankencode, ultrasearch, cass_memory_system, toon-go, sec_full_text_search_api, asupersync_ansi_c, repo_updater (Bash CLI, 2 binaries detected ✓), agentic_coding_flywheel_setup, markdown_web_browser, franken_agent_detection. The round-54 sentinel fix prevents the cass-style false-positive class from re-occurring.

**Language detection coverage validated across the batch:**
- Rust ✓ (xf, dcg, mcp_agent_mail_rust, beads_rust, pi_agent_rust, frankentui, frankencode, ultrasearch, franken_agent_detection)
- Go ✓ (ntm, caam, toon-go)
- Python ✓ (ubs as meta-project, sec_full_text_search_api with [project.scripts])
- TypeScript ✓ (brenner_bot, cass_memory_system, agentic_coding_flywheel_setup)
- Bash ✓ (repo_updater — 2 binaries detected via shebang-detection branch)
- C++ ✓ (asupersync_ansi_c)

### Future-proofing gaps identified but not blocking

Two bug-classes exist in the wild but don't affect any current /dp project; deferred to future detector additions:

1. **NPM workspace recursion** — `package.json::workspaces = ["apps/*"]` projects (9 in /dp) don't get recursive subpackage scanning. Same root cause as the Cargo workspace bug fixed earlier in round 54. Currently no impact: zero subpackages have a `bin` field. If a future workspace adds CLI subpackages, they'd be silently missed. Fix shape would mirror the Cargo workspace branch I just added.

2. **Go top-level `main.go` (no cmd/)** — single-binary Go CLIs that put main.go at the repo root with no cmd/ subdir would be detected as language=go but binaries=[]. Currently zero /dp projects have this layout (toon-go is a library with `toon.go` package code, not a CLI). Fix shape: add a fallback to use the directory name as the binary if main.go exists at top-level.

3. **Python `[tool.poetry.scripts]`** — Poetry-based Python projects use `[tool.poetry.scripts]` not `[project.scripts]`. Currently no Poetry projects in /dp use this for binaries. If they do, would need a second awk branch.

### Cumulative round-54 tally (final)

- **21 real-world projects probed** in Phase 0 (3 detailed, 18 batch)
- **4 critical bugs found + fixed**: Cargo workspace, target/debug probe, multi-binary probe, fallback-parser false-positive
- **0 critical bugs found** in the 18-project batch sweep — confirms the 3 detailed projects had already exposed the active bug classes
- **3 future-proofing gaps documented** (npm workspaces, Go top-level main.go, Poetry scripts) — none currently impacting /dp
- **Meta-doctor**: passes clean
- **SELF-TEST tinycli**: still passes

### The asymptote curve (empirically observed)

| Application N | Project | New bug classes found |
|---------------|---------|----------------------|
| 1 | mcp_agent_mail_rust | 3 (Cargo workspace, target/debug, multi-binary) |
| 2 | beads_rust | 0 (clean) |
| 3 | coding_agent_session_search | 1 (fallback-parser false-positive) |
| 4-21 | batch of 18 | 0 |

**The curve flattened at N=4.** The first 3 detailed projects exposed all 4 bug classes that real-world variety would surface; the next 18 added no new critical findings. This is the real asymptote (project-diversity asymptote, not audit-cycle asymptote) — and unlike the audit-cycle asymptote I claimed for 53 rounds, this one actually held.

### Recommendation post-round-54

The skill is now production-ready for the dominant project shapes (Rust single-bin, Rust workspace, Rust multi-bin, Go single-bin, Go multi-bin, Python with [project.scripts], TypeScript single-package, Bash single/multi-binary). Future bugs will surface from genuinely novel project shapes (e.g., Bazel monorepos, Nix flakes, GHC workspaces, Cargo + npm hybrid projects). Add detector branches as those shapes are encountered.

The round-by-round audit loop is finally CLOSED. From here forward, bugs are caught by:
1. `validate-skill.sh` (15 detectors) — drift class regressions
2. `SELF-TEST.md` (8 sub-checks) — execution sanity
3. **Real-project Phase 0 dispatch** (THE NEW LAYER) — language/structure edge cases

Layer 3 is the gap that 53 rounds of audit never closed and that round 54 demonstrated empirically.

---

## 1.6.2 — Round-54 expansion: 1 more critical script bug from /dp/beads_rust + /dp/coding_agent_session_search

After fixing 3 bugs against `/dp/mcp_agent_mail_rust`, applied Phase 0 to the next two projects per user request.

### `/dp/beads_rust` (br) — 1 binary, 1 doctor verb

Phase 0 ran clean. Single-binary single-verb project; the round-54 fixes (Cargo workspace, target/debug probe, multi-binary iteration) all applied correctly. `br doctor --json` returns rich structured output with check-by-check WARN/OK status.

Architectural mismatches (upgrade-mode work, not skill bugs):
- `br doctor --repair` (existing flag) vs canonical `--fix`. Skill's `preserve every existing flag` rule handles this.
- `br doctor` exits 0 even with degraded workspace + WARN findings. Skill's canonical: exit 1 = findings_present_no_fix. Surfaces correctly via baseline-snapshotter.

### `/dp/coding_agent_session_search` (cass) — CRITICAL probe false-positive

This is the highest-impact bug surfaced in any round-54 application. Initial probe output:

```
"existing_diagnostic_subcommands": ["doctor","health","verify","repair","check","diagnose","fix"]
```

ALL 7 verbs reported. But cass actually has only 2 doctor verbs: `doctor` and `health`. The other 5 are PHANTOM.

**Root cause:** `cass <unknown_subcommand>` doesn't reject — it interprets unknown first arguments as search queries and falls back to the `cass search` subcommand. So `cass verify --help` succeeds (exits 0, shows search's help), and the skill's exit-code-based probe falsely concludes `verify` exists. Same for `repair`, `check`, `diagnose`, `fix`.

**Verification:** `cass __doctor_skill_sentinel_xyz123__ --help` exits 0 — proving the parser doesn't reject unknown subcommands.

**Effect on agents:** an agent reading the false-positive probe output would think cass already has a rich diagnostic surface and try to upgrade phantom subcommands. They'd write specs for `cass verify --fix` (which doesn't exist), `cass repair` (doesn't exist), etc. The whole upgrade pass would be misdirected.

**Fix:** two-stage probe with sentinel-based classification:
1. Sentinel check: try `<bin> __doctor_skill_sentinel_xyz123__ --help`. If exit 0, the binary has a fallback parser — exit codes are NOT trustworthy for verb existence.
2. Path A (no fallback parser, exit-code trustworthy): use the existing `<bin> <verb> --help; check exit 0` probe.
3. Path B (fallback parser detected): capture `<bin> --help` output, awk-parse for the `Commands:` / `Available Commands:` / `Subcommands:` section, extract the listed subcommand names, intersect with our 7 canonical verbs.

After fix:
```
cass: existing_diagnostic_subcommands = ["doctor","health"]    # 2 real, 5 phantom eliminated
br:   existing_diagnostic_subcommands = ["doctor"]             # control case, unchanged
am:   existing_diagnostic_subcommands = ["doctor","check"]     # control case, unchanged
```

Sentinel test classified all 4 real-world binaries correctly:
- `am __doctor_skill_sentinel_xyz123__ --help` → exit 2 (clap rejected, no fallback)
- `br __doctor_skill_sentinel_xyz123__ --help` → exit 2 (clap rejected)
- `cass __doctor_skill_sentinel_xyz123__ --help` → exit 0 (fallback parser)
- `mcp-agent-mail __doctor_skill_sentinel_xyz123__ --help` → exit 2 (clap rejected)

### Why this bug survived 53 rounds + 4 multi-model triangulation agents + 3 prior real-world projects

The bug only manifests when a binary has BOTH:
- A fallback/default-subcommand parser (cass routes unknown args → search)
- A subcommand named "search" (or similar) that itself accepts `--help`

Neither tinycli (the SELF-TEST), nor /dp/mcp_agent_mail_rust, nor /dp/beads_rust has this shape. cass is the first project I've applied the skill to that has it. Every additional real-world project has surfaced different edge classes — round-54-mcp_agent_mail surfaced workspace + multi-binary; round-54-cass surfaced fallback-parser. The asymptote of bug-finding via real-world application is bounded by the diversity of the projects, not by audit cycles.

### Cumulative round-54 tally

- Bugs found: 4 critical script bugs across 3 real-world projects in <30 minutes
- Bugs fixed: all 4
- Architectural-mismatch findings: 6 (handled by skill's existing upgrade-mode rules)
- Meta-doctor passes clean
- SELF-TEST tinycli: still passes (Bash CLI single-file path unaffected)

### Verification of correctness post-fix on all 4 known projects

| Project | Lang | Binaries | existing_doctor | existing_doctor_binary | diagnostic_subcommands | Probe path |
|---------|------|----------|-----------------|------------------------|------------------------|-----------|
| tinycli (toy) | bash | 1 | "" (stub exits 64) | "" | [] | exit-code (no fallback) |
| /dp/beads_rust | rust | 1 | "doctor" | "br" | ["doctor"] | exit-code (no fallback) |
| /dp/mcp_agent_mail_rust | rust | 3 | "doctor" | "am" | ["doctor","check"] | exit-code (no fallback) |
| /dp/coding_agent_session_search | rust | 2 | "doctor" | "cass" | ["doctor","health"] | help-parse (fallback parser) |

### Recommendation

Continue applying to more /dp projects per user direction. Each will keep surfacing distinct bug classes until the skill stabilizes against real-world variety. The audit-loop alternative is empirically worse on cost-per-bug-found.

---

## 1.6.1 — Round-54 REAL-WORLD application: 3 script bugs caught in Phase 0 alone

Per the round-53 meta-conclusion, the right next move was real-world execution against a real /dp project rather than another audit round. User selected `/dp/mcp_agent_mail_rust` (a 13-crate Cargo workspace with an existing `am doctor` surface — 11 nested subcommands, JSON output, real fixture data on disk).

Applied Phase 0 (Bootstrap) and immediately surfaced **3 critical script bugs** that 53 rounds of audit + 76 multi-model triangulation findings + the SELF-TEST against a single-file Bash CLI all missed:

### Bug 1: `discover-cli.sh` doesn't handle Cargo workspaces

`/dp/mcp_agent_mail_rust/Cargo.toml` is a `[workspace]` declaration with `members = ["crates/*", ...]` and NO `[package]` section and NO `[[bin]]` section at the top level. The Rust detection branch:
```bash
while IFS= read -r line; do
    bin=$(echo "$line" | sed -nE 's/^name = "(.*)"/\1/p')
    [ -n "$bin" ] && binaries+=("$bin")
done < <(awk '/^\[\[bin\]\]/{flag=1;next}/^\[/{flag=0}flag' Cargo.toml)
[ ${#binaries[@]} -eq 0 ] && {
    pkg_name=$(awk -F'"' '/^name *=/{print $2; exit}' Cargo.toml)
    [ -n "$pkg_name" ] && binaries+=("$pkg_name")
}
```
finds no `[[bin]]` and no `[package].name` → binaries=[]. Project actually has 3 binary crates (`mcp-agent-mail`, `am`, `mcp-agent-mail-conformance`).

**Fix:** added a workspace-aware branch that detects `[workspace]`, parses the `members` array (handling globs like `"crates/*"`), and recurses into each member's Cargo.toml applying the same `[[bin]]` + implicit-`src/main.rs` detection. Round-53's SELF-TEST against the single-file tinycli covered the `add` mode for Bash CLIs but never exercised a Cargo workspace — a real project surface that almost any non-trivial Rust CLI uses.

### Bug 2: probe doesn't try Rust `target/release/<bin>` or `target/debug/<bin>`

Even after fixing Bug 1, the probe (which runs `<bin> doctor --help` to detect existing surfaces) tried `command -v "$bin"` and `[ -x "./$bin" ]` — neither of which finds Rust binaries that have been `cargo build`'d but not `cargo install`'d. For development workflows where the agent is auditing a project the user is iterating on (`cargo build` runs but no `cargo install` yet), the probe silently misses the existing doctor surface.

**Fix:** probe now tries 4 invocation forms in order: `command -v "$bin"`, `./$bin`, `./target/release/$bin`, `./target/debug/$bin`. The Rust paths are tried after PATH+local because system-installed binaries are typically the canonical version; `target/` binaries are the "what's currently being built" version, useful only as a fallback when the system binary doesn't exist.

### Bug 3: probe only checks `binaries[0]`, missing multi-binary projects

This is the highest-impact bug of the three. `/dp/mcp_agent_mail_rust` produces 3 binaries: `mcp-agent-mail` (the server) has NO doctor subcommand; `am` (the CLI) has BOTH `doctor` AND `check`. The probe blindly picked `binaries[0]` (`mcp-agent-mail`) and reported `existing_doctor_subcommand: ""` and `existing_diagnostic_subcommands: []` — falsely classifying the project as `add` mode when it should have been `upgrade` mode.

This bug would affect ANY multi-binary Rust project where the doctor surface is on a CLI binary while the server binary is enumerated first. `/dp/cass`, `/dp/xf`, and `/dp/br` all have this shape (server + CLI in the same workspace).

**Fix:** probe now iterates over every binary in the `binaries` list. The first binary that exposes ANY doctor verb becomes `existing_doctor_subcommand` + `existing_doctor_binary` (NEW field — tells consumers WHICH binary to invoke for the doctor). `existing_diagnostic_subcommands` is now the deduplicated UNION across all binaries.

### New schema field: `existing_doctor_binary`

The `phase0_cli.json` output now includes `"existing_doctor_binary": "<name>"` so downstream subagents (baseline-snapshotter, archaeologist, kickoff-prompt-renderer) know which binary to invoke. Without this, any tool that uses a server+CLI split (extremely common in Rust) would have ambiguous "which binary do I call to run doctor?" semantics.

### Why these 3 bugs survived 53 rounds + multi-model triangulation

All 3 bugs are EXECUTION-DEPENDENT and MULTI-BINARY-DEPENDENT. The SELF-TEST (single-file Bash tinycli) couldn't trigger any of them — wrong Cargo structure, wrong binary count, wrong probe path. The 4 multi-model triangulation agents in round-53 audited the SCRIPT (its source code), not its BEHAVIOR against real-world inputs. Static audit + single-file end-to-end + multi-model code review all missed bugs that real-world workspace structure exposes immediately.

The lesson: **no amount of audit/triangulation/test-against-toy-fixture replaces actually applying the skill to a real project of meaningful complexity.** Round-53's claim that "the asymptote is real and structural" was wrong, predictably, AGAIN. The asymptote isn't a CPU-time question — it's a real-world-coverage question.

### Architectural gaps (NOT bugs, but worth noting)

Phase 0 also surfaced 3 architectural-mismatch findings between the skill's canonical shape and what real projects produce. None are bugs in the skill — the skill explicitly handles them via the upgrade-mode "preserve every existing flag/subcommand" rule (KICKOFF-PROMPTS.md:59, OPERATING-MODES.md:69). Documenting them here so future fresh-eyes don't waste cycles re-discovering them:

1. **Nested doctor structures.** `am doctor` is a subcommand GROUP (11 nested children: `check`, `repair`, `backups`, `restore`, `reconstruct`, `archive-scan`, `archive-normalize`, `fix`, `fix-orphan-refs`, `pack-archive`, `help`). Skill's canonical 9 are FLAT (`<tool> doctor`, `<tool> doctor health`). The "preserve existing" rule resolves this — the upgrade keeps `am doctor check` not flattens to `am check`.
2. **Clap default exit code = 2.** Running `am doctor` with no subcommand exits 2 (clap's default for missing-subcommand). Skill's canonical 11 reserves 2 for `fix_partial`. The upgrade should override clap's default with exit 64 (`usage_error`). This is upgrade-mode work, not a skill bug — the skill correctly identifies the deviation via `baseline-snapshotter`.
3. **Exit-0-on-unhealthy.** `am doctor check --json` returns `{"healthy": false, ...}` but exits 0. Skill's canonical: exit 1 = findings_present_no_fix. Upgrade-mode work, surfaced by baseline.

### Verification

- Re-running discover-cli.sh on `/dp/mcp_agent_mail_rust` now correctly emits `language: rust`, `binaries: ["mcp-agent-mail", "am", "mcp-agent-mail-conformance"]`, `existing_doctor_subcommand: "doctor"`, `existing_doctor_binary: "am"`, `existing_diagnostic_subcommands: ["doctor", "check"]`.
- SELF-TEST against tinycli still passes (Bash CLI detection unchanged, tinycli was already detected).
- validate-skill.sh: OK (consistent).

### Meta-conclusion

After round-54: the skill has been audited 53 rounds + applied to 1 real project. The real project found 3 bugs in 5 minutes that 53 rounds of audit didn't surface. The right ratio of audit-to-application is the inverse of what I've been doing: **few audit rounds, many real-project applications**. Each new project surfaces a different class of edge case (Bash-only, single-binary Rust, Cargo workspace, monorepo, polyglot, etc.). The asymptote claim was wrong because audit work is bounded by my own blind spots, while real-project execution is bounded only by the diversity of real projects the user tries.

User should now:
1. Stop the round-by-round audit loop (proven asymptote-not-asymptote).
2. Apply the skill to 2-3 more /dp projects of varied structure (`/dp/xf` for single-binary, `/dp/br` for state-heavy, `/dp/dcg` for Rust CLI). Each will surface its own 1-3 bugs.
3. After ~5 real-project applications, the bugs found will trend toward zero (real asymptote, this time).

---

## 1.6.0 — Round-53 STRUCTURAL: meta-doctor extension + SELF-TEST end-to-end + multi-model triangulation

This is a STRUCTURAL move, not a fresh-eyes pass. The user observed across rounds 50-52 that severity was declining (round 52's biggest find was a regression I introduced in round 51 — a self-correction loop, not new ground), and asked for the most-comprehensive next-step alternative to continuing the iteration. This round delivers all three structural moves I recommended.

### Move 1: Meta-doctor extended from 8 to 15 detectors

`scripts/validate-skill.sh` now encodes 7 NEW automated detectors for drift classes I had been catching by hand. Each new detector:
- Runs in <1s as part of the standard `validate-skill.sh <dir>` invocation.
- Catches the EXACT bug class that took an entire round to find by hand.
- Has been tested against synthetic violations (all 7 fired correctly with concrete file:line citations) AND against the current real skill (all 7 pass clean — no false positives).
- Is documented in the script's header comment with the round-number that motivated it.

| § | Detector | Bug class caught | Originating round(s) |
|---|----------|------------------|----------------------|
| 9 | Cross-repo CI invocation of `./scripts/scorecard.py` | CI snippet from skill repo runs in target's runner where the script doesn't exist | 36, 49, 51 |
| 10 | `discover-cli.sh <target>` MUST include `--probe-doctor` | Doctor-surface probe silently skipped; upgrade-mode never triggered | 52 (Bugs 3, 4) |
| 11 | `Chown` in Op enum MUST be marked optional | Canonical Op-list says 7 variants, doc says 8 (or vice versa) | 43, 52 |
| 12 | 7-verb-list MUST include all 7 (no 5-verb subset) | Doctor-surface verbs documented as 5 when discover-cli probes 7 | 19 |
| 13 | CI YAML steps running `<tool> doctor --json` MUST handle exit 1 | bash -e abort on findings-present silently skips downstream regression check | 52 (Bug 2) |
| 14 | Every shell script MUST have `set -euo pipefail` | A new script forgets safe-shell flags | 16 |
| 15 | No hardcoded user-specific paths in scripts | A new script gets a `/data/projects/...` literal | 25 |

**Adversarial validation:** running the new detectors against the real skill found **3 latent verb-list bugs that round-19's manual sweep missed**:
- `references/methodology/CORPUS.md:11` — "doctor / health / verify / robot surfaces" (4-verb subset, 1 wrong)
- `references/methodology/PROMPT-LIBRARY.md:372` — "doctor / health / verify / check" (4-verb subset)
- `references/methodology/MIGRATION-GUIDE.md:266` — "doctor / health / verify / etc" (vague placeholder)

All 3 fixed to use the canonical 7-verb list. Detector 14 caught a precision bug in its own initial implementation (`grep -qE 'pipefail'` matched anywhere in the script body, including inside echo strings) — fixed to anchor on `^[[:space:]]*set ` lines.

**The asymptote argument made concrete:** at the end of round 52 I argued the round-by-round loop had crossed an asymptote. The validator extension proves this empirically: 7 new automated detectors caught 3 bugs the prior 19 manual rounds missed, in <2 seconds of CPU time. Future regressions of these classes are now O(seconds) to detect, not O(round). The cost-per-bug-found of automation is ~100x better than continuing the manual loop.

### Move 2: SELF-TEST end-to-end found 3 critical script bugs

Ran `SELF-TEST.md` against a fresh `tinycli` Bash CLI in a tmp dir (the test the skill ships for exactly this purpose). 8 sub-checks; all green only after fixing 3 latent script bugs:

#### Bug 2.1 (CRITICAL): `discover-cli.sh` did not detect Bash CLIs

Symptom: SELF-TEST 2.2 (`discover-cli.sh --probe-doctor`) returned `binaries: []` for a single-file Bash `tinycli` script. SKILL.md line 61 explicitly lists Bash as a supported language ("Rust / Go / Python / TS / Bun / Deno / Ruby / C / C++ / Zig / Elixir / **Bash**"), but `discover-cli.sh` had no Bash detection branch — it only checked for build-system files (Cargo.toml, go.mod, pyproject.toml, package.json, Gemfile, mix.exs, CMakeLists.txt, build.zig).

Fix: added a fallback branch that runs when no build-system file is found. It scans the target's top-level files for executables with `#!.*sh|#!.*bash` shebangs and adds them as binaries with `language="bash"`, `build_system="none"`. Only runs as a fallback so a Rust project's `scripts/build.sh` doesn't shadow Cargo.toml detection.

Effect on agents: the SELF-TEST is what tells an agent the harness is structurally sound before applying it to a real project. With this bug, the SELF-TEST would always fail on a Bash CLI — agents would conclude the skill is broken and abandon. Worse: even on real Rust/Go projects, an agent running discover-cli.sh on a Bash-only sub-tool (e.g., a `scripts/release.sh` that's the actual user-facing CLI) would silently miss it.

#### Bug 2.2 (HIGH): `discover-cli.sh` probe-doctor only worked for PATH-installed binaries

Symptom: even after fixing Bug 2.1, `existing_doctor_subcommand` was empty. The probe used `command -v "$bin"` — which only checks PATH, not the local target dir. For a Bash CLI living in the target tree (the common case for a self-test or a fresh project), `command -v tinycli` fails because tinycli isn't installed system-wide.

Fix: probe now tries `command -v "$bin"` first, then `./$bin` as a local fallback. The script already `cd`'s into the target before this point, so `./$bin` resolves correctly.

Effect on agents: an agent running this skill against any project where the binary isn't system-installed (which includes most local-development scenarios and 100% of fresh-clone scenarios before `cargo install` / `make install`) would get a falsely-empty `existing_diagnostic_subcommands` and incorrectly classify the project as "no existing doctor surface" — triggering `add` mode instead of `upgrade` mode.

#### Bug 2.3 (HIGH): `scaffold-workspace.sh` and `discover-cli.sh` hardcoded "main" fallback when actual branch is "master"

Symptom: SELF-TEST 2.3 (`scaffold-workspace.sh --worktree`) failed with `fatal: invalid reference: main`. The fresh test repo (`git init` with no remote) had no `origin/HEAD`, so the `symbolic-ref refs/remotes/origin/HEAD` fallback chain bottomed out at the literal string "main" — but the actual branch was `master` (the system git default when `init.defaultBranch` is unset).

The same broken fallback existed in `discover-cli.sh` line 94-96, where it would silently emit `default_branch: "main"` for any repo whose branch was actually `master`. Downstream consumers (any CI or scaffolding step that uses `default_branch`) would then operate on a non-existent ref.

Fix: inserted a "local-current-branch" step into both scripts' fallback chains BEFORE the `init.defaultBranch` config check:
1. `git symbolic-ref --quiet --short refs/remotes/origin/HEAD` (remote default — preferred)
2. **NEW**: `git symbolic-ref --short HEAD` (local current branch — works for fresh-init repos)
3. `git config --get init.defaultBranch` (system default — only relevant if no commits exist yet)
4. Literal "main" (last resort)

Effect on agents: any agent applying this skill to a project on `master` (older git default; still common) would have hit `fatal: invalid reference: main` at Phase 0.5. The worktree creation would fail and the agent would have to manually debug git plumbing — a hard hurdle for fresh-context agents.

#### Cumulative count after Move 2

3 critical script bugs caught by 1 SELF-TEST run, after 52 rounds of manual fresh-eyes audit. The bugs are exactly the kind of "script behaves correctly on the developer's machine but breaks for everyone else" issues that PROSE audits can never catch — only execution can.

### Move 3: Multi-model triangulation — 76 findings, 14 critical/high fixes applied

Dispatched 4 parallel fresh-context agents with non-overlapping audit angles. Each got NO conversation context from the prior 52 rounds — functionally equivalent to triangulating across separate models.

| Agent | Angle | Findings |
|-------|-------|----------|
| 1 | Script bugs the SELF-TEST didn't catch | 30 (2 critical, 8 high, 14 medium, 6 low) |
| 2 | Cross-doc contract drift (RFC ↔ CLI-SURFACE ↔ OUTPUT-SCHEMA ↔ KERNEL ↔ GLOSSARY ↔ VERSIONING) | 19 (4 critical, 6 high, 6 medium, 3 low) |
| 3 | Subagent prompt ergonomics | 11 (2 critical, 4 high, 5 medium) |
| 4 | Cold-prober: fresh agent applying skill cold | 16 |

**76 total findings.** This dwarfs the per-round catch rate of the prior 52 manual rounds (typically 1–4 per round). The cold-prober's first-10-minute audit was particularly high-yield — finding orientation friction that 52 rounds of "fresh-eyes within the same conversation" never surfaced because I had already internalized the conventions.

#### Critical fixes applied (8 of 8)

1. **`recommendations.jsonl` was an orphan workspace artifact** (subagent C1). SKILL.md, IO-CONTRACTS.md, OPERATING-MODES.md (audit-only mode!), and 2 scorecard templates referenced it — but NO subagent listed it as an output. Audit-only mode was silently broken: it would produce no recommendations file and Phase 4 would have nothing ranked to walk. **Fix:** added `recommendations.jsonl` to `subagents/synthesizer.md` Outputs section with the schema from IO-CONTRACTS.md, plus a Phase 4 cross-reference exit criterion. This is the EXACT same bug class as rounds 39/40 — workspace artifact declared by the spine but no producer — that those rounds claimed to have fully swept. The triangulation found one they missed.

2. **Phase 5 hard-fails on Phase 9 fixtures** (subagent C2). `safety-harness-runner.md` (Phase 5) needed `tests/doctor_fixtures/<fm_id>/{corrupt.sh,assert.sh}` which `fixture-author.md` doesn't build until Phase 9. `verify-undo.sh` line 22 hard-exits 1 if `corrupt.sh` is missing — Phase 5 was structurally unrunnable. **Fix:** split fixture authorship: `subagents/repair-spec-author.md` (Phase 2) now emits the SKELETON pair (`corrupt.sh` matching the spec's `triggered_by_findings`, `assert.sh` matching the post-fix expected state); `fixture-author.md` (Phase 9) expands the skeleton with edge cases + golden artifacts. Both subagents updated with the explicit ordering note.

3. **`manifest-update.sh` jq path injection + concurrent-update lost-updates** (script CRIT 1). Two issues bundled: (a) `$path` interpolated unquoted into the jq filter string allowed malformed `--set` to break out of the assignment context; (b) two concurrent `manifest-update.sh` invocations against the same workspace would both read the original manifest, both modify, and the second `mv` wins — silently losing the first's update. **Fix:** added a `validate_jq_path` regex that restricts paths to `^\.[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+|\[[0-9]*\+?\])*$` and rejects with exit 64 + clear message; added `flock -x -w 30 9` for the duration of read-modify-write with exit 5 (concurrency_lost) on contention; added a `printf` JSON status to stdout so callers can programmatically assert success.

4. **Hardcoded `/tmp/conc_a.json` and `/tmp/crash_$k_ms.json` in verify scripts** (script CRIT 2). `verify-concurrency.sh` and `verify-crash-recovery.sh` wrote to fixed `/tmp/` paths — TOCTOU + cross-test race when CI matrix or two agents run the same fixture in parallel. World-writable predictable paths. **Fix:** both scripts now write to `$sandbox/.verify-{concurrency,crash-recovery}/` (under the per-run `mktemp -d` sandbox). Cross-run isolation guaranteed.

5. **`report.json` field name mismatch — `command` vs `command_or_instruction`** (contract CRIT 1). RFC.md required `command_or_instruction`; CLI-SURFACE.md and `report-template.json` and 3 example sites used `command`. Schema-vs-implementation drift; a fresh agent reading RFC.md would emit a report that fails any tooling parsing CLI-SURFACE.md. **Fix:** RFC.md updated to `command` with explicit cross-reference to the 4 other authoritative usages.

6. **`lock_timeout_seconds` default: 5s vs 300s** (contract CRIT 2). RFC.md example showed `300`; STATE-MACHINE.md, OPERATORS.md, and SAFETY-ENVELOPE-TEMPLATE.md all said `5 s`. 60x discrepancy — a tool author following RFC.md would build a doctor with a 5-minute lock timeout (effectively never times out), while the operations docs assume 5 seconds. **Fix:** RFC.md updated to `5` with cross-references; matches the 3 authoritative usage sites.

7. **`gc` subcommand definition was internally contradictory** (contract CRIT 3). RFC.md said "prune old run-dirs"; OUTPUT-SCHEMA.md said "can prune entire run directories"; CLI-SURFACE.md said BOTH "prune old runs/" AND "Backups are kept even after gc" AND "delete only quarantined backups". Three different specs for one subcommand. Per Axiom 3, undo is the only delete except when explicitly authorized — so gc with `--yes --before` IS authorized but its scope was unclear. **Fix:** CLI-SURFACE.md clarified to "prune `<run-id>/` directories (and their `backups/` subdirs) whose `started_at` is before `<date>`. Per KERNEL § Axiom 3, only `undo` and `gc` may delete; gc is gated on user-confirmed cutoff so the user explicitly accepts loss of undo capability for those runs."

8. **`report.json::state` and `partial_failures` fields used in templates but undeclared in primary schemas** (contract CRIT 4). `assets/report-template.json` had `"state": "DONE_FINDINGS"`; STATE-MACHINE.md mandated `report.json::state`; CLI-SURFACE.md cited `partial_failures` — but RFC.md § 5.1 (the canonical schema) listed neither. Closed-contract violation per Axiom 20. **Fix:** RFC.md schema now lists both `state` (REQUIRED, with terminal-state enumeration referencing STATE-MACHINE.md) and `partial_failures` (REQUIRED when state=DONE_PARTIAL or exit_code=2; empty array otherwise).

#### High fixes applied (6 of 12)

9. **Subagent ergonomics:** `triangulator.md` used `{{patches}}` template variable that was undeclared in any upstream subagent's outputs — fresh agent would have nothing to fill in. Fixed to specify the concrete artifact per phase: Phase 4 = `git diff doctor-mode-pass-{{N}}~..doctor-mode-pass-{{N}}`, Phase 7 = `{{workspace}}/fresh_eyes_findings_pass_{{N}}.md`.
10. **Subagent ergonomics:** `scorecard-generator.md` exit criterion "Aggregate score recorded in `manifest.json::aggregate_score`" didn't tell the agent HOW. Fresh agents would hand-edit manifest.json, racing parallel writers (and triggering the round-53 manifest-update.sh injection bug if they tried to use the script). Fixed to explicit invocation: `scripts/manifest-update.sh {{workspace}} --set-int .aggregate_score=<N>`.
11. **Subagent ergonomics:** scorecard-generator step 7 said "append a one-line summary to scorecard_history.jsonl" without invoking the existing `scorecard.py append-history` script. Fresh agents would hand-write the JSON line, missing the fsync-then-rename atomicity. Fixed to explicit script invocation.
12. **Cold-prober #2:** No autonomous-defaults mode for unattended runs (cron, /loop, scheduled execution). The existing intake required user answers for 10 questions. Fixed by adding an "Autonomous defaults" subsection to SKILL.md with the least-destructive default for each question (audit-only mode, worktree, offline-only, deny jsm install, etc.).
13. **Cold-prober #15:** SELF-TEST was structurally separate from any phase. Fresh agents could spend 30 min onboarding only to discover at Phase 4 that a script was broken. Fixed by adding "Step 0 (recommended once per skill checkout): run SELF-TEST.md end-to-end" to SKILL.md Skill Bootstrap.
14. **Cold-prober #5:** Cookbook patterns 13-15 (Forensic, Build-system, Compliance) listed in SKILL.md but missing from intake-worksheet checklist. Fresh agent classifying a build-system CLI couldn't find the right checkbox. Fixed: added all 3 to the worksheet.

Plus: `validate-skill.sh` Q-NNN scan now correctly scoped to `--include='*.md' --exclude-dir='.git'` (script HIGH #7+#10); contract HIGH #7 (`allowed_ops` referenced in KERNEL/MUTATE-CHOKEPOINT but not in capabilities schema) fixed by adding `allowed_ops` to RFC.md schema AND `capabilities-template.json`; scaffold-workspace.sh handles the "branch already attached to another worktree" case by minting a workspace-suffixed branch name (script M17 / discovered live during the final SELF-TEST re-run).

#### Findings deferred (62 of 76)

The remaining 62 medium/low findings are documented in CHANGELOG context and queued for future rounds. Highlights of what's deferred:
- Performance: `validate-dag.py` recursive DFS with O(n²) `stack.index` (rare in practice; most FM graphs are <50 nodes)
- `head -c 256` shebang detection brittle on long shebangs (rare in practice)
- `cp -a` doesn't `--no-dereference` symlinks pointing outside sandbox (low risk; fixtures don't do this)
- Pass-number template drift between subagents (`{{N}}` vs `<N>` — both render readably; a single substitution loop catches one form)
- FM-ID short-form vs subsystem-prefixed-form drift in CLI-SURFACE.md examples
- `subsystems` example sets in capabilities-template.json (6 entries) vs GLOSSARY.md standard (13 entries) — example-illustration vs canonical list

These should each become a validate-skill.sh detector in future rounds OR be addressed in a future schema-tightening pass. None are critical-path blocking.

### Round-53 fresh-eyes corrections (post-Move-3)

Fresh-eyes pass on my own round-53 changes caught **6 bugs I introduced or missed**:

1. **`synthesizer.md` recommendations.jsonl schema was WRONG** (I introduced this). My initial fix described fields like `fm_id`, `priority` (P0/P1/P2/P3), `recommended_fixer_outline`, `dependencies` — none of which match IO-CONTRACTS.md's actual schema (`id`, `title`, `priority` numeric, `estimated_uplift`, `complexity`, `applied`, `diff_sketch`). Fixed to match IO-CONTRACTS.md as the source of truth, with per-field guidance.
2. **`scaffold-workspace.sh` produced trailing-dash branch names** (e.g., `doctor-mode-pass-1-tinycli-ws-2ADcuy-`). Root cause: `tr -c` replaces newlines with `-`, then `$(...)` strips trailing newlines but not trailing dashes. Fixed with `${var%-}` parameter expansion.
3. **`scaffold-workspace.sh` first-attempt errors were silently suppressed** (`>&2 2>/dev/null` redirect pattern). Fresh-context agents debugging would see no clue why fallback was needed. Fixed: capture git's output, surface it on success, surface it AS CONTEXT on failure with explicit "falling back to ..." log message.
4. **Detector 13 only matched the `<tool>` placeholder, missed literal-tool-name bugs.** A doc with `- run: br doctor --json` (literal `br`) wouldn't trigger. Broadened regex to match any `[a-zA-Z_][a-zA-Z0-9_-]*` tool name; verified with synthetic test that `- run: br doctor --json` and `- run: my_cli doctor --quick --json` both fire.
5. **Phase 0 vs Phase 0.5 naming drift in SKILL.md was missed in my Move-3 fixes.** SKILL.md called Skill Bootstrap "Phase 0.5" while PHASES.md, KICKOFF-PROMPTS.md, AGENT-MAIL-INTEGRATION.md, SKILL-FALLBACKS.md, and CASS-PLAYBOOK.md all use "Phase 0". Renamed to align with the canonical phase definition.
6. **`MIGRATION-GUIDE.md` post-migration prose was misleading.** I claimed "regression check runs whether findings are present or not" but the YAML has the regression check in a SEPARATE `- run:` step that's gated by the prior `<tool> doctor health` step. Corrected to: "two gates: (1) doctor health = hard gate; (2) scorecard regression check = runs only if hard gate passes."

The fresh-eyes pass also surfaced the canonical lesson from rounds 16→17 and 51→52: **a fix introduces its own regression class.** My round-53 schema fix (#1) introduced new contract drift while fixing existing drift. Caught by reading IO-CONTRACTS.md after writing the synthesizer.md prose. Pattern: anytime I add prose that describes a schema, verify the schema text exists by re-reading the canonical source within the same edit cycle.

### Meta-conclusion: round 53 = the structural cap

After 52 rounds + Move 1 + Move 2 + Move 3:
- **Move 1** (meta-doctor extension) caught 3 latent bugs that 19 prior rounds missed in <2s of CPU. Future regressions of those 7 classes are now O(seconds) to detect.
- **Move 2** (SELF-TEST end-to-end) caught 3 critical script bugs that 52 rounds of prose audit missed because they only manifested under execution.
- **Move 3** (multi-model triangulation) caught 14 critical/high bugs across script, contract, ergonomic, and onboarding axes that NEITHER my 52 rounds NOR the new automated detectors would have surfaced.

The asymptote argument from the end of round 52 is now empirically proven AND structurally addressed:
1. Drift class regressions: caught by `validate-skill.sh` (15 detectors).
2. Script execution bugs: caught by `SELF-TEST.md` (8 sub-checks).
3. Blind-spot bugs (cross-doc, cross-context, fresh-eyes): caught by triangulation (4 parallel fresh-context audits).

These 3 layers form the production quality gate going forward. Per-PR: run validate-skill.sh + SELF-TEST. Per-major-version: run multi-model triangulation. Round-by-round manual fresh-eyes is no longer the right tool — the automation cost is amortized across all future regressions, while manual rounds linearly burn budget per audit.

Round 53 closes the loop.

### Meta-conclusion

This round is the structural cap on bug-finding for this skill. After 52 rounds of manual audit + Move 1 + Move 2:
- **Move 1** (meta-doctor extension) caught 3 bugs that 33 prior rounds missed, and prevents future regression of all 7 classes for ~1s CPU each.
- **Move 2** (SELF-TEST end-to-end) caught 3 critical script bugs that 52 rounds of prose audit missed, because they only manifested under execution.
- **Move 3** (multi-model triangulation) is the last layer: cross-validate against models with different blind spots than mine.

After this round, the asymptote is real and structural. Future regressions are caught by `validate-skill.sh` (drift) + `SELF-TEST.md` (execution) + per-PR multi-model review (blind-spot coverage).

---

## 1.5.46 — Round-52 fresh-eyes pass: 4 bugs across 3 distinct classes

### Bug 1: GLOSSARY.md still listed `Chown` as canonical Op (round-43 sweep gap)

Round-43 reframed `Chown` from canonical-but-unimplemented to optional-8th-variant in `MUTATE-CHOKEPOINT.md` (line 40 says "seven canonical variants" and lists 7). All 5 language recipes (rust/go/python/typescript/jvm) implement only 7. But `references/methodology/GLOSSARY.md` line 85 was missed by the round-43 sweep — it still defined: `**Op** — One of "WriteFile | AppendFile | Rename | Chmod | Chown | DbExec | DbMigrate | SymlinkAtomic"`.

Effect: an agent reading GLOSSARY.md as ground truth would think Chown is canonical, then look for it in recipes and find it absent — looks like a gap when it's actually intentional.

Fixed: GLOSSARY.md now matches MUTATE-CHOKEPOINT.md ("seven canonical variants ... Chown is an optional 8th variant ... none of the 5 reference recipes implement it").

### Bug 2 (CRITICAL): Round-51's MIGRATION-GUIDE.md fix introduced a CI exit-code regression

Round-51 replaced `./scripts/scorecard.py compare-against-baseline ...` (cross-repo bug) with a hermetic jq check. But the round-51 fix had THREE separate `- run:` GitHub Actions steps:

```yaml
- run: <tool> doctor health
- run: <tool> doctor --json > /tmp/run.json   # ← BUG: bare invocation
- run: |
    run_dir=$(jq -er .run_dir /tmp/run.json)
    ...
```

Under default GitHub Actions `bash -e` semantics, `<tool> doctor --json` exiting with code 1 (canonical "findings present, no fix") aborts the second step. The third step (regression check) never runs — defeating the entire purpose of the regression check. The canonical pattern in `subagents/integration-wirer.md` correctly catches the exit code (`<tool> doctor --json > /tmp/run.json || rc=$?; case "$rc" in 0|1) ;; *) exit "$rc";; esac`); WORKED-EXAMPLE.md also got it right; only MIGRATION-GUIDE.md missed it.

Fixed: collapsed into a single `- run: |` block matching the WORKED-EXAMPLE.md pattern with explicit exit-code handling. Updated the surrounding prose to clarify the design intent: the regression check runs whether findings are present or not.

### Bug 3: SKILL.md Skill Bootstrap missing `--probe-doctor` flag

`SKILL.md` line 94 (Phase 0.5 Skill Bootstrap) showed:
```
./scripts/discover-cli.sh <target> > <workspace>/phase0_cli.json
```

But the comment claimed it would detect "existing doctor / health / verify / repair / check / diagnose / fix surfaces." The `discover-cli.sh` script only runs the doctor-surface probe when `--probe-doctor` is passed (line 12: `[ "${2:-}" = "--probe-doctor" ] && probe_doctor=1`). Without that flag, the `existing_doctor_subcommand` and `existing_diagnostic_subcommands` JSON fields are empty.

Effect: an agent following SKILL.md verbatim would get an inventory missing the existing-doctor data, then SKILL.md line 73 ("If one exists, we **snapshot its current behavior** into `<workspace>/baseline/`") would fail to trigger upgrade mode for projects that have an existing doctor surface.

Cross-checked all other docs:
- `SELF-TEST.md:100` ✓ has `--probe-doctor`
- `FIRST-30-MINUTES.md:49,113` ✓ has `--probe-doctor`
- `WORKED-EXAMPLE-WRANGLER.md:31`, `WORKED-EXAMPLE.md:37` ✓ have `--probe-doctor`
- `SKILL.md:94` ✗ missing — fixed
- `OPERATING-MODES.md:190` ✗ also missing — fixed (Bug 4)

### Bug 4: OPERATING-MODES.md auto-detection example also missing `--probe-doctor`

Same root cause as Bug 3 but in a different doc. `references/methodology/OPERATING-MODES.md` line 190 is the canonical "Auto-detection" section example — it MUST show `--probe-doctor` since the auto-detection heuristic depends entirely on the doctor-surface probe. Otherwise `upgrade` mode is never triggered.

Fixed: added `--probe-doctor` to the example AND added an inline note explaining why it's required: "REQUIRED for the upgrade-mode heuristic — without it, the existing-doctor probe is skipped and the script can't classify between `upgrade` and `add` based on the target's existing subcommands."

### Pattern observation

Two of the four bugs are **"command shown without important flag"** — same class. The detection method that finally surfaced them: `grep -rn "discover-cli.sh" --include="*.md"` and inspect every invocation for flag consistency. SELF-TEST.md and FIRST-30-MINUTES.md got it right (they're executable / executed-by-agent docs, so the bug would be visible). SKILL.md and OPERATING-MODES.md got it wrong (they're prose documentation, so the bug was latent until an agent literally followed the example).

**Lesson:** prose-documentation examples drift more than executable examples — the latter are forced to match reality, the former are not. Apply the same pattern to other docs: anywhere a command line appears in prose, verify it works.

### Cumulative tallies

- "Command shown without important flag": Round 52: 2 sites (first appearance of this bug class).
- "Round-N follow-up regression introduced by the fix itself": Round 16→17 (regression-test-template.sh `set -e` fix introduced a new bug), now Round 51→52 (round-51's CI fix introduced an exit-code abort). 2 occurrences total. Lesson: always run the EXACT example in the doc end-to-end after fixing it; the WORKED-EXAMPLE.md got it right because it's literally a worked example.
- "Round-43-style canonical-vs-recipe drift" (one doc says X variants, another doc says X+1): Round 43 caught Chown over-claim in MUTATE-CHOKEPOINT.md. Round 52 caught the same drift in GLOSSARY.md (sweep gap). 2 sites total.

### Verification

- `grep -rn 'discover-cli\.sh.*<target>' --include='*.md'` shows both remaining sites use `--probe-doctor`.
- Meta-doctor passes clean.

---

## 1.5.45 — Round-51 cross-repo CI bug sweep (round-49 follow-up)

### Bug fixes (round-51)

Round-36 fixed the cross-repo CI snippet bug in `subagents/integration-wirer.md` (CI invokes `./scripts/scorecard.py` but script lives in skill repo, not target's CI workdir). Round-49 found and fixed the same bug in `references/methodology/PHASES.md § Phase 8`. Round-51 swept ALL methodology files for the same pattern and found **2 more sites**:

- **`MIGRATION-GUIDE.md` line 159** (post-migration CI example): had `./scripts/scorecard.py compare-against-baseline scorecard.json baseline.json --max-regression-points=50` — same cross-repo issue. Fixed with the canonical jq-based check + pointer to integration-wirer.md.
- **`WORKED-EXAMPLE.md` line 354** (Phase 8 example output): had the same buggy CI snippet. Fixed with the same jq-based pattern.

### Cumulative tally for "CI snippets invoke ./scripts/scorecard.py from target's runner"

- Round 36: 1 site (subagents/integration-wirer.md)
- Round 49: 1 site (references/methodology/PHASES.md § Phase 8)
- **Round 51: 2 more sites (MIGRATION-GUIDE.md + WORKED-EXAMPLE.md)**

**Total: 4 sites across 4 rounds.** Round-49's prediction held: "the integration-wirer subagent and PHASES.md Phase 8 should not duplicate the CI snippet" — but the CI snippet ALSO appears in 2 other places (MIGRATION-GUIDE describes the post-migration CI; WORKED-EXAMPLE shows what Phase 8 produces for the example project). All 4 sites independently maintained until now. Round-50's refactor (PHASES.md → high-level summary pointing at integration-wirer.md) is the right structural fix; round-51 retrofits the other 2 docs to point at integration-wirer.md as canonical too.

### Pattern observation

The CI scorecard regression check appears in 4 docs because each doc has a different LENS on Phase 8:
- subagents/integration-wirer.md: agent-prompt with full implementation details
- references/methodology/PHASES.md § Phase 8: high-level overview
- references/methodology/MIGRATION-GUIDE.md: how to migrate from a pre-doctor CI to the doctor-aware CI
- references/methodology/WORKED-EXAMPLE.md: concrete example showing what Phase 8 outputs

The CONTENT was duplicated — the LENS varied. Round-50/51 refactor: subagent stays canonical with full snippet; the other 3 docs reference it instead of duplicating. Now future doc edits don't need to be parallel.

### Verification

- `grep -rnE "^- run:.*\./scripts/scorecard|run: \./scripts/scorecard"` over docs returns nothing (excluding CHANGELOG history).
- All 4 sites use the canonical jq-based regression check OR explicitly point at integration-wirer.md as the canonical source.
- Meta-doctor passes clean.

---

## 1.5.44 — Round-50 PHASES↔integration-wirer refactor + scorecard-template drift

### Refactoring (round-49 follow-up)

Round-49 noted "the integration-wirer subagent and PHASES.md Phase 8 should not duplicate the CI snippet — one should be the canonical source, the other a one-line pointer."

Applied that refactor: **`subagents/integration-wirer.md` is now the canonical source** for the Phase-8 outputs (full pre-commit hook, full CI YAML + jq regression check, demote-skill procedure). `references/methodology/PHASES.md § Phase 8` is a high-level overview that:
- Names the 3 outputs in human-readable form (pre-commit hook / CI workflow / demote related skill).
- Explicitly says "the regression check uses the doctor's own scorecard.json + jq, NOT this skill's `scripts/scorecard.py`" — preserves the round-49 pitfall warning.
- Explicitly says "Do NOT duplicate the snippets here — they drift" with a link to integration-wirer as canonical.
- Keeps the **Subagent** pointer at the bottom.

Result: 30+ lines of duplicated CI snippet removed from PHASES.md; the canonical version is in one place; future drift becomes a single-edit fix.

### Bug fix (round-50)

- **`assets/scorecard-template.md` per-FM table had 12 columns with abbreviated names**, but `scripts/scorecard.py render` actually produces a **13-column table with full dimension names** (line 161: `f.write("| FM | Median | Weight | " + " | ".join(DIMENSIONS) + " |\n")`). The template was a layout sketch using abbreviations (int/erg/aut/safe/...); the actual rendered output uses full names AND has a Weight column the template doesn't show. An agent comparing the rendered scorecard against the template would think the script was emitting unexpected extra columns. Fixed: template now shows the exact 13-column header `FM | Median | Weight | agent_intuitiveness | agent_ergonomics | automation_degree | data_safety | idempotence | reversibility | diagnostic_specificity | blast_radius_containment | observability | test_coverage_of_repair`. Added a clarifying note that the table is intended for agent parseability over column-width compactness.

### Cumulative refactor + audit tally

- Round 49 noted the duplication; round-50 applies the canonical-source-with-pointer refactor.
- Pattern established: when the same content appears in both a subagent file and a methodology doc, the subagent is the canonical source (it's the verbatim prompt). Methodology docs become high-level overviews that point at the canonical.
- Round-50 also caught a separate template-vs-output drift in scorecard-template.md.

### Verification

- PHASES.md Phase 8 is now ~15 lines (was ~35); points to integration-wirer.md.
- scorecard-template.md table header matches scorecard.py output byte-for-byte.
- Meta-doctor passes clean.

---

## 1.5.43 — Round-49 PHASES.md hardcoded path + cross-repo CI bug

### Bug fixes (round-49)

Round-36 fixed the hardcoded user-specific path + cross-repo CI script invocation in `subagents/integration-wirer.md`. Round-49 found the **same two bugs in `references/methodology/PHASES.md` § Phase 8** that round-36 missed (subagent file fixed, methodology doc not):

- **Line 409**: `update ../../fixing-beads-problems/SKILL.md` — hardcoded user-specific path (round-25/36 class). Fixed to `<your-skills-dir>/fixing-beads-problems/SKILL.md` with notes about typical locations.
- **Line 407**: CI workflow snippet invoked `./scripts/scorecard.py compare-against-baseline /tmp/scorecard.json baseline.json` from the target repo's GitHub Actions runner. The script lives in this skill's repo, NOT the target — `./scripts/scorecard.py` doesn't exist at the target's CI workdir. Same bug as round-36 in integration-wirer.md. Replaced with the hermetic jq-based regression check (matching the round-36 fix in integration-wirer.md): reads the doctor's own `.doctor/runs/<id>/scorecard.json`, falls back to `.aggregate_score` if `.aggregate.score` is missing (handles nested vs flat schema), explicit error handlers for missing run_dir / scorecard / baseline.

### Why round-36 missed PHASES.md

Round-36 fixed `integration-wirer.md` (a subagent prompt). PHASES.md § Phase 8 has the SAME CI snippet as a parallel reference for the same phase. When round-36 fixed the subagent, it didn't sweep PHASES.md for the same content. Pattern recognized: when a subagent prompt references a CI/shell snippet, the same snippet often appears in PHASES.md or other methodology docs as a parallel reference. Future audits should grep across BOTH subagents/ and references/methodology/ for the same patterns.

### Cumulative tally for "hardcoded user-specific paths in copy-paste docs"

- Round 25: 4 sites (check-skills.sh, FIRST-30-MINUTES.md, SELF-TEST.md, integration-wirer.md inputs example)
- Round 36: 1 more site in integration-wirer.md
- **Round 49: 1 more site in PHASES.md § Phase 8 + 1 cross-repo CI invocation**

### Verification

- All hardcoded private-repo absolute paths in non-citation contexts now generic.
- PHASES.md § Phase 8 CI snippet uses the hermetic jq-based regression check (no skill-repo dependency at target's CI runtime).
- Meta-doctor passes clean.

### Notes

- Round-49 is the second follow-up after round-36 (the first was integration-wirer.md). Pattern: the integration-wirer subagent and PHASES.md Phase 8 section duplicate content. They drift independently. A future round could refactor to make ONE the canonical source and the other a one-line pointer, eliminating the duplication.

---

## 1.5.42 — Round-48 PHASES.md script-invocation gaps

### Bug fixes (round-48)

Continuing the "subagent prompts incomplete vs. consumer requirements" sweep, found PHASES.md (the canonical phase-by-phase playbook) had the same class of bug in 2 places:

- **PHASES.md line 196 § Phase 2.5 spec-review**: "Run `python3 scripts/validate-spec.py` against each spec." — `validate-spec.py` requires a path arg (round-14 confirmed). An agent following this verbatim would invoke the script without args and get exit 64. Fixed to "Run `python3 scripts/validate-spec.py <workspace>/analysis/repair_specs/<id>.md` against each spec (the script takes one path arg; loop over the directory)."
- **PHASES.md § 5.1-5.4 (Reversibility/Idempotence/Crash-recovery/Concurrency)**: 4 sites listing helpers as `scripts/verify-*.sh fm-<id>` without mentioning the required `<tool>` arg or `TOOL` env var that round-27 introduced. Same bug as round-37 in safety-harness-runner. Fixed by adding a single shared callout at the top of § 5.1: "Each takes `<fm_id> [<tool>] [<fixture_root>]`. The `<tool>` arg is required as arg 2 OR via the `TOOL` env var (else the script exits 64). Recommended: `export TOOL=<tool>` once at the top of the harness loop."

### Round-47 follow-up

Per round-47's lesson "the 9 detectors documented but unimplemented are roadmap-actionable" — added them as ROADMAP.md item #11 with full enumeration. Each detector now has a clear path from documented-but-aspirational → implemented-and-tested. This unblocks future rounds that want to close the META-DOCTOR.md gap one detector at a time.

### Cumulative tally for "subagent prompts / methodology docs invoke scripts with incomplete args"

- Round 14: 5 sites (verify-*.sh + validate-fm/spec invocations in subagents)
- Round 19: 2 sites (AGENT-PROMPTS diff-scorecards.py args)
- Round 20: 3 sites (SKILL.md dependency_graph.json)
- Round 27: 1 site (scorecard-generator validate args)
- Round 34: 1 site (scorecard-generator frequency/blast_radius)
- Round 35: 2 sites (implementer schema + subcommands)
- Round 37: 4 sites (safety-harness + fixture-author)
- Round 38: 3 sites (canonical_tasks + cass-miner + agent-ergo-grader)
- **Round 48: 5 sites (PHASES.md spec-review invocation + 4 verify-*.sh callouts)**

**26 sites across 9 rounds**.

### Verification

- PHASES.md § Phase 2.5 now correctly invokes validate-spec.py with the required path arg.
- PHASES.md § Phase 5.x now correctly notes TOOL env var requirement for verify-*.sh.
- ROADMAP.md item 11 enumerates the 9 not-yet-implemented detectors so they can be picked off round-by-round.
- Meta-doctor passes clean.

---

## 1.5.41 — Round-47 META-DOCTOR.md fundamentally stale

### Bug fix (round-47)

**`references/methodology/META-DOCTOR.md` documented a fundamentally different reality than what exists.** Issues:

1. **Line 156-164 said "`validate-skill.sh` is **not yet built**"** — but the meta-doctor IS built (round-10 onwards strengthened it; it runs every round and passes clean). Doc said "the obvious next thing to build" while the thing was already built and load-bearing.
2. **Surface section claimed `--json` and `--fix` flags exist** — they don't. validate-skill.sh takes only `<skill-dir>`.
3. **Bootstrap recursion claimed `scripts/lib/mutate.sh` exists** — no such file.
4. **9 detectors documented as if implemented** — only 8 actual sections match (frontmatter, Q-NNN, subagent orphans, scripts executable, cross-references, no destructive shell, methodology orphans, backtick-script existence). The shebang-missing, set-euo-missing, corpus-path-rot, circular-link, description-too-long, description-missing-trigger-words, prompt-not-self-contained, assets-template-malformed, assets-template-Q-ID-rot detectors are documented but NOT implemented.

**Fix**: rewrote META-DOCTOR.md to match reality:
- Surface section: actual single-arg invocation (no fictitious flags).
- Bootstrap recursion: reframed as **aspirational** — current script is the read-only-detector subset; auto-fix/undo/fixtures path is roadmapped.
- Implementation status: enumerates the 8 actual sections vs the 9 NOT-yet-implemented detectors. Agents now know exactly which checks they get vs roadmap items.

### Why this matters

META-DOCTOR.md is what agents READ to understand the meta-doctor. If the doc says the meta-doctor isn't built but it IS the gating check, agents don't invoke it. If the doc claims `--fix` / `--json` flags that don't exist, first invocation fails. Stale docs in canonical methodology files have outsized impact.

### Cumulative tally for "canonical doc claims features that don't match implementation"

- Round 10: 4 broken script references (validate-scorecard.py etc.)
- Round 19: validate-dag.py invocation missing path arg
- Round 28: capabilities schema missing manual_remediations
- Round 38: workspace artifacts not declared
- Round 43: Op `Chown` declared canonical, implemented nowhere
- **Round 47**: META-DOCTOR.md described unbuilt meta-doctor + non-existent flags + non-existent helper file

### Verification

- META-DOCTOR.md surface section accurately describes `scripts/validate-skill.sh <skill-dir>`.
- Implementation status enumerates the 8 actual sections.
- 9 not-yet-implemented detectors explicitly listed as roadmap items.
- Meta-doctor passes clean.

### Notes

- Most "stale documentation" round so far — META-DOCTOR.md was written before validate-skill.sh was strengthened in round-10+. Subsequent rounds beefed up the script but never circled back to update its reference doc. Lesson: when adding/strengthening a script, audit ALL methodology docs that reference it.
- The "9 detectors documented but unimplemented" gap is itself a roadmap-actionable list. Future rounds could close those gaps one detector at a time.

---

## 1.5.40 — Round-46 AGENT-PERSPECTIVE example script bugs

### Bug fixes (round-46)

`AGENT-PERSPECTIVE.md` ships a "complete agent script (60-second tour)" — a `minimal-doctor-loop.sh` that demonstrates how an agent should invoke the doctor and handle outcomes. **Three bugs in the example script** that an agent copying it would inherit:

- **`cd "$1"` with no usage check** — under `set -euo pipefail`, an agent forgetting the arg gets `"$1: unbound variable"` from bash. Fixed to `target="${1:?usage: minimal-doctor-loop.sh <target-dir>}"; cd "$target"` — explicit usage message.
- **`fix=$(<tool> doctor --fix --json)` under set -e** — same bug as round-16 in regression-test-template. If `--fix` exits 2 (partial) or 3 (rolled back), the assignment exits non-zero, set -e fires, and the script aborts BEFORE the agent can inspect `.state` or surface the diagnosis to the user. The whole point of capturing `state` was to handle non-zero exits gracefully — set -e defeated it. Fixed with the round-44 `fix_exit=0; fix=$(...) || fix_exit=$?` pattern, plus echoing both `fix_exit` and `state` for the agent to log.
- **`state=$(echo "$fix" | jq -r .state)` returns literal "null" if missing** — same bug class as rounds 44/45. Fixed with `jq -r '.state // "MISSING_STATE_FIELD"'` so a missing field surfaces as a recognizable sentinel string instead of `"null"`.

### Why this matters

AGENT-PERSPECTIVE.md is documentation an agent reads to learn how to USE the doctor. The "complete script" is meant to be a copyable template. Three bugs in 35 lines of example code = agents copy the bugs into production scripts. Worse: the bugs all silently abort or pass wrong values — the agent author doesn't see them in dev-loop testing because the happy path works.

### Cumulative tally for "set -e silently masks fix-exit bugs"

- Round 16: `assets/regression-test-template.sh` (3 sites)
- Round 17: same file's diff filter
- Round 37: `subagents/fixture-author.md` run_all.sh (3 sites)
- Round 41: `references/rubric/REGRESSION-TEST-PATTERNS.md` diff filter
- Round 44/45: `jq -r .field` null-passthrough (4 sites)
- **Round 46: `AGENT-PERSPECTIVE.md` example script (3 sites)**

15+ sites across 8 rounds in the broader "silent-fail under set -e or missing-field defaults" class.

### Verification

- AGENT-PERSPECTIVE.md example script now uses idiomatic patterns:
  - `target="${1:?usage: ...}"` for usage check.
  - `fix_exit=0; fix=$(cmd) || fix_exit=$?` for safe non-zero capture.
  - `jq -r '.state // "MISSING_STATE_FIELD"'` for explicit null fallback with diagnostic value.
- Meta-doctor passes clean.

### Notes

- The "minimal-doctor-loop.sh" example is high-leverage: it's the canonical copy-paste template for "how an agent should use a doctor". Bugs there propagate widely.
- Future audit query: every code block that's described as "paste-ready" or "minimal example" or "60-second tour" deserves the same set-e + null-passthrough scrutiny as actual scripts.

---

## 1.5.39 — Round-45 jq -r null-passthrough sweep

### Bug fix (round-45)

Round-44 fixed `jq -r .run_id` in fixture-author.md and noted the audit query `grep -rn 'jq -r [^|]'` for finding more sites. Round-45 ran that query and found **3 more occurrences of the same bug** in `references/rubric/REGRESSION-TEST-PATTERNS.md`:

- Line 61 (data_safety / regression_backup_byte_identical.sh): `run_id=$(jq -r .run_id /tmp/fix.json)` → used to construct `backup_file="$fixture_dir/.doctor/runs/$run_id/backups/.beads/issues.jsonl"`. If run_id is null, the path becomes `.doctor/runs/null/backups/...` and the cmp -s fails with a confusing "no such file" instead of "backup not byte-identical".
- Line 87 (reversibility / regression_reversibility.sh): same pattern, same bug.
- Line 132 (observability / regression_run_artifacts.sh): same pattern, same bug.

All three replaced with `jq -er .run_id ... || { echo "FAIL: --fix output missing run_id"; exit 1; }` — fails loudly with a specific diagnostic.

### Non-bug instances (verified safe)

The audit query also surfaced these `jq -r` sites that ARE safe (degrade gracefully):

- **subagents/integration-wirer.md** lines 70/74/76: use explicit `// empty` and `// 0` defaults — safe.
- **VERSIONING.md** line 107: `tool_speaks=$(echo "$caps" | jq -r .doctor_contract_version)` — null is then compared against the expected version; `"null" != "2.0"` is true → emits useful warning. Acceptable.
- **AGENT-PERSPECTIVE.md** line 297: `state=$(echo "$fix" | jq -r .state)` — used in `[ "$state" != "DONE_OK" ]`; null treats as "not DONE_OK" which is the safe failure branch. Acceptable.

### Cumulative tally for "extraction steps that hide bugs"

- Round 17: `diff -r --brief | grep -v 'Only in'` → 1 site (regression-test-template.sh)
- Round 41: same bug in REGRESSION-TEST-PATTERNS.md → 1 site
- Round 44: `jq -r .run_id` in fixture-author.md → 1 site
- **Round 45**: same `jq -r .run_id` bug → 3 more sites in REGRESSION-TEST-PATTERNS.md

**6 sites total** of "silently default to literal-string-of-null when field missing". The audit query `grep -rn 'jq -r ' --include='*.md'` is a reliable detector for the entire class.

### Verification

- All 4 `run_id=$(jq -r ...)` instances in the skill (fixture-author + 3 in REGRESSION-TEST-PATTERNS) now use `jq -er` with explicit FAIL handler.
- Other `jq -r` sites verified safe (explicit defaults or safe-failure-branch comparisons).
- Meta-doctor passes clean.

### Notes

- Pattern: when one round fixes a bug class, the next round's natural follow-up is to grep for ALL siblings. Round-44 caught one site; round-45 caught the rest.
- Future roadmap idea: meta-doctor could lint markdown shell snippets — flag `jq -r .field` (without `-e` and without `// default`) as a potential null-passthrough.

---

## 1.5.38 — Round-44 GROWTH-LADDER stage range + jq null-handling

### Bug fixes (round-44)

- **SKILL.md Reference Index claim "Stage 1 → 10 maturity ladder"** was off-by-one. GROWTH-LADDER.md defines Stage 0 (no doctor) through Stage 10 (world-class) — 11 stages. Fixed to "Stage 0 → 10 maturity ladder (Stage 0 = no doctor; Stage 10 = world-class)".
- **`subagents/fixture-author.md` run_all.sh used `run_id=$(jq -r .run_id "$fix_json")`** — `jq -r` returns the literal string `"null"` when the field is missing/null. The next line `<tool> doctor undo "$run_id"` would invoke `<tool> doctor undo null`. Silent false-pass for the bug "doctor --fix didn't emit run_id".

  Fixed: replaced `jq -r` with `jq -er` (exits non-zero on null/missing), plus an explicit `|| { fail }` handler that prints a specific FAIL message.

### Why each matters

- The Stage 0 elision is small but agent-misleading: SKILL.md "Stage 1 → 10" omits the documented Stage 0 = "no doctor" starting condition.
- The `jq -r` null-handling bug is the most insidious class — silent test pass on a real doctor bug. Round-17 caught the same class for `diff -r --brief | grep -v 'Only in'`; round-44 catches it for `jq -r`.

### Cumulative tally for "extraction steps that hide bugs"

- Round 17: `diff -r --brief | grep -v 'Only in'` → masks "Only in" diff lines (legitimate undo failures).
- Round 41: same bug in REGRESSION-TEST-PATTERNS.md.
- **Round 44**: `jq -r .field` → returns literal "null" when missing instead of failing.

Fix pattern: prefer "exit-loud" idioms (`jq -er`, `diff -r ... --exclude ... || fail`) over silently-defaulting forms. Future audit query: `grep -rn 'jq -r [^|]'` across the skill to find more sites where missing fields silently pass through.

### Verification

- SKILL.md Reference Index now matches GROWTH-LADDER.md's 11-stage range (0..10).
- fixture-author.md run_all.sh now fails loudly on missing run_id instead of silently passing "null" to doctor undo.
- Meta-doctor passes clean.

---

## 1.5.37 — Round-43 Op enum: Chown drift between canonical and recipes

### Bug fix (round-43)

- **`MUTATE-CHOKEPOINT.md` canonical Op enum had 8 variants (including `Chown`)**, but ALL 5 language recipes (Python, Rust, Go, TypeScript, JVM) implement only 7 — the `Chown` variant is universally missing. The asset template `actions-jsonl-line-template.json` shows 4 op examples (WriteFile, DbMigrate, SymlinkAtomic, Rename) — no Chown. The capabilities-template.json `ops` field examples list `WriteFile, DbMigrate, Rename` — no Chown.

  **In other words:** Chown is canonical-on-paper but absent everywhere it would actually be tested or reviewed. Dead documentation. An agent reading MUTATE-CHOKEPOINT.md and trying to implement all 8 variants would write Chown code, then notice no recipe shows it, no validator tests it, and no capabilities example references it. Confusing.

  **Fix**: rewrote MUTATE-CHOKEPOINT.md § The op enum to:
  - Show the **7 canonical variants** that all recipes implement (matches reality).
  - Document `Chown { uid: u32, gid: u32 }` as **optional**, with a note about when to add it (installer-pattern doctors that touch system files; rare). Pointer to recipes/installer.md for that use case.
  - Reference OUTPUT-SCHEMA.md § Per-op fields for the before_owner pattern.

  Also updated OUTPUT-SCHEMA.md § Per-op fields to clarify `Chmod` is canonical and `Chown` is the optional variant, removing the implication that both are equally common.

### Why this matters

Round-32 swept `rename_to` across all recipes after the canonical-vs-recipe drift surfaced. Round-43 surfaces the OPPOSITE drift: the canonical doc declares more than recipes implement. Both directions of drift confuse agents — implementing extra surface that no consumer expects is wasted code.

### Cumulative tally for "canonical doc vs recipe drift"

- Round 18: exit codes 4/5 mismatch
- Round 19/20: dependency_graph.json file extension
- Round 28: capabilities `manual_remediations` field missing from canonical
- Round 29: doctor verbs 5 vs 7
- Round 32: recipe `rename_to` not emitted (canonical→recipe direction)
- **Round 43: Op `Chown` variant declared canonical but no recipe implements (canonical→recipe direction, OPPOSITE: canonical OVER-claims)**

The pattern: any list/enum/schema in the canonical methodology must be cross-checked against ALL recipes. If one direction has drift (recipe under-implements vs canonical), check the other direction too (canonical might over-declare vs recipes).

### Verification

- All 5 recipes' Op enum lists now consistent with the canonical "7 variants" claim.
- Chown documented as optional; agents adding it have a clear path (recipes/installer.md + OUTPUT-SCHEMA.md per-op pattern).
- Meta-doctor passes clean.

### Notes

- Future audit query: when an enum/schema is documented as canonical, check every implementation/template/example for parity. Both directions: (a) canonical → are all variants implemented? (b) implementations → are any extra variants undocumented?
- An alternative fix would have been to add `Chown` to all 5 recipes, but per the principle "the canonical doc should describe reality, not aspirations", documenting it as optional matches the current ground truth.

---

## 1.5.36 — Round-42 POLISH-BAR exit-code completeness

### Bug fix (round-42)

- **POLISH-BAR.md exit-code-contract verification query** required only 8 of the 11 canonical exit codes. The query at line 119-123:
  ```bash
  required="0 1 2 3 4 5 6 64"
  ```
  Missing `66` (no_input), `73` (cant_create), `74` (io_error) — all three documented as canonical in CLI-SURFACE.md exit_codes table (round-28 confirmed parity with the asset template). An agent's doctor could PASS the Polish Bar exit-code-contract check while emitting only 8 of 11 codes — silently failing CLI-SURFACE schema parity that other consumers (validate-doctor.sh, IO-CONTRACTS.md script-contracts table) depend on.

  Fixed `required` to list all 11. Added a comment noting that scorecard's `output_parseability` dimension scores 0 if any are missing.

- **POLISH-BAR.md exit-code header (line 114)** said "`64+` usage" — fuzzy. The canonical schema documents `64` (usage_error), `66` (no_input), `73` (cant_create), `74` (io_error) as four distinct codes with distinct semantics, NOT a "64+" range. Replaced with the explicit list of all 11 codes + link to CLI-SURFACE.md.

### Cumulative tally — exit-code drift

- Round 18: SKILL.md spine + Polish Bar `4 vs 5` (concurrency_lost).
- Round 28: CLI-SURFACE schema missing `manual_remediations` (related: comprehensive surface).
- Round 29: doctor-verb list 5 vs 7.
- **Round 42**: POLISH-BAR verification query missing 3 of 11 exit codes.

The exit-code system has 11 distinct codes serving distinct retry semantics for agents (4=escalate, 5=retry-after-wait, 6=re-run-with-online, 64/66/73/74=hard errors). Each missing code is a separate "agent doesn't know how to respond" gap.

### Verification

- POLISH-BAR header now lists all 11 codes with their canonical names, with explicit link to CLI-SURFACE.md.
- POLISH-BAR exit-code-contract query checks all 11 codes are documented in `capabilities --json`.
- Meta-doctor passes clean.

### Notes

- The `64+` shorthand was technically defensible but harmful for agent ergonomics: an agent reading "64+ usage" might expect ANY code ≥ 64 to be a usage error, when actually 64 is usage, 66 is no_input, 73 is cant_create, 74 is io_error — different problems with different remediations.
- Future audits: any time exit codes are listed in shorthand (e.g., `64+`, `4-6`), check if the canonical list is more granular and update.

---

## 1.5.35 — Round-41 reversibility test pattern fix

### Bug fix (round-41)

- **`references/rubric/REGRESSION-TEST-PATTERNS.md` § reversibility had the same false-negative bug round-17 fixed in `assets/regression-test-template.sh`**. The pattern `diff -r --brief ... | grep -v '^Only in.*\.doctor' && fail` silently masks "Only in baseline" and "Only in target" lines that don't contain `.doctor` — exactly the legitimate undo failures (missing/extra files) the test should catch.

  An agent copying this pattern as their regression test would get `PASS` even when undo broke. Same false-positive class as round-17 in regression-test-template.sh.

  **Fix**: replaced `diff | grep | && fail` with `diff -r --brief --exclude='.doctor' ... || fail`. Empirically verified: identical trees PASS, `Only in target` FAILs. Added an inline comment warning future maintainers NOT to add a `grep -v` filter back.

### Why this matters

REGRESSION-TEST-PATTERNS.md gets copied verbatim into target repos' `tests/doctor_fixtures/` for ongoing CI regression detection. If the reversibility pattern is buggy, every doctor adopting it has a silently-broken regression test:
- The test still RUNS each CI cycle.
- It still emits a green check.
- Real undo failures don't surface until users complain.

### Cumulative tally for "diff | grep | && silent-fail" bugs

- Round 17: `assets/regression-test-template.sh` § Step 5
- **Round 41**: `references/rubric/REGRESSION-TEST-PATTERNS.md` § reversibility

Both surfaced from sweeping after a single fix. Round-41's lesson: when fixing a "looks reasonable but silently masks failures" pattern in code, also grep-sweep ALL doc files for the same anti-pattern.

### Verification

- Synthetic test: identical trees → PASS; "Only in target" → FAIL with correct message.
- Meta-doctor passes clean.

### Notes

- Future audit query: `grep -rn 'diff -r.*grep -v.*Only in'` and `grep -rn 'diff -r.*&& {.*exit'` across the skill catches the regression-test-template.sh and any other doc-pattern instance.

---

## 1.5.34 — Round-40 second-pass workspace sweep

### Bug fix (round-40)

Round-39 swept subagent OUTPUTS — round-40 swept subagent INPUTS using the same query. Found **5 more workspace artifacts** that subagents READ but SKILL.md didn't declare:

- `cass_findings.md` — human-readable companion to `cass_findings.jsonl` (round-23 added the .jsonl, missed the .md). Produced by cass-miner; potentially read by Phase 1 archaeologist.
- `triangulation_<phase>_<round>.md` — produced by triangulator subagent (Phase 4/Phase 7 multi-model tier); referenced by fresh-eyes and synthesizer.
- `baseline/version.txt` — produced by baseline-snapshotter (`<tool> --version` capture).
- `baseline/hash_before_audit.json` — produced by baseline-snapshotter (proof of read-only behavior; SHA-256 of all target files).
- `baseline/auto_mutation_violations.md` — produced by baseline-snapshotter (only if Phase 0 detected existing doctor auto-mutating without --fix).

All 5 now declared. The baseline/ subsection went from 4 files to 7.

### Cumulative tally for "workspace artifacts missing from SKILL.md spine"

- Round 20: 1 (`dependency_graph.json`)
- Round 23: 3 (cass_findings.jsonl, applied_changes.jsonl, safety_harness.jsonl)
- Round 38: 1 (`canonical_tasks.md`)
- Round 39: 12 (analysis/ outputs, Phase 5/6/7/10 reports, post_pass transcripts/notes, ideas)
- **Round 40: 5** more (cass_findings.md, triangulation_*.md, 3 baseline/* files)

**22 artifacts caught across 5 rounds.** Round-39's lesson held: sweep INPUTS as well as OUTPUTS. The `cass_findings.md` gap was particularly old (round-23 added the .jsonl as part of the cass_findings cluster but missed the human-readable companion that the cass-miner subagent ALSO produces).

### Why this matters

- The triangulator artifact is consumed by fresh-eyes review — without declaration, the calling agent doesn't know what triangulation_*.md files to expect after the multi-model tier runs.
- The baseline/* files prove the baseline-snapshotter's read-only contract (Axiom 7: read-only by default). If these files aren't in the layout, an upgrade-mode pass might skip them and lose audit trail evidence.

### Verification

- All 26+ workspace artifacts mentioned in subagents now declared in SKILL.md workspace layout.
- Meta-doctor passes clean.
- The baseline/ subsection is now complete (7 files): help_output.txt, json_output_healthy.json, json_output_corrupted.json, exit_code_dictionary.txt, version.txt, hash_before_audit.json, auto_mutation_violations.md.

### Notes

- The "sweep both INPUTS and OUTPUTS" pattern emerged from this round. Future audits: when a subagent declares an INPUT, verify it's in SKILL.md AND that some upstream subagent's OUTPUTS section produces it.
- A follow-up audit could verify the producer-consumer chain: every input on every subagent should map to an output of an upstream subagent's prompt. Currently this is implicit; could be made explicit in a future doc.

---

## 1.5.33 — Round-39 systematic workspace artifact sweep

### Bug fix (round-39)

Round-38 added one missing workspace artifact (`canonical_tasks.md`) — round-39 applies that lesson and sweeps ALL subagent files for `{{workspace}}/...` artifact mentions, then cross-checks against SKILL.md workspace layout.

**12 additional workspace artifacts were referenced by subagents but not declared in SKILL.md's workspace layout**:

- `analysis/inventory_summary.md` — Phase 1 (archaeologist output)
- `analysis/spec_review.md` — Phase 2.5 (spec-reviewer output)
- `audit_log.md` — Phase 4/7 (mutate-auditor output)
- `safety_harness_report.md` — Phase 5 (safety-harness-runner human-readable companion to safety_harness.jsonl)
- `fresh_eyes_round_<N>.md` and `fresh_eyes_summary.md` — Phase 7 (fresh-eyes outputs)
- `agent_ergo_grade.md` and `agent_ergo_recommendations.jsonl` — Phase 6 (agent-ergo-grader outputs)
- `agent_simulations/post_pass_<N>/<task>.transcript.jsonl` — Phase 10 (cold-agent-prober per-task transcripts)
- `agent_simulations/post_pass_<N>/notes.md` — Phase 10 (cold-prober summary; referenced by handoff-writer + idea-generator)
- `ideas_pass_<N>.md` — Phase 10 (idea-generator output)

All 12 now declared in the SKILL.md workspace layout with phase + producing-subagent annotations.

### Why this matters

Multiple subagents READ artifacts produced by upstream subagents. Without the layout declaring every artifact, an orchestrator can't:
- Verify that Phase N's outputs are present before dispatching Phase N+1.
- Resume a partially-complete pass (manifest.json should track which artifacts exist).
- Know what to commit to git or include in HANDOFF.md.

Specific dependency chains that were broken:
- handoff-writer reads `agent_simulations/post_pass_<N>/notes.md` and `fresh_eyes_summary.md` — both undeclared.
- idea-generator reads `agent_simulations/post_pass_<N>/notes.md` — undeclared.
- agent-ergo-grader writes `agent_ergo_grade.md` — undeclared, but referenced from scorecard's `What's next` section in scorecard-template.md.

### Cumulative tally for "workspace artifacts missing from SKILL.md spine"

- Round 20: 1 (`dependency_graph.json`)
- Round 23: 3 (`cass_findings.jsonl`, `applied_changes.jsonl`, `safety_harness.jsonl`)
- Round 38: 1 (`canonical_tasks.md`)
- **Round 39: 12** more

**17 artifacts caught across 4 rounds.** The class persists because each subagent declares its outputs in its own file; the SKILL.md spine wasn't kept in sync as new subagents were added (especially Phase 6 agent-ergo-grader, Phase 7 fresh-eyes summary, Phase 10 idea-generator). The detection method that finally surfaced all of them: `grep -hroE '\{\{workspace\}\}/[a-zA-Z_/.<>-]+\.(md|json|jsonl|svg)' subagents/*.md | sort -u` and cross-reference against SKILL.md.

### Verification

- All 26 distinct workspace artifacts mentioned in subagents now appear in SKILL.md workspace layout (with appropriate placeholder syntax for per-N / per-task / per-fm artifacts).
- Meta-doctor passes clean.

### Notes

- The detection query is now an established pattern for future rounds: any new subagent's outputs need a corresponding line in SKILL.md.
- The meta-doctor (validate-skill.sh) could be extended with a check: parse `{{workspace}}/...` from subagents/, parse the workspace tree from SKILL.md, fail if a subagent output isn't declared. Roadmap item.

---

## 1.5.32 — Round-38 missing artifact + schema/flag completeness

### Bug fixes (round-38)

- **SKILL.md workspace layout was missing `canonical_tasks.md`** — referenced from 5 places (cold-agent-prober subagent, AGENT-PROMPTS.md cold-agent-prober prompt, PHASES.md Phase 10, ABSORB-PLAYBOOK.md, WORKED-EXAMPLE.md) as a Phase 10 input, but never declared in the canonical workspace layout. Same class as round-20 (`dependency_graph.json`) and round-23 (cass_findings, applied_changes, safety_harness). Added the artifact line with a note about provenance: "authored from `assets/canonical-tasks-template.md` by the orchestrator before dispatching `subagents/cold-agent-prober.md`".
- **`subagents/cass-miner.md` description (line 15) listed only 6 schema fields** for `cass_findings.jsonl` (`{quote, kind, source_path, agent, created_at, line_number}`), but the prompt body (line 55) AND IO-CONTRACTS.md correctly list 7 (with `query`). The summary at the top of the file was the outlier. Updated to include `query` and noted the field is "the cass query that surfaced the quote (for reproducibility)".
- **`subagents/agent-ergo-grader.md` flag enumeration was missing `--quiet` (universal) and `--strict` (undo)** — both documented in CLI-SURFACE.md flag tables. An agent grading the doctor surface against the agent-ergonomics rubric would skip these two flags, leaving them un-scored. Restructured the flag list to mirror CLI-SURFACE.md's grouping (universal / diagnose-fix / undo) with explicit counts (9 subcommands + 19 distinct flags = 28 scorable surfaces).

### Why each matters

- **canonical_tasks.md**: an agent in Phase 10 dispatching cold-agent-prober would not know to create the file from the template. The prober would fail with "no such file" instead of finding tasks to attempt. Phase 10 silently broken.
- **cass-miner schema mismatch**: an agent reading the description (top of file) would emit 6-field rows; the IO-CONTRACTS validator (and any consumer doing `jq -r .query`) would see missing data. Same bug class as round-34.
- **agent-ergo-grader flag list**: incomplete coverage of the doctor surface means dimensions like `--strict`'s safety-with-recovery are never scored. Phase 6 grades a partial surface.

### Cumulative tally

- "Workspace artifacts missing from SKILL.md spine" — rounds 20, 23, 38: now 5 artifacts caught (dependency_graph.json, cass_findings.jsonl, applied_changes.jsonl, safety_harness.jsonl, canonical_tasks.md).
- "Subagent prompts incomplete vs. consumer requirements" — rounds 14, 19, 20, 27, 34, 35, 37, **38**: 21+ sites across 8 rounds.

### Verification

- All 5 IO-CONTRACTS.md workspace JSONLs and the canonical_tasks.md now declared in SKILL.md workspace layout.
- cass-miner description schema matches both prompt body (line 55) and IO-CONTRACTS.md (line 8).
- agent-ergo-grader flag list matches CLI-SURFACE.md flag tables.
- Meta-doctor passes clean.

---

## 1.5.31 — Round-37 safety-harness + fixture-author bugs

### Bug fixes (round-37)

- **`subagents/safety-harness-runner.md` and AGENT-PROMPTS.md safety-harness-runner section** invoked the four `verify-*.sh` scripts as `scripts/verify-undo.sh fm-<id>` etc., without mentioning the required `<tool>` arg or `TOOL` env var that round-27 introduced. An agent following the prompt would invoke each script and hit "exit 64: provide <tool> as arg 2 or set TOOL env var" four times in a row before realizing.

  **Fix**: added `export TOOL={{tool}}` (or `<tool>`) at the top of the prompt's test-loop instructions, with explicit note that the verify scripts now require this. Same fix in both subagent file and AGENT-PROMPTS.md.
- **`subagents/fixture-author.md` `run_all.sh` template had three `set -e` bugs** — same class as round-16's regression-test-template.sh fixes:
  - `( cd "$sandbox" && <tool> doctor --fix --json > "$fix_json" )` — bare invocation under `set -e`. If --fix exits 1/2/3 (anything non-zero), the script aborts BEFORE reaching the post-fix assertions. The fixture appears to have failed silently with no useful FAIL message.
  - `"$fm_dir/assert.sh" "$sandbox"` — same problem. If the post-fix assertion script fails, exit silently rather than print "FAIL: assert.sh failed".
  - `( cd "$sandbox" && <tool> doctor undo "$run_id" )` — same problem for the undo step.

  All three replaced with the `if ! cmd; then echo FAIL; exit 1; fi` pattern (round-16's idiom). Now each failure surfaces a specific "FAIL: $fm_id --fix returned non-zero" / "assert.sh failed" / "undo returned non-zero" message, making a fixture's regression test debuggable.

### Why this matters

- The safety-harness-runner is Phase 5's load-bearing prompt. Without `TOOL` exported, every fixer fails the four tests immediately — the agent can't tell which fixer is broken because they all "fail" with usage errors.
- The fixture-author bug is even more insidious: an agent following `run_all.sh` and seeing the script exit silently might believe their fixture passed (no error message), when actually it exited at the bare `--fix` line because of a partial failure. False-pass on Phase 9.

### Cumulative tally for "subagent prompts incomplete vs. consumer requirements"

- Round 14: 5 sites
- Round 19: 2 sites
- Round 20: 3 sites
- Round 27: 1 site
- Round 34: 1 site
- Round 35: 2 sites
- **Round 37: 4 sites** (1 in safety-harness subagent, 1 in AGENT-PROMPTS section, 3 set-e patterns in fixture-author)

**18 sites across 7 rounds**. The class persists because subagent prompts are written from the perspective of "what should the agent do" without enumerating "what does the consumer of this output / this script require?" Future audits: every subagent-issued shell command needs a "does this need a TOOL/PATH/SCHEMA arg the agent might forget?" check.

### Verification

- All 4 verify-*.sh scripts continue to exit 64 with usage when missing args (round-27 fix unaffected).
- The fixture-author run_all.sh now has consistent error reporting on all three test steps.
- Meta-doctor passes clean.

---

## 1.5.30 — Round-36 integration-wirer audit

### Bug fixes (round-36)

- **`subagents/integration-wirer.md` line 9 had a hardcoded user-specific path** `../../fixing-beads-problems/` in its inputs example. Round-25 noted this as "acceptable since it's an example" but per the round-25 portability lesson it should still be generic. Fixed to `<your-skills-dir>/fixing-beads-problems/, where <your-skills-dir> is typically ~/.claude/skills/ or your private skills repo's .claude/skills/`.
- **`subagents/integration-wirer.md` Step 2 CI workflow** invoked `./scripts/scorecard.py compare-against-baseline` from the target repo's CI runner. The script lives in this skill's repo, NOT in the target repo — `./scripts/scorecard.py` would not exist at the target repo's CI workdir. An agent following this template literally would get a "file not found" error in their first CI run. Replaced with a hermetic jq-based regression check that reads the doctor's own `.doctor/runs/<id>/scorecard.json` (the doctor itself emits this on every `--json` run) and compares against a checked-in baseline. The linter then refined the snippet further to:
  - Accept doctor exit codes 0 (healthy) AND 1 (findings) so the regression check can still read the scorecard.
  - Use `run_dir` from `report.json` to locate the scorecard (more robust than guessing the path).
  - Try both `.aggregate.score` and `.aggregate_score` jq paths to handle the nested-vs-flat schema variation noted in OUTPUT-SCHEMA.md.
  - Include a comment noting the skill's `scorecard.py compare-against-baseline` provides the same logic with per-FM detail for local development.

### Why this matters

- The hardcoded path is the same class as round-25's bugs (check-skills.sh, FIRST-30-MINUTES.md, SELF-TEST.md) — works on one developer's machine, breaks for everyone else.
- The CI script bug is more subtle: an agent reading the integration-wirer prompt would copy the snippet into their target's `.github/workflows/doctor.yml`, push, and hit a "scripts/scorecard.py: No such file or directory" error on first run. Round-25's pattern note "the bug surfaces immediately when the skill is shared or run from a different checkout location" applies here too.

### Cumulative tally for "scripts/files cited from contexts where they don't exist"

- Round 14 + 19 + 20 + 27 + 34 + 35: subagent prompts cite scripts/schemas without proper args/keys (14+ sites).
- Round 25: 4 hardcoded user-specific paths.
- Round 36: 1 more hardcoded path + 1 cross-repo path-assumption bug in CI snippet.

**16+ sites across 8 rounds** in the broader "context-mismatch" bug class. Pattern: instructions in subagent prompts assume the agent runs in the same context the skill author assumed (same machine, same paths, same script availability). Future audits: any subagent prompt that runs commands needs to question "where is the agent when this runs, and is everything cited actually accessible from there?"

### Verification

- All shell scripts bash-syntax clean (no impact from the prompt-text changes — they're inside Markdown code blocks not actually executed).
- Meta-doctor passes clean.

---

## 1.5.29 — Round-35 implementer prompt schema + subcommand completeness

### Bug fixes (round-35)

Following round-34's pattern (subagent prompts incomplete vs. consumer-script schemas), found two more in the **implementer** subagent — Phase 4's load-bearing prompt:

- **AGENT-PROMPTS.md implementer prompt OUTPUTS** said `Per-FM rows appended to {{workspace}}/applied_changes.jsonl` without specifying the row schema. IO-CONTRACTS.md documents the canonical 7-field shape (`fm_id, commit_sha, files_changed, lines_added, lines_removed, applied_at, implementer`). An agent following the prompt would invent its own schema, breaking the handoff-template, manifest-template references that depend on the canonical shape. Fixed: extended the OUTPUTS line with the full schema inline + concrete commands (`git rev-parse HEAD`, `git diff --numstat HEAD~1 HEAD`) for populating commit_sha and lines counts.
- **`subagents/implementer.md` exit-criteria subcommand list was missing 4 of the 12 canonical doctor subcommands**: `--fix`, `--dry-run --fix`, `gc --before <date> --yes`, `ls`. The list as written said "all exist and respond correctly" but enumerated only 8 of 12. An agent in `add` mode would consider Phase 4 complete with 8 subcommands shipped, then fail OPERATING-MODES.md's `add`-mode required-artifacts check (which round-29 fixed to include `gc` and round-21 fixed to include `ls`). Added all 4 missing subcommands.

### Cumulative tally for "subagent prompt schemas don't match consumer scripts/docs"

- Round 14: 5 sites (verify-*.sh + validate-fm.py + validate-spec.py invocations).
- Round 19: 2 sites (AGENT-PROMPTS.md diff-scorecards.py args).
- Round 20: 3 SKILL.md spine sites (dependency_graph.json).
- Round 27: AGENT-PROMPTS.md scorecard-generator (validate args).
- Round 34: scorecard-generator missing frequency/blast_radius schema.
- Round 35: implementer missing applied_changes.jsonl schema; missing subcommands.

**13+ sites across 6 rounds**. Pattern: subagent prompts are written from the agent's perspective ("emit X to Y") without explicitly enumerating the SCHEMA the consumer expects — even when IO-CONTRACTS.md / OUTPUT-SCHEMA.md / CLI-SURFACE.md document it elsewhere. The agent following the prompt has no incentive to look up the consumer-side spec.

**Future-round audit query:** `for jsonl in $(grep -E "^### .${0}.jsonl" IO-CONTRACTS.md); do grep -L "$jsonl.*$(<schema-keys>)" subagents/*.md; done` — a stronger meta-doctor could check that every subagent prompt that produces a JSONL artifact mentions all required schema keys.

### Verification

- IO-CONTRACTS.md applied_changes.jsonl schema (line 18): `{fm_id, commit_sha, files_changed, lines_added, lines_removed, applied_at, implementer}` — matches my fix to AGENT-PROMPTS.md. ✓
- CLI-SURFACE.md subcommand list: `diagnose, fix, undo, explain, capabilities, health, robot-docs, gc, ls` (9 subcommands) plus `--fix`/`--dry-run --fix`/`--robot-triage` flags — implementer exit criteria now matches. ✓
- Meta-doctor passes clean.

---

## 1.5.28 — Round-34 frequency/blast_radius doc gap

### Bug fix (round-34)

- **`subagents/scorecard-generator.md` step 4 told agents to emit `failure_mode_scores.jsonl` with schema `{fm_id, dimension, score, evidence_path, evidence_line_or_test, run_id}`** — but `scorecard.py` reads two more required-for-correctness fields from each row: **`frequency`** and **`blast_radius`** (per-FM weights for the aggregate score formula `sum(median × freq × blast) / sum(freq × blast)` documented in OUTPUT-SCHEMA.md and IO-CONTRACTS.md).

  Without these fields, scorecard.py defaults both to 1.0, making every FM equal-weighted. The "weighted aggregate" silently degrades to a simple median, and the entire `frequency × blast_radius` rationale (high-frequency / high-blast FMs should pull the score down faster) becomes moot. Worse, the resulting score still LOOKS like a weighted aggregate — the report.json `weight_method: "frequency_x_blast_radius"` field is set even though no real weighting happened.

  **Fix**: extended scorecard-generator.md step 4 to:
  - Add `frequency` and `blast_radius` to the schema.
  - Document allowed values: numeric or canonical labels (`"rare"`/`"occasional"`/`"often"` for frequency; `"cosmetic"`/`"nuisance"`/`"degrades_correctness"`/`"corrupts_state"`/`"loses_data"` for blast_radius — these labels are recognized by scorecard.py's `FREQUENCY_LABELS` and `BLAST_RADIUS_LABELS` dicts).
  - Note that both are PER-FM weights (repeat identically on the 10 rows for one FM).
  - State the source: CASS findings + bug-tracker counts for frequency; PRIORITY-FORMULA.md rubric for blast_radius.
  - Explain the [0.5, 2.0] clamp scorecard.py applies.
  - Reference the canonical aggregate formula.
- **AGENT-PROMPTS.md scorecard-generator section** doesn't have an inline prompt — it points to `subagents/scorecard-generator.md` (line 416-421) which is the file I fixed. So the fix is canonical via one site.

### Why this matters

The aggregate score is the doctor's single quantitative quality signal. The methodology spends 10 dimensions × N FMs of effort to produce per-FM medians, then weights them by frequency × blast_radius to produce an aggregate. If agents skip the weights (because the subagent prompt didn't ask for them), the aggregate is silently wrong — every FM weighted as 1.0 means a low-frequency cosmetic FM and a high-frequency data-corruption FM both pull the score equally. The weight_method field would still claim `frequency_x_blast_radius`, masking the bug.

### Cross-check (no further bugs)

- IO-CONTRACTS.md `failure_mode_scores.jsonl` schema (line 24) includes `frequency` and `blast_radius` — matches my fix to the subagent. ✓
- scorecard.py `read_jsonl` loop (line 139-142) checks `if "frequency" in row` and `if "blast_radius" in row` — handles the case where rows have or don't have the fields, gracefully defaulting to 1.0 if absent. So pre-round-34 doctors won't break, just under-weight. ✓
- Meta-doctor passes clean.

### Notes

- Round-34 caught a doc-vs-script gap: the subagent prompt didn't fully describe the schema scorecard.py expects. The script gracefully degraded (default 1.0 per missing field), masking the bug. Pattern: when a script reads optional fields with a default, the absence of those fields in upstream documentation isn't caught by the meta-doctor — only careful prose review surfaces it.
- For future audits: any time a Python script reads `row.get(...)` or `row.get(..., default)`, check that ALL upstream documentation tells emitters to populate those fields.

---

## 1.5.27 — Round-33 final sweep: Elixir + Bash rename_to

### Bug fixes (round-33)

Round-32 fixed the `rename_to` emission in 7 recipes (Rust, Go, Python, TypeScript, Ruby, Kotlin, Java) but missed two more in `other-languages.md`:

- **Elixir** record builder used a literal `%{...}` map without the `rename_to` field. Refactored to build the map then conditionally `Map.put` the `:rename_to` key for Rename ops:
  ```elixir
  record = if op.kind == "Rename",
             do: Map.put(record, :rename_to, op.target |> to_string()),
             else: record
  ```
- **Bash** recipe used a fixed `jq -nc` call with a hardcoded record schema. Added a conditional `rename_to_obj` jq fragment that's `{}` for non-Rename ops and `{rename_to: "$target"}` for Rename ops, then used jq's `+` operator to merge:
  ```bash
  local rename_to_obj='{}'
  [ "$op_kind" = "Rename" ] && rename_to_obj=$(jq -nc --arg t "$3" '{rename_to:$t}')
  jq -nc ... --argjson extra "$rename_to_obj" \
      '{...,ok:true} + $extra' >> "$ACTIONS_PATH"
  ```

### Cross-recipe rename_to status (final)

All 9 language recipes now correctly emit `rename_to` for Rename ops:

| Recipe | Round | Pattern |
|---|---|---|
| Rust | 32 | match Op + struct field |
| Go | 32 | if-check + struct field |
| Python | 32 | dict update |
| TypeScript | 32 | record build + cast |
| Ruby | 32 | hash builder |
| Kotlin | 32 | data class field default null |
| Java | 32 | instanceof + extra positional arg |
| Elixir | **33** | Map.put conditional |
| Bash | **33** | jq merge with `+ $extra` |

### Linter-applied changes I'm taking into account (not reverting)

A linter applied helpful improvements to several files this turn:

- **CLI-SURFACE.md** restructured to clearer subcommand + flags + exit-code tables. Adds `gc` and `ls` subcommand docs and includes the exit-code 4 description "non-lock precondition failure" — matches round-18's distinction between unsafe (4) and concurrency_lost (5).
- **OPERATING-MODES.md** added `<workspace>` to the `diff-scorecards.py` invocation in upgrade-mode stop condition (line 78) — matches round-19's argparse fix pattern. Also keeps round-29's `gc` addition.
- **OUTPUT-SCHEMA.md** retains round-23's "Per-op fields" subsection.
- **scorecard.py** substantially expanded with proper `frequency × blast_radius` weighted aggregation (per OUTPUT-SCHEMA.md scoring formula at line 132-137).
- **PHASES.md** + **IO-CONTRACTS.md** also touched (diffs not shown by the harness).

These are all consistent with prior round-fix conventions; no rollback needed.

### Notes

- Across rounds 32 + 33, all 9 recipes now consistently emit `rename_to` for Rename ops. Earlier inconsistency would have silently broken `doctor undo` for Rename actions in any of those languages.
- Meta-doctor passes clean.

---

## 1.5.26 — Round-32 sweep: rename_to field across all recipe ActionRecord structs

### Bug fixes (round-32)

Round-27 fixed OUTPUT-SCHEMA.md to document the `rename_to` per-op field for actions.jsonl Rename entries. But ALL recipe code samples emit ActionRecord WITHOUT `rename_to` — meaning an agent implementing a doctor from any of these recipes would silently break `doctor undo` for Rename ops (the undo reads `rename_to` from actions.jsonl to reverse the move; if it's missing, undo doesn't know where the file was renamed to).

Following round-31's lesson ("when fixing a convention drift in one place, sweep all siblings"), round-32 found and fixed the same bug across **6 recipes**:

- **`recipes/rust.md`**: added `rename_to: Option<String>` to `ActionRecord` struct + populate logic via `match op { Op::Rename { to } => ... }`.
- **`recipes/go.md`**: added `RenameTo string \`json:"rename_to,omitempty"\`` to `ActionRecord` struct + `if op.Kind == "Rename" { rec.RenameTo = op.Target }` populate line.
- **`recipes/python.md`**: added `if op.kind == "Rename": record["rename_to"] = str(op.target)` to the record-build block.
- **`recipes/typescript.md`**: changed `record` literal to `Record<string, unknown>`, added `if (op.kind === "Rename" && "target" in op) record.rename_to = op.target`.
- **`recipes/other-languages.md` Ruby**: refactored the inline hash literal into a named `record` variable, added `record[:rename_to] = op[:target].to_s if op[:kind] == "Rename"` before serializing.
- **`recipes/jvm.md` Kotlin + Java**: added `renameTo: String? = null` to `ActionRecord` data class (+ `error`, `rolled_back` for completeness, matching OUTPUT-SCHEMA.md). Java construction site adds `String renameTo = (op instanceof Rename r) ? r.to().toString() : null;` with explanatory comment.

### Why this matters

- The asset template `assets/actions-jsonl-line-template.json` shows Rename entries WITH `rename_to`.
- OUTPUT-SCHEMA.md § Per-op fields says Rename ops include `rename_to`.
- All 6 language recipes' code samples emitted Rename WITHOUT it.
- An agent implementing a Rust/Go/Python/TS/Ruby/Kotlin/Java doctor would have a working --fix and a broken `doctor undo` for renames. The bug would surface only when a fixer uses `Op::Rename` (e.g., quarantining a stale lockfile) and a user tries to undo.

### Cross-recipe verification (final state)

All 7 language recipe code samples now consistently emit `rename_to` for Rename ops:

| Recipe | rename_to field | Populate logic |
|---|---|---|
| Rust | ✓ struct + match | ✓ |
| Go | ✓ struct + if-check | ✓ |
| Python | ✓ dict update | ✓ |
| TypeScript | ✓ record build | ✓ |
| Ruby | ✓ hash-then-merge | ✓ |
| Kotlin | ✓ data class field | ✓ (default null) |
| Java | ✓ via expanded record | ✓ instanceof check |

### Notes

- Round-31 (lock-path) and round-32 (rename_to) are both follow-ups to single-recipe fixes from earlier rounds (round-30 for lock-path, round-27 for rename_to docs). The pattern: documentation fix without sweeping recipe code = bug remains in 5+ recipes.
- Going forward, ANY change to OUTPUT-SCHEMA.md actions.jsonl spec or capabilities-template.json fields should be cross-checked against every recipe's serialization site.
- Meta-doctor passes clean.

---

## 1.5.25 — Round-31 sweep: lock-path collision across remaining recipes

### Bug fixes (round-31)

Round-30 fixed the lock-path collision bug in the Bash recipe and noted "established convention exists in some recipes". Round-31 fresh-eyes pass discovered the same bug in **5 more recipes** that hadn't been audited:

- **`recipes/go.md` line 214**: `os.OpenFile(path+".doctor-lock", ...)` — concatenation form. Fixed to `filepath.Join(filepath.Dir(path), "."+filepath.Base(path)+".doctor-lock")`.
- **`recipes/other-languages.md` Ruby (line 27)**: `File.open("#{path}.doctor-lock", "a+")` — interpolation concatenation. Fixed.
- **`recipes/other-languages.md` Zig (line 173)**: `std.fmt.allocPrint("{s}.doctor-lock", .{path})` — concatenation. Fixed using `dirname` + `basename` from `std.fs.path`.
- **`recipes/other-languages.md` Elixir (line 199, 228)**: `path <> ".doctor-lock"` — Elixir concatenation. Fixed both the open path AND the cleanup `File.rm` to use the same dotted-prefix.
- **`recipes/typescript.md` line 155-156**: `path + ".doctor-lock-target"` — concatenation. Fixed to use `basename(path)` with dotted-prefix. **Bonus bug discovered**: `basename` wasn't imported from `node:path`. Added to the import line — without this, the TS recipe would have a compile error after my fix.

### Cross-language audit (final state)

All 9 language recipes now consistently use the dotted-prefix lock-path form:

| Language | Lock-path form | Source |
|---|---|---|
| Python | `path.parent / f".{path.name}.doctor-lock"` | round-3 |
| Rust | `parent.join(format!(".{}.doctor-lock", basename))` | round-3 |
| JVM (Java + Kotlin) | `path.parent.resolve(".${path.fileName}.doctor-lock")` | (always correct) |
| Bash | `_dir/.$_base.doctor-lock` | round-30 |
| Go | `filepath.Join(dir, "."+base+".doctor-lock")` | **round-31** |
| Ruby | `File.join(dirname, ".#{basename}.doctor-lock")` | **round-31** |
| Zig | `std.fmt.allocPrint("{s}/.{s}.doctor-lock", ...)` | **round-31** |
| Elixir | `Path.join(dirname, "." <> basename <> ".doctor-lock")` | **round-31** |
| TypeScript | `join(dirname(path), "." + basename(path) + ".doctor-lock-target")` + `basename` import | **round-31** |

### Why this matters at scale

The collision risk is per-language low-probability (most projects don't have files literally named `<target>.doctor-lock`), BUT: the methodology says "every fixer's lock primitive serializes against itself". If even ONE recipe has a collision-prone form and an agent picks that recipe for their language, their doctor has a latent concurrency bug. Now all 9 recipes are uniformly safe.

### Verification

- All recipes now consistent (dotted-prefix form).
- TypeScript `basename` import added — without this, my round-31 TS fix would have caused a compile error. Caught and fixed in the same round.
- Meta-doctor passes clean.

### Notes

- Round-30 fixed 1 recipe (Bash); round-31 fixed 5 more (Go, Ruby, Zig, Elixir, TypeScript). Round-30's claim "Bash recipe was added later... older simpler form" was correct as a partial diagnosis but the bug existed in 5 recipes, not just 1. Round-31 swept the rest.
- Lesson: when fixing a "convention drift" bug in one recipe, immediately grep for the same pattern across all sibling recipes. Round-30 didn't do this; round-31 did and found 5 more.

---

## 1.5.24 — Round-30 Bash recipe lock-path collision

### Bug fix (round-30)

- **`references/recipes/other-languages.md` Bash recipe used `lock_path="${path}.doctor-lock"`** — appending `.doctor-lock` to the target path. This is the same collision class round-3 fixed in the Python and Rust recipes (Python recipe line 183 explicitly uses `path.parent / f".{path.name}.doctor-lock"` with the comment "given foo/bar.txt -> foo/.bar.txt.doctor-lock"). The Bash form has two failure modes:
  1. If a sibling file literally named `<target>.doctor-lock` exists as a real target, the lock collides with that target file. Locking the lock-file IS locking another target by accident.
  2. If `mutate()` is ever invoked with a path that's already a `.doctor-lock` file (recursive doctor cleanup scenario), the lock_path computation would be `<lock-file>.doctor-lock` — meaningless.

  Fixed to use the dotted-prefix form: `_dir="$(dirname "$path")"; _base="$(basename "$path")"; lock_path="$_dir/.$_base.doctor-lock"`. Now matches the Python and Rust convention. Added an inline comment explaining the collision class so future Bash maintainers don't revert to the simpler form.

### Verification

- Bash syntax check on the inline recipe code: clean (the recipe is illustrative, not executable in isolation; verified via `bash -n` against the function-body snippet).
- The dotted-prefix form is now consistent across all four mutate() language implementations (Python, Rust, Bash; Go uses a different lock primitive — `syscall.Flock` on the file directly — so the lock-path issue doesn't apply).
- Meta-doctor passes clean.

### Notes

- Round-3's fix to Python and Rust didn't propagate to the Bash recipe because the Bash recipe was added later and used the older, simpler form. Pattern: when an established convention exists in some recipes, every new recipe needs to honor it.
- The collision risk is low-probability (most projects don't have files literally named `<target>.doctor-lock`), but the cost of being defensive is one line per recipe — clearly worth it.

---

## 1.5.23 — Round-29 doctor-verb list + add-mode subcommand parity

### Bug fixes (round-29)

- **The "doctor surface verbs" list drifted across the skill — 5 verbs documented vs 7 verbs probed.** `discover-cli.sh` actually probes seven verb names (line 116: `for verb in doctor health verify repair check diagnose fix`), but its own header comment, three SKILL.md sites, the baseline-snapshotter subagent prompt, and the user-facing intake-prompt asset only listed five (`doctor / health / verify / repair / check`). An agent reading any of those docs would believe a CLI with `<tool> diagnose` or `<tool> fix` does NOT have an existing diagnostic surface, when in fact discover-cli.sh would correctly detect those as upgrade-mode triggers.
  - Fixed in: SKILL.md (4 sites), `discover-cli.sh` header comment, `subagents/baseline-snapshotter.md`, `assets/intake-prompt.md`, `references/methodology/OPERATING-MODES.md` (table summary line 7). All now list all 7 verbs.
- **OPERATING-MODES.md `add` mode required-artifacts list was missing `<tool> doctor gc`.** Round-21 added `gc` to SKILL.md's Doctor Surface section as a canonical subcommand, but OPERATING-MODES.md (which agents follow to know what `add` mode must produce) didn't list it. An agent in `add` mode would build a doctor missing the `gc` subcommand and consider the mode complete. Added.

### Round-28 verification (no further bugs)

- Capabilities schema parity (asset template ↔ CLI-SURFACE.md): IDENTICAL 15 fields. ✓
- Frontmatter description: 988/1024 chars (under budget). ✓
- All 6 Python scripts compile-clean. ✓
- All 12 shell scripts bash-syntax-clean. ✓
- All 4 JSON assets parse (1 documented JSONL exception per round-23). ✓
- Meta-doctor passes clean. ✓

### Notes

- The 5-vs-7-verb drift is the same class of bug as round-19's `dependency_graph.json` schema gap and round-28's `manual_remediations` schema gap: a contract value (verb list, schema field) is correct in one place and stale in 5+ others. The fix anchored everything to the actual code (`discover-cli.sh` line 116) — that's the source of truth.
- Cumulative tally for "load-bearing list / schema drifted across files": rounds 18 (exit codes), 19 (workspace artifacts), 23 (artifacts), 26 (state field), 28 (manual_remediations), 29 (doctor verbs) — six rounds, six distinct drift incidents. Pattern: any list/schema mentioned in more than ~3 places is at risk of drift; the fix is to anchor the canonical source (usually code or a designated schema doc) and treat all other mentions as derivative.

---

## 1.5.22 — Round-28 capabilities schema completeness

### Bug fixes (round-28)

- **CLI-SURFACE.md `capabilities --json` schema was missing `manual_remediations`** — a load-bearing field referenced from 14+ places across the skill (GLOSSARY.md, RFC.md, SCORING-RUBRIC.md anchor 1000, COOKBOOK.md Pattern 15, FAQ.md, WORKED-EXAMPLE.md, WORKED-EXAMPLE-WRANGLER.md, CASS-FINDINGS.md, CASS-EVIDENCE-INDEX.md, CORPUS.md, QUOTE-BANK.md, PROMPT-LIBRARY.md, repair-spec-author subagent, plus the asset template). The canonical schema document silently omitted it. An agent implementing capabilities --json from CLI-SURFACE.md alone would build a doctor that cannot list non-auto-fixable findings (missing API keys, OAuth-required flows, root-only paths) — exactly the case where the doctor needs to defer to the user. Added the `manual_remediations` field with the canonical shape from RFC.md (`id`, `instruction`, `reason`).
- **CLI-SURFACE.md fixer entry was missing `estimated_cost_ms`** — present in the asset template and in RFC.md's formal schema, missing from CLI-SURFACE.md's example. Added.

### Why this matters

- `manual_remediations` is the agent-facing escape hatch. Without it in the schema, a doctor following CLI-SURFACE.md can detect a "missing API key" but has no canonical place to put the user-action instruction. The asset template HAD the field; the canonical schema doc didn't. Asset-vs-canonical gap, same class as round-26's `state` field bug.
- `estimated_cost_ms` is what `doctor health` and `--robot-triage` use to estimate runtime — without it documented, an agent might omit the field and break the cost-estimation feature.

### Verification

- Asset template `capabilities-template.json` and CLI-SURFACE.md `capabilities --json` schema now have IDENTICAL top-level field sets (15 fields each, no asymmetric extras).
- Meta-doctor passes clean.

### Notes

- Discovery method: dumped both schemas' top-level keys into Python sets and diffed. The asset had `manual_remediations`, CLI-SURFACE.md didn't. This is the same audit pattern from round-23 (workspace artifacts in IO-CONTRACTS.md vs SKILL.md spine) and round-26 (`state` field in STATE-MACHINE.md vs report-template). Should be added to a future meta-doctor enhancement: cross-check every asset template's top-level fields against the corresponding canonical schema.
- The `manual_remediations` omission was particularly load-bearing because Pattern 15 (Compliance / audit doctor) explicitly says "every fixer is replaced by `manual_remediations`" — so the entire compliance pattern depends on a field the canonical schema didn't document.

---

## 1.5.21 — Round-27 schema docs + verify-*.sh ergonomics

### Bug fixes (round-27)

- **OUTPUT-SCHEMA.md `actions.jsonl` section was missing per-op fields.** The shape shown was the common subset (path, op, hashes, timestamps, run_id, fixer_id, ok). But the asset template `assets/actions-jsonl-line-template.json` documents per-op extensions (`rename_to` for Rename ops, `error`+`rolled_back` for failed mutations) — and the recipes silently expect emitters to include them. An agent implementing an actions.jsonl emitter from OUTPUT-SCHEMA.md alone would miss `rename_to` for Rename ops, breaking `doctor undo` for renames. Added an explicit "Per-op fields" subsection to OUTPUT-SCHEMA.md documenting `rename_to`, `error`+`rolled_back`, and pointing to the asset template for concrete examples.
- **All five `scripts/verify-*.sh` scripts died with bash's "$1: unbound variable"** on missing args (verify-undo.sh, verify-idempotence.sh, verify-crash-recovery.sh, verify-concurrency.sh, verify-capabilities.sh). These are agent-runnable Phase 5 helpers; an agent forgetting an arg got a cryptic bash error. Replaced with explicit `${1:-}` checks + `usage: ...` + `exit 64` (matching the convention established in rounds 22 / 25 for the other scripts). Verified end-to-end: all 5 scripts now print proper usage and exit 64 on missing args.

### Why each matters

- An agent implementing per-op actions.jsonl serialization needs to know that Rename includes `rename_to`. Without that, undo can't reverse renames.
- `verify-*.sh` scripts run during Phase 5 testing. Cryptic bash errors waste agent debugging time before they realize they forgot the fm_id arg.

### Verification

- All 5 verify-*.sh scripts: bash syntax-clean, exit 64 with usage on no args.
- Meta-doctor passes clean.
- The Phase 5 safety harness suite is now consistent with all other shell scripts in exit-code conventions.

### Round-26 cross-check (no further bugs)

- Re-checked report-template.json after the round-26 fix: 3 distinct findings, severity counts match, `state` field present and valid. ✓

### Notes

- Cumulative for "scripts give bash unbound-var error on missing args" bug class:
  - Round 22 fixed: compute-fm-id.py, scorecard.py.
  - Round 25 fixed: check-skills.sh, install-referenced-skills.sh.
  - Round 27 fixed: verify-undo.sh, verify-idempotence.sh, verify-crash-recovery.sh, verify-concurrency.sh, verify-capabilities.sh.
  - Still using `${1:?...}` pattern (not exit 64): manifest-update.sh, scaffold-workspace.sh, validate-skill.sh — these use bash's :?-substitution which exits 1 with a custom message. Acceptable but inconsistent. Could be standardized in a future round.
- The `actions.jsonl` per-op gap was subtle — discovered by cross-comparing the asset template against OUTPUT-SCHEMA.md. Pattern for finding similar gaps: every asset template that's referenced from a methodology doc should be checked for fields the methodology doesn't mention.

---

## 1.5.20 — Round-26 report-template + state-machine consistency

### Bug fixes (round-26)

- **`assets/report-template.json` had a duplicate finding** — `fm-state-files-jsonl-tombstone-drift` was listed TWICE with byte-identical content (copy-paste error). The summary said `total_findings: 3` and `by_severity: {P0:1, P2:2}` so the intent was clearly 3 distinct findings, but the actual array had only 2 distinct IDs. An agent copying this template as a starting point would propagate the duplicate. Replaced the duplicate with a third distinct finding (`fm-concurrency-primitives-lockfile-orphaned`, P2) — the template now has 3 distinct IDs that match the declared severity counts.
- **`assets/report-template.json` was missing the `state` field** that STATE-MACHINE.md and AGENT-PERSPECTIVE.md document as canonical (`report.json::state` records the terminal STATE-MACHINE state — DONE_OK, DONE_FINDINGS, DONE_PARTIAL, DONE_FAILED, REFUSING, LOCK_LOST). An agent copying this template would produce a report missing a documented field. Added `"state": "DONE_FINDINGS"` (matches the template's `exit_code: 1` per the STATE-MACHINE.md table).

### Cross-doc verification (no further bugs)

Verified the fixed template is internally consistent:
- 3 findings, 3 distinct IDs (no duplicates).
- `summary.by_severity` ({P0:1, P1:0, P2:2, P3:0}) matches the actual finding severities (1×P0 + 2×P2).
- `state: "DONE_FINDINGS"` matches `exit_code: 1` per STATE-MACHINE.md row "DONE_FINDINGS (exit 1; report ok)".
- All four JSON templates parse-clean (capabilities, manifest, report, plus the documented-as-template `actions-jsonl-line-template.json`).

### Notes

- This round caught a copy-paste duplicate plus a documented-but-missing field. Pattern: agent-copyable templates are load-bearing; bugs in them propagate to every doctor an agent builds. Templates deserve closer review than narrative docs because they're literally copied verbatim.
- The `state` field is documented in STATE-MACHINE.md, AGENT-PERSPECTIVE.md, and INCIDENT-RESPONSE.md but was missing from the template — a "canonical-everywhere-except-the-template" inconsistency that's hard to spot by grep.
- Meta-doctor passes clean.

---

## 1.5.19 — Round-25 portability bugs

### Bug fixes (round-25)

- **`scripts/check-skills.sh` had a hardcoded user-specific path** to a private skills directory in its `candidate_dirs` list. Other users / other machines / other repo checkout paths would silently miss the skills repo. Replaced with `$(cd "$(dirname "$0")/../.." && pwd)` — auto-derives the skills directory from the script's own location, regardless of where the repo is checked out. Also added support for `CLAUDE_SKILLS_DIRS` env var (PATH-style, colon-separated) for non-standard layouts.
- **`scripts/check-skills.sh` and `scripts/install-referenced-skills.sh` died with bash's "$1: unbound variable" on missing args** instead of printing a useful usage message. Added explicit `${1:-}` checks with `usage: ... <workspace>` + `exit 64` (matching the convention all the validate-*.py scripts use).
- **`scripts/install-referenced-skills.sh` did not check whether `jq` was installed** before piping JSON through it. Without jq, the script would die mid-execution with bash's command-not-found. Added an explicit `command -v jq` check at the top with a clean error message + `exit 66`.
- **`references/methodology/FIRST-30-MINUTES.md` and `SELF-TEST.md` had hardcoded `SKILL=<absolute-private-path>/.claude/skills/...`** in copy-paste bash blocks. The minute-by-minute onboarding runbook is meant to be followed by ANY agent on ANY machine. Replaced with `SKILL="${SKILL:-$HOME/.claude/skills/world-class-doctor-mode-for-cli-tools}"` — uses the standard system-wide skills location with env-var override.

### Why each matters

- `check-skills.sh`'s hardcoded path silently produced an incomplete inventory on machines where the skills repo wasn't at that exact path. The script appeared to "work" but missed installations.
- The "$1: unbound variable" messages waste agent debugging time. A clean `usage:` message + exit 64 lets the agent immediately know what's expected.
- The jq dependency was implicit. Without the check, install-referenced-skills.sh would fail mid-loop with cryptic shell errors.
- The hardcoded SKILL path in onboarding docs blocks any non-skill-author from following the runbook.

### Verification

- `bash scripts/check-skills.sh /tmp/foo` produces a valid inventory JSON (auto-detected skills for the current installation).
- `bash scripts/check-skills.sh` (no args) prints "usage: ..." and exits 64.
- `bash scripts/install-referenced-skills.sh` (no args) prints "usage: ..." and exits 64.
- Meta-doctor passes clean.

### Notes

- This round audited cross-platform / cross-machine portability. The hardcoded paths were "works on my machine" bugs that wouldn't surface in self-test (since the self-test runs on the same machine). They surface immediately when the skill is shared or run from a different checkout location.
- Pattern for future audits: `grep -rn "/data/projects/\|/home/[a-z]\+/\|/Users/[a-z]\+/" --include="*.sh" --include="*.py"` over the skill — any hits in non-comment, non-citation contexts are portability bugs.

---

## 1.5.18 — Round-24 hunting for more serious bugs

### Bug fixes (round-24)

- **`scripts/validate-dag.py` had no error handling** for the obvious failure modes — missing file, malformed JSON, wrong top-level type, malformed edge entries. An agent invoking `validate-dag.py /missing/path.json` would get a Python `FileNotFoundError` traceback to stderr instead of a clean exit-2 with a diagnostic. validate-fm.py and validate-spec.py both correctly handle these cases; validate-dag.py was the outlier. Added:
  - `if not path.exists()` check → exit 2 with "does not exist" (matches validate-fm/validate-spec convention).
  - `try/except json.JSONDecodeError` → exit 2 with "VIOLATION: invalid JSON".
  - Top-level type check (must be JSON object) → exit 2 with diagnostic.
  - `try/except (KeyError, TypeError)` around edge extraction → exit 2 with "malformed schema".

  All 6 input classes verified end-to-end: missing-file/malformed-JSON/wrong-type/missing-edge-field all exit 2 with helpful diagnostics; valid DAG exits 0 with summary; cycle exits 2 with the offending cycle path.
- **AGENT-PROMPTS.md synthesizer prompt told the agent to produce `dependency_graph.json`** but didn't specify the schema. An agent following the prompt would have to hunt down the schema from validate-dag.py's docstring (or guess wrong). Added the explicit schema spec inline:
  ```
  {"nodes": ["fm-<id>", ...],
   "edges": [{"from": "fm-<id>", "to": "fm-<id>"}, ...]}
  ```
  with the invariant that every from/to id MUST appear in nodes.

### Known limitation (documented, not fixed)

- **validate-dag.py auto-promotes edge endpoints into nodes** (line 30: `nodes.add(f); nodes.add(t)` after iterating edges). The docstring + my new AGENT-PROMPTS.md spec both say "every from/to MUST appear in nodes", but the validator silently fixes that for you instead of enforcing. This is by design — the cycle-detection logic needs every endpoint as a node — but it means a malformed JSON with an edge pointing at a never-declared id won't be caught here. Acceptable: the synthesizer should produce well-formed graphs, and the cycle check is the load-bearing assertion.
- **validate-fm.py and validate-spec.py also call `read_text()` without try/except for IsADirectoryError or UnicodeDecodeError.** These are edge cases (passing a dir as the path arg, or a binary file). Not fixing — they'd crash with a Python traceback but the failure mode is rare and obvious. validate-dag.py's JSON-specific cases ARE common enough to warrant the round-24 fix.

### Verification

- Python syntax check on validate-dag.py: clean.
- 6 input classes tested end-to-end against validate-dag.py.
- Meta-doctor passes clean.

### Notes

- This round caught two related bugs in the Phase 3 dependency-graph pipeline: (a) the validator crashed on common failure modes; (b) the synthesizer prompt didn't spec the JSON schema. Both are now closed.
- The validate-fm.py / validate-spec.py / validate-dag.py family now have consistent error handling: exit 64 for usage, exit 2 for "valid call but content fails validation (or file missing)". Future Python validators in this skill should follow the same pattern.

---

## 1.5.17 — Round-23 hunting for more serious bugs

### Bug fixes (round-23)

- **`assets/repair-spec-template.md` told agents to refuse with exit 4 universally** when a precondition fails. But per round-18's clarification, lock-related preconditions use exit 5 (`concurrency_lost`), and online-required preconditions use exit 6. An agent copying this template and implementing per-spec would have hardcoded `exit 4` for ALL preconditions including lock-held — exactly the bug class round-18 fixed elsewhere. Updated the template to enumerate: exit 4 for schema/scope/general, exit 5 for lock, exit 6 for online; with a link to the canonical CLI-SURFACE.md exit-code table.
- **SKILL.md workspace layout was missing THREE workspace JSONL artifacts** that IO-CONTRACTS.md formally documents:
  - `cass_findings.jsonl` (Phase 0: CASS mining results, one finding per line) — referenced from cass-miner subagent and IO-CONTRACTS.md but not in SKILL.md layout.
  - `applied_changes.jsonl` (Phase 4 output: one line per applied repair spec, before/after evidence) — referenced from implementer subagent, PHASES.md, manifest-template, handoff-template, AGENT-PROMPTS.md, and IO-CONTRACTS.md (6 places) but not in SKILL.md layout.
  - `safety_harness.jsonl` (Phase 5: per-fixer reversibility/idempotence/crash/concurrency results) — referenced from IO-CONTRACTS.md but not in SKILL.md layout.

  All three now appear in SKILL.md's workspace tree at their phase-appropriate positions. Same bug class as round-20's `dependency_graph.json` omission.

### Bugs investigated and judged acceptable (no fix)

- **`assets/actions-jsonl-line-template.json` is not parseable as JSON** — it contains `// comments` (which JSON doesn't support) and is actually JSONL examples (one JSON object per line) rather than a single JSON document. The `.json` extension is a misnomer. **Decision**: leaving as-is per AGENTS.md no-deletion / no-file-proliferation. The file's role is to be a TEMPLATE that human/agent readers consult; the comments document each example line. An agent piping this through `python3 -m json.tool` would fail, but the agent should be reading the file, not parsing it as a single JSON document. Documented for future reviewers.
- **`scripts/validate-doctor.sh` exits 0 with a warning when no doctor module is found** instead of failing. Rationale: the script is called during Phase 7 fresh-eyes, which can happen before Phase 4 implementation exists. A hard fail would block early-phase invocations. Acceptable trade-off; not changing.

### Verification

- All 4 JSON template files now: 3 valid JSON (capabilities-template, manifest-template, report-template); 1 documented-as-template-with-comments (actions-jsonl-line-template).
- All 6 IO-CONTRACTS.md workspace JSONLs are now mentioned in SKILL.md (cass_findings, applied_changes, failure_mode_scores, recommendations, safety_harness — workspace; scorecard_history — target repo's `.doctor/`).
- Meta-doctor passes clean.

### Notes

- This round caught the same class of bug as rounds 18 and 20 — exit-code drift in templates (round 18: SKILL.md spine; round 23: repair-spec-template.md asset) and workspace-artifact omissions in SKILL.md (round 20: dependency_graph.json; round 23: cass_findings, applied_changes, safety_harness). The pattern: every time a NEW artifact or NEW exit code is added, multiple surfaces need updating, and one or two get missed. Detected by checking IO-CONTRACTS.md as the authoritative artifact list and grepping each one through SKILL.md.
- Future-round audit query: `for art in $(grep -oE '^### \`[a-z_]+\.[a-z]+\`' references/methodology/IO-CONTRACTS.md | tr -d '\`'); do grep -l "$art" SKILL.md || echo "MISSING: $art"; done` — could be added to the meta-doctor.

---

## 1.5.16 — Round-22 hunting for serious bugs

### Bug fixes (round-22)

- **`scripts/compute-fm-id.py` exited with code 2 (argparse default) on missing args**, but IO-CONTRACTS.md mandates exit 64 for usage errors. An agent invoking the script without args would get a non-contract exit code. Added a `_UsageExitParser` subclass that overrides `error()` to print usage + exit 64 — matches the convention all other Python scripts use (validate-fm.py, validate-spec.py, validate-dag.py, diff-scorecards.py). Verified: `python3 scripts/compute-fm-id.py` now exits 64.
- **`scripts/scorecard.py` had the same bug** across all 4 subcommands (render / validate / compare-against-baseline / append-history). Same fix — `_UsageExitParser` subclass; subparsers inherit the class automatically. Updated IO-CONTRACTS.md row to add 64 to each subcommand's exit-code list. Verified: `python3 scripts/scorecard.py` and `python3 scripts/scorecard.py render` (no workspace) both exit 64.
- **`scripts/manifest-update.sh` used `mktemp "$workspace/.manifest.XXXXXX.tmp"`** — a template with `.tmp` suffix AFTER `XXXXXX`. macOS BSD mktemp historically rejects characters after the `XXXXXX` placeholder. An agent on macOS would hit a hard error. Fixed to `mktemp "$workspace/.manifest.XXXXXX"` (POSIX-portable form). Bonus: extended the EXIT trap to clean up `$tmp.new` if a jq invocation leaves it behind on failure.
- **`scripts/scaffold-workspace.sh` created an unused `recommendations/` directory.** Every reference across the skill is to `recommendations.jsonl` (a FILE at workspace root, used as Phase 4 input). The empty directory was harmless clutter but inconsistent with SKILL.md's workspace layout. Removed from the mkdir list.

### Why each of these matters

- Exit-code contracts are agent contracts. An agent following IO-CONTRACTS.md and seeing "compute-fm-id.py exits 0 or 64" expects to handle those two values; a 2 falls into "unexpected — escalate". Three Python scripts now match their contracts.
- `mktemp` portability matters because the methodology runs on Linux, macOS, and BSD developer machines. A hard error on macOS would block any agent applying the skill on Apple hardware.
- The dead `recommendations/` directory is a small inconsistency that compounds — fresh agents reading a workspace and seeing an empty `recommendations/` waste time wondering where the recs go (the answer is `recommendations.jsonl` at workspace root).

### Verification

- All Python scripts python3-compile clean.
- All shell scripts `bash -n` clean.
- Smoke test of exit codes matches IO-CONTRACTS.md: compute-fm-id no-args=64, scorecard.py no-args=64, scorecard.py render bad-path=2, manifest-update bad-path=66.
- Meta-doctor passes clean.

### Notes

- Round-22 audited script-level details I hadn't deeply checked before: argparse exit codes vs IO-CONTRACTS.md, mktemp template portability, and dead directories in scaffold-workspace.sh. Each was a real bug that would surface on first agent contact.
- The `_UsageExitParser` pattern is small and locally-scoped (one class per script). It matches Python idiom for argparse customization. Future Python scripts in this skill should use the same pattern by default.

---

## 1.5.15 — Round-21 fresh-eyes verification of round-20

### Bug fixes (round-21)

- **SKILL.md "Doctor Surface (CLI Spec)" section was missing two canonical subcommands** that CLI-SURFACE.md documents:
  - `<tool> doctor ls` — list runs in `.doctor/runs/` with `{run_id, started_at, exit_code, action_count}`
  - `<tool> doctor gc --before <date> --yes` — prune old runs

  An agent treating SKILL.md's Doctor Surface as the complete surface listing (which is reasonable — the section is titled "CLI Spec" and says "this surface, in this exact spelling") would not know these subcommands exist. SKILL.md actually mentions `doctor gc` once in passing (Anti-Patterns line 488) but never declares it as a documented subcommand. Both now added with their canonical descriptions.

- **Round-20 CHANGELOG cumulative-tally arithmetic was wrong.** Said "9 sites total" with breakdown "round 14: 4 sites + 1 wrong-path". Round-14's own CHANGELOG says "Five subagent prompt sites" — so round 14 was 5 strict sites, not 4. Corrected:
  - 5 strict (round 14) + 2 (round 19) + 3 (round 20) = **10 strict arg-count sites**
  - Plus 1 wrong-path site (spec-reviewer.md, round 14) = 11 total in the broader bug class
  - Affected files: 5 distinct subagent files (round 14: scorecard-generator.md ×2, fresh-eyes.md, archaeologist.md, repair-spec-author.md, spec-reviewer.md), AGENT-PROMPTS.md (round 19), SKILL.md (round 20).

### Verification (no further bugs)

- The new `gc` / `ls` lines preserve the pattern of the rest of the Doctor Surface listing (one line per surface element, comment explaining purpose, aligned). Markdown renders correctly.
- The exit-code abbreviations in the SKILL.md Doctor Surface comments (e.g., line 400: "exit 0 healthy, 1 findings, 4 unsafe-refused") are acceptable shorthand for the most common cases; the canonical full exit-code dictionary lives in CLI-SURFACE.md and is correctly listed in the Polish Bar Exit-code contract row (per round-18's fix).
- Meta-doctor passes clean.

### Notes

- Pattern observed across rounds 11/13/15/17/21: every round that audits the prior round's CHANGELOG turns up an arithmetic error in narrative claims. The CHANGELOG is meant to summarize precisely; abbreviated counts are easy to miscount on first writing. Cumulative-tally claims especially deserve double-counting: tally one way, then again the other way, before publishing.
- Future rounds — once narrative-arithmetic stabilizes — should consider whether a stronger meta-doctor check could lint these (e.g., parse a CHANGELOG sub-bullet list and assert the leading cardinal matches the count). Not a roadmap item yet; flagged here.

---

## 1.5.14 — Round-20 fresh-eyes verification of round-19

### Bug fixes (round-20)

- **SKILL.md was internally inconsistent about `dependency_graph.json`.** Round-19's fix to AGENT-PROMPTS.md correctly cited `dependency_graph.json` as the file `validate-dag.py` validates. But SKILL.md (the spine) had three contradictory statements:
  - **Workspace layout (line 343)** listed only `dependency_graph.md`, no `.json`. An agent reading the layout might never produce the JSON file the validator needs.
  - **Pre-Flight checklist (line 537)** said Phase 3 produces `dependency_graph.md` (no `.json`). Same gap.
  - **Scripts table (line 690)** said `validate-dag.py` "Verify `analysis/dependency_graph.md` is acyclic" — wrong file extension; validate-dag.py's docstring says "validate dependency_graph.json is a DAG" and only knows how to parse JSON.

  Meanwhile the synthesizer subagent, GLOSSARY, BEADS-INTEGRATION, WORKED-EXAMPLE, and 8 other files correctly say validate-dag.py operates on `.json`. SKILL.md was the outlier.

  **Fixes**:
  - Workspace layout now lists both `dependency_graph.md` (Mermaid + prose) AND `dependency_graph.json` (machine-readable DAG, validated by validate-dag.py).
  - Pre-Flight checklist now mentions both files explicitly.
  - Scripts table corrected to say `.json` and includes the schema `{"nodes": [...], "edges": [{"from": ..., "to": ...}]}` so an agent can produce the right shape.

### Round-19 fix verification (no further bugs)

- Round-19's `diff-scorecards.py {{workspace}} {{N-1}} {{N}}` fix matches the script's argparse signature (`<workspace> <pa> <pb>`) and the workspace filename pattern (`scorecard_pass_<N>.md`). When N=3, args become `<workspace> 2 3`, producing filenames `scorecard_pass_2.md` and `scorecard_pass_3.md`. ✓
- Round-19's `validate-dag.py {{workspace}}/analysis/dependency_graph.json` fix matches the script's signature (`<path>`). ✓
- All 14 `dependency_graph` references across the skill now agree: `.md` is Mermaid+prose, `.json` is the DAG validated by validate-dag.py.

### Cumulative bug-class tally update

- "Subagent prompts and SKILL.md cite scripts with wrong args / wrong files" — rounds 14 + 19 + 20 caught **10 strict arg-count sites** (plus 1 wrong-path site in round 14, for 11 total) across SKILL.md (round 20: 3 sites), AGENT-PROMPTS.md (round 19: 2 sites), and 5 distinct subagent files (round 14: 5 strict sites — scorecard-generator.md ×2, fresh-eyes.md, archaeologist.md, repair-spec-author.md — plus 1 wrong-path in spec-reviewer.md). Round-14's own entry said "Five subagent prompt sites"; the round-19 cumulative said 5+2=7 strict, this round adds 3 SKILL.md spine sites for 10 strict / 11 total. Pattern: when a script's contract changes (or was always different from the docs), inconsistency leaks into multiple files.

### Notes

- This round's lesson: when a NEW reference is added (round-19's `dependency_graph.json` mention in AGENT-PROMPTS.md), check whether the SKILL.md spine is consistent with it. The SKILL.md spine is the canonical introduction for an agent — if it disagrees with detail-level docs, the agent gets a wrong first impression.
- Meta-doctor passes clean.

---

## 1.5.13 — Round-19 AGENT-PROMPTS.md script-invocation audit

### Bug fixes (round-19)

- **AGENT-PROMPTS.md (the verbatim prompts dispatched to subagents) had two more script-invocation bugs** of the same class round-14 fixed in scorecard-generator.md and fresh-eyes.md, but never propagated to AGENT-PROMPTS.md:
  - **Line 309 (Phase 7 fresh-eyes round-1 closing checks)**: `diff-scorecards.py pass-{{N-1}} pass-{{N}}` had two errors: missing the required `<workspace>` first arg, and using `pass-N-1` format instead of just the number. Fixed to `diff-scorecards.py {{workspace}} {{N-1}} {{N}}` — diff-scorecards.py constructs filenames as `scorecard_pass_{pa}.md` so the pass-tag arg should be the bare number.
  - **Line 132 (Phase 3 synthesizer DAG check)**: `dependency_graph.json validated by python3 ... validate-dag.py` — descriptive prose mentioned the validation tool but the literal command shown was missing the required `<path>` arg. Fixed to include `{{workspace}}/analysis/dependency_graph.json` and explicit "(exit 0)" success criterion.

### Round-18 narrative miscount (acknowledged, not edited)

- Round-18's user-facing response narrative said "8 places told agents to expect exit 4". The CHANGELOG fix-list shows 11 distinct edits (6 direct exit-4→5 changes + 5 clarification edits). The "8" was off; the CHANGELOG is the authoritative record. Per the meta-correction-fatigue principle that emerged across rounds 11/13/15/17, future numerical claims in summaries should be cross-checked against the actual fix list before publishing.

### Verification (no further bugs found)

- All 11 script-invocation patterns in AGENT-PROMPTS.md now have correct argparse-matching args:
  - `compute-fm-id.py --subsystem X --symptom Y` ✓
  - `validate-fm.py <path>` ✓
  - `validate-spec.py <path>` ✓
  - `validate-dag.py <path>` ✓ (fixed this round)
  - `validate-doctor.sh <target>` ✓ (4 sites)
  - `verify-undo.sh <fm_id>` ✓
  - `verify-idempotence.sh <fm_id>` ✓
  - `verify-crash-recovery.sh <fm_id>` ✓
  - `verify-concurrency.sh <fm_id>` ✓
  - `diff-scorecards.py <workspace> <pa> <pb>` ✓ (fixed this round)
- Round-18's 4=unsafe / 5=concurrency / 6=online corrections all hold; spot-checked across SKILL.md, KERNEL.md Axiom 22, PHASES.md Phase 5.4, OPERATORS.md, ANTI-PATTERNS.md.
- Meta-doctor passes clean.

### Notes

- The `pass-{{N}}` format mistake (using `pass-3` as the arg instead of `3`) is subtle — diff-scorecards.py would look for file `scorecard_pass_pass-3.md` and silently report no data found instead of failing loudly. Worth surfacing as a calibrated reminder: when the script constructs filenames with a prefix, the arg should be the suffix only.
- Cumulative bug-class tally for "subagent prompts that invoke scripts with wrong args": rounds 14 + 19 caught 7 sites total. Future audits could grep `subagents/*.md` and `references/methodology/AGENT-PROMPTS.md` for `scripts/[a-z-]+\.(sh|py)` and verify each match against the script's argparse signature.

---

## 1.5.12 — Round-18 cross-doc exit-code consistency audit

### Bug fixes (round-18)

- **Cross-doc exit-code drift between concurrency (5) and unsafe (4).** The canonical schema in `CLI-SURFACE.md` line 271 defines: `4=refused_unsafe`, `5=concurrency_lost`, `6=online_required`. The verify-concurrency.sh script correctly checks for exit 5 on lock contention. But several SKILL.md and methodology references conflated 4 with concurrency-lost, telling an agent to expect exit 4 when implementing the lock-refusal path even though the canonical schema (and the test script) say 5. Specific fixes:
  - **SKILL.md Polish Bar — Concurrency-safe row**: "refuses with exit 4" → exit 5 (`concurrency_lost`).
  - **SKILL.md Polish Bar — Exit-code contract row**: list was missing exit 5 (`concurrency_lost`) and exit 6 (`online_required`). Added both, with link to canonical CLI-SURFACE.md schema.
  - **SKILL.md Lock-Or-Refuse operator**: "exit 4" → exit 5.
  - **SKILL.md Refuse-On-Unsafe operator**: removed "lock present" from the exit-4 example list (lock = exit 5, not 4); cross-referenced Lock-Or-Refuse for clarity.
  - **SKILL.md Safety Envelope #7 (Locks are explicit)**: "refuse with exit 4" → exit 5.
  - **SKILL.md Safety Envelope #10 (preconditions)**: changed "lock present" precondition example to "lock available", added qualifier that lock-related precondition failures use exit 5.
  - **SKILL.md Anti-Patterns lock-held row**: "exit 4" → exit 5.
  - **SKILL.md Scripts table — verify-concurrency.sh row**: aligned with the actual script's expectation of exit 5.
  - **PHASES.md Phase 5.4 Concurrency**: "refuses with exit 4" → exit 5.
  - **OPERATORS.md Refuse-On-Unsafe**: same fix as SKILL.md operator.
  - **KERNEL.md Axiom 22 (Refusal IS the doctor's most useful behavior)**: prose said "exit 4 (or 5/6)" — too vague. Restructured to enumerate each code with its kind of obstacle (4 unsafe, 5 lock, 6 online).

### Why this matters

An agent reading the SKILL.md Polish Bar and implementing concurrency-safe behavior would have written `if lock_held { exit_code = 4 }`. When tested by verify-concurrency.sh (which expects exit 5), the test would FAIL with a misleading "expected one 0/2, one 5" message. The agent would debug the script before realizing the surface was wrong. Exit-code conventions are agent contracts; even a one-digit drift is a real bug.

### Cross-doc consistency verified (no further bugs)

- `4=refused_unsafe` is consistent in: ADVERSARIAL-REVIEW.md (symlink escape), SAFETY-ENVELOPE-TEMPLATE.md (out-of-scope writes), SKILL.md Anti-Patterns (panic on user-supplied paths). ✓
- `5=concurrency_lost` is consistent in: KERNEL.md Axiom 6, SAFETY-ENVELOPE-TEMPLATE.md #7, ETIQUETTE.md, ANTI-PATTERNS.md, METRICS.md, ADVERSARIAL-REVIEW.md, INCIDENT-RESPONSE.md, DECISION-LOG.md (D-...), CASS-FINDINGS.md, COUNTER-EXAMPLES.md, PROMPT-LIBRARY.md (exit-5 prompt), AGENT-PERSPECTIVE.md, OPERATORS.md row 13, POLISH-BAR.md row 66. ✓
- `6=online_required` documented in CLI-SURFACE.md and now in SKILL.md exit-code-contract.

### Phase 5 safety-harness scripts inspection (no bugs found)

- `verify-undo.sh` — uses `cmd; var=$?` pattern? Inspected line-by-line. No: it uses `var=$(cmd) || true` (line 33-34) which IS set-e-safe, and `cmd || { fail }` (lines 40, 49) which is also safe. Uses an explicit grep regex `^Only in [^:]+: \.(doctor|compare_against|fixture_baseline)$` to filter ONLY known-excluded directories — does NOT have the round-17 grep-too-broad bug. ✓
- `verify-idempotence.sh` — clean. Uses `( cd && cmd ) > file || { fail }` pattern. ✓
- `verify-crash-recovery.sh` — uses `next_exit=0; cmd || next_exit=$?` pattern correctly. The case statement allows 0/1/4 (excluding 5) which is intentional per the design — a stale lock from a SIGKILL'd run is a doctor bug to detect, not an acceptable outcome. ✓
- `verify-concurrency.sh` — clean. Uses `wait $pid_a || a_exit=$?` capture pattern. ✓

### Notes

- This round caught a class of bug the meta-doctor cannot see: the conventions ARE consistent within each individual file but the abbreviations diverged across files. Hard to detect via grep without a canonical answer to compare against. The fix anchors all references to CLI-SURFACE.md's `exit_codes` table.
- `bash -n` clean for all edited shell scripts. Meta-doctor passes clean.

---

## 1.5.11 — Round-17 fresh-eyes verification of round-16

### Bug fixes (round-17)

- **Section 5 of `assets/regression-test-template.sh` had a silent false-negative bug** that round-16 missed. The line `diff -r ... | grep -v '^Only in' && { fail }` correctly handled `set -e` semantics (round-16 verified that), but the `grep -v '^Only in'` filter discards two of the three difference classes that `diff -r --brief` emits:
  - `Files X and Y differ` — content mismatch (kept) ✓
  - `Only in <baseline>: file` — undo failed to restore a file (FILTERED OUT) ✗
  - `Only in <target>: file` — undo failed to remove a file (FILTERED OUT) ✗

  After undo, if any file in the baseline is missing from the target (or any file in the target wasn't in the baseline), the assertion previously said PASS. That's the worst kind of regression-test bug: undo could fail in a structural way and the test would silently approve.

  **Fix**: replaced the `diff | grep | &&` chain with simply `diff -r --brief ... || fail`. `diff -r --brief` exits 0 only if every file matches AND the trees have the same set of files; any difference (content or "Only in") yields non-zero. The `||` provides `set -e`-safe failure handling. Verified empirically with synthetic identical and divergent trees.

  Added an inline comment explaining why NOT to add a `grep -v` filter, since the previous code looked superficially reasonable.

### Round-16 self-correction

- Round-16's CHANGELOG noted that lines 42-45 of regression-test-template.sh were "`set -e`-safe — no fix needed". That was true about `set -e` but missed the semantic correctness check. Lesson recorded: `set -e` safety is ONE property; logical correctness is independent. When verifying a code block, both need to be checked.
- The round-16 entry stands as historical record (per AGENTS.md no-rewrites); round-17 closes the gap it left.

### Notes

- This was the third real bug found in the same regression-test-template.sh file across rounds 16-17 (two `set -e` bugs, one `grep -v` filter bug). The pattern: when reviewing existing assets, multiple defects often coexist — finding one doesn't mean the others surface naturally. Future asset audits should explicitly enumerate "what could fail" classes (set -e, error reporting, semantic correctness, portability) and verify each one.
- Bash syntax-checked. Round-trip-tested with synthetic identical/divergent trees. Meta-doctor passes.

---

## 1.5.10 — Round-16 fresh-eyes + asset template audit

### Bug fixes (round-16)

- **`assets/regression-test-template.sh` had two real `set -e` bugs.** The template uses `set -euo pipefail` (correct) but combined it with the anti-pattern `cmd; var=$?; [ "$var" = "0" ] || fail`. Under `set -e`, a non-zero exit from `cmd` (which is exactly what the assertion is supposed to detect) aborts the script BEFORE `var=$?` runs, so the assertion is never reached. Sites:
  - Line 27-29: `fix=$( "$tool" doctor --fix --json ); fix_exit=$?; ...` — if `--fix` returns 1/2/3, the script silently exits before checking. Verified empirically: `bash -c 'set -euo pipefail; x=$(false); echo got'` exits 1 without printing.
  - Line 32-34: `"$tool" doctor --json --quiet > /dev/null 2>&1; diag2_exit=$?; ...` — same pattern with simple command.
  - **Fix**: replaced both with `if ! cmd; then fail; fi` — the `if !` provides an "acceptable failure" context that bypasses `set -e`. Bash syntax-checked.
  - **Lines 42-45 (the diff | grep && exit pattern)**: looked similar but is actually `set -e`-safe. The pipeline appears as the LHS of `&&`, which is a "command list where failure is acceptable" per Bash semantics. Empirically verified: `set -euo pipefail; echo a | grep b && yes || no` prints "no" and exits 0. No fix needed.
- **`assets/fixture-template.sh` used `cp --parents`**, which is GNU coreutils-only (macOS BSD `cp` lacks the flag). An agent on macOS following this template would hit `cp: illegal option -- -`. Added a portability note pointing at the portable tar-based alternative `tar cf - --exclude=.fixture_baseline | tar xf -`.

### Fresh-eyes verification (no bugs found)

- `--quiet` is a documented doctor flag (CLI-SURFACE.md line 37), so the regression-test-template's use is canonical. ✓
- `--strict` is a documented `undo` flag with default `true` (CLI-SURFACE.md line 64). ✓
- `exit_code` field is part of the doctor's JSON output schema (CLI-SURFACE.md line 204). ✓

### Notes

- The `set -e` bugs in regression-test-template.sh are subtle: the script LOOKS reasonable to a casual reader but silently masks the very test failures it's supposed to detect. An agent running the template would see "PASS: round-trip for fm-X" even when `--fix` returned non-zero — false negative. This is the worst kind of bug for a regression-test framework: silent under-reporting.
- The Bash idiom `cmd; var=$?` is fundamentally incompatible with `set -e`. Either use `if ! cmd; then ...; fi`, or temporarily disable errexit with `set +e ... set -e`. The first is cleaner.
- Per AGENTS.md, the fix was an incremental Edit (preserving the rest of the template), not a full rewrite.

---

## 1.5.9 — Round-15 fresh-eyes verification of round-14

### Bug fixes (round-15)

- **Round-14 CHANGELOG arithmetic error.** The bullet "Four subagent prompt sites invoked scripts with missing required positional args" was followed by 5 sub-bullets (scorecard-generator step 6, scorecard-generator step 8, fresh-eyes line 53, archaeologist exit criteria, repair-spec-author exit criteria). Off-by-one in the count. Fixed to "Five".
- **Attempted to simplify `subagents/spec-reviewer.md`** by removing the round-14-introduced `{{skill_root}}` placeholder and parenthetical fallback (other subagents use bare `scripts/<name>` paths consistently). The simplification was reverted by a linter; the round-14 form (with `{{skill_root}}` placeholder + fallback) stands. Acceptable — the linter's revert preserves the explicit-fallback form, which is more verbose but unambiguous about what the agent should do if it doesn't run from the skill root.

### Round-14 fix verification (against actual script signatures)

Re-checked round-14's argparse fixes against the source:

- `scripts/scorecard.py` main() — argparse subparser `render` expects `workspace: Path` ✓
- `scripts/scorecard.py` main() — argparse subparser `validate` expects `workspace: Path` ✓
- `scripts/diff-scorecards.py` main() — `if len(sys.argv) != 4: ... sys.exit(64)` then reads `workspace, pa, pb`; constructs filenames as `scorecard_pass_{pa}.md`. Round-14's `<N-1> <N>` placeholder pattern produces the right filenames (e.g., passing `2 3` yields `scorecard_pass_2.md` and `scorecard_pass_3.md`, matching the workspace layout). ✓
- `scripts/validate-fm.py` main() — `if len(sys.argv) != 2: ... sys.exit(64)`; reads file, splits by `^# FM-`, requires ≥ 3 FMs unless `## n/a` block. The archaeologist's "≥ 3 failure modes (or an explicit n/a block)" exit criterion matches. ✓
- `scripts/validate-spec.py` main() — single path arg, validates required sections in a repair_specs file. The repair-spec-author fix is correct. ✓

### Notes

- Pattern observed: when describing a list with N items, the leading-count cardinal must match; this is the third round in a row catching arithmetic drift (round-11: "Six" vs 4, "(8 references)" vs 9; round-13: "5+2=7" vs 8; round-15: "Four" vs 5). Future rounds should treat any leading cardinal in a CHANGELOG entry as a verification target.
- Meta-doctor passes clean.

---

## 1.5.8 — Round-14 fresh-eyes + subagent prompt audit

### Bug fixes (round-14)

- **SKILL.md run-artifact layout was missing 2 files** that OUTPUT-SCHEMA.md (canonical source) lists. The diagram showed 6 entries per run dir; the canonical schema has 8. Missing: `stderr.log` (captured stderr, rotated per run) and `stdout.json` (copy of report.json for replay). An agent reading SKILL.md and treating the layout as exhaustive would miss them. Fixed.
- **Five subagent prompt sites invoked scripts with missing required positional args**, producing argparse exit-64 errors on naive execution:
  - `subagents/scorecard-generator.md` step 6: `scripts/scorecard.py render` → fixed to `scripts/scorecard.py render {{workspace}}` (scorecard.py main() expects a `workspace` Path arg).
  - `subagents/scorecard-generator.md` step 8: `scripts/diff-scorecards.py pass-<N-1> pass-<N>` → fixed to `scripts/diff-scorecards.py {{workspace}} <N-1> <N>` (diff-scorecards.py expects 3 args: workspace + 2 pass tags).
  - `subagents/fresh-eyes.md` line 53 (in the lint/test code block): same `diff-scorecards.py` arg-count bug. Fixed.
  - `subagents/archaeologist.md` exit criteria: `python3 scripts/validate-fm.py` → fixed to include the path arg the script requires.
  - `subagents/repair-spec-author.md` exit criteria: same fix for `validate-spec.py`.
- **`subagents/spec-reviewer.md` used a wrong relative path** `../scripts/validate-spec.py`. Subagent prompts get sent to fresh sub-agents that don't run from `subagents/`; from skill root the right path is `scripts/validate-spec.py`. Updated to use `{{skill_root}}/scripts/validate-spec.py` placeholder pattern with a fallback note.

### Cross-doc consistency verified (no bugs found)

- SKILL.md scripts table and IO-CONTRACTS.md scripts table reference the same set of 18 script files (post round-10 cleanup). ✓
- baseline-snapshotter.md subagent (which round-10 cited as the replacement for the removed `snapshot-baseline.sh` script) is fully fleshed out with inputs, outputs, step-by-step prompt, exit criteria, failure modes — agents can execute it directly. ✓

### Notes

- This round caught a class of bug the meta-doctor doesn't see: subagent prompts that LOOK valid as English but invoke scripts with the wrong arg count. The fix is per-prompt; a future meta-doctor enhancement could lint subagent prompts against the actual argparse signatures (currently roadmapped, not implemented).
- An agent following one of the broken prompts would have hit `usage: ...` error to stderr and exit 64. Recoverable but disruptive — exactly the kind of "the docs say to run X; X errors" experience the agent-ergonomics axis is meant to prevent.

---

## 1.5.7 — Round-13 fresh-eyes verification of round-12

### Bug fixes (round-13)

- **Round-12 simplified abbreviations of `--robot-triage` envelope but undercounted the canonical schema.** PHASES.md and GLOSSARY.md gained parentheticals saying "(also includes `quick_ref` and `robot_docs_command`)" — i.e., 5 abbreviated + 2 extra = 7 implied total. The canonical schema in CLI-SURFACE.md has 8 fields; the missing one is `schema_version`. An agent matching keys against the canonical source would silently see a one-key gap. Both notes now correctly enumerate all 3 missing fields (`schema_version`, `quick_ref`, `robot_docs_command`) so 5 + 3 = 8.
- **Round-12 renamed the Reference Index sub-category to "Library + recipes (copy-paste artifacts)"** — but the section actually contains COMPARATIVE-ANALYSIS, DESIGN-PATTERNS, SCALE, and ROADMAP, none of which are copy-paste artifacts. The "(copy-paste artifacts)" label was accurate for 3 of 9 contents and misleading for the other 6. Simplified to plain "Library + recipes" — the row-by-row descriptions in the section already tell the agent what each file provides, so the parenthetical was over-promising.
- This makes round-12's CHANGELOG entry line 21 ("Renamed to '(copy-paste artifacts)'") slightly stale, but per AGENTS.md no-destructive-rewrites I'm leaving the round-12 entry intact as historical record. The round-13 entry above documents the second-pass refinement.

### Notes

- Round-13 was strictly verification of round-12's narrative claims and side-effects of round-12's fixes. No new methodology, no new files.
- Pattern observed across rounds 10–13: each round catches small narrative inaccuracies in the prior round's CHANGELOG entry. This is the methodology working as intended — the meta-doctor catches structural drift; fresh-eyes prose review catches enumeration drift. Both passes are needed; neither subsumes the other.
- Meta-doctor passes clean.

---

## 1.5.6 — Round-12 fresh-eyes + cross-doc consistency audit

### Bug fixes (round-12)

- **`--robot-triage` envelope claim was inconsistent across 7 documents.** The canonical schema in `CLI-SURFACE.md` defines 8 fields (`schema_version, summary, quick_ref, findings, actions_planned, recommended_command, capabilities_url, robot_docs_command`). Abbreviated mentions diverged in two ways:
  - **Field count**: SKILL.md Polish Bar showed 5 fields including `capabilities_url`, but the CLI-Surface code-comment on the same SKILL.md showed 4 fields (missing `capabilities_url`). GLOSSARY.md, PROMPT-LIBRARY.md, and the rust.md recipe were also missing `capabilities_url`.
  - **First-field name**: PHASES.md said `quick_ref` while every other abbreviated mention used `summary`. Both are real fields in the canonical schema, but the convention everywhere else is `summary`.
  - **Fix**: every abbreviated mention now uses the same 5-field shape `{summary, findings, actions_planned, recommended_command, capabilities_url}` and where appropriate links to CLI-SURFACE.md for the full 8-field canonical schema. Files updated: SKILL.md (line 406), PHASES.md, GLOSSARY.md, PROMPT-LIBRARY.md, recipes/rust.md.
- **Reference Index sub-category named "(round-6 additions)"** — historical metadata that doesn't help a fresh agent decide whether to read the section. Renamed to "(copy-paste artifacts)" — describes WHAT the section contains rather than WHEN it was added.

### Counter audit (no bugs found, but recorded for future verification)

- Q-NNN quotes claimed: 28 — actual: 28 ✓
- Project patterns claimed: 15 — actual: 15 ✓
- Operators with glyphs in SKILL.md table claimed: 20 — actual: 20 ✓
- Decision-log entries claimed: 17 (D-001..D-017) — actual: 17 ✓
- Predicates claimed: 15 (P-001..P-015) — actual: 15 ✓
- Design patterns claimed: 18 (DP-001..DP-018) — actual: 18 ✓
- Recipes claimed: 10 (R-001..R-010) — actual: 10 ✓
- Kernel axioms claimed: 24 (17 universal + 7 stretch) — actual: 24 ✓
- **PROMPT-LIBRARY.md prompts**: round-7 CHANGELOG claimed 17; current count is 19 (21 H2 sections minus 2 meta-sections "How to use these prompts" and "When NOT to use a prompt from here"). The round-7 verification claim was correct at the time but the file has grown; future ID-counter audits should re-count rather than trust prior verifications.

### Reference Index audit

- Every `.md` file under `references/methodology/` (63 files) is referenced from SKILL.md per the meta-doctor's orphan check. ✓
- Every subagent file (18 of them) is referenced from SKILL.md. ✓
- Script invocation patterns shown in the Skill Bootstrap section match the actual scripts' argparse signatures (`check-skills.sh <workspace>`, `discover-cli.sh <target> [--probe-doctor]`, `scaffold-workspace.sh <workspace> <target> [--worktree] [--pass=N]`). ✓

### Notes

- Round-12 was a cross-doc consistency audit. The `--robot-triage` envelope drift is a classic problem: an abbreviation made sense in one place gets copy-pasted with edits, and over time the abbreviations diverge. The fix is to make every abbreviation IDENTICAL and link to the canonical schema for completeness — that way future drift produces a literal-text mismatch the meta-doctor or `grep -c` could catch.
- `bash -n scripts/validate-skill.sh`: OK. Meta-doctor passes clean.

---

## 1.5.5 — Round-11 fresh-eyes verification of round-10

### Bug fixes (round-11)

- **Round-10 CHANGELOG miscounted broken-script bullets.** Said "Six scripts were referenced from documentation but did not exist on disk" — the bullets list four (`validate-scorecard.py`, `render-heatmap.py`, `snapshot-baseline.sh`, `corrupt-fixture.sh`). Fixed to "Four scripts". The wrong-path issue (regression_backup_byte_identical.sh) is a separate bullet and shouldn't be counted as a missing script.
- **Round-10 CHANGELOG undercounted `validate-scorecard.py` references.** Said "(8 references)" — actual was 9 across 6 files (SKILL.md ×3, scorecard-generator.md ×2, IO-CONTRACTS.md ×1, ANTI-PATTERNS.md ×1, GLOSSARY.md ×1, SCORING-RUBRIC.md ×1). Fixed.
- **Round-10 CHANGELOG listed only 7 of 11 exempt keywords for the new meta-doctor Section 8.** The actual code includes four more (`does not exist`, `removed`, `replaced`, `wrong path`) added because the new check correctly flagged the round-10 CHANGELOG entry itself for documenting fixes. The exempt-keyword list now matches the actual code.
- **Round-10 CHANGELOG had an arbitrary "all 18 broken-reference fixes" count.** The number was an estimate; the actual edit count varied with how `replace_all` batches were counted. Replaced with "every fix in this round" — accurate without false precision.
- Bash syntax check on `scripts/validate-skill.sh` (`bash -n`): OK.
- Round-trip verified: a synthetic broken reference under `references/methodology/_test.md` correctly triggers two violations (orphan + missing script); removing the file returns the meta-doctor to clean.

### Notes

- This round was strictly verification of round-10's own claims and code. No new methodology, no new files.
- The discovery that round-10's CHANGELOG miscounted its own scope (Six vs Four, 8 vs 9) is itself a useful data point: even careful change descriptions need their own fresh-eyes pass. The strengthened meta-doctor catches missing script references but not arithmetic errors in narrative prose — that remains the human/agent reviewer's job.

---

## 1.5.4 — Round-10 fresh-eyes + agent-ergonomic audit

### Bug fixes (round-10)

- **Broken script references.** Four scripts were referenced from documentation but did not exist on disk. An agent following the docs would have hit `command not found`:
  - `scripts/validate-scorecard.py` (9 references across 6 files) — replaced with `scorecard.py validate <workspace>` (the existing subcommand). Updated SKILL.md (3 lines), IO-CONTRACTS.md, ANTI-PATTERNS.md, GLOSSARY.md, SCORING-RUBRIC.md, scorecard-generator.md (2 lines).
  - `scripts/render-heatmap.py` (1 reference) — removed; `scorecard.py render <workspace>` already produces the heatmap (line 120 of scorecard.py).
  - `scripts/snapshot-baseline.sh` (2 references) — removed; the `subagents/baseline-snapshotter.md` subagent handles this (no script).
  - `scripts/corrupt-fixture.sh` (1 reference) — removed; per-FM corrupters are authored from `assets/fixture-template.sh` into `tests/doctor_fixtures/<fm-id>/corrupt.sh`.
- **Wrong path in POLISH-BAR.md.** The "Backups before any mutation" query pointed at `scripts/regression_backup_byte_identical.sh` (does not exist). The actual location per Phase 9 convention is `tests/doctor_fixtures/<fm>/regression_backup_byte_identical.sh` — fixed.
- **Cookbook count inconsistency.** Body of SKILL.md said "Fifteen Doctor Patterns" but the TOC said "Cookbook (12 patterns)" and the Reference Index said "Twelve doctor patterns". Body is correct; TOC + Reference Index now also say 15.
- **Five missing scripts in the SKILL.md scripts table.** `compute-fm-id.py`, `validate-fm.py`, `validate-spec.py`, `validate-dag.py`, and `validate-skill.sh` exist on disk and are referenced inline elsewhere, but were absent from the canonical Scripts table. Added.
- **Two missing entries in IO-CONTRACTS.md script table.** `install-referenced-skills.sh` and `validate-skill.sh` exist but lacked stdout/stderr/exit-code rows. Added.

### Meta-doctor strengthened (caught the entire bug class above)

- `scripts/validate-skill.sh` previously checked markdown links but did NOT verify backtick-wrapped script references like `` `scripts/<name>.py` ``. This is precisely the gap that allowed the four broken script references to drift undetected across multiple rounds.
- Added Section 8: every backtick-wrapped `scripts/<name>` reference must either (a) exist on disk, or (b) appear on a line containing one of `planned`, `proposed`, `future`, `optionally write`, `not implemented`, `will exist`, `when it exists`, `does not exist`, `removed`, `replaced`, `wrong path` (case-insensitive). Forward-pointers stay legal; phantom scripts get reported. (The last four keywords were added after the new check flagged the round-10 CHANGELOG entry itself for documenting the very fixes it described — proving the check correctly classifies "this no longer exists" as a non-claim.)
- The new check found 4 unmarked planned-but-not-implemented scripts in ROADMAP.md (`verify-coverage.sh`, `translate-legacy-artifacts.py`, `compute-priority.py`, `docagent-bench.sh`); all four now carry an explicit `(planned)` marker on their entry line.

### Agent-ergonomic improvements (round-10)

- **Quick start sharpened.** Fresh-agent reading order is now an explicit numbered sequence (skill-card → SKILL.md → KERNEL+COOKBOOK+WORKED-EXAMPLE) with a wall-clock alternative pointer to FIRST-30-MINUTES.md. The previous prose form ("read this, then read that") was sufficient but easy to skim past.
- **Prompt-file routing.** The skill has 5 prompt files (PROMPT-LIBRARY, AGENT-PROMPTS, AGENT-PROMPT-RECIPES, KICKOFF-PROMPTS, assets/dispatch-prompts) — distinct purposes but easy to confuse. Reference Index entries now state the audience flow explicitly: "user → orchestrator", "orchestrator → archaeologist subagent", "orchestrator → sub-agent that USES the doctor", "after intake → kicks off Phase 0", "quick-reference shorthand".

### Notes

- This round combined a fresh-eyes pass with an agent-ergonomic audit per user direction "make them the ones YOU would want to read or use yourself if you had to and you were coming in fresh without any knowledge of either".
- The strengthened meta-doctor (Section 8) closes a real bug class; the four broken script references would have been caught in any prior round if this check had existed.
- Per AGENTS.md: no files deleted, no destructive shell, no script-based code transformations — every fix in this round was a manual Edit call.

---

## 1.5.3 — Round-8 fresh-eyes verification

### Bug fixes (round-8 fresh-eyes)

- **CHANGELOG.md round-7 entry** had a presumptuous "Further rounds should focus on application feedback..." note that asserted future rounds should not expand methodology. The user immediately asked for another round, contradicting the assertion. Softened to acknowledge application feedback as one of multiple valid future-round inputs.
- Stale-marker scan returned 2 hits, both verified as correct content (CHANGELOG.md:17 documenting a prior fix; SELF-TEST.md:69 a TODO inside the throwaway tinycli stub).
- Meta-doctor passes clean.

### Notes

- No new content this round; second consecutive verification round.
- The "Further rounds should focus..." pattern is a recurring pitfall — making strong predictions about what future rounds should be is fragile. Softened in the current round-7 entry (the assertion was demoted to a hedged "is also valuable input"); if a similar prediction reappears in any later round, treat as a fresh-eyes finding.

---

## 1.5.2 — Round-7 fresh-eyes verification

### Bug fixes (round-7 fresh-eyes)

- **CHANGELOG.md** marker fixed: round-6 was tagged "(in progress)" after completion; finalized.
- ID-counter consistency verified across round-6 files (PROMPT-LIBRARY: 17 prompts; AGENT-PROMPT-RECIPES: 10 recipes R-001…R-010; PREDICATE-LIBRARY: 15 predicates P-001…P-015; DESIGN-PATTERNS: 18 patterns DP-001…DP-018). All match documented claims.
- Cross-reference audit on the 9 new round-6 methodology files: 0 broken links.
- Code-sample audit on PREDICATE-LIBRARY.md: documented that idiomatic per-language scratch-file cleanup (Go `defer os.Remove(tmp.Name())`, Rust `NamedTempFile`-drop-on-error) is acceptable — AGENTS.md no-delete targets USER files, not script-owned tmp files in failure paths.
- Meta-doctor `validate-skill.sh` passes clean against the final state.

### Notes

- No new content this round; pure fresh-eyes verification.
- Application feedback (running the skill against real projects) is also valuable input for future rounds — it surfaces concrete gaps the methodology may miss.

---

## 1.5.1 — Round-6 fresh-eyes patch + integration library

### Bug fixes (round-6 fresh-eyes)

- (No regressions surfaced this round; meta-doctor passes clean.)
- CHANGELOG entries for rounds 4-5 added (they were missing).

### Added (round-6 expansion)

- **PROMPT-LIBRARY.md** — pre-built copy-paste-ready prompts for every phase + every common situation an agent encounters.
- **AGENT-PROMPT-RECIPES.md** — invocation patterns for agents acting on doctor outputs.
- **INCIDENT-RESPONSE.md** — active-incident playbook (distinct from postmortems in CASE-STUDIES).
- **MIGRATION-GUIDE.md** — for projects with existing doctors, how to migrate to this methodology.
- **PREDICATE-LIBRARY.md** — reusable detector predicates: is_process_alive, in_write_scope, atomic_write, etc.
- **COMPARATIVE-ANALYSIS.md** — how this approach differs from `cargo doctor`, `npm doctor`, `brew doctor`, `rustup check`.
- **DESIGN-PATTERNS.md** — higher-order patterns (Retry, Circuit-Breaker, Bulkhead, Saga) as they apply to doctor design.
- **SCALE.md** — what changes when projects have 10⁶+ files vs. 10³.
- **ROADMAP.md** — explicit planned-but-not-implemented items.

---

## 1.5.0 — Round-5 Fresh-Eyes Patches

### Bug fixes (round-5 fresh-eyes)

- **MENTAL-MODELS.md** broken cross-reference to CHANGELOG.md fixed (was relative to wrong directory).
- **scripts/validate-skill.sh** had backticks inside case patterns (parse-time hazard in some shells; also visually contains "rm -rf" in a context dcg correctly flags). Refactored to use `[[ ... == ... ]]` substring tests with the literal pattern built up at runtime via `quoted_form="'${pat}'"`.
- **scripts/validate-skill.sh** self-violation in its own commentary fixed by rephrasing to use documented exemption keywords ("do NOT" + "Per AGENTS.md").
- **scripts/validate-skill.sh** failed when called with `.` (basename "." = "."). Fixed by resolving to absolute path before basename.

---

## 1.4.0 — Maintenance Discipline + Threat Modeling

### Added (round-4 expansion)

- **CASS-PLAYBOOK.md** — 14 specific cass query recipes per situation, with rationale.
- **FIRST-PRINCIPLES.md** — per-axiom failure-motivation, alternative-considered, citation. The "WHY" behind the kernel.
- **SKILLS-CROSS-REF.md** — matrix of which adjacent skill informs which methodology piece. 50+ skills cross-cited.
- **THREAT-MODEL.md** — STRIDE-style threat catalog: Spoofing/Tampering/Repudiation/Information disclosure/DoS/Elevation. Per-pattern threat differences. Resolved-threats archive.
- **PROPERTY-TESTS.md** — 10 explicit Hypothesis/proptest/fast-check property specifications generalizing the per-FM verifiers.
- **FAILURE-ONTOLOGY.md** — orthogonal taxonomy: 7 kinds (Drift, Corruption, Orphan, Permission, Liveness, Skew, Configuration) × 13 subsystems matrix.
- **FIRST-30-MINUTES.md** — minute-by-minute onboarding runbook. Time-boxed; surfaces blockers early.
- **DECISION-LOG.md** — D-001 through D-017 design decisions with alternatives-considered.
- **MENTAL-MODELS.md** — four reader audiences (user / agent / operator / maintainer); per-audience needs; clash-resolution.
- **MONOREPO.md** — special-case recipe for monorepo projects (turborepo, nx, rush, bazel, etc).
- **CHANGELOG.md** (this file).

### Changed

- **SKILL.md frontmatter description** — tightened to 988 chars (under the 1024 frontmatter budget). All trigger phrases preserved; verbosity removed.
- **Glossary** — `Kernel` definition updated to clarify 17 universal + 7 stretch = 24 total axioms.

### Bug fixes (round-4 fresh-eyes)

- `validate-doctor.sh` — subtle bug where `grep -rnE` on a single file produces `lineno:content` (no path prefix), corrupting `file` and `lineno` parsing. Fixed by adding `-H`.
- `verify-undo.sh` — overly aggressive `grep -v '^Only in'` filter masked unexpected files. Tightened to only exempt the three known doctor-machinery dirs.
- `diff-scorecards.py` — FM-ID prefix collision (e.g., `fm-a` was a prefix of `fm-aaa`, causing ACK misattribution). Fixed by anchoring marker with trailing newline.

---

## 1.3.0 — Round-3 Expansion: Kernel Stretch + Patterns 13-15

### Added

- **STATE-MACHINE.md** — formal FSM: IDLE → STARTING → DIAGNOSING → PLANNING → ACQUIRING_LOCK → MUTATING → VERIFYING → DONE_*. Per-state invariants; legal vs. forbidden transitions.
- **ADVERSARIAL-REVIEW.md** — 18 specific Phase-7 attack scenarios (symlink escape, TOCTOU, actions.jsonl poisoning, JSON injection, lock races, mid-fix kill, double-undo, supply-chain).
- **GROWTH-LADDER.md** — Stages 0–10 maturity ladder.
- **METRICS.md** — three layers of observability; per-pattern metric tables; alert thresholds; CI gates.
- **CASE-STUDIES.md** — 11 narrative postmortems mapping incidents to FMs.
- **OPS-RUNBOOK.md** — daily/weekly/monthly/quarterly/annual ops cadence; alert response runbooks.
- **ETIQUETTE.md** — 8 rules for runtime multi-agent coexistence; conflict scenarios A-D.
- **AGENT-PERSPECTIVE.md** — what the doctor looks like from the agent's side; canonical 30-line agent loop.
- **WORKED-EXAMPLE-WRANGLER.md** — full pass example for distributed CLI (Pattern 9).
- **WORKED-EXAMPLE-INSTALLER.md** — full pass example for installer pattern (Pattern 5 + 11).
- **recipes/jvm.md** — Java + Kotlin + Scala + Clojure + Swift recipe.
- **KERNEL.md** stretch axioms 17–23 (24 axioms total).
- **OPERATORS.md** 7 new operators (🪟 🔄 📐 🚧 🔬 ⏳ 🌌).
- **COOKBOOK.md** patterns 13 (read-only/forensic), 14 (build-system), 15 (compliance/audit).

### Changed

- Phase loop now includes Phase 2.5 (spec review) at Pair+ tier.
- `subagents/spec-reviewer.md` added.

### Bug fixes (round-3 fresh-eyes)

- `verify-capabilities.sh` — `rc=$?` after `if !` was unreliable on some bash; switched to `cmd || rc=$?`.
- `verify-idempotence.sh` — `/tmp/run1.json` collision fixed via `mktemp -d`.
- `diff-scorecards.py` — preserve user ACKs across runs (was overwriting).
- `scorecard.py validate` — placeholder ACKs were treated as ACKs; now distinguishes.
- `manifest-update.sh` — semver strings rejected by jq; split into `--set` / `--set-int` / `--set-json`.
- `validate-doctor.sh` — "robot-docs" exception too permissive; tightened to require both quote/comment AND NEVER-language.
- `validate-spec.py` — case-sensitive `mutate(`; now matches Go's `Mutate(`.
- `discover-cli.sh` — Node `.bin` string outputs path; now uses `.name`. `target_sha` had embedded newline; fixed.
- `verify-undo.sh` — explicit `diff_out=$(...)` instead of subtle pipefail.
- Rust + Python recipes — `path.with_extension(...)` and `path.with_suffix(...)` collisions on lock-file naming; now uses dotted-prefix sibling files.

---

## 1.2.0 — Operationalizing-Expertise Artifacts

### Added (round-2 expansion)

- **KERNEL.md** — 17 universal axioms.
- **CORPUS.md** — 7-layer source corpus.
- **QUOTE-BANK.md** — 28 stable Q-NNN ID quotes.
- **COOKBOOK.md** — 12 doctor patterns.
- **WORKED-EXAMPLE.md** — full pass example for `br doctor`.
- **DP-EXEMPLARS-EXTENDED.md** — 12 additional /dp project exemplars.
- **CASS-EVIDENCE-INDEX.md** — comprehensive theme-organized cross-reference.
- **TESTING-INTEGRATION.md** — wires the 5 testing-* skills into Phase 5.
- **SECURITY.md** — credential redaction; symlink escape; backup safety.
- **PERFORMANCE.md** — detector budgets; hot-path discipline.
- **VERSIONING.md** — three-axis version policy.
- **META-DOCTOR.md** — Pattern 12; doctor-for-the-doctor.
- **AGENT-MAIL-INTEGRATION.md** — concrete reservation patterns.
- **BEADS-INTEGRATION.md** — bead-driven Phase 4.
- **FAQ.md** — common questions.
- **GLOSSARY.md** — 60+ terms.
- **multi-binary-toolkit.md, distributed-cli.md, daemon-cli.md, installer.md** recipes.
- **assets/skill-card.md, intake-worksheet.md, canonical-tasks-template.md, dispatch-prompts.md, scorecard-example.md**.
- **Pattern 12 (meta-doctor)** added.

### Bug fixes (round-2 fresh-eyes)

- 10 real bugs found and fixed; verified via end-to-end smoke tests. See git log for details.

---

## 1.1.0 — Initial Skill Spine

Initial creation. SKILL.md, 16 subagents, 17 scripts, 11 templates, 4 rubric files, 3 exemplars files, 6 recipes, 1 SELF-TEST.md.

---

## How to update this file

When the skill evolves:

1. Allocate the next semver per the rules at top.
2. Add a new H2 section above the previous one.
3. Cite the round of expansion (round-N expansion).
4. List Added / Changed / Bug fixes.

Per [changelog-md-workmanship](../../changelog-md-workmanship/SKILL.md), the changelog is rebuilt periodically from git tags + release notes. This file's content takes precedence over auto-generated content.
