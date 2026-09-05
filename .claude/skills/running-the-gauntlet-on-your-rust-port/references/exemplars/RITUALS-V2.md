# Rituals — Round 5 Additions

Eight new recurring agent behaviors that emerged after [`RITUALS.md`](RITUALS.md) was authored. Each ritual: trigger condition / verbatim command sequence / rationale / cross-references.

Per `/flywheel`'s "extract the generative grammar" principle: these are the precise sequences that keep getting reached for; codified so future agents inherit the precision.

---

## Ritual: BEFORE-CONFORMANCE-WORK

Triggered: agent about to touch a conformance-affecting file (oracle wiring, normalize_value, metamorphic transforms, mismatch minimizer, fault VFS).

```bash
# 1. Health-check cass for conformance-relevant prior findings.
cass health --robot

# 2. Mine the conformance ledger for prior rejections of this same area.
./scripts/mine-ledger.sh <workspace> --terms "conformance,<candidate-slug>"

# 3. Mine 60-day cass across machines for conformance failure terms.
./scripts/mine-cass-cross-machine.sh <workspace>

# 4. Cross-reference recent commits in the affected area.
git log --since='60 days ago' --grep -iE 'oracle|conformance|metamorphic|<candidate>'

# 5. Run the oracle preflight doctor to confirm green precondition.
./scripts/oracle-preflight-doctor.sh <target> --workspace <workspace>

# 6. Run the existing conformance baseline to confirm what's currently divergent.
./scripts/run-conformance-suite.sh <target> <workspace> --package "<candidate-crate>"

# Decision point: proceed only if the ledger is silent OR the predicate is satisfied.
```

Mirror of `BEFORE-PERF-WORK` from RITUALS.md, but for conformance. The same negative-ledger discipline applies: a CONFORMANCE_NEGATIVE_RESULTS.md entry with a satisfied retry-condition predicate UNBLOCKS new work; an entry without satisfaction BLOCKS it.

**Cross-link:** [`pattern:180-NEGATIVE-LEDGER`](../patterns/180-NEGATIVE-LEDGER.md), [`RITUALS.md § BEFORE-PERF-WORK`](RITUALS.md).

---

## Ritual: BEFORE-SPEC-EDIT (greenfield-specific)

