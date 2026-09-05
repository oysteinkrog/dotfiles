# Rituals

The recurring agent behaviors mined from FrankenSQLite session history that became the methodology. Each ritual is a fixed sequence of commands the agent reaches for in a specific situation; the gauntlet codifies them so future agents inherit the precision.

Per `/flywheel` skill's "extract the generative grammar" principle: these are NOT summaries of what the user did; they ARE the methodology, distilled.

---

## Ritual: BEFORE-PERF-WORK

Triggered: agent about to touch a perf-affecting file (per ast-grep patterns + `pattern:160-MT8-ATTRIBUTION` threshold).

```bash
# 1. Health-check cass.
cass health --robot

# 2. Mine the perf ledger for this candidate's name/area.
./scripts/mine-ledger.sh <workspace> --terms "perf,<candidate-slug>"

# 3. Mine 60-day cass across machines for failure terms tied to this candidate.
./scripts/mine-cass-cross-machine.sh <workspace>

# 4. Cross-reference recent commits.
git log --since='60 days ago' --grep -iE 'perf|optimiz|hot.path|bench|<candidate>'

# 5. Run a refresh profile to establish current state.
./scripts/run-narrow-benches.sh <target> --bench <primary>

# Decision point: proceed only if the ledger is silent OR the predicate is satisfied.
```

Cross-link: [`pattern:180-NEGATIVE-LEDGER`](../patterns/180-NEGATIVE-LEDGER.md), [`assets/agents-md-mandate-paragraph.md`](../../assets/agents-md-mandate-paragraph.md).

---

## Ritual: WRITE-THE-KEEP-ENTRY

Triggered: a perf candidate passed all gates and is about to commit.

```bash
# 1. Confirm both gates moved in the same window.
ls -la .bench-history/<primary>.latest.json     # check mtime
git log --oneline -1 .bench-history/<primary>.latest.json
hostname && date -u +%FT%TZ                     # platform + minute

# 2. Build the proof pack.
mkdir -p artifacts/<bead_id>/proof_pack
cp <baseline-profile.{flame.svg,samply.json}> artifacts/<bead_id>/proof_pack/baseline_profile.*
cp <candidate-profile.{flame.svg,samply.json}> artifacts/<bead_id>/proof_pack/candidate_profile.*
./scripts/generate-delta-summary.sh artifacts/<bead_id>/proof_pack/

# 3. Author the 19-field card.md per pattern:150-PROFILE-FIRST-CARD.

# 4. Write the rerun.sh + rollback.md.
cp ../skills/running-the-gauntlet-on-your-rust-port/assets/proof-pack-skeleton/rerun.sh artifacts/<bead_id>/proof_pack/
# edit with this bead's specifics

# 5. Update .bench-history.
./scripts/update-ratchet-state.sh <workspace> <scorecard>

# 6. Add the keep entry to the ledger (yes, even keep wins land in the ledger
#    so the cumulative history of decisions is durable).
# In docs/progress/perf-negative-results.md (paradoxically named — it's the perf
# DECISION log, not just rejections):
#
#   ### 2026-MM-DD — <candidate-name> — KEPT
#   - target_workload: <bench>
#   - measured_result: <numbers + cv_pct>
#   - mt8_attribution: "Closed <X>% MT8 <symbol> residual"
#   - bead_id: <bd-...>
#   - retry_condition_predicate: N/A — kept

# 7. Commit.
git add artifacts/<bead_id>/ .bench-history/<primary>.latest.json docs/progress/perf-negative-results.md
git commit -m "perf: <one-line>; closed <X>% MT8 <symbol>; bd-<id>"
```

Cross-link: [`methodology/PROOF-PACK-RUBRIC.md`](../methodology/PROOF-PACK-RUBRIC.md), [`cookbook/perf-regression-triage.md`](../cookbook/perf-regression-triage.md).

---

## Ritual: WRITE-THE-REJECTION-ENTRY

Triggered: a perf candidate failed a gate; we're abandoning OR keeping in scratch.

