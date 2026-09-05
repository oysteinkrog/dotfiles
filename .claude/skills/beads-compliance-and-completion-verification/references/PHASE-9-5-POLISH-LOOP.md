# PHASE-9-5-POLISH-LOOP.md — Mandatory iterative polish after Phase 9 writes

<!-- TOC: Why | When it fires | The loop | The verbatim prompt | Operational rules | Worked example | Bv interaction | Non-convergence | Edge cases | Anti-patterns -->

## Why this exists

Phase 9 writes new beads (or reopens originals) so the bead graph reflects every false-closed item from the audit. But beads written *during* an audit are necessarily rough — they're transcribed from the scorecard's "Missing items" section, which is itself a derivative of the spec, which was itself written by someone else, possibly months ago. **The remediation beads are first drafts.** Without polish, an implementation session picks up vague AC, misses cross-bead implications, and re-introduces the same theater the audit was supposed to flush out.

> Plan-space is cheap. Implementation-space is 10× more expensive. **Polish in plan-space.**

The user's standing instruction is that the polish loop is mandatory whenever Phase 9 wrote beads. The loop applies one specific prompt three times in a row, with `bv` consulted between sweeps, and every edit going through `br update`. This file is the deep-dive; SKILL.md's Phase 9.5 section is the at-a-glance.

## When it fires

| Condition | Phase 9.5 runs? |
|-----------|:--:|
| `--policy=completion-debt` AND Phase 9 wrote ≥ 1 bead | ✅ MUST run |
| `--policy=reopen` AND Phase 9 reopened ≥ 1 bead | ✅ MUST run |
| `--policy=report-only` (no bead writes) | ❌ N/A — nothing to polish |
| Phase 9 wrote 0 beads (every closed bead scored ≥ threshold) | ❌ N/A — log "no polish needed" |
| Tripwire mode (autonomous CI) | ⚠️ Skipped by design — tripwire never writes beads autonomously |

`run-pass.sh` invokes the scaffold script automatically when the conditions above hold. To skip explicitly (only when the user requested it, NOT to save time), pass `--no-polish`.

## The loop (3 sweeps, plus auto-extend)

```
Phase 9 writes N beads
        │
        ▼
┌───────────────────────────────────┐
│  scripts/polish-remediation-      │
│    beads.sh writes scaffold       │
│  → polish_log.md (3 sections)     │
│  → polish_bv_initial.json         │
└───────────────────────────────────┘
        │
        ▼
   Sweep 1 — orchestrator agent applies
   the verbatim polish prompt to every
   bead in turn; routes edits via
   br update / br comment
        │
        ▼
   bv --robot-suggest (between sweeps)
        │
        ▼
   Sweep 2 — same prompt, but now the
   orchestrator can see the cross-bead
   consistency it didn't see in Sweep 1
        │
        ▼
   Sweep 3 — same prompt, mostly a no-op
   if Sweeps 1+2 caught the real gaps
        │
        ▼
   Did Sweep 3 produce meaningful edits?
        │
        ├── No → DONE. Run `br sync --flush-only`
        │        commit `.beads/`, do NOT push.
        │
        └── Yes → run a Sweep 4 (and Sweep 5,
                  up to ~6 total). If still
                  non-converged, escalate to
                  /idea-wizard or /planning-
                  workflow — the bead set is
                  genuinely under-specified.
```

## The verbatim prompt

The canonical text lives in **`assets/polish-prompt.txt`**. SKILL.md's Phase 9.5 section and `scripts/polish-remediation-beads.sh`'s `POLISH_PROMPT` bash variable both must match it character-for-character. Use **`scripts/validate-polish-prompt-consistency.py`** (pre-commit or CI) to catch silent drift.

> Check over each bead super carefully — are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Make sure to ONLY use the `br` cli tool for all changes, and you can and should also use the `bv` tool to help diagnose potential problems with the beads.

The five non-negotiables embedded in the prompt:

1. **"Plan space" framing** — the orchestrator should think about whether the bead is *correctly scoped* before any code is written.
2. **DO NOT OVERSIMPLIFY** — preserve all useful complexity. The first instinct of an LLM polishing prose is to compress; that's wrong here.
3. **DO NOT LOSE FUNCTIONALITY** — the AC may have implicit requirements (rollback, observability) the audit caught; keep them.
4. **Comprehensive tests + detailed logging** — every polished bead must include unit AND e2e test specs with great logging in the AC.
5. **Use `br` and `bv` only** — never hand-edit the JSONL / SQLite. `br update` keeps both stores atomically in sync.

