# Beads Integration — The Implementation Backbone

Per AGENTS.md § Beads Workflow Integration (and skills `br` + `bv`), the project's bead store is the source-of-truth for "what's pending, what's blocked, what's done." This skill uses beads for Phase 4 implementer task assignment, Phase 5 safety-harness failure tracking, and Phase 10 handoff queue.

---

## Bead lifecycle in a doctor pass

```
Phase 1 — archaeologist creates beads for FM coverage gaps:
  br create --type=task --priority=1 \
            --title="doctor: archaeology: <subsystem> needs deeper FM mining" \
            --body="..."

Phase 2 — repair-spec-author files beads for unanswered questions:
  br create --type=question --priority=2 \
            --title="doctor: spec: <fm-id>: open question on <topic>"

Phase 4 — one bead per spec; the implementer claims, works, closes:
  br create --type=task --priority=<P0..P3 mapped to 0..3> \
            --title="doctor(<subsystem>): <fm-id>: implement detect+fix+fixture"

  br update <bead-id> --status=in_progress  (claim)
  ... work ...
  br close <bead-id> --reason="implemented; commit <sha>"

Phase 5 — failures auto-file beads:
  br create --type=bug --priority=0 \
            --title="doctor: phase5: <test>:<fm-id>:fail"
            --body="<exit_code, stderr_excerpt, sandbox_path>"

Phase 7 — fresh-eyes findings file beads:
  br create --type=bug --priority=<derived from severity> \
            --title="doctor: fresh-eyes round <N>: <terse>"

Phase 10 — open beads at pass-end become the next-pass queue:
  HANDOFF.md links to `br list --status=open --json | jq '.issues[]? | select(.title | startswith("doctor:"))'`
```

---

## The pre-pass cleanup

At Phase 0 of pass N+1, the cass-miner / archaeologist subagents run:

```bash
br ready --json | jq '.[] | select(.title | startswith("doctor:") and (.priority | tonumber <= 1))'
```

This is the priority-0/-1 backlog from prior passes. The archaeologist treats each as a candidate FM to re-mine. Closed beads from prior passes are reference (via `br closed --since`) — they tell you what was done, what worked.

---

## Priority mapping

| Doctor severity | Bead priority | When |
|-----------------|---------------|------|
| P0 (corrupts state, loses data) | 0 (critical) | New blocking finding; Phase 5 hard-stop |
| P1 (degrades correctness) | 1 (high) | Phase 4 implementer should pick before P2 |
| P2 (nuisance) | 2 (medium) | Phase 4 default; address in current pass |
| P3 (cosmetic) | 3 (low) | Backlog; address in future pass |
| Phase-10 idea-wizard suggestions | 3 (backlog) | Always backlog; never block current pass |

---

## Bead bodies (the standard template)

Each Phase 4 bead body:

```markdown
**Failure mode:** fm-<id>
**Subsystem:** <subsystem>
**Severity:** P<N>
**Spec:** [<workspace>/analysis/repair_specs/<id>.md](workspace://...)
**Estimated effort:** S | M | L

## Detector pseudocode
<copy from spec>

## Fixer pseudocode
<copy from spec>

## Fixture spec
<copy from spec>

## Acceptance criteria
- [ ] cargo build green
- [ ] verify-undo.sh fm-<id> exits 0
- [ ] verify-idempotence.sh fm-<id> exits 0
- [ ] verify-crash-recovery.sh fm-<id> exits 0
- [ ] verify-concurrency.sh fm-<id> exits 0
- [ ] verify-metamorphic.sh fm-<id> exits 0
- [ ] capabilities --json::detectors[].id contains fm-<id>
- [ ] capabilities --json::fixers[].id contains fm-<id>
- [ ] tests/doctor_fixtures/fm-<id>/{corrupt.sh, assert.sh, README.md} present

## Dependencies
- Blocked by: <bead-ids if any from dependency_graph.json>
```

The archaeologist or implementer fills in the dependencies from `<workspace>/analysis/dependency_graph.json` so `br ready` correctly sequences the work.

---

## bv triage at Phase 4 dispatch

Before Phase 4 dispatches implementers, the lead agent runs:

```bash
bv --robot-triage --label=doctor-pass-<N>
```

This returns:
- `quick_ref` — count of ready beads, blocked beads, top-3 picks.
- `recommendations[]` — ranked actionable items with reasons.
- `quick_wins[]` — low-effort high-impact items.
- `blockers_to_clear[]` — items that unblock the most downstream work.

The lead dispatches in the order bv recommends. If bv reports cycles, that's a Phase 3 dependency_graph.json error; re-enter Phase 3 to fix.

---

## Closing beads with traceability

Per AGENTS.md, commits that close beads include the bead ID:

```
git commit -m "doctor(state_files): fm-jsonl-tombstone-drift: detect + fix + fixture (br-1234)"
```

`br close 1234 --reason="implemented; commit <sha>"` then crosses the work off. The mapping:

| Mail thread | Bead | Commit |
|-------------|------|--------|
| `doctor-<pass>-impl-state_files` | `br-1234` | `<sha>` with `br-1234` in message |

Phase 8's CI workflow includes a check that every doctor-prefixed commit references at least one bead ID; a fresh-eyes round caught a missing reference can refile the bead retroactively (`br create` with `--existing-commit=<sha>`).

---

## Beads as the handoff currency

`HANDOFF.md`'s "Open issues" section is generated from:

```bash
br list --status=open --json \
  | jq '.[] | select(.title | startswith("doctor:")) | {id, priority, title, type}' \
  | jq -s .
```

The next pass's archaeologist starts from this list. No work is "stranded in a transcript"; everything is in beads.

Per AGENTS.md § Landing the Plane, the pass isn't done until:

```bash
br sync --flush-only
git add .beads/
git commit -m "doctor pass-<N>: sync beads"
git push
```

These are user actions per AGENTS.md (the skill never pushes); the handoff-writer's HANDOFF.md includes a reminder.

---

## When br/bv aren't available

Fallback (per [SKILL-FALLBACKS.md](SKILL-FALLBACKS.md)): a Markdown checklist at `<workspace>/beads_pending.md`. Less ergonomic but preserves the contract: "every gap has a row, every row gets owned, every owned row gets closed."

---

## Beads compliance and completion verification

The user's repo includes a `beads-compliance-and-completion-verification` skill that audits doctor-related beads at pass end. Run it in Phase 10:

```
The pass is "complete" only when:
- Every Phase-4 bead is closed OR explicitly deferred to next pass.
- Every Phase-5 hard-stop bead is closed.
- No bead has been "in_progress" longer than 2× its estimated duration without a comment.
- The top-3 ready beads at pass start are all closed (or explicitly deferred).
```

Failure to clear this audit means the pass remains "in flight" — the next pass continues from where this one left off, not starts fresh.
