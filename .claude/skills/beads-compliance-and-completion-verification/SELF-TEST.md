# SELF-TEST.md — Trigger phrases and smoke test

## Trigger phrases (should activate this skill)

- "Audit all our closed beads — did we actually finish them?"
- "I don't trust the bead status field — verify completion for every bead"
- "Run a beads compliance audit on this project"
- "Score every closed bead from 0 to 1000 on actual completion"
- "Find false-closed beads in /data/projects/frankensqlite"
- "Verify bead bd-abc123 was actually completed properly"
- "Re-verify the beads compliance audit — did the agents finish the remediation?"
- "Check whether the conformance harness in bead bd-foo actually runs"
- "Audit beads completion claims; report bead-by-bead with evidence"
- "Are these closed beads actually done or just status-flipped?"
- "Build me a beads audit report with per-bead scores"
- "Make the bead graph truthful again — find the lying status fields"
- "Re-run the beads compliance pass on this audit dir"
- "The audit said 153 false-closed but most of those look fine — what's going on?"
- "Calibrate the bottom-N flagged beads against the real codebase"
- "Spot-check the lowest-scoring beads before I create completion-debt"
- "Polish the new beads from Phase 9 before we implement them"
- "Apply the polish prompt to these remediation beads three times in a row"
- "Phase 9.5 polish loop on this audit pass"
- "The audit just wrote 30 completion-debt beads — make them implementation-ready"
- "Why did my audit flag idiomatic Rust as theater?" → check theater-scan v1.2 patterns
- "The audit dir got created as a sibling instead of inside the project — fix it"

## Trigger phrases (should NOT activate this skill — route elsewhere)

- "Plan a new feature using beads" → `/beads-workflow`
- "What bead should I work on next?" → `/bv`
- "The bead DB is corrupted, fix it" → `/fixing-beads-problems`
- "Find stubs and mocks in this codebase" → `/mock-code-finder`
- "Are we delivering on the README vision?" → `/reality-check-for-project`
- "Review this PR for bugs" → `/multi-pass-bug-hunting`
- "Write a conformance harness for this RFC" → `/testing-conformance-harnesses`
- "Set up E2E tests with no mocks" → `/testing-perfect-e2e-integration-tests-with-logging-and-no-mocks`

## Scope-creep regression probes

| Prompt | Expected scope decision |
|--------|-------------------------|
| "Audit just the recently closed beads" | mode=`delta-since <ref>` (or `closed-only` with date filter); skip `full-audit` |
| "Just look at bd-abc123" | mode=`single-bead`; skip Phase 7 cross-bead synthesis |
| "Run another pass" | mode=`re-verification`; resume in existing audit dir; new `passes/<UTC>/` |
| "Audit and fix everything you find" | DO NOT silently fix. Audit produces remediation beads (Phase 9); implementation is a separate session |
| "Just give me the numbers, don't make new beads" | policy=`report-only`; no `br` writes |

The agent should propose `manifest.json#mode` and `manifest.json#remediation_policy` in the up-front confirmation step. If those aren't proposed, the skill has regressed.

## Smoke test (tiny project, full pipeline)

