# REMEDIATION-PATTERNS.md — How To Make The Bead Graph Truthful Again

Phase 9 turns the audit findings into bead-graph changes. The goal: after remediation, **every gap is represented by an open bead** so downstream agents pick up the correct work.

---

## The three policies

### Policy A — Reopen the original bead

Use when:
- The original bead's spec is still accurate (you don't need a new spec).
- The original closer is likely the agent who would resume the work.
- Status hygiene matters more than dependency hygiene.

```bash
br reopen <bead-id>
br update <bead-id> --status open
# Add a comment with the audit context (if br supports comments):
br comments add <bead-id> --body "Reopened by audit pass <UTC>; score <X>/1000. Missing items:\n<verbatim list from scorecard.md>"
```

**Pros:** Minimal change to bead graph. Original ID remains the source of truth.

**Cons:** Loses the audit-trail signal that the bead was *previously* closed in error. Downstream beads that depended on this one may have already been closed assuming this was done.

---

### Policy B — Completion-debt bead (default)

Create a new bead that **inherits the gap**, links to the original, and re-models any dependencies that were assuming the original was complete.

```bash
# 1. Read the missing-items list verbatim from scorecard.md.
MISSING=$(awk '/^## Missing items/,/^## /' scorecard.md | tail -n +2)

# 2. Create the completion-debt bead.
NEW_ID=$(br create \
  --title "[completion-debt] $(jq -r .title show.json)" \
  --type task \
  --priority $(jq -r .priority show.json) \
  --parent <original-bead-id> \
  --description "$(printf 'Completion-debt for bead %s, identified in audit pass %s.\n\nOriginal close reason: %s\nAudit score: %d/1000\nScorecard: %s\n\n## Missing items (verbatim)\n\n%s' \
    "<original-bead-id>" "<UTC>" \
    "$(jq -r .close_reason show.json)" \
    "$SCORE" \
    "passes/<UTC>/beads/<original-bead-id>/scorecard.md" \
    "$MISSING")" \
  --json | jq -r .id)

# 3. Re-link downstream dependencies.
# Any bead that depended on <original-bead-id> should now also depend on <NEW_ID>
# (in case the missing items were what the downstream needed).
for downstream in $(jq -r ".dependencies | .[] | select(.depends_on == \"<original-bead-id>\") | .id" dag.json); do
  br dep add "$downstream" "$NEW_ID"
done
```

**Pros:** Preserves the audit signal. Downstream is correctly modeled. The original bead remains closed, so historical metrics aren't disrupted.

**Cons:** Adds beads to the graph. A perfectly remediated completion-debt bead's parent is still in `closed` status (that's correct — the original closed claim was always going to be partially fictional; the new bead carries the unfinished part).

**This is the default** because it's additive (no destructive operations) and most informative.

---

### Policy C — Report only

Don't touch the bead graph at all. Just produce `remediation.md` listing what *would* have been done. The user can apply it manually later.

Use when:
- The user wants to review the audit before any bead writes.
- The bead store is read-only for some reason (e.g., audit-only role).
- You're auditing someone else's project and don't have write authority.

---

## Picking the policy

The user picks once during up-front confirmations. They can re-run with a different policy on a later pass.

| Project state | Suggested policy |
|---------------|------------------|
| Active project, agents are working | **Completion-debt** (default) |
| Project is paused; review-only mode | **Report only** |
| Many false-closed P0/P1 beads (5+) | **Completion-debt** (parent bead structure helps triage) |
| Single false-closed bead, recent | **Reopen** (the closer can finish what they started) |
| Audit of an external repo you don't own | **Report only** |

---

## Title and metadata conventions

Completion-debt beads use these conventions so they're searchable and visually distinguishable:

- **Title prefix:** `[completion-debt]` (preserves searchability via `br list --title-contains "[completion-debt]"`).
- **Type:** match the original (feature → feature; bug → bug). Don't downgrade to `chore` — the work is still substantive.
- **Priority:** match the original, **bumped one level higher** if the audit score was below 500 (severe theater = urgent fix).
- **Labels:** add `audit-debt` and `audit-pass-<YYYY-MM-DD>` so all of one pass's debts can be queried together.
- **Parent:** the original bead ID (so `br dep tree <original>` shows the debt as a child).
- **External ref:** `audit-scorecard:passes/<UTC>/beads/<original-id>/scorecard.md` (a stable anchor for the rubric-derived gap list).

