---
name: beads-polish
description: "Review and polish all beads in the current project for correctness, completeness, and quality. Checks every bead carefully, finds issues, and fixes them using br/bv. Triggers on: polish beads, review beads, check beads, beads polish, qa beads."
---

# Beads Polish

Carefully review every bead in the project, find issues, and fix them — before any implementation begins.

**Core principle:** Operate in plan space. Do NOT start implementing. The goal is to make every bead maximally clear, correct, and self-contained so that agents can implement them without surprises.

---

## Step 1: Read All Beads

Collect all bead IDs and read them in full:

```bash
# Get all open bead IDs
br ready --json 2>/dev/null | jq -r '.[].id'
br blocked --json 2>/dev/null | jq -r '.[].id'
```

Then read each bead:

```bash
for id in <bead-ids>; do
  echo "========== $id =========="
  br show "$id"
done
```

Or use `bv` for structural overview:

```bash
bv -robot-triage        # prioritized view
bv -robot-plan          # parallel tracks
bv -robot-insights      # dependency graph, cycle detection
```

---

## Step 2: Review Each Bead

Check every bead super carefully. For each bead, ask:

1. **Does it make sense?** Is the description clear and unambiguous?
2. **Is it optimal?** Could the design or approach be improved for the user?
3. **Is it correctly placed?** Does it belong in the right track/epic?
4. **Are the acceptance criteria machine-verifiable?** "Works correctly" → BAD. Specific, checkable criteria → GOOD.
5. **Is it self-contained?** Can an agent implement it without reading other beads or the full PRD?
6. **Does it include tests?** Must include comprehensive unit tests AND integration/K8s test scripts with detailed logging.
7. **Is it over-specified?** Remove implementation details that constrain the agent unnecessarily.
8. **Are dependencies correct?** No false deps (would serialize work that could parallelize). No missing deps (would cause conflicts).
9. **Are there contradictions?** Comments, descriptions, or acceptance criteria that conflict with each other.
10. **Is anything missing?** Features, edge cases, error handling, observability.

### DO NOT:
- Over-specify implementation details
- Lose any features or functionality
- Start implementing anything
- Merge or split beads unless sizing is clearly wrong

---

## Step 3: Fix Issues

Use **only** `br` CLI for all changes:

```bash
# Fix title
br update <bead-id> --title "New title"

# Fix description (use heredoc for multi-line)
br update <bead-id> --description "$(cat <<'EOF'
Updated description here.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Tests Required
- Unit tests for all public functions
- Integration test with logging
EOF
)"

# Fix dependencies
br dep add <blocked-id> <blocker-id>    # add dep
br dep remove <blocked-id> <blocker-id> # remove false dep

# Fix track/priority
br update <bead-id> --priority 1
```

For each fix, output:

```
BEAD: <id>
ISSUE: <what was wrong>
FIX: <what was changed>
RATIONALE: <why this matters>
```

---

## Step 4: Iterative Review Passes

Run multiple passes until changes flatline:

```
Pass 1 → significant changes (wrong tracks, contradictions, missing features)
Pass 2 → moderate changes (edge cases, missing test criteria, context gaps)
Pass 3 → minor changes (wording, small clarifications)
Pass 4 → no meaningful changes → STOP
```

Never run more than 5 passes.

---

## Step 5: Final Verification

```bash
bv --robot-insights 2>&1 | python3 -c "
import json, sys
j = json.load(sys.stdin)
print('Cycles:', j.get('cycles', 'None'))
for node in j.get('nodes', []):
    print(f\"{node['id']}: direct={node.get('direct',0)}, trans={node.get('trans',0)}\")
"
```

Zero cycles = clean graph. Then sync:

```bash
br sync --flush-only
git add .beads/
git commit -m "chore: polish beads pre-implementation"
```

---

## Checklist

Before finishing:

- [ ] Every bead re-read at least once
- [ ] All contradictions resolved
- [ ] All beads are in the correct track
- [ ] All acceptance criteria are machine-verifiable
- [ ] All beads include test requirements (unit + integration/K8s with logging)
- [ ] No over-specification (no unnecessary implementation constraints)
- [ ] No features or functionality lost
- [ ] Dependency graph is acyclic (`bv --robot-insights` shows zero cycles)
- [ ] Beads are self-contained (implementable without reading other beads)
- [ ] Changes committed to `.beads/`

## Related Skills
- `/swarm-beads-quality` — Multi-agent bead quality pipeline (10-agent review + oracle + hardening). Use for thorough quality assurance on large bead sets.
- `/swarm-beads-rewrite` — Rewrite beads after architecture audit findings
- `/swarm-hardening` — Full hardening loop (review → oracle → fresh-eyes → verify)

