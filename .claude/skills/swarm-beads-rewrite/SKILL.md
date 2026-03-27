---
name: bead-rewrite
model: opus
description: Apply architecture audit findings to rewrite, augment, or restructure existing beads. Use after a code audit reveals gaps, when VM/model splits are needed, or when beads need restructuring based on new understanding of the codebase.
triggers:
  - "rewrite beads"
  - "apply audit to beads"
  - "restructure beads"
  - "update beads from findings"
argument-hint: "<findings-file-or-summary> [--beads <ids>] [--epic <id>] [--dry-run]"
---

# Bead Rewrite Skill

Apply architecture audit findings, code review discoveries, and oracle recommendations to rewrite existing beads.

## When to Use

- After an architecture audit reveals quality issues or missing concerns
- When a VM/model needs splitting beyond what beads originally planned
- When oracle validation recommends structural changes
- When new bugs or gaps are discovered that affect existing beads
- When priority re-labeling is needed (two-track execution)

## Arguments

- First argument: path to findings file, or inline summary
- `--beads <ids>`: specific beads to rewrite
- `--epic <id>`: rewrite all beads in an epic
- `--dry-run`: preview changes without applying

## Workflow

### Step 1: Load Findings & Current Beads

```bash
# Read findings
cat <findings-file>

# List all open beads
br list --status open --json | jq '.[] | {id, title, priority, labels}'

# For each affected epic, get bead details
br show <bead-id>
```

Classify each finding into one of these action types:

| Action | When | Example |
|--------|------|---------|
| **New bead** | Gap not covered by any existing bead | Missing error state, undiscovered bug |
| **Split bead** | Existing bead tries to do too much | 4-way VM split should be 5-way |
| **Merge beads** | Two beads are too granular | Separate "add property" + "bind property" beads |
| **Augment bead** | Bead exists but missing details | Add error handling AC, add edge case |
| **Re-prioritize** | Priority wrong based on new understanding | Architecture bead blocks safety bead |
| **Re-dependency** | Dependency chain incorrect | New bead must come before existing one |
| **Delete bead** | Bead is superseded or invalid | Plan changed, bead no longer needed |

### Step 2: Plan Rewrites

Before modifying any beads, create a change plan:

```markdown
## Rewrite Plan

### New Beads
1. bd-NEW-1: "<title>" — <why needed, what finding drives it>
   - Priority: P<N>, Track: <A/B/C>
   - Blocks: <existing bead IDs>
   - Epic: <epic ID>

### Splits
1. bd-xxx → split into:
   - bd-NEW-2: "<narrowed scope 1>"
   - bd-NEW-3: "<narrowed scope 2>"
   - Original bd-xxx: close with reason "Split into bd-NEW-2, bd-NEW-3"

### Augmentations
1. bd-yyy: Add ACs for <finding>. Add cross-cutting <requirement>.

### Priority Changes
1. bd-zzz: P2→P0 (blocks data integrity, per audit finding)

### Dependency Changes
1. bd-aaa now depends on bd-NEW-1 (audit found prerequisite)

### Deletions
1. bd-bbb: superseded by bd-NEW-2 (audit found better approach)
```

### Step 3: Execute — New Beads

For gaps and bugs discovered during audit:

```bash
br create "<title>" \
  -t <task|bug> \
  -p <0-4> \
  -d "$(cat <<'EOF'
## Context
Discovered during architecture audit of <area>.
Finding: <specific finding from audit>.

## Acceptance Criteria
- **Given** <precondition>
  **When** <action>
  **Then** <outcome>

## Files
- `path/to/File.cs` — <what changes>

## Cross-Cutting
- Localization: <specific or N/A>
- Error handling: <specific or N/A>

## Test Requirements
- Unit: <specific tests>

## Dependencies
- Blocks: <bead IDs that can't start until this is done>
EOF
)" \
  --parent <epic-id> \
  -l "track-a,audit-fix"

# Wire dependencies
br dep add <blocked-bead> <new-bead>
```

### Step 4: Execute — Splits

When a bead needs decomposition (e.g., 4-way VM split should be 5-way):

```bash
# Read original bead fully
br show <original-id>

# Create each split part
br create "Part 1: <specific scope>" \
  -t task -p <priority> \
  --parent <epic-id> \
  -d "$(cat <<'EOF'
## Context
Split from bd-<original>. Original was too broad — audit found <reason>.

## Acceptance Criteria
<subset of original ACs relevant to this part>

## Files
<subset of original files>

## Cross-Cutting
<relevant subset>

## Dependencies
- Depends on: <other split parts if ordered>
EOF
)"

# Repeat for each split part...

# Transfer dependencies from original to appropriate split parts
br dep list <original-id> --json
# For each dep: br dep add <split-part> <original-dep>

# Close original
br close <original-id> --reason "Split into bd-xxx, bd-yyy, bd-zzz per audit finding"
```

**Split patterns from session:**

