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

## Step 6: Beads QA Review Passes

**"Check your beads N times, implement once."** After creating all issues, run iterative QA passes to catch missing context, unclear criteria, and dependency errors. This saves implementation tokens by front-loading planning quality.

### How It Works

Run review passes until changes flatline (typically 2-4 passes):

```
Pass 1 → significant changes (missing stories, wrong deps, unclear criteria)
Pass 2 → moderate changes (edge cases, missing test criteria, context gaps)
Pass 3 → minor changes (wording, small clarifications)
Pass 4 → no meaningful changes → STOP
```

### What to Check Each Pass

For EACH bead, review:

1. **Self-containment**: Can an agent implement this bead WITHOUT re-reading the PRD or other beads? If not, add the missing context directly into the bead's description.
2. **Acceptance criteria quality**: Are criteria machine-verifiable? "Works correctly" → BAD. "Returns 401 for non-initialforce.com emails" → GOOD.
3. **Dependencies**: Are all upstream beads listed? Are there false dependencies that could be removed to parallelize work?
4. **Missing stories**: Are there implicit tasks (test setup, config, migrations, observability) not covered by any bead?
5. **Sizing**: Can each bead be completed in ONE agent session? If not, split it.
6. **Architecture context**: Does the bead include enough context about the tech stack, file paths, and patterns for the implementing agent?

### Pass Format

For each proposed change, output:
```
BEAD: bd-s4s.3
CHANGE: Add missing context about OAuth redirect URI for dev mode
DIFF: + "Local dev: redirect to http://localhost:3000/auth/callback"
RATIONALE: Implementing agent won't know the callback URL pattern
```

After each pass, apply changes via `br update`, then re-review.

### Stop Condition

Stop when a pass produces only trivial wording changes or no changes at all. Never run more than 5 passes.

---

## Making Beads Self-Contained

**Critical principle:** Each bead must be independently implementable. An agent picking up a bead should NOT need to:
- Re-read the full PRD
- Look at sibling beads for context
- Guess at tech stack decisions

### What to Include in Each Bead

- **Tech stack context**: What framework, libraries, and patterns to use
- **File paths**: Where to create/modify files (if known from scaffolding decisions)
- **Integration points**: How this bead connects to upstream dependencies
- **Specific API/CLI commands**: Exact commands or API signatures, not vague references
- **Error cases**: What should happen when things go wrong

### Example: BAD vs GOOD

**BAD bead:**
> "Implement Google SSO authentication"
> - [ ] OAuth flow works
> - [ ] Only company emails accepted

**GOOD bead:**
> "Implement Google SSO using @fastify/oauth2 plugin on the Fastify backend (packages/backend).
> Uses JWT stored in httpOnly/secure/sameSite=strict cookie. Check `hd` claim equals 'initialforce.com'.
> Session timeout: 8h max, 30min inactivity. Local dev mode: skip OAuth, use DEV_USER_EMAIL env var."
> - [ ] @fastify/oauth2 configured with Google provider
> - [ ] hd claim checked, non-initialforce.com returns 403 with error message
> - [ ] JWT issued with {email, name, role} claims, 8h expiry
> - [ ] Cookie: httpOnly, secure, sameSite=strict
> - [ ] GET /auth/me returns current user or 401
> - [ ] DEV_USER_EMAIL env var bypasses OAuth in development

---

## Verification

After creating all issues and completing QA passes, verify:

```bash
# List all issues
br list

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
- [ ] Beads are self-contained (implementable without re-reading PRD)
- [ ] QA review passes completed (changes flatlined)
- [ ] `br sync --flush-only` executed
- [ ] `.beads/` committed to git