```bash
# 1. Spin up a throwaway project with a bead store and one closed-but-fake bead.
mkdir /tmp/audit-smoke && cd /tmp/audit-smoke
git init -q
br init >/dev/null
echo 'fn process() { todo!() }' > stub.rs
git add stub.rs && git commit -m "initial stub" >/dev/null

# Create a bead and close it with a self-reported "implemented" reason.
# `br create` does not accept --acceptance-criteria; populate it via `br update`.
# Use the `--acceptance-criteria=...` equals form for values that begin with `-`
# (clap otherwise reads the leading hyphen as a flag indicator).
ID=$(br create --title "Implement process() with real logic" \
                --type feature --priority 1 \
                --description="process() must validate input, transform it, and return Result<T, E>. Include unit tests covering the happy path and error path. Add a fuzzer that runs for 60s in CI." \
                --json | jq -r .id)
br update "$ID" --acceptance-criteria="$(printf '%s\n' \
  '- process() handles empty input gracefully' \
  '- process() handles malformed input by returning Err' \
  '- unit tests cover both paths' \
  '- fuzz target runs for 60s in CI without crashes')"
br close "$ID" --reason "Implemented and tested" >/dev/null

# 2. Run the audit. Resolve the skill dir relative to this file so the test
# runs whether the skill is installed under ~/.claude/skills, ~/.codex/skills,
# or vendored under .claude/skills/ in some project.
SKILL_DIR="$(dirname "$(realpath "${BASH_SOURCE:-$0}")" 2>/dev/null || \
            echo "$HOME/.claude/skills/beads-compliance-and-completion-verification")"
bash "$SKILL_DIR/scripts/run-pass.sh" /tmp/audit-smoke --threshold 700 --policy completion-debt

# 3. Expected outcomes (v1.2 — UPDATED for the Phase-4/6 WAIVED-on-stub behavior):
#   - /tmp/audit-smoke/beads_compliance_audit/ exists with .git/
#   - REPORT.md exists with the canonical "X total beads audited; Y false-closed
#     (status=closed, score<700) — Z% of all closed beads (of N total closed)" line.
#   - In a deterministic-only run (run-pass.sh with stub Phase 4 / 6), false-
#     closed counts depend on whether the Phase-3 baseline can extract code
#     artifacts from the spec. For the prose-style spec above, deterministic
#     extraction yields zero code_artifacts → Implementation dim returns max,
#     and Tests/TestDepth dims are WAIVED-on-stub. The bead scores ~970/1000
#     (with 30 deducted for theater findings on the `todo!()` stub).
#     This is CORRECT v1.2 behavior — the deterministic-only banner explicitly
#     marks the score as an UPPER BOUND. To trigger false-closed for this
#     bead, dispatch the LLM evidence-gatherer + compliance-verifier subagents
#     (which DO extract structured code/test artifacts from prose ACs).
#   - <pass-dir>/calibration.md exists (calibrate-bottom-n.sh ran).
#   - <pass-dir>/polish_log.md exists (Phase 9.5 scaffold ran; will say
#     "nothing to polish" when no false-closed beads are flagged).
#   - convergence.json present (Phase 10 verdict).

# 4. Verify the audit dir.
cat /tmp/audit-smoke/beads_compliance_audit/REPORT.md
ls /tmp/audit-smoke/beads_compliance_audit/passes/*/calibration.md \
   /tmp/audit-smoke/beads_compliance_audit/passes/*/polish_log.md
br list --status open --json | jq '.[] | select(.title | startswith("[completion-debt]"))'
```

Canonical exec-summary line (matched by fixtures and validators — must be
present verbatim in every REPORT.md regardless of mode; the deterministic-
only "Calibration framing" bullet appears as a SEPARATE line below it):
```
- **N** total beads audited; **M** false-closed (status=closed, score<700) — **K%** of all closed beads (of N total closed).
```

## Validation

```bash
THIS_SKILL="$(realpath "$(dirname "${BASH_SOURCE:-$0}")")"

# Validators run against an existing pass — use the smoke-test pass
# generated above.
python3 "$THIS_SKILL/scripts/validate-audit-dir.py" /tmp/audit-smoke/beads_compliance_audit
python3 "$THIS_SKILL/scripts/validate-rubric.py" \
  /tmp/audit-smoke/beads_compliance_audit/rubric.md \
  --manifest /tmp/audit-smoke/beads_compliance_audit/manifest.json
```

Expected: exit 0 from each (well-formed manifest, rubric sums to 1000, score bands cover [0,1000]).

## Known sharp edges (not bugs in this skill — known caveats of the underlying tooling)

- `br doctor` exit-code conventions vary across `br` versions; `bootstrap-audit.sh` checks both `--json` shape and exit code.
- Phase 4 timing budgets are project-dependent; cap individual test commands at ~10× the bead's stated test budget to prevent runaway audits.
- Coverage tools that don't support per-file filtering require the auditor to compute the bead-scoped subset by hand.