## Operational rules (every sweep)

- **All edits via `br update <id>` / `br comment <id> --body=…`.** `br create` is allowed when splitting a bead into two. Hand-editing `.beads/issues.jsonl` or `.beads/*.db` is strictly forbidden — drift between the two stores is the #1 cause of bead corruption (`/fixing-beads-problems` exists because of this).
- **Touch every bead at least once per sweep,** even when no change is needed. Record the "no change" decision via `br comment <id> --body="sweep N: no-change — already optimal because <reason>"` so future passes see the deliberation.
- **Consult `bv` between sweeps:**
  - `bv --robot-suggest` for duplicates / missing dependencies / hygiene flags.
  - `bv --robot-priority` for priority-misalignment detection.
  - `bv --robot-alerts` for stale issues, blocking cascades.
  - The scaffold captures one initial snapshot at `<pass-dir>/polish_bv_initial.json`; recapture between sweeps to see how the graph improved.
- **Sweep budget:** ~30s–2 min per bead per sweep with a frontier model. For ≥ 30 new beads, fan out across subagents (one bead per subagent, each runs the verbatim prompt) but verify the prompt is bit-identical via `validate-polish-prompt-consistency.py`.
- **End-of-loop:** `br sync --flush-only`, then `git add .beads/` and a single commit. **Do NOT `git push`** — that's the user's call. The Phase 9.5 commit message convention is `audit: polish loop for pass <PASS_ID> (N beads, M sweeps)`.

## Worked example

Pre-Phase 9.5 bead created by Phase 9 (verbatim from a real audit run):

```
Title: [completion-debt] Implement process() with real logic
Description: process() must validate input, transform it, and return Result<T, E>.
             Include unit tests covering the happy path and error path.
             Add a fuzzer that runs for 60s in CI.
Priority: P1
AC:
  - process() handles empty input gracefully
  - process() handles malformed input by returning Err
  - unit tests cover both paths
  - fuzz target runs for 60s in CI without crashes
```

**Sweep 1 polish (orchestrator applies the verbatim prompt):**

```bash
br update bd-foo --description='process() validates input (empty / malformed → Err with structured error code), transforms it via the pipeline declared in design.md#processing-pipeline (NEVER short-circuit; the production code path must be exercised by every test), and returns Result<TransformedT, ValidationError>. Detailed logging at INFO for the happy path and ERROR for each rejection class so test runs can be diagnosed without re-running.'

br update bd-foo --acceptance-criteria='- process(empty_input) → Err(ValidationError::Empty); covered by unit test in tests/unit/process_empty.rs that asserts the exact error variant
- process(malformed_input) → Err(ValidationError::Malformed { reason }); covered by unit test in tests/unit/process_malformed.rs that asserts the reason string is non-empty
- process(happy_path_input) → Ok(transformed) where transformed.field_x == expected_value; covered by tests/unit/process_happy.rs
- e2e test: tests/e2e/process_smoke.rs spawns the full pipeline (no mocks) and asserts the database row count increments by 1; logs at INFO and ERROR are captured into tests/e2e/logs/<test>.jsonl for post-mortem
- fuzz target in fuzz/fuzz_targets/process_input.rs runs for 60s in GitHub Actions CI on every push to main without crashes; cargo fuzz corpus seeded with 100 hand-crafted inputs covering empty, malformed, valid edge cases'

br comment bd-foo --body='sweep 1: tightened verbatim AC to per-test cite; added e2e + fuzzer details with structured logging requirement per polish prompt'
```

**Sweep 2 (the orchestrator now sees the cross-bead implications):**

```bash
# `bv --robot-suggest` flagged that a sibling bead bd-bar references the same
# pipeline. The orchestrator adds an explicit dependency to make it visible.
br dep add bd-foo bd-bar
br comment bd-foo --body='sweep 2: bd-bar (pipeline contract owner) added as dep; surfaced via bv suggest'
```

**Sweep 3:**

```bash
br comment bd-foo --body='sweep 3: no-change — AC, deps, and tests are explicit; ready for implementation'
```

The bead is now ready for the next implementation session. The orchestrator's `polish_log.md` records every decision, with timestamps, so future audits can attribute changes back.

## Bv interaction patterns

Between Sweep 1 and Sweep 2, run:

```bash
bv --robot-suggest > /tmp/bv-suggest-after-sweep-1.json
bv --robot-priority > /tmp/bv-priority-after-sweep-1.json
```

