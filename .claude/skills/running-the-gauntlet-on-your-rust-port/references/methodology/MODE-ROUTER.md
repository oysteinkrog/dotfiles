# MODE-ROUTER — Operating Modes for the Gauntlet

Pick a mode FIRST. The 16-phase loop in [PHASES.md](../PHASES.md) is the same engine; the mode tells the orchestrator **which phases run, which can be skipped, what the stop condition is, and which artifacts are mandatory**. Running `gauntlet-full` when the user actually wanted `audit-only` wastes weeks; running `audit-only` when they wanted `gauntlet-full` ships a report with no fixes. Most run-time mistakes come from skipping this step.

Modes compose with **tier** (see [TIER-TRIAGE.md](TIER-TRIAGE.md)) — tier sizes the parallelism and depth; mode chooses which phases. Mode is dispatched from [KICKOFF-PROMPTS.md](KICKOFF-PROMPTS.md); the orchestrator emits the verbatim per-mode prompt to itself or to the user.

---

## How to pick the mode

```
Does the user want a release certificate at the end?
├─ YES (certification bundle is the deliverable)
│   ├─ Reference version moved since last green run?  → migration
│   ├─ Re-certifying against a moved reference?       → compliance-pass
│   └─ Fresh certification of a mature port?          → gauntlet-full
│
└─ NO
    │
    Is the port mature, has a workspace already, AND only one pillar regressed?
    ├─ YES                                            → harden-pillar
    │
    Is the port already certified, but a new Feature must be added?
    ├─ YES                                            → add-feature
    │
    Did the port's main branch move since the last green run?
    ├─ YES (git diff small)                           → incremental-rebase
    │
    Is the user asking only for findings + remediation plan?
    ├─ YES                                            → audit-only
    │
    Is the user asking only for adversarial coverage of existing gates?
    ├─ YES                                            → red-team
    │
    Is this just to mine prior session history before a campaign?
    ├─ YES                                            → cass-mine-only
    │
    Is this the SELF-TEST workflow against a tiny port?
    ├─ YES                                            → quick-smoke
    │
    Else (default)                                    → gauntlet-full
```

`scripts/gauntlet.sh --mode <mode>` is the shipped entrypoint. Modes that need
an extra value use explicit flags: `--pillar <pillar>`,
`--feature-id <feature-id>`, or `--new-ref-version <version>`. The orchestrator
applies this tree during up-front confirmations and then passes the selected
mode explicitly; there is no separate shipped `detect-mode.sh` helper. The user
can override the proposed mode at the up-front-confirmations step (see
[SKILL.md § Up-Front Confirmations](../../SKILL.md)).

---

## Mode Definitions

### `gauntlet-full` (default)

