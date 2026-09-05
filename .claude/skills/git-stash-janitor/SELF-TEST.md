# Self-Test

Trigger phrases that should activate this skill. If any of these fail to wake the skill, tighten the description in SKILL.md frontmatter.

---

## Should trigger

- "Clean up my git stashes in `/data/projects/asupersync`"
- "I have 200 stashes, are any worth keeping?"
- "Mine my stashes for useful work"
- "Stash archaeology on `<path>`"
- "What's in my stashes?"
- "Triage these stashes — which are superseded?"
- "Recover useful WIP from my stash pile and drop the rest"
- "I see `*127` in my prompt — is that 127 commits ahead?"
- "Help me figure out what to do with my stashes"
- "An agent swarm left a bunch of stashes — clean them up safely"
- "Stash janitor pass on `<repo>`"
- "Triage my git stashes safely"
- "What does *127 mean in my zsh prompt?"
- "Audit my stashes before I clean them up"

---

## Should NOT trigger

- "Stash my current changes" → just `git stash push`; this skill is for triaging accumulated stashes
- "What does `git stash` do?" → general git documentation; not this skill
- "Recover a deleted branch" → use `git reflog` directly
- "Clean up old branches" → `/git-branch-janitor` (doesn't exist; suggest manual `git branch -d`)
- "Squash my commits before pushing" → interactive rebase, not stashes
- "Resolve a merge conflict" → general git workflow
- "I lost my work after `git reset --hard`" → reflog recovery, not stash recovery
- "Set up `git stash` aliases" → shell config, not this skill
- "Build a documentation site" → `/documentation-website-for-software-project`
- "Audit billing for SOC2" → `/saas-billing-patterns-for-stripe-and-paypal`

---

## End-to-end smoke test on a 3-stash dummy repo (forced after warning)

The skill should classify these three stashes correctly:

```bash
# Setup: create a dummy repo with 3 stashes
mkdir -p /tmp/stash-janitor-smoke && cd /tmp/stash-janitor-smoke
git init -q -b main
echo "fn add(a: i32, b: i32) -> i32 { a + b }" > lib.rs
git add lib.rs && git commit -q -m "initial"

# Stash 1: SUPERSEDED — content already on main as another commit will land
echo 'fn add(a: i32, b: i32) -> i32 { a + b }
fn sub(a: i32, b: i32) -> i32 { a - b }' > lib.rs
git stash push -m "wip-add-sub"
# Then "land" the polished version on main:
echo 'fn add(a: i32, b: i32) -> i32 { a + b }
fn sub(a: i32, b: i32) -> i32 { a - b }' > lib.rs
git add lib.rs && git commit -q -m "feat: add sub function"

# Stash 2: NOVEL-AND-ACCRETIVE — defensive guard not yet on main
echo 'fn add(a: i32, b: i32) -> i32 { a + b }
fn sub(a: i32, b: i32) -> i32 { a - b }
fn safe_div(a: i32, b: i32) -> Option<i32> { if b == 0 { None } else { Some(a / b) } }' > lib.rs
git stash push -m "wip-safe-div"

# Stash 3: GARBAGE — explicitly labeled
echo 'broken' > lib.rs
git stash push -m "other-agent-broken"

# Verify setup
git stash list
# stash@{0}: On main: other-agent-broken
# stash@{1}: On main: wip-safe-div
# stash@{2}: On main: wip-add-sub
```

Invoke the skill with: "Triage the stashes in /tmp/stash-janitor-smoke".
Because this repo has fewer than 5 stashes, Phase 0 should warn that manual
inspection is the default. For this smoke test, reply "run anyway" so the
pipeline exercises the full Quick-mode path.

Expected behavior:

1. Phase 0: skill detects 3 stashes; tells the user `*3` ahead-of-prompt; warns that <5 stashes defaults to manual inspection; after tester says "run anyway", uses Quick mode.
2. Phase 1: `project_profile.json` has `primary_branch=main`, `test_command=cargo test --workspace` (or `<empty>` if no Cargo.toml — adjust dummy if needed).
3. Phase 2: `inventory.tsv` has 3 rows; `inventory_grouped.md` has 3 families.
4. Phase 3: bundle has 3 backup refs + 3 diffs + 3 meta files; verification log clean.
5. Phase 4: triage produces:
   - stash@{2} (wip-add-sub) → `superseded` (sub fn now on main)
   - stash@{1} (wip-safe-div) → `novel-and-accretive` (safe_div not on main)
   - stash@{0} (other-agent-broken) → `garbage` (prefix match)
6. Phase 5: user-facing decision table groups correctly; user says "go".
7. Phase 6: applies stash@{1} to recovery branch; commits; gates pass (or skipped if no test command).
8. Phase 7: skipped (no partial-novel rows).
9. Phase 8: fresh-eyes runs ≥2 rounds; both clean.
10. Phase 9: gated authorization; user types verbatim; drops in order garbage → superseded → applied-keeper, highest-index-first per bucket.
11. Phase 10: handoff report shows 3 triaged → 1 applied + 3 dropped + 0 final stashes. Push command printed.

A run that misclassifies any of the three stashes is a failure for this smoke test.

---

## Smoke test on this skill's static structure

```bash
SKILL_DIR=<repo>/.claude/skills/git-stash-janitor

# Frontmatter parses
head -7 "$SKILL_DIR/SKILL.md" | grep -E '^name:|^description:'

# Every reference exists
for f in "$SKILL_DIR/references"/*.md; do
  [[ -f "$f" ]] || echo "MISSING: $f"
done

# Every subagent exists
for f in "$SKILL_DIR/subagents"/*.md; do
  [[ -f "$f" ]] || echo "MISSING: $f"
done

# Every script is executable + has shebang
for s in "$SKILL_DIR/scripts"/*.sh; do
  [[ -x "$s" ]] || echo "NOT EXECUTABLE: $s"
  head -1 "$s" | grep -q '^#!' || echo "NO SHEBANG: $s"
done

# discover-project.sh works on a real repo
bash "$SKILL_DIR/scripts/discover-project.sh" "$SKILL_DIR/../../.." 2>&1 | grep -E 'primary_branch|test_command'
```

Expected: no errors, frontmatter has both fields, all references / subagents / scripts present, discover-project produces a profile.

---

## Resumption smoke test

```bash
# Run the skill on the smoke test repo; kill mid-Phase 6.
# Re-run on the same repo; verify:
# - Phase 1 re-uses project_profile.json
# - Phase 2 re-runs (cheap)
# - Phase 3 detects existing bundle, re-verifies (skips re-build if intact)
# - Phase 4 re-runs only un-batched ranges
# - Phase 5 re-presents the table
# - Phase 6 reads apply_log.tsv and skips already-applied stashes
# - No duplicate commits authored
```

---

## Idempotence smoke test

```bash
# Run the skill on a repo with 0 stashes:
cd /tmp && mkdir empty-repo && cd empty-repo
git init -q -b main
echo a > a.txt && git add a.txt && git commit -q -m init

# Invoke skill: "Clean up my stashes in /tmp/empty-repo"
# Expected:
# - Phase 1 produces project_profile.json
# - Phase 2 produces empty inventory.tsv
# - Phase 3 produces empty bundle
# - Phases 4–9 short-circuit
# - Phase 10 emits "0 stashes triaged, 0 commits authored"
# - No commits on the repo
# - No git stash list changes
```

---

## Validation checklist (when forking / extending this skill)

- [ ] Frontmatter starts at line 1 (no blank line before `---`)
- [ ] Description is third-person and includes "Use when" triggers
- [ ] SKILL.md body < ~700 lines (the spine should be punchy; depth is in references/)
- [ ] Every reference linked from SKILL.md exists
- [ ] Every subagent linked from SKILL.md exists
- [ ] Every script is executable + has a shebang
- [ ] No hardcoded `/data/projects/asupersync` references outside the WORKED-EXAMPLES context
- [ ] `git format-patch` is mentioned only as an explicit footgun, never as a recommended command
- [ ] Drop-order rule (highest index first per bucket) is in: SKILL.md anti-patterns, ANTI-PATTERNS.md A4, FAILURE-MODES.md F3, OPERATOR-LIBRARY.md ⊙ DROP, scripts/drop-confirmed.sh sanity check, subagents/cleanup-conductor.md
