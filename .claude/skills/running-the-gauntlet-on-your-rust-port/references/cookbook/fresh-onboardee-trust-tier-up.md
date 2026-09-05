# fresh-onboardee-trust-tier-up

> A new contributor (human or agent) completed their week-4 onboarding milestone. Advance their trust tier; reassign their workload; close the onboarding bead.

## Trigger

Any of:

- The `knowledge-transfer.md` subagent emits `<workspace>/onboardees/<name>/week_4_milestone.json` with `status: complete`.
- A maintainer manually flags an onboardee for review.
- The 4-week trust ladder timer expires (set at onboardee creation).
- The onboardee has closed N beads matching the trust-ladder criteria (typically: 2 perf-regression-triage beads, 1 oracle-divergence-triage bead, 1 surface-gap-found bead, all with fresh-eyes-clean closures).

Unlike the other 11 motions, this recipe is workflow-administrative, not gauntlet-discipline-enforcement. It uses no operator glyphs because the trust ladder is a social contract, not a measurement.

## Trust ladder

The gauntlet's trust ladder has four tiers; this recipe handles `T0 → T1 → T2` advancement. `T2 → T3` is a manual call by the project maintainer (typically after 6+ months and 50+ closed beads).

| Tier | Permissions | Onboarding milestone |
|---|---|---|
| **T0 — Observer** | Read-only; can comment on beads. | First week. |
| **T1 — Contributor** | Can claim non-priority-0 beads; cannot close own work. | Weeks 2-3. |
| **T2 — Trusted Contributor** | Can claim and close beads; can be a fresh-eyes reviewer on others' work. | Week 4. |
| **T3 — Maintainer** | Can author waivers; can update ratchet floors; can advance other contributors. | 6+ months, by manual review. |

## Workflow (no operator glyphs)

```
1. Verify the milestone evidence is present and complete.
2. Inspect the closed-bead trail: each must have test/bench/doc deps; each must have fresh-eyes-clean.
3. Run the trust-tier-up smoke (small, scripted; not a real review).
4. Author the advancement note in <workspace>/onboardees/<name>/advancement.md.
5. Update the trust-ladder index in <workspace>/onboardees/INDEX.md.
6. Reassign the onboardee's bead workload to T<new>-eligible beads.
7. Pair the onboardee with a buddy (a T2 contributor or T3 maintainer) for the next 4 weeks.
8. Close the onboardee-<name>-week<N> bead.
```

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
ONBOARDEE_NAME=<contributor name, e.g., new-hire-q2>
NEW_TIER=<T1 | T2>

# 1. Verify milestone evidence
test -f "$WORKSPACE/onboardees/$ONBOARDEE_NAME/week_4_milestone.json"
jq -r '.status' "$WORKSPACE/onboardees/$ONBOARDEE_NAME/week_4_milestone.json"  # expect "complete"

