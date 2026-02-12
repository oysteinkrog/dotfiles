---
name: prd-to-br
description: "Convert a PRD to br (beads_rust) issues. Creates an epic with child issues for each user story, sets up dependencies, and appends quality gates. Triggers on: convert prd, prd to beads, create beads from prd, prd to br, create issues from prd."
---

# PRD → br (beads_rust) Converter

Convert a Product Requirements Document into br issues: one epic + one issue per user story, with dependencies and quality gates.

---

## The Job

1. Read the PRD (file path or inline text)
2. Extract **Quality Gates** section
3. Create an **epic** for the feature
4. Create one **issue per user story** as children of the epic
5. Set up **dependencies** between issues using the PRD's dependency graph
6. Append quality gates to each issue's acceptance criteria
7. Sync to JSONL for git tracking

**Do NOT start implementing any stories. Just create the issues.**

---

## Step 1: Extract Quality Gates

Find the PRD's "Quality Gates" section and extract:
- **Universal gates**: Commands that apply to ALL stories
- **Conditional gates**: Commands for specific story types (e.g., "agent-editing stories")

If no Quality Gates section exists, ask the user.

---

## Step 2: Create Epic

```bash
br create --type=epic \
  --title="[PRD Title]" \
  --description="$(cat <<'EOF'
[Overview section from PRD]

Source: [path to PRD file]
EOF
)" \
  --external-ref="prd:[path-to-prd.md]"
```

Note the epic ID from output (e.g., `InitialForce-1`).

---

## Step 3: Create Issues

For each user story in the PRD, create a child issue:

```bash
br create \
  --parent=[EPIC_ID] \
  --title="[US-NNN]: [Story Title]" \
  --description="$(cat <<'EOF'
[Story description]

## Acceptance Criteria
[Story-specific criteria from PRD]

## Quality Gates
[Universal gates appended here]
[Conditional gates if applicable]
EOF
)" \
  --priority=[0-4]
```

### Rules:
- **HEREDOC**: Always use `<<'EOF'` (single-quoted) to prevent shell interpretation
- **One issue per story**: Never combine stories
- **Priority mapping**: Phase 0 → P0, Phase 1 → P1, Phase 2 → P2, Phase 3 → P3
- **Quality gates appended**: Every issue gets universal gates; conditional gates only if applicable
- **Acceptance criteria verbatim**: Copy from PRD, do not rephrase or simplify

---

## Step 4: Set Up Dependencies

Use the PRD's dependency graph (if present) to add dependencies:

```bash
br dep add [ISSUE_ID] [DEPENDS_ON_ID]
```

Syntax: `br dep add <blocked-issue> <blocker-issue>` — the first issue is blocked by the second.

### Dependency rules:
- Follow the PRD's explicit dependency graph if one exists
- If no graph: order by phase, then by document order within phase
- Within a phase: schema → backend → frontend → integration
- Cross-phase: all Phase N+1 stories depend on completing Phase N

### Example:
```bash
# US-003 (auth) depends on US-002 (scaffolding)
br dep add InitialForce-3 InitialForce-2

# US-007 (agent) depends on US-003 (auth) AND US-006 (chat UI)
br dep add InitialForce-7 InitialForce-3
br dep add InitialForce-7 InitialForce-6
```

---

## Step 5: Sync

After creating all issues and dependencies:

```bash
br sync --flush-only
```

This exports the SQLite database to `.beads/issues.jsonl` for git tracking.

Then commit:
```bash
git add .beads/
git commit -m "Create beads from PRD: [feature name]"
```

---

## Story Sizing

Each story must be completable in ONE agent session (~one context window).

**Right-sized:**
- Add a single API endpoint
- Add a UI component to an existing page
- Configure authentication middleware
- Add a pre-commit validation hook

**Too big — split:**
- "Build the entire chat UI" → split into: layout, message list, input box, streaming, markdown rendering
- "Add authentication" → split into: OAuth flow, session management, route guards, dev bypass

If a PRD story is too large, split it into sub-stories before creating issues. Note the split in the epic description.

---

## Handling Phased PRDs

For PRDs with multiple phases:
- Create ONE epic for the entire feature
- All stories across all phases are children of that epic
- Dependencies between phases are explicit (`br dep add`)
- Phase 0 stories have no dependencies
- Phase 1 stories may depend on Phase 0
- Phase 2 stories depend on relevant Phase 1 stories
- etc.

---

## Verification

After creating all issues, verify:

```bash
# List all issues in the epic
br list --parent=[EPIC_ID]

# Check dependency graph
br graph [EPIC_ID]

# Verify no orphaned dependencies
br doctor
```

---

## Checklist

Before finishing:

- [ ] Quality gates extracted from PRD
- [ ] Epic created with PRD overview and external-ref
- [ ] One issue per user story (no merging, no splitting unless too large)
- [ ] Acceptance criteria copied verbatim from PRD
- [ ] Quality gates appended to every issue
- [ ] Dependencies match PRD's dependency graph
- [ ] No circular dependencies
- [ ] Priorities set by phase (P0-P3)
- [ ] `br sync --flush-only` executed
- [ ] `.beads/` committed to git