```bash
# 1. Capture the scratch worktree (so the rejected code lives somewhere).
SCRATCH="/data/tmp/<project>-<feature>-$(date -u +%Y%m%dT%H%M%SZ)"
git worktree add "$SCRATCH"
# (move the rejected branch / commits into $SCRATCH; don't pollute main)

# 2. Author the rejection in perf-negative-results.md per pattern:185-RETRY-CONDITION-PREDICATE.
cat >> docs/progress/perf-negative-results.md <<EOF
### $(date +%Y-%m-%d) — <candidate-name> — REJECTED (<one-line-why>)
- target_workload: <bench>
- files_touched: reverted-uncommitted-kept-in-scratch  (path: $SCRATCH)
- correctness_proof: "<all oracle E2E pass + selections= byte-identical>"
- evidence_artifact_paths:
  - tests/artifacts/perf/<lane>/baseline-<bench>.json
  - tests/artifacts/perf/<lane>/candidate-<bench>.json
- baseline_configuration: $(jq -r '.environment | {git_sha, platform, mode, rustflags}' .bench-history/<bench>.latest.json)
- candidate_configuration: <same shape>
- measured_result: <numbers + cv_pct per micro>
- retry_condition_predicate: "<ONE of the 8 verbatim forms>"
- bead_id: <bd-...>
EOF

# 3. Run the ledger-lint to confirm the predicate isn't forbidden.
./scripts/mine-ledger.sh --lint docs/progress/perf-negative-results.md

# 4. Commit.
git add docs/progress/perf-negative-results.md
git commit -m "ledger: reject <candidate>; <one-line predicate>"
```

Cross-link: [`pattern:185-RETRY-CONDITION-PREDICATE`](../patterns/185-RETRY-CONDITION-PREDICATE.md), [`assets/negative-ledger-seed.md`](../../assets/negative-ledger-seed.md).

---

## Ritual: PHASE-9-BASELINE

Triggered: starting a baseline run on a workspace that's just completed Phase 0-8 OR re-baselining for an incremental-rebase.

```bash
# 1. Pre-flight.
./scripts/oracle-preflight-doctor.sh <target> --workspace <workspace>      # MUST be green

# 2. Parallel dispatch (one per pillar — use rch for any >5min).
rch exec --worker baseline-perf -- ./scripts/run-bench-matrix.sh <target> <workspace> &
rch exec --worker baseline-conformance -- ./scripts/run-conformance-suite.sh <target> <workspace> &
./scripts/compute-feature-coverage.sh <workspace> &
wait

# 3. Capture profiles under MT8-equivalent load.
./scripts/run-narrow-benches.sh <target> <workspace>

# 4. Compute parity score + apply ratchet.
./scripts/compute-parity-score.sh <workspace>
./scripts/apply-ratchet.sh <workspace>

# 5. Render the baseline summary.
./scripts/render-baseline-summary.sh <workspace>     # → phase9_baseline_summary.md
```

Cross-link: [`PHASES.md § Phase 9`](../PHASES.md).

---

## Ritual: PHASE-11-ROUND-CYCLE

Triggered: end of round N; need to decide whether to start round N+1 or declare convergence.

```bash
# 1. Per-pillar in parallel for round N+1.
ROUND=$((N+1))
for pillar in perf conformance surface; do
  rch exec --worker round-$ROUND-$pillar -- \
    ./scripts/run-round.sh <target> --round $ROUND --pillar $pillar &
done
wait

# 2. Synthesize.
./scripts/synthesize-round.sh <workspace> $ROUND       # → round_$ROUND/synthesis.md

# 3. Idea-wizard if it's been ≥3 rounds since last invocation.
if [ $((ROUND % 3)) -eq 0 ]; then
  # Dispatch idea-wizard-orchestrator subagent
  : # see subagents/idea-wizard-orchestrator.md
fi

# 4. Convergence check.
./scripts/convergence-tracker.sh <workspace>
# Exit 0 = converged → proceed to Phase 12.
# Exit non-zero = another round needed → loop back.
```

