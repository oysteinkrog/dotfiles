---
name: prd-to-beads
model: opus
description: Convert implementation plans into actionable beads with proper structure, acceptance criteria, dependencies, and test requirements. Use after completing an implementation plan and before starting development.
triggers:
  - "create beads from plan"
  - "plan to beads"
  - "convert plan to beads"
  - "make beads"
argument-hint: "<plan-file-or-dir> [--epic-prefix E] [--dry-run]"
---

# Plan-to-Beads Skill

Convert implementation plans into self-contained, implementation-ready beads.

## When to Use

- After completing an implementation plan (feature doc, PDR, design doc)
- When a reviewed plan needs to become actionable work items
- To break a large feature into parallelizable units

## Arguments

- First argument: path to plan file or directory of plan files
- `--epic-prefix E`: override epic label prefix (default: auto from plan)
- `--dry-run`: preview beads without creating them

## Workflow

### Step 1: Read & Analyze Plan

Read the plan file(s) and extract:
1. **Epics/phases** — high-level groupings
2. **Changes per file** — which files are modified, what changes
3. **Cross-cutting concerns** — l10n, a11y, error handling, perf, security
4. **Test requirements** — unit, integration, UI tests
5. **Dependencies** — ordering constraints between changes

```bash
# If plan is a directory, read all docs
fd '\.md$' <plan-dir> --exec cat {}
```

### Step 2: Identify Bead Boundaries

Split work into beads following these sizing rules:

| Rule | Rationale |
|------|-----------|
| 1-3 files per bead | Keeps diffs reviewable, avoids merge conflicts |
| Single responsibility | Each bead does ONE thing completely |
| Test bead per feature bead | Tests are separate beads unless trivial |
| Cross-cutting embedded | Don't make separate "add l10n" beads; embed in each bead |

**Splitting heuristics:**
- VM with >3 new properties → split into core + extended
- New model + VM + view → 3 beads (model first, VM depends on model, view depends on VM)
- Migration/schema change → always its own bead (P0)
- Bug fix discovered during planning → separate P0 bead

### Step 3: Write Bead Descriptions

Each bead description MUST include these sections:

```markdown
## Context
Why this change exists. Link to plan section.

## Acceptance Criteria
Given/When/Then format ONLY. No prose criteria.

- **Given** <precondition>
  **When** <action>
  **Then** <observable outcome>

## Files
- `path/to/File.cs` — what changes and why
- `path/to/Other.cs` — what changes and why

## Cross-Cutting
- [ ] Localization: <specific resx keys needed, or "N/A">
- [ ] Error handling: <specific error states, or "N/A">
- [ ] Accessibility: <specific a11y reqs, or "N/A">
- [ ] Performance: <specific constraints, or "N/A">

## Test Requirements
- Unit: <what to test, expected count>
- Integration: <what to test, or "N/A">
- UI: <what to test, or "N/A">

## Dependencies
- Depends on: <bead IDs or "none">
- Blocks: <bead IDs or "none">

## Notes
Implementation hints, gotchas, links to relevant code.
```

### Step 4: Self-Containment Checklist

Before creating each bead, verify:

- [ ] Can an agent implement this bead reading ONLY its description + source code?
- [ ] Are all file paths absolute from repo root?
- [ ] Are acceptance criteria testable without human judgment?
- [ ] Are cross-cutting requirements embedded (not "see other bead")?
- [ ] Is the bead small enough for a single atomic commit?
- [ ] Does the description specify WHAT changes, not just WHY?
- [ ] Are error/edge cases explicitly listed in ACs?
- [ ] Are resx keys specified if UI text changes?
- [ ] Is the test requirement specific (not "add tests")?
- [ ] Are dependencies explicit and correct (no circular refs)?

### Step 5: Create Beads

Create beads using `br` CLI:

```bash
# Create epic first
br epic create "Epic Name" --prefix E1

# Create beads within epic
br create "Bead title" \
  -t task \
  -p <0-4> \
  -d "$(cat <<'EOF'
<full description from Step 3>
EOF
)" \
  --parent <epic-id> \
  -l "track-a,phase-1"

# Add dependencies after all beads exist
br dep add <child-id> <parent-id>
```

### Step 6: Verify Dependency Graph

```bash
# Check for cycles
br dep cycles

# Verify graph structure
br graph

# List ready beads (should be leaf nodes only)
br ready

# Lint all new beads
br lint
```

### Step 7: Priority Labeling

Apply two-track priority labels:

| Track | Priority | What |
|-------|----------|------|
| A | P0-P1 | Data integrity, safety, correctness — ships first |
| B | P2 | Architecture, UX, features — ships second |
| C | P3-P4 | Polish, terminology, nice-to-have — ships last |

```bash
# Label beads by track
br update <id> -l "track-a" -p 0
br update <id> -l "track-b" -p 2
```

## Given/When/Then Conversion Patterns

Transform prose acceptance criteria into testable GWT:

| Prose AC | GWT AC |
|----------|--------|
| "User can see device status" | Given a station with 2 plates, When settings opens, Then each plate shows status icon matching DeviceStatus enum |
| "Error shown for invalid config" | Given plate count > station.MaxPlates, When user clicks Save, Then validation error "Maximum {max} plates" appears AND save is blocked |
| "Supports composite plates" | Given a CompositeDevice with 4 quadrants, When layout detection runs, Then all 4 quadrants resolve to the same physical position |

**Rules:**
- Given = setup/precondition (specific values, not "some data")
- When = single action (not "user does various things")
- Then = observable assertion (UI text, return value, state change)
- Use AND for multiple assertions in one scenario
- Separate NEGATIVE cases into their own GWT

## Cross-Cutting Embedding Pattern

Do NOT create standalone beads like "Add localization for feature X". Instead, embed cross-cutting requirements into each bead:

```markdown
## Cross-Cutting
- Localization: Add keys `Settings_Plate_Status_Online`, `Settings_Plate_Status_Offline`
  to `Strings.resx`. Use `Loc["Settings_Plate_Status_Online"]` in VM.
- Error handling: Wrap `DetectLayout()` in try/catch; show toast on
  `DeviceException`; log with `Log.Hardware.Error`.
- Performance: Layout detection must complete in <2s for 4 plates.
```

## Output

After creating all beads, report:

```markdown
## Beads Created: <count>

### By Epic
| Epic | Beads | Track |
|------|-------|-------|
| E1: ... | bd-xxx, bd-yyy | A |
| E2: ... | bd-zzz | B |

### Dependency Summary
- Root beads (no deps): <list>
- Leaf beads (nothing depends on them): <list>
- Critical path: <longest chain>
- Parallel tracks: <independent groups>

### Quality Check
- [x] br lint: 0 issues
- [x] br dep cycles: 0 cycles
- [x] All ACs in Given/When/Then
- [x] All cross-cutting embedded
- [x] Self-containment checklist passed for all beads
```