```bash
br create \
  --title "[completion-debt] <original title>" \
  --type "$(jq -r .issue_type show.json)" \
  --priority "$(if [ "$SCORE" -lt 500 ]; then jq -r '.priority - 1 | if . < 0 then 0 else . end' show.json; else jq -r .priority show.json; fi)" \
  --parent "<original-bead-id>" \
  --labels "audit-debt,audit-pass-$(date -u +%Y-%m-%d)" \
  --external-ref "audit-scorecard:passes/<UTC>/beads/<original-id>/scorecard.md" \
  --description "..."
```

---

## Description template (verbatim)

The completion-debt bead's description must be **self-contained** — a future implementer should be able to act on it without consulting the audit dir. Use this template:

```markdown
Completion-debt for bead <ORIGINAL_ID>, identified in audit pass <UTC>.

## Original bead context
- Title: <original title>
- Type: <type>  Priority: P<n>
- Closed at: <closed_at>
- Close reason (verbatim): "<close_reason>"
- Closed by session: <closed_by_session or "unknown">

## Audit verdict
- Score: <X> / 1000
- Verdict band: <🟠 False-closed (mild) | 🔴 False-closed (severe) | 🚨 Theater>
- Scorecard: passes/<UTC>/beads/<ORIGINAL_ID>/scorecard.md (in the audit dir)

## Missing items (verbatim from scorecard)

<copy the exact "Missing items" section from scorecard.md>

## Acceptance criteria for THIS completion-debt bead

This bead is closed when EVERY missing item above has:
- A corresponding implementation cited at file:line in the close-reason
- A corresponding test cited (passing) in the close-reason
- The next audit pass scores the original bead ≥ <threshold>/1000

## How to verify this bead is actually done

When closing, the closer must:
1. Run the verification subset for this bead's spec items:
   `<commands extracted from spec.json>`
2. Check that scorecard would now produce ≥ <threshold>:
   `cd <audit-dir> && ./scripts/score-bead.py --bead <ORIGINAL_ID> --pass-dir passes/<latest>/`
3. Reference both this bead AND the original in the closing commit message.
```

---

## Acceptance criteria field

Beads in beads_rust have an explicit `acceptance_criteria` field. The Phase 9 remediator MUST populate it (not just the description) so future spec extractors find the criteria in the canonical place:

```bash
br update <NEW_ID> --acceptance-criteria "<verbatim missing items>"
```

If the version of `br` doesn't support `--acceptance-criteria` on update, fall back to including the AC bullets in the description under a clearly marked `## Acceptance criteria` section.

---

## After all remediations

Sync and commit:

```bash
br sync --flush-only
git -C <PROJECT> add .beads/
git -C <PROJECT> commit -m "audit: remediation for pass <UTC> — created N completion-debt beads, reopened M"
# Do NOT git push unless the user explicitly authorized it.
```

Update `remediation.md` in the audit dir with the action table per `EVIDENCE-SCHEMAS.md`.

---

## What NOT to do during remediation

| Don't | Why |
|-------|-----|
| Silently fix code while remediating | Remediation is graph maintenance, not implementation. Implementation happens in a *separate* session by the agent that picks up the new bead. |
| `br close <id> --reason "duplicate"` to dismiss the gap | Hiding the gap doesn't make it go away. The audit will rediscover it next pass and the score will be even worse. |
| Bulk-rewrite scorecards to inflate scores | The rubric is the rubric. If you disagree, change the rubric (in the next pass) and document the change. |
| Delete the original bead | Tombstoning loses the history. The original `closed` status is part of the audit story. |
| Force-push the project's main branch | Even after pre-commit hooks fail, never `--no-verify`. Investigate. |

---

## Re-verification after remediation

After remediation work is done (likely by *other* agents in subsequent sessions), the user invokes this skill again. The next pass:

1. Re-runs Phase 1–8 over the now-updated bead graph.
2. The original false-closed beads should now have either: (a) been reopened and re-closed with proper evidence, or (b) have a satisfied completion-debt bead pointing back at them.
3. Phase 8's score for the original bead should now be ≥ threshold (because the completion-debt bead's fix landed and is cited in evidence).
4. Phase 10 detects convergence by comparing pass-over-pass.

The skill is **converged** when two consecutive passes produce no score changes greater than ±10 and zero new false-closed findings.