| Field | Value |
|---|---|
| **When** | Default. Fresh certification of a mature Rust port against a pinned reference; user wants the full release-readiness bundle. |
| **Phases run** | 0 → 16 (all phases). |
| **Required artifacts** | Every phase's exit-criteria output from [PHASES.md](../PHASES.md). `FINAL_GAUNTLET_REPORT.md` + `PARITY_RUNBOOK.md` + `RELEASE_CERTIFICATION_TEMPLATE.md` + polished bead graph + certification bundle. |
| **Stop condition** | `scripts/convergence-tracker.sh` exits 0 (≥10 rounds, ≥2 consecutive clean, every open hypothesis resolved) AND Phase 14 ≥2 clean rounds AND Phase 15 soak clean AND `scripts/final-report-builder.sh` exits 0. |
| **Forbidden** | Skipping Phase 11 minimum-round count. Skipping Phase 15 soak. Editing the target port outside of Phase-13 bead-author output. |
| **Wall time** | Days-to-weeks per tier (T1: hours; T3: ~2 weeks; T4: 30+ days). See [TIER-TRIAGE.md](TIER-TRIAGE.md). |
| **Kickoff** | [KICKOFF-PROMPTS.md § gauntlet-full](KICKOFF-PROMPTS.md#gauntlet-full-kickoff). |

### `audit-only`

| Field | Value |
|---|---|
| **When** | The user wants an honest assessment without any source-port mutation. Stakeholder ask, procurement review, "is this safe to ship?" question. |
| **Phases run** | 0 → 9 (recon through baseline). Then a *condensed* Phase 12 that produces a remediation **plan** but NOT beads/implementation. |
| **Required artifacts** | All Phase 0-9 outputs + `<workspace>/AUDIT_REPORT.md` (≤4 pages, executive-summary first) + `<workspace>/REMEDIATION_PLAN.md` (gap-by-gap proposals with rubric scores) + the three populated negative-ledgers. |
| **Stop condition** | `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` are committed and reviewed by the user. |
| **Forbidden** | Phase 11 iteration loop. Phase 13 bead handoff. Phase 14 fresh-eyes (the report itself is the deliverable; reviewing the report is the user's job). Any `Edit`/`Write` to `<target>/` outside `<workspace>/`. |
| **Wall time** | 1-5 days depending on tier. |
| **Kickoff** | [KICKOFF-PROMPTS.md § audit-only](KICKOFF-PROMPTS.md#audit-only-kickoff). |

`audit-only` is **not a draft of `gauntlet-full`**. The output shape differs (report vs. certification bundle). Recommend `gauntlet-full` as the natural follow-up if the audit findings warrant remediation.

### `harden-pillar`

| Field | Value |
|---|---|
| **When** | The port is already in green-cert state but one pillar (perf | conformance | surface) just regressed; user wants all parallel capacity focused on that pillar. Common after a fresh-eyes round caught a real regression that the ratchet quarantine flagged but didn't auto-block. |
| **Phases run** | 0 (workspace re-init) → 1 (scoped recon: only the regressed pillar's surface) → 5 OR 6 OR 7 (the regressed pillar's harness expansion only) → 9 (scoped baseline) → 10 (idea-wizard on the regressed pillar) → 11 (iteration: minimum 5 rounds, ≥2 clean) → 12 → 13 → 14 → optional 15 (soak only on the regressed lane). |
| **Required artifacts** | All listed phase outputs **scoped to the chosen pillar** + a `PILLAR_REMEDIATION_REPORT.md` naming what regressed, the bead trail of the fix, and the new ratchet state. |
| **Stop condition** | The ratchet quarantine clears for the regressed pillar (`scripts/apply-ratchet.sh` exits 0 for that pillar) AND Phase 14 ≥1 clean round AND `<workspace>/.bench-history/<bench>.latest.json` updated. |
| **Forbidden** | Touching the other two pillars' harnesses (out of scope; defer to next `gauntlet-full`). |
| **Wall time** | Days (typically 3-7 for a single-pillar campaign at T3). |
| **Pillar token** | The kickoff prompt fills `<PILLAR>` with one of `perf | conformance | surface`. |

### `add-feature`

| Field | Value |
|---|---|
| **When** | A new feature must be added to the FeatureUniverse (e.g., new PRAGMA, new RESP3 type, new tensor op, new HTTP middleware). Scope is bounded; user does not want a full audit of unrelated bundles. |
| **Phases run** | 0 (workspace check) → scoped Phase 1 (recon for the feature's surface region) → Phase 2 (FeatureUniverse weight rebalance — `sum(weights) == 1.0` must still hold) → Phases 5-13 scoped to the feature (`5` to add the perf bench for it; `6` to add oracle/metamorphic/fuzz; `7` to update FeatureUniverse + InvariantCatalog; `9` to baseline; `10-11` to find sibling gaps; `12-13` to remediate). |
| **Required artifacts** | `<workspace>/feature/<feature-id>/` containing: `recon.md`, `weight_rebalance.md`, per-pillar harness additions, `baseline.md`, beads-graph delta, and an `INTEGRATION_REPORT.md` confirming the new feature has `present` status in `supported_surface_matrix.toml`. |
| **Stop condition** | The new Feature row has `status = Passing` (not `Partial`) in `feature_coverage_dashboard.rs` AND has at least one oracle test + one metamorphic test + one fuzz target + one bench + one invariant in the InvariantCatalog. |
| **Forbidden** | Phase 14 full fresh-eyes (only the feature region needs reviewer attention). Phase 15 soak unless the feature touches a fault/crash boundary. Rebalancing weights to favor the new feature ("Feature pumping"). |
| **Wall time** | Hours (T1) to days (T3-T4) per feature. |
| **Blast-radius escalator** | If the feature touches >3 other features' boundaries OR introduces a new crash boundary OR introduces a new fault category, escalate to `gauntlet-full` for the affected subtree. Document the escalation in `<workspace>/feature/<feature-id>/escalation.md`. |

### `incremental-rebase`

| Field | Value |
|---|---|
| **When** | The port's main branch moved since the last green gauntlet run. User wants to re-run only the affected phases (auto-detected from `git diff` since last green tag). |
| **Phases run** | 0 (workspace reuse) → Phase 1 *delta* (recon only changed crates) → Phase 9 *delta* (re-baseline only affected workload families, identified from the git diff + `crates/*/PHASE_OWNERS.toml`, or by a project-local affected-benches helper) → if any divergence: Phases 11-14 scoped to affected lanes → Phase 16 (re-stamp the certification with the new git SHA). |
| **Required artifacts** | `<workspace>/incremental_<git-sha>/` with: `git_diff_summary.md`, `affected_phases.json`, `affected_lanes.json`, per-lane re-baseline output, and a `REBASE_REPORT.md` showing what changed vs. last green. |
| **Stop condition** | All affected lanes re-baseline within ratchet thresholds AND any divergence resolved AND `scripts/final-report-builder.sh <workspace> --incremental` exits 0. |
| **Forbidden** | Full re-iteration of unaffected lanes (wastes compute). Skipping the `git diff` analysis (would silently miss affected lanes). |
| **Detection heuristic** | Read `git diff <last-green-sha>..HEAD --name-only`, map file paths → owning crates → owning phases via `crates/*/PHASE_OWNERS.toml`, and emit `affected_phases.json`. Teams may wrap this as a project-local `scripts/detect-affected-phases.sh`; it is not a shipped gauntlet helper. |
| **Wall time** | Hours-to-days (much faster than `gauntlet-full`). |

### `compliance-pass`

| Field | Value |
|---|---|
| **When** | Re-certifying an already-green port against a moved reference version. Auditor needs evidence; user does not want to introduce new gaps. |
| **Phases run** | 0 → 1 → 2 (re-pin the reference) → 9 (full sweep against new reference) → 14 (fresh-eyes on the evidence bundle) → 16 (re-stamp certification bundle). Phase 11 iteration is SKIPPED — this mode does not invite new hypothesis generation. |
| **Required artifacts** | Updated `<reference>_version_contract.toml`, new `round_<N>/` outputs against new reference, refreshed `certification_bundle/`, and a `COMPLIANCE_DELTA.md` mapping every changed gate to its evidence. |
| **Stop condition** | Every required-pass constant from [CERTIFICATION.md](CERTIFICATION.md) holds for the new reference version AND the certification bundle is signed. |
| **Forbidden** | New features. New patterns. Anything that would force a freshly-written gate to be re-audited. Phase 10 idea-wizard. Phase 11 iteration. Phase 12 remediation design. |
| **Wall time** | 1-3 days. |
| **Important** | If `compliance-pass` *discovers* a real gap against the new reference, **STOP**. Recommend the user switch to `migration` mode. Auditors need stability; an undisclosed gap discovered during compliance is a finding worse than the gap itself. |

### `red-team`

| Field | Value |
|---|---|
| **When** | A specific gate (or set of gates) needs adversarial coverage. The harness exists; the user wants to confirm the gates can't be lied to. Typically run before a high-stakes release or after a "the agent honest enough to write the gate is biased toward making it pass" suspicion. |
| **Phases run** | 0 (workspace check) → Phase 15 *adversarial-search-only* (`subagents/soak-runner-adversarial.md`). Phase 16 is REPLACED by `<workspace>/RED_TEAM_REPORT.md`. No remediation in this mode — counterexamples are surfaced to the user, not auto-fixed. |
| **Required artifacts** | Per-gate counterexample list, `gate_vulnerabilities.md`, regression test stubs for each counterexample. |
| **Stop condition** | Every gate in `<workspace>/docs/gates_inventory.toml` has had ≥1,000 adversarial perturbations applied AND any found counterexample is recorded with `(perturbations_in_order, random_seed, expected_decision, actual_decision, repro_command)`. |
| **Forbidden** | Auto-fixing any found vulnerability (defeats the purpose). Modifying any gate based on adversarial findings (defer to a follow-up `harden-pillar` run with the user's sign-off). |
| **Wall time** | 1-3 days (most time spent on adversarial perturbation generation). |
| **Important** | Counterexamples ARE the deliverable. A red-team run that finds nothing on a complex port is suspicious; calibrate the adversarial search budget and rerun. |

### `migration`

| Field | Value |
|---|---|
| **When** | Switching reference versions (e.g., `sqlite-3.50 → 3.52`, `redis-7.2 → 7.4`, `torch-2.X → 2.Y`). Some surface will move; some will break; some will newly appear. |
| **Phases run** | 0 → 1 → Phase 2 *re-pinning* (new `<reference>_version_contract.toml`; diff against old; surface delta committed to `migration/<old>_to_<new>/surface_delta.md`) → Phase 4 *re-capture* (golden artifacts re-captured against new reference) → Phase 6 *targeted iteration* (every behavior-class lane that the delta touches gets a re-run) → Phases 9-11 (re-baseline + iterate) → 12-16 normal. |
| **Required artifacts** | `<workspace>/migration/<old>_to_<new>/` containing: `surface_delta.md`, `golden_delta.md`, `behavior_delta.md`, per-affected-lane re-run, `MIGRATION_REPORT.md` with the full transition story. |
| **Stop condition** | New reference version fully accepted (every Feature row has a `status` against new reference) AND old version's `.bench-history/<bench>.latest.json` archived to `<workspace>/migration/<old>_to_<new>/archived_baselines/` (not deleted). |
| **Forbidden** | Deleting old reference's artifacts (archive them; the historical record is part of the proof). Skipping the surface delta step (would silently drop features that the new reference removed). Asserting "the new version is strictly better" without behavior-delta evidence. |
| **Wall time** | Days-to-weeks (depends on delta size; SQLite minor-version is usually days, major-version is weeks). |
| **Important** | Migrations across major versions almost always uncover patterns that were "implicit" (relying on undocumented behavior of the old version). Mine the 60-day cass for failure terms from BOTH versions; the delta is where bugs live. |

### `cass-mine-only`

| Field | Value |
|---|---|
| **When** | Before kicking off a perf/conformance campaign, the user wants to know what's already been tried, rejected, or abandoned on this codebase. Useful pre-flight even outside of a gauntlet run. |
| **Phases run** | Phase 8 *only* (negative-ledger seeding + cass mining). Skips everything else. |
| **Required artifacts** | `<workspace>/cass_findings_<run_id>.jsonl` (per the schema in [CASS-MINING.md](CASS-MINING.md)) + a `CASS_SUMMARY.md` grouping findings by failure class + the three populated negative-ledgers (or seeded versions if they don't exist). |
| **Stop condition** | All five machines (local + css + csd + ts1 + ts2) have been queried, the JSONL is non-empty (or "no findings" is explicitly logged with a blocker entry per the AGENTS.md mandate), and the summary is reviewed by the user. |
| **Forbidden** | Implementing anything based on findings (this mode is read-only). Touching `<target>/` source. |
| **Wall time** | 15-60 minutes. |
| **Important** | The findings are the input to the *next* mode invocation. The user reads them and then dispatches `gauntlet-full` or `harden-pillar` or `add-feature` with the cass evidence in hand. |

### `quick-smoke`

| Field | Value |
|---|---|
| **When** | The SELF-TEST workflow. A tiny port (typically a single-crate skeleton built solely to verify the skill itself works end-to-end). Used in CI for the skill, not for real ports. |
| **Phases run** | 0 → 9 in quick mode. The orchestrator lists the non-scripted phases in dry-run output but does not dispatch full Phase 1-7 fan-out. Phases 10-16 SKIPPED. |
| **Required artifacts** | Minimal: one oracle test, one bench, one Feature row, one FailureBundle pathway exercised. `<workspace>/SELF_TEST_REPORT.md` confirms each phase ran. |
| **Stop condition** | `scripts/validate-skill.py` exits 0, `scripts/check-cross-links.py <skill-root>` exits 0, `scripts/gauntlet.sh <target> <workspace> --mode quick-smoke --dry-run` exits 0, and any harnessed toy used for a real smoke has green `cargo test -p <port>-harness` plus `cargo run --bin comprehensive_bench -- --quick`. |
| **Forbidden** | Long-running operations (every step ≤5 min wall time). Soak runs. Iteration loop. |
| **Wall time** | ≤30 minutes (CI budget). |
| **See** | [SELF-TEST.md](../../SELF-TEST.md) for the trigger phrases and the tiny-port scaffold the skill builds. |

### `gauntlet-greenfield`

| Field | Value |
|---|---|
| **When** | The target is a novel non-port Rust project (no upstream reference to diff against). Auto-detect: `scripts/detect-project-class.sh` returns `UNKNOWN`. Canonical example: `eidetic_engine_cli`. |
| **Phases run** | 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13 → 14 → 15 → 16 (same as `gauntlet-full`, but Phase 2 becomes SPEC PINNING instead of REFERENCE PINNING, and Phase 3 dispatches `greenfield-oracle-wirer` instead of `oracle-wirer`). |
| **Required artifacts** | Same as `gauntlet-full`, with these greenfield-specific additions: `docs/contracts/spec_version_contract.toml` (instead of `<reference>_version_contract.toml`), `docs/spec/SPEC-TAGS.md` (catalog of every `[SPEC-NNN]` assertion), the 5-mode oracle suite (`spec_oracle.rs`, `property_oracle.rs`, `self_oracle.rs`, `roundtrip_oracle.rs`, `external_tool_oracle.rs`), `tests/golden/` directory of insta + roundtrip baselines. |
| **Stop condition** | Same as `gauntlet-full` convergence rule (≥10 rounds, 2 consecutive clean rounds, every open hypothesis resolved) PLUS: every `[SPEC-NNN]` tag has a passing verifier; every (encode, decode) pair has a passing round-trip; external-tool oracle (Miri + Clippy + cargo-deny + cargo-audit) is green. |
| **Required artifacts (post-Phase-16)** | All of `gauntlet-full`, plus `certification_bundle/spec_sha256.txt` + `certification_bundle/property_suite_version.txt` so an auditor can reproduce the certification. |
| **Wall time** | Same range as `gauntlet-full` (10-15+ days). Greenfield projects with strong informal floors (like `eidetic_engine_cli`) often converge faster because most of the work is *formalizing* existing practice rather than building new harness. |
| **See** | [`GREENFIELD-ADAPTATION.md`](GREENFIELD-ADAPTATION.md) for the full meta-pattern; [`../case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md) for the worked example. |
| **Forbidden** | Attempting to diff against an "upstream reference" that doesn't exist; treating Phase 2's spec pinning as optional (it's where the Oracle gets defined); running `gauntlet-greenfield` when the project actually IS a port (use the matching class-specific mode instead). |

---

## Mode-to-phase coverage matrix

| Phase | gauntlet-full | gauntlet-greenfield | audit-only | harden-pillar | add-feature | incremental-rebase | compliance-pass | red-team | migration | cass-mine-only | quick-smoke |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 0 Bootstrap | ✓ | ✓ | ✓ | reuse | reuse | reuse | reuse | reuse | reuse | reuse | ✓ |
| 1 Recon | ✓ | ✓ | ✓ | scoped | scoped | delta | ✓ | — | ✓ | — | ✓ |
| 2 Reference pin | ✓ | spec-pin | ✓ | — | rebalance | — | re-pin | — | re-pin | — | ✓ |
| 3 Oracle wiring | ✓ | 5-mode | ✓ | — | — | — | — | — | — | — | ✓ |
| 4 Golden capture | ✓ | ✓ | ✓ | — | scoped | — | — | — | re-capture | — | ✓ |
| 5 Perf harness | ✓ | ✓ | ✓ | perf-only | scoped | delta | — | — | — | — | ✓ |
| 6 Conformance harness | ✓ | ✓ | ✓ | conf-only | scoped | delta | — | — | targeted | — | ✓ |
| 7 Surface inventory | ✓ | ✓ | ✓ | surf-only | scoped | delta | — | — | — | — | ✓ |
| 8 Negative ledgers | ✓ | ✓ | ✓ | reuse | reuse | reuse | reuse | reuse | reuse | ✓ | — |
| 9 Baseline | ✓ | ✓ | ✓ | scoped | scoped | delta | ✓ | — | ✓ | — | ✓ |
| 10 Idea-wizard | ✓ | ✓ | — | scoped | scoped | — | — | — | scoped | — | — |
| 11 Iterate | ✓ (≥10) | ✓ (≥10) | — | scoped (≥5) | scoped | scoped | — | — | scoped | — | — |
| 12 Remediation | ✓ | ✓ | plan-only | scoped | scoped | scoped | — | — | scoped | — | — |
| 13 Beads handoff | ✓ | ✓ | — | scoped | scoped | scoped | — | — | scoped | — | — |
| 14 Fresh-eyes | ✓ (≥2) | ✓ (≥2) | — | ≥1 | scoped | scoped | ✓ | — | ✓ | — | — |
| 15 Soak | ✓ | ✓ | — | optional | — | — | — | **adversarial-only** | optional | — | — |
| 16 Final artifacts | ✓ | cert | report-only | pillar-report | feature-report | rebase-report | re-stamp | red-team-report | migration-report | summary | self-test-report |

Legend: `✓` runs in full; `scoped` runs only on the affected subset; `delta` runs only on files/lanes changed since last green; `reuse` uses existing workspace state; `—` does not run; `re-pin`/`re-capture`/`re-stamp` is mode-specific.

---

## Auto-detect heuristic table

The orchestrator evaluates these in order before invoking `scripts/gauntlet.sh --mode <mode>`; first match wins:

| Heuristic | If true → propose mode |
|---|---|
| `phase0_project_class.json.detected_class == "UNKNOWN"` OR user says "greenfield" / "no upstream reference" / "not a port" | `gauntlet-greenfield` |
| `<workspace>/` does not exist AND `<target>/` is a sibling port path | `gauntlet-full` (fresh) |
| `<workspace>/RELEASE_CERTIFICATION.md` exists AND `<target>/git log` shows new commits since last cert | `incremental-rebase` |
| `<workspace>/.bench-history/<bench>.latest.json` shows ratchet quarantine on exactly one pillar | `harden-pillar --pillar=<name>` |
| User prompt contains "audit", "review", "assessment", "where does this stand" (no "fix" or "ship") | `audit-only` |
| User prompt contains "certify", "release-ready", "bundle for the auditor" | `gauntlet-full` (or `compliance-pass` if cert exists) |
| User prompt contains "new feature", "add support for", "implement Feature-X" | `add-feature` |
| User prompt contains "switch reference to", "upgrade from", "rebased onto new <reference> version" | `migration` |
| User prompt contains "adversarial", "red team", "can I trust this gate" | `red-team` |
| User prompt contains "mine cass", "before I touch", "what's already been tried" | `cass-mine-only` |
| `<target>` is `<basename>__selftest_port` or `tests/fixtures/tiny-port/` | `quick-smoke` |
| Else | `gauntlet-full` (default) |

The user can ALWAYS override at the Up-Front Confirmations step. The detector is a *recommendation*, not a decision.

---

## Mode-tier overlay

Modes are orthogonal to tiers (see [TIER-TRIAGE.md](TIER-TRIAGE.md)). A T4 platform port can run `add-feature` mode (small scope, fast loop), and a T1 tiny port can run `gauntlet-full` (full discipline, completed in hours).

| Tier × Mode | Typical wall time | Typical worker count |
|---|---|---|
| T1 × gauntlet-full | hours | 1-2 |
| T1 × quick-smoke | 15-30 min | 1 |
| T2 × gauntlet-full | days | 2-4 |
| T3 × gauntlet-full | ~2 weeks | 4-8 |
| T3 × harden-pillar | 3-7 days | 4-8 (concentrated on one pillar) |
| T3 × incremental-rebase | hours-days | 2-4 |
| T3 × add-feature | hours-days | 2 |
| T4 × gauntlet-full | 30+ days | 8-12 (Swarm) |
| T4 × compliance-pass | 1-3 days | 4-6 |
| T4 × migration | weeks | 8-12 |
| T5 × gauntlet-full | months | NTM-orchestrated swarm |

Use this table to set user expectations at Up-Front Confirmations. A T4 `gauntlet-full` quoted at "a day" is a red flag — the agent has either underscoped or under-tiered.

---

## Mode handoff template

When you finish a mode, emit this exact stanza for the user:

```
You ran <mode> on <port>. Status: <complete | partial>.

What's done:
- <one bullet per phase that produced an artifact>

What's open:
- <each remaining gap with bead ID, severity, and the mode that would close it>

Recommended next mode: <mode-name>
Why: <one paragraph>
Estimated wall time: <hours | days | weeks>
Gates that would block: <e.g. "no reference binary for sqlite-3.53 yet — need the user to install">
```

This keeps users from accidentally re-running the same mode hoping for different output, and from skipping straight to `compliance-pass` when there's still a CONFIRMED_GAP in the conformance pillar.

---

## Common confusions

- **`audit-only` is not a draft of `gauntlet-full`.** Different output shape (report vs. certification bundle). Don't promise a report and ship code; don't promise a cert and ship a report.
- **`harden-pillar` is not a license to skip Phase 14.** Even pillar-scoped work requires fresh-eyes — the regression that triggered the harden run could mask sibling regressions.
- **`add-feature` is not "audit a slice."** If the feature touches the FeatureUniverse weight invariant or introduces a new fault/crash boundary, you've crossed into `gauntlet-full` territory for the affected subtree. Document the escalation up front.
- **`compliance-pass` forbids new findings.** Auditors need stability. If you find a gap, STOP and recommend `migration` or `harden-pillar`. Do not paper over.
- **`red-team` does not auto-fix.** Counterexamples are the deliverable; fixing them is a separate `harden-pillar` run with the user's explicit sign-off.
- **`cass-mine-only` is read-only.** It produces evidence; it does not act on it. The next mode invocation consumes the output.
- **`quick-smoke` is for the skill's own tests.** Do not use it on a real port (it skips too much).

See [SKILL.md § Up-Front Confirmations](../../SKILL.md) for how the orchestrator confirms the chosen mode with the user before any phase runs.