# 2. Inspect closed-bead trail
br list --label "claimed-by:$ONBOARDEE_NAME" --status closed --json --limit 0 | jq -r '(.issues // .)[] | {
  id, title, has_test_dep: ((.dependencies // .deps // []) | any((.id // .) | contains("test"))),
  has_bench_dep: ((.dependencies // .deps // []) | any((.id // .) | contains("bench"))),
  has_doc_dep:   ((.dependencies // .deps // []) | any((.id // .) | contains("doc"))),
  fresh_eyes_clean: (.events | any(.kind == "fresh-eyes-clean"))
}'
# Expect: every closed bead has all four columns true.

# 3. Run the trust-tier-up smoke (sanity check; not a review)
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --onboardee "$ONBOARDEE_NAME" --tier-up-smoke

# 4. Author the advancement note
cat > "$WORKSPACE/onboardees/$ONBOARDEE_NAME/advancement.md" <<EOF
# Trust-tier advancement: $ONBOARDEE_NAME → $NEW_TIER

## Effective date
$(date -u +%Y-%m-%d)

## Closed-bead trail (week 1 - 4)
$(br list --label "claimed-by:$ONBOARDEE_NAME" --status closed --json --limit 0 | jq -r '(.issues // .)[] | "- \(.id) \(.title)"')

## Buddy assignment
- Buddy: <T2/T3 contributor name>
- Pairing window: 4 weeks from advancement date

## New permissions
- $(case $NEW_TIER in
    T1) echo "Can claim non-priority-0 beads; cannot close own work; cannot author waivers." ;;
    T2) echo "Can claim and close beads (with the fresh-eyes-clean dep enforced by the bead-graph-validator); can be a fresh-eyes reviewer on others' work; cannot author waivers." ;;
  esac)

## Pending review
- None.
EOF

# 5. Update the trust-ladder index
$EDITOR "$WORKSPACE/onboardees/INDEX.md"
# Add a row: | name | T<old> | T<new> | YYYY-MM-DD | buddy |

# 6. Reassign workload to T<new>-eligible beads
br ready --label "tier:$NEW_TIER" --json --limit 0 | jq -r '(.issues // .)[]?.id' \
  | head -3 \
  | xargs -I {} br update {} --assignee "$ONBOARDEE_NAME"

# 7. Pair with buddy
BUDDY=<chosen buddy>
br create \
  --title "buddy-pair-$ONBOARDEE_NAME-$BUDDY" \
  --priority 3 \
  --type meta \
  --labels "onboarding,buddy,tier:$NEW_TIER" \
  --due "$(date -d '4 weeks' +%Y-%m-%d)"

# 8. Close the onboarding bead
br update "onboardee-$ONBOARDEE_NAME-week4" --status closed \
  --close-note "Advanced to $NEW_TIER on $(date -u +%Y-%m-%d). Buddy: $BUDDY."
```

## Beads to claim (or create)

- `onboardee-<name>-week<N>` (closed by this recipe).
- New bead: `buddy-pair-<onboardee>-<buddy>` — 4-week pairing window.
- No pattern dependencies (administrative motion).
- Dependency (doc): the advancement note IS the documentation; no separate doc bead.

## Exit Criteria

- [ ] Week-4 milestone evidence present.
- [ ] All closed beads by the onboardee have test+bench+doc deps and fresh-eyes-clean closure events.
- [ ] Tier-up smoke ran without surfacing concerns.
- [ ] Advancement note authored.
- [ ] Trust-ladder index updated.
- [ ] Workload reassigned to new-tier-eligible beads.
- [ ] Buddy pairing created with a 4-week window.
- [ ] Onboarding bead closed with close-note referencing the advancement.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Advancing without the closed-bead trail audit. | Tenure ≠ trust. The trail is the evidence. |
| Advancing across two tiers (T0 → T2) at once. | The trust ladder is per-tier; skipping levels skips the fresh-eyes-reviewer practice that T1 builds. |
| Skipping the buddy assignment. | The buddy is the safety net for the new tier's expanded permissions. |
| Self-advancing. | A contributor cannot advance their own tier; a T2 or T3 maintainer authors the note. |
| Auto-advancement based purely on bead count. | The trail must include diverse bead types (≥1 perf, ≥1 conformance, ≥1 surface) per the trust-ladder criteria. |
| Closing the onboarding bead without the close-note. | The close-note is the durable record; chat scrollback isn't searchable in 6 months. |
| Re-assigning P0 beads to a fresh T1. | T1 cannot close own work; assigning a P0 to a T1 creates a coordination headache. P0s go to T2+ only. |
| Naming a T0 as a buddy. | The buddy is teaching the new tier's practices; can't teach what you haven't done. T2 minimum. |

## Cross-references

- [../../subagents/knowledge-transfer.md](../../subagents/knowledge-transfer.md) — the onboarding curriculum generator.
- [../../SKILL.md § Subagents § knowledge-transfer](../../SKILL.md) — subagent listing.
- [../methodology/CASE-STUDIES.md](../methodology/CASE-STUDIES.md) — per-sibling case studies often describe onboardee experiences.
- [../orchestration/ORCHESTRATION.md](../orchestration/ORCHESTRATION.md) — lane assignments; new onboardees stay in their assigned lane initially.
- The trust ladder is project-local; the SKILL doesn't ship a global ladder definition. Adapt to your project's contributor norms.
- Related motions: none (this recipe is administrative, not gauntlet-discipline-enforcement).