Cross-link: [`methodology/CONVERGENCE.md`](../methodology/CONVERGENCE.md).

---

## Ritual: PHASE-14-FRESH-EYES-LOOP

Triggered: after Phase 13 bead-author + bead-polisher; before Phase 15 soak.

```bash
# Loop: 2 consecutive clean rounds required.
ROUND=0
CLEAN=0
while [ $CLEAN -lt 2 ]; do
  ROUND=$((ROUND+1))
  echo "Fresh-eyes round $ROUND"

  # Dispatch the three subagents (verbatim prompts per methodology/FRESH-EYES-PROMPTS.md).
  # See subagents/fresh-eyes-reviewer-{a,b,c}.md

  # Static gates.
  cargo check --all-targets &&
    cargo clippy --all-targets -- -D warnings &&
    cargo fmt --check &&
    cargo test --workspace
  GATES_GREEN=$?

  # Material-change check.
  MATERIAL=$(./scripts/count-material-changes.sh <workspace>/phase14_fresh_eyes_round_$ROUND/)

  if [ $GATES_GREEN -eq 0 ] && [ $MATERIAL -lt 3 ]; then
    CLEAN=$((CLEAN+1))
  else
    CLEAN=0  # streak resets on any dirty round
  fi
done

# If T3+: triangulate.
# Dispatch subagents/triangulator.md and subagents/red-team-attacker.md.
```

Cross-link: [`methodology/FRESH-EYES-PROMPTS.md`](../methodology/FRESH-EYES-PROMPTS.md), [`scripts/run-fresh-eyes-pass.sh`](../../scripts/run-fresh-eyes-pass.sh).

---

## Ritual: COMPACTION-RESUME

Triggered: agent dropped into the workspace mid-flight (cold start, context reset, fresh agent).

```bash
# 1. Restore the skill.
cat ~/.claude/skills/running-the-gauntlet-on-your-rust-port/SKILL.md

# 2. Read MEMORY.md (≤200 lines).
cat <workspace>/MEMORY.md

# 3. Read generated convergence state if Phase 11 has produced it.
test -f <workspace>/reports/convergence_tracker.json && jq . <workspace>/reports/convergence_tracker.json

# 4. Read the most recent session detail.
ls -t <workspace>/sessions/session_*.md | head -1 | xargs cat

# 5. Read the latest phase decision record.
ls -t <workspace>/phase*_*.md 2>/dev/null | head -1 | xargs -r cat

# 6. If Phase 11 has started, read the latest round directory.
ROUND_DIR=$(ls -d <workspace>/round_* 2>/dev/null | sort -V | tail -1)
if [ -n "$ROUND_DIR" ]; then
  ls "$ROUND_DIR"/
  test -f "$ROUND_DIR/synthesis.md" && cat "$ROUND_DIR/synthesis.md"
fi

# 7. Decide next action from MEMORY.md + latest phase/round artifacts; resume.
```

Cross-link: [`methodology/COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md), [`methodology/MEMORY-MD-CONVENTION.md`](../methodology/MEMORY-MD-CONVENTION.md).

---

## Ritual: BEFORE-COMMIT (per AGENTS.md "Landing the Plane")

Triggered: end of session OR before any push.

```bash
git status                  # check what changed
git add <files>             # stage code changes
br sync --flush-only        # export beads to JSONL
git add .beads/             # stage beads changes
git commit -m "..."         # commit code and beads together
git pull --rebase           # in case others pushed
git push                    # MANDATORY
git status                  # MUST show "up to date with origin"
```

Cross-link: AGENTS.md "Landing the Plane" section (target project's AGENTS.md, after `subagents/ledger-seeder.md` installs the mandate paragraph).

---

## Adding new rituals

A new ritual emerges when:
- The same 3+ command sequence keeps getting reached for in a session
- It survives 5+ sessions without modification
- It's not already covered by an existing ritual

Then: add an entry here + cross-link from the relevant cookbook recipe / pattern / methodology file.