Look for:

- **`suggest.duplicates`** — bd-foo polished to look like bd-bar? If so, decide: merge (close one with reason "duplicate of bd-bar"), or differentiate (rename so the distinction is explicit).
- **`suggest.missing_dependencies`** — Phase 7 already ran synthesis, but new edits in Sweep 1 may have introduced fresh contracts. Add explicit deps.
- **`priority.mismatches`** — if Sweep 1 raised the priority of an unblocking bead but a downstream bead is still P3, fix the cascade.
- **`alerts.stale_issues`** — should be empty for newly-written beads; if anything appears, it's a sign you accidentally edited an old bead.

## Handling non-convergence

If Sweep 3 still produces meaningful edits:

1. **Run a Sweep 4.** The polish-remediation-beads.sh scaffold pre-allocates only 3 sweep sections, but you can append a `## Sweep 4` section by hand. (The script's `--sweeps 4` flag also works for fresh runs.)
2. **If Sweep 4 still changes things, run a Sweep 5.** Past Sweep 5, stop. The bead set is *under-specified* — the polish prompt is no longer converging on a stable target.
3. **Escalation path:**
   - For a single under-specified bead → `/idea-wizard` to brainstorm what's missing.
   - For multiple beads with shared theme → `/planning-workflow` to step back and re-derive the slice.
   - For an entire epic → consider closing the epic with reason "needs re-scoping" and creating a new draft epic via the `/beads-workflow` skill.

Record the escalation decision in the polish_log.md `## Sign-off` section.

## Edge cases

| Situation | Handling |
|-----------|----------|
| Phase 9 wrote a bead, but `br show <new-id>` fails (tombstoned somehow) | Skip in the polish loop; record "tombstoned post-creation" in polish_log.md and surface in remediation.md as a Phase-9 anomaly |
| Two new beads are duplicates of each other | Merge in Sweep 1 (close one with `--reason="duplicate of <other-id>"`); record the merge in polish_log.md |
| Polish prompt drift detected by validator | Stop. Run `validate-polish-prompt-consistency.py` to identify the drifted source, copy from canonical, re-validate |
| Orchestrator runs Sweep 1, then crashes mid-sweep — restart? | The script REFUSES to overwrite an existing polish_log.md. Inspect partial state, decide: continue manually (best), or `--force` overwrite (only if no notes were captured) |
| User says "skip Phase 9.5, I just want the report" | Pass `--no-polish` to run-pass.sh AND record the user's instruction in `<pass-dir>/skip_polish_reason.md` so the audit trail is auditable |
| `br sync --flush-only` fails at the end | Don't commit yet. Diagnose with `br doctor`; almost always fixable. If unfixable, surface to `/fixing-beads-problems` |

## Anti-patterns

| ✗ | Why |
|---|-----|
| Hand-editing `.beads/issues.jsonl` to "speed up" polish | Loses the SQLite store's invariants; next `br ready` may see stale state |
| Compressing the AC during polish to make it "cleaner" | Violates the "DO NOT OVERSIMPLIFY" non-negotiable; the original AC was specific for a reason |
| Skipping the bv consultation between sweeps | Sweep 2's value is *seeing the new graph*; without bv, you're just re-applying Sweep 1 logic |
| Running Sweep 3 only because the user is impatient | Plan-space is cheap. Implementation-space is 10× more expensive. Trust the rule. |
| Treating "no change needed" as a reason to skip the bead | Even no-change decisions need a `br comment` so future passes see the deliberation |
| Pushing the `.beads/` commit to the project's remote | The user's call, not yours. Stage and commit locally; let the user `git push` |

## Cross-references

- **Operational rules:** [SKILL.md § Phase 9.5](../SKILL.md#phase-95--mandatory-polish-loop-after-bead-writes)
- **The verbatim prompt:** [assets/polish-prompt.txt](../assets/polish-prompt.txt)
- **Driver script:** [scripts/polish-remediation-beads.sh](../scripts/polish-remediation-beads.sh)
- **Drift validator:** [scripts/validate-polish-prompt-consistency.py](../scripts/validate-polish-prompt-consistency.py)
- **Pre-implementation gate:** [SPEC-QUALITY-GATE.md](SPEC-QUALITY-GATE.md) — the Phase 9.5 prompt is the audit-side analog of the spec-quality reviewer
- **What happens after Phase 9.5:** the polished beads are picked up by `/beads-workflow` or `/multi-agent-swarm-workflow` for implementation