| Original Shape | Split Pattern |
|---------------|---------------|
| VM with N responsibilities | One bead per responsibility (core, extended, validation, etc.) |
| Model + VM + View | 3 beads: model -> VM -> view (dependency chain) |
| Phased rewrite | Phase 1: extract interface, Phase 2: new impl, Phase 3: swap |
| Cross-cutting concern | Embed in each affected bead, don't split into separate concern bead |

### Step 5: Execute — Augmentations

When beads exist but need strengthening:

```bash
# Read current description
CURRENT=$(br show <id> --json | jq -r '.description')

# Append or replace sections
br update <id> -d "$(cat <<'EOF'
<original description with additions marked>

## Additional ACs (from audit)
- **Given** <new precondition from finding>
  **When** <trigger>
  **Then** <expected behavior>

## Updated Cross-Cutting
- Error handling: <added from audit finding>
EOF
)"
```

Common augmentations:
- Add missing error/edge case ACs
- Add missing Failed/Error state handling
- Add missing enum values to AC assertions
- Embed cross-cutting that was deferred
- Add specific resx keys for new text
- Strengthen "supports X" into testable GWT

### Step 6: Execute — Priority & Track Re-labeling

Apply two-track execution model:

```bash
# Track A (P0-P1): Data integrity, safety, correctness
br update <id> -p 0 -l "track-a"

# Track B (P2): Architecture, UX, features
br update <id> -p 2 -l "track-b"

# Track C (P3-P4): Polish, terminology
br update <id> -p 3 -l "track-c"
```

**Re-prioritization triggers:**
- Audit finds data corruption risk → P0 track-a
- Audit finds missing validation → P1 track-a
- Audit recommends VM split → P2 track-b (unless blocking P0)
- Audit suggests terminology fix → P3 track-c

### Step 7: Execute — Dependency Rewiring

```bash
# Add new deps
br dep add <child> <parent>

# Remove incorrect deps
br dep remove <child> <parent>

# Verify no cycles introduced
br dep cycles

# Verify graph makes sense
br graph
```

### Step 8: Validate Rewrites

After all changes:

```bash
# Lint all modified beads
br lint <modified-bead-ids>

# Check for cycles
br dep cycles

# Verify ready beads
br ready

# Count beads by track
br list --status open --json | jq 'group_by(.labels) | map({label: .[0].labels, count: length})'
```

Run the self-containment checklist from `/swarm-beads-create` on every modified bead.

### Step 9: Oracle Validation (Optional)

For significant rewrites (>5 beads changed), validate with oracles:

```
/consult-oracles "Evaluate these bead rewrites against the original audit findings.
Findings: <audit summary>
Changes made: <rewrite plan from Step 2>
Key question: Did the rewrites adequately address all audit findings?"
```

## Output Report

```markdown
## Bead Rewrite Report

### Source
- Findings from: <audit/oracle/review>
- Beads affected: <count>

### Changes Applied
| Action | Count | Beads |
|--------|-------|-------|
| New beads created | N | bd-xxx, bd-yyy |
| Beads split | N | bd-aaa -> bd-bbb, bd-ccc |
| Beads augmented | N | bd-ddd, bd-eee |
| Priority changes | N | bd-fff (P2->P0) |
| Dependency changes | N | +N added, -N removed |
| Beads deleted | N | bd-ggg |

### Before/After
| Metric | Before | After |
|--------|--------|-------|
| Total open beads | N | M |
| Track A (P0-P1) | N | M |
| Track B (P2) | N | M |
| Track C (P3-P4) | N | M |
| Dependency edges | N | M |
| Cycles | 0 | 0 |

### Unresolved Findings
<list any audit findings NOT addressed, with rationale>
```

## Common Rewrite Scenarios

### Scenario: VM Split Expansion

Audit finds a 4-way VM split should be 5-way:

1. Read existing 4 bead descriptions
2. Identify the missing responsibility
3. Create 5th bead with proper ACs
4. Adjust deps: new bead may block or be blocked by existing split beads
5. Update any bead that referenced "4 VMs" to say "5 VMs"

### Scenario: Bug Fix Creates Blocking Bead

Audit discovers a bug in existing code that beads build on:

1. Create P0 bug-fix bead with regression test AC
2. Add as dependency to all beads that touch affected code
3. Label `track-a` (ships first)
4. Verify no existing bead assumes the buggy behavior

### Scenario: Two-Track Execution Pivot

Oracle recommends "data integrity first, architecture second":

1. List all beads, classify into Track A vs B vs C
2. Re-label priorities: all safety/data beads -> P0-P1, all arch beads -> P2
3. Add deps: Track B beads depend on Track A completion
4. Verify Track A beads have no deps on Track B beads (would create deadlock)

### Scenario: Cross-Cutting Embedding

Review finds cross-cutting requirements were deferred to separate beads:

1. For each "Add l10n for X" bead: extract the specific resx keys
2. Embed those keys into the feature bead's Cross-Cutting section
3. Close the standalone cross-cutting bead
4. Verify feature bead is now self-contained