Triggered: user about to edit a spec source (docs/spec/v1/*.md, AGENTS.md Hard Requirements, COMPREHENSIVE_PLAN_*.md).

```bash
# 1. Snapshot the current SPEC-TAGS.md (so post-edit diff is clean).
cp <workspace>/docs/spec/SPEC-TAGS.md /tmp/SPEC-TAGS-pre-edit-$(date -u +%Y%m%dT%H%M%SZ).md

# 2. Identify which [SPEC-NNN] tags currently anchor to the source you're editing.
grep "<source-name>" <workspace>/docs/spec/SPEC-TAGS.md | head

# 3. Note the pre-edit SHA-256 of the source for the spec_version_contract.toml bump.
PRE_EDIT_SHA=$(sha256sum <source-path> | awk '{print $1}')
echo "Pre-edit SHA: $PRE_EDIT_SHA"

# Make the edit (manually).

# 4. After edit, recompute SHA-256.
POST_EDIT_SHA=$(sha256sum <source-path> | awk '{print $1}')

# 5. Re-invoke spec-tag-extractor to detect changes.
./scripts/dispatch-subagent.sh spec-tag-extractor --param workspace=<workspace> --param target=<target>

# 6. Diff the pre/post tag catalogs.
diff /tmp/SPEC-TAGS-pre-edit-*.md <workspace>/docs/spec/SPEC-TAGS.md

# 7. For any new orphan tag (in post, not pre): dispatch the greenfield-oracle-wirer to author the verifier.
# 8. For any retired tag (in pre, not post): apply cookbook/spec-tag-orphan-cleanup.md.

# 9. Update spec_version_contract.toml with the post-edit SHA-256 + bumped revision.
# 10. Commit: "spec: edit <source-name>; revision N → N+1; tags +K -L"
```

Without this ritual: spec edits silently break the harness because tag↔verifier alignment drifts.

**Cross-link:** [`methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md), [`cookbook/spec-tag-orphan-cleanup.md`](../cookbook/spec-tag-orphan-cleanup.md), [`subagents/spec-tag-extractor.md`](../../subagents/spec-tag-extractor.md).

---

## Ritual: AFTER-SOAK-FINDING

Triggered: any Phase 15 soak runner emits a finding (TrueDivergence, UB, data-race, ShiftDetected, CRITICAL adversarial).

```bash
# 1. Read the finding's FailureBundle to identify the affected hypothesis.
SOAK_RUNNER="$1"  # fuzz | miri | loom | crash-boundary | bocpd | adversarial
SIG="$2"          # MismatchSignature or per-runner sig

BUNDLE_PATH="<workspace>/phase15_soak_${SOAK_RUNNER}/findings/${SIG}/bundle.json"
test -f "$BUNDLE_PATH" || { echo "Bundle missing"; exit 1; }

# 2. Classify by pillar (auto-extract from bundle metadata).
PILLAR=$(jq -r '.metadata.pillar' "$BUNDLE_PATH")  # perf | conformance | surface
HYPOTHESIS_ID=$(jq -r '.metadata.affected_hypothesis_id' "$BUNDLE_PATH")

# 3. Write the loop-back marker (signals Phase 12 to reopen the hypothesis).
cat > <workspace>/phase15_loopback_required.md <<EOF
# Phase 15 Loopback Required

**Triggered at:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Soak runner:** ${SOAK_RUNNER}
**Finding sig:** ${SIG}
**Pillar:** ${PILLAR}
**Affected hypothesis ID:** ${HYPOTHESIS_ID}
**FailureBundle:** ${BUNDLE_PATH}

## Next action
Loop back to Phase 12 (REMEDIATION DESIGN) for the affected hypothesis.
EOF

# 4. Reopen the hypothesis in the appropriate ledger.
case "$PILLAR" in
  perf)        LEDGER=<workspace>/PERF_HYPOTHESIS_LEDGER.md ;;
  conformance) LEDGER=<workspace>/CONFORMANCE_HYPOTHESIS_LEDGER.md ;;
  surface)     LEDGER=<workspace>/SURFACE_PARITY_HYPOTHESIS_LEDGER.md ;;
esac

# Append to the ledger:
echo "" >> "$LEDGER"
echo "## REOPENED: ${HYPOTHESIS_ID} — Phase 15 ${SOAK_RUNNER} finding" >> "$LEDGER"
echo "- Soak finding: ${BUNDLE_PATH}" >> "$LEDGER"
echo "- Reason: $(jq -r .metadata.reason "$BUNDLE_PATH")" >> "$LEDGER"
echo "- Reopened at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LEDGER"

# 5. Recompute the generated convergence tracker; do not edit it by hand.
scripts/convergence-tracker.sh <workspace> || true

# 6. Commit + notify.
git add <workspace>/phase15_loopback_required.md "$LEDGER" <workspace>/reports/convergence_tracker.json
git commit -m "phase15: loopback — ${SOAK_RUNNER} finding ${SIG} reopens ${HYPOTHESIS_ID}"
# Notify per HOOKS-INTEGRATION.md
```

**Cross-link:** [`methodology/HOOKS-INTEGRATION.md`](../methodology/HOOKS-INTEGRATION.md), [`pattern:90-FAILURE-BUNDLE`](../patterns/90-FAILURE-BUNDLE.md).

---

## Ritual: AFTER-BOCPD-SHIFT-DETECTED

Triggered: Phase 15 BOCPD runner reports `Regime::ShiftDetected` on the parity-score stream.

```bash
# 1. Inspect the regime change point.
WORKSPACE="$1"
CHANGE_POINT=$(jq -r '.last_change_point_timestamp' <workspace>/phase15_soak_bocpd/regime_changes.jsonl | tail -1)
PRE_MEAN=$(jq -r '.pre_change_mean' <workspace>/phase15_soak_bocpd/regime_changes.jsonl | tail -1)
POST_MEAN=$(jq -r '.post_change_mean' <workspace>/phase15_soak_bocpd/regime_changes.jsonl | tail -1)

echo "Regime shift at: $CHANGE_POINT"
echo "Pre-shift mean: $PRE_MEAN; post-shift mean: $POST_MEAN"

# 2. Identify which commits landed in the change-point window.
git log --since="$CHANGE_POINT - 1 hour" --until="$CHANGE_POINT + 1 hour" --oneline

# 3. If the shift is REGRESSING (post < pre): this is a real regression — Phase 12 loopback.
if [ "$(echo "$POST_MEAN < $PRE_MEAN" | bc)" -eq 1 ]; then
  ./AFTER-SOAK-FINDING.sh bocpd "$(date -u +%Y%m%dT%H%M%SZ)-bocpd-regress"
fi

# 4. If the shift is IMPROVING (post > pre): this might be a legitimate optimization or a bench corruption.
# Verify with a clean-state bench re-run.
if [ "$(echo "$POST_MEAN > $PRE_MEAN" | bc)" -eq 1 ]; then
  echo "Improvement detected; verifying with fresh-state re-run..."
  CARGO_TARGET_DIR=/data/tmp/gauntlet-bocpd-verify-target \
    ./scripts/run-bench-matrix.sh <target> <workspace>
fi

# 5. Either way, document in phase15_bocpd_shifts.md.
```

**Cross-link:** [`pattern:80-BOCPD-REGIME-DETECTION`](../patterns/80-BOCPD-REGIME-DETECTION.md), [`math/bocpd-worked.md`](../math/bocpd-worked.md), [`subagents/soak-runner-bocpd.md`](../../subagents/soak-runner-bocpd.md).

---

## Ritual: BEFORE-DEEP-REVIEW-ESCALATION (THE AUTHORIZATION GATE)

Triggered: orchestrator detects a deep-review escalation trigger per [`pattern:265-DEEP-HYPOTHESIS-ESCALATION-TRIGGER`](../patterns/265-DEEP-HYPOTHESIS-ESCALATION-TRIGGER.md).

```bash
# 0. Bind the concrete workspace path before running the ritual.
WORKSPACE="${WORKSPACE:?set WORKSPACE to the gauntlet workspace path}"
mkdir -p "$WORKSPACE/.gauntlet"

# 1. Stop the routine Phase 11 progression.
touch "$WORKSPACE/.gauntlet/deep_review_escalation_pending.flag"

# 2. Document the escalation request.
TRIGGER_TYPE="$1"     # stall | tie-break | gate-flaw | adversarial-followup
QUESTION="$2"         # one sentence; specific enough to falsify
BUDGET_HOURS="${3:-6}"
PANE_HOURS=$((BUDGET_HOURS * 5))

cat > "$WORKSPACE/phase11_deep_review_authorization_request.md" <<EOF
# Deep Review Escalation — Authorization Request

**Triggered at:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Trigger type:** ${TRIGGER_TYPE}
**Question:** ${QUESTION}
**Estimated budget:** ${BUDGET_HOURS} hours × 5 panes = ~${PANE_HOURS} pane-hours
**Workspace:** ${WORKSPACE}__deep_review/ (sibling)

## Why escalate
$(cat "$WORKSPACE/phase11_deep_review_escalation_rationale.md" 2>/dev/null || echo "<rationale not provided>")

## Pre-flight checks
- NTM ready: $(ntm --robot-capabilities | jq -r '.commands | length') commands available
- The question is falsifiable: <verify before proceeding>

## CONFIRM TO PROCEED (yes/no): _____________
EOF

# 3. STOP. Wait for user signoff. NEVER auto-authorize.

# 4. After signoff:
#    - Leave "$WORKSPACE/.gauntlet/deep_review_escalation_pending.flag" in place for audit.
#    - Append a consumed marker to "$WORKSPACE/.gauntlet/deep_review_escalation_pending.flag.consumed"
#    - Dispatch subagents/deep-hypothesis-reviewer.md
#    - Append signoff message verbatim to phase11_deep_review_authorization_log.md
```

**Cross-link:** [`pattern:265-DEEP-HYPOTHESIS-ESCALATION-TRIGGER`](../patterns/265-DEEP-HYPOTHESIS-ESCALATION-TRIGGER.md), [`subagents/deep-hypothesis-reviewer.md`](../../subagents/deep-hypothesis-reviewer.md), [`methodology/DEEP-HYPOTHESIS-REVIEW.md`](../methodology/DEEP-HYPOTHESIS-REVIEW.md).

---

## Ritual: WRITE-THE-WAIVER-ENTRY

Triggered: `apply-ratchet.sh` returned Block on a pillar; user authorized a waiver (fix-vs-waiver decision per [`methodology/DECISION-TREES.md § DT-8`](../methodology/DECISION-TREES.md)).

```bash
# 1. Mint the waiver slug.
PILLAR="$1"
REASON_SLUG="$2"  # e.g., "feature-flag-rollout"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
WAIVER_PATH="<workspace>/waivers/${TIMESTAMP}-${PILLAR}-${REASON_SLUG}.md"
mkdir -p <workspace>/waivers/

# 2. Author the waiver per the structured-dated convention.
cat > "$WAIVER_PATH" <<EOF
# Waiver: ${PILLAR} ratchet block

**Issued at:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Issued by:** <user-email-or-identifier>
**Pillar:** ${PILLAR}
**Slug:** ${REASON_SLUG}

## Block details
- Ratchet decision: Block
- Conformal lower-bound this round: $(jq -r ".${PILLAR}.lower_bound" <workspace>/reports/scorecards.json)
- Persisted high-water mark: $(jq -r ".${PILLAR}.persisted_high_water_mark" <workspace>/reports/ratchet_state.json)
- Delta: $(python3 -c "print($(jq -r ".${PILLAR}.lower_bound" <workspace>/reports/scorecards.json) - $(jq -r ".${PILLAR}.persisted_high_water_mark" <workspace>/reports/ratchet_state.json))")

## Waiver rationale
<2-3 sentences: why is this regression temporarily acceptable; what is the dependent timeline (feature flag ramp, customer rollout, etc.)>

## Calendar expiration
- Expires at: <ISO 8601; MAX 30 days from now>
- Fix bead: <bd-XXX>
- Cleanup bead: <bd-YYY>

## Sign-off
<verbatim user signoff message>
EOF

# 3. Commit the waiver.
git add "$WAIVER_PATH"
git commit -m "waiver: ${PILLAR} ratchet block — ${REASON_SLUG} (expires <date>)"

# 4. Update apply-ratchet.sh's state to reflect the waiver.
jq --arg w "$WAIVER_PATH" --arg p "$PILLAR" \
  '.[$p].active_waiver = $w' \
  <workspace>/reports/ratchet_state.json > /tmp/rs.json && mv /tmp/rs.json <workspace>/reports/ratchet_state.json

# 5. Schedule expiration check.
# (Cron via NTM ScheduleWakeup or external scheduler)
```

Mirror of `WRITE-THE-KEEP-ENTRY` from RITUALS.md, but for waivers. Waivers are NOT silent — they're structured, dated, and expire.

**Cross-link:** [`methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md), [`subagents/waiver-author.md`](../../subagents/waiver-author.md), [`cookbook/ratchet-block.md`](../cookbook/ratchet-block.md).

---

## Ritual: DAILY-RATCHET-AUDIT

Triggered: cron / nightly schedule during long-running gauntlets (10+ days).

```bash
# Daily run (e.g., 09:00 UTC):
# 1. Snapshot ratchet state.
cp <workspace>/reports/ratchet_state.json <workspace>/reports/ratchet_state_$(date -u +%Y%m%d).json

# 2. Inspect waivers for expirations.
TODAY=$(date -u +%Y-%m-%dT00:00:00Z)
for WAIVER in <workspace>/waivers/*.md; do
  EXPIRES=$(grep "Expires at:" "$WAIVER" | awk '{print $4}')
  if [ "$EXPIRES" \< "$TODAY" ]; then
    echo "EXPIRED: $WAIVER"
    # Trigger ratchet re-evaluation; if still Block, escalate to user.
  fi
done

# 3. Inspect per-pillar lower-bound trends.
./scripts/ratchet-trend-audit.sh <workspace> --window 7d

# 4. If any pillar's lower-bound dropped > 3% in the window, alert user.

# 5. Run subagents/ratchet-curator.md to verify monotonicity.
./scripts/dispatch-subagent.sh ratchet-curator --param workspace=<workspace>

# 6. Commit the daily snapshot.
git add <workspace>/reports/ratchet_state_*.json
git commit -m "ratchet: daily audit snapshot $(date -u +%Y-%m-%d)"
```

**Cross-link:** [`subagents/ratchet-curator.md`](../../subagents/ratchet-curator.md), [`methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md).

---

## Ritual: PRE-COMMIT-SAFETY-NET

Triggered: about to `git commit` in any gauntlet-aware project.

```bash
# 1. dcg first (destructive-command guard from AGENTS.md).
echo "$INTENDED_COMMAND" | dcg-check || { echo "BLOCKED by dcg"; exit 1; }

# 2. UBS scan on changed Rust files (warning-only per AGENTS.md but still useful).
ubs --warn-only $(git diff --cached --name-only --diff-filter=AM | grep '\.rs$')

# 3. cargo fmt --check (mandatory).
cargo fmt --check || { echo "fmt issues; run cargo fmt first"; exit 1; }

# 4. cargo clippy --all-targets -- -D warnings (mandatory).
cargo clippy --all-targets -- -D warnings || { echo "clippy issues; fix before commit"; exit 1; }

# 5. cargo check --all-targets (mandatory).
cargo check --all-targets || { echo "build broken; fix before commit"; exit 1; }

# 6. cargo test --workspace (only on touched test files).
TOUCHED_TESTS=$(git diff --cached --name-only --diff-filter=AM | grep -E 'tests/.*\.rs$')
if [ -n "$TOUCHED_TESTS" ]; then
  cargo test --workspace -- --test-threads=1
fi

# 7. ledger-lint on any touched negative-results file.
LEDGER_FILES=$(git diff --cached --name-only --diff-filter=AM | grep '_NEGATIVE_RESULTS.md\|_HYPOTHESIS_LEDGER.md')
for f in $LEDGER_FILES; do
  ./scripts/mine-ledger.sh --lint "$f" || { echo "ledger lint failed on $f"; exit 1; }
done

# 8. Cross-link integrity (no broken markdown links in changed docs).
TOUCHED_MD=$(git diff --cached --name-only --diff-filter=AM | grep '\.md$')
if [ -n "$TOUCHED_MD" ]; then
  python3 ./scripts/check-cross-links.py $TOUCHED_MD
fi

# 9. Phase-complete-flag synchronization (per-phase exit criteria per DEFINITION-OF-DONE.md).
# (Skip if not in a gauntlet workspace.)

# 10. Now safe to commit.
echo "Pre-commit safety net green. Proceed."
```

The bundle of `dcg + UBS + fmt + clippy + check + test + ledger-lint + cross-link + phase-sync` catches ~90% of pre-commit bugs. Without it, every other commit ships a regression.

**Cross-link:** AGENTS.md "Compiler Checks (CRITICAL)", [`assets/hooks/`](../../assets/hooks/), [`methodology/DEFINITION-OF-DONE.md`](../methodology/DEFINITION-OF-DONE.md).

---

## Adding new rituals

A ritual emerges when:
- The same 3+ command sequence keeps getting reached for in a session.
- It survives 5+ sessions without modification.
- It's not already covered by an existing ritual (in RITUALS.md or RITUALS-V2.md).

Then: add an entry to RITUALS-V2.md (or a future RITUALS-V3.md) + cross-link from the relevant cookbook recipe / pattern / methodology file.
