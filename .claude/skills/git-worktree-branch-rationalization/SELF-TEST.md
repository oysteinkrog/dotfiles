# Self-Test

Trigger phrases that should activate this skill. If any of these fail to wake the skill, tighten the description in SKILL.md frontmatter.

---

## Should trigger

- "Rationalize my branches in `/data/projects/asupersync`"
- "I have 200 local branches and 47 worktrees, can we clean up?"
- "Kill all my worktrees, save what's worth saving"
- "Branch archaeology on `/data/projects/foo`"
- "I'm out of disk because of worktrees"
- "What's in all these `agent-*` branches?"
- "Merge what's worth merging and delete the rest"
- "Consolidate all agent branches into master"
- "Collapse my repo down to main"
- "Figure out which worktrees can be removed safely"
- "Mine old branches for useful code"
- "Clean up after the agent swarm — branches and worktrees both"
- "Two agents collided on the same file in different branches; which version do I keep?"
- "I have 30 worktrees, are any of them worth keeping?"
- "Help me delete most of these branches, but harmonize the useful ones first"
- "Branch + worktree janitor pass on `<repo>`"
- "Audit my branches and worktrees before I clean them up"

---

## Should NOT trigger

- "What does `git worktree` do?" → general git documentation; not this skill.
- "How do I create a new branch?" → general git workflow.
- "Recover a deleted branch" → use `git reflog` directly, not this skill.
- "Set up a feature-branch workflow" → general workflow design, not cleanup.
- "Push my branch" → general git; not cleanup.
- "Resolve a merge conflict on the active branch" → general workflow; this skill triages and harmonizes accumulated state, not in-flight conflicts.
- "Squash my commits before pushing" → interactive rebase, not branches.
- "Stash my current changes" → `git stash push`; this skill is for branches and worktrees, not stashes.
- "Triage my stashes" → `/git-stash-janitor` (the sibling skill).
- "Build a documentation site" → `/documentation-website-for-software-project`.
- "Audit billing for SOC2" → `/saas-billing-patterns-for-stripe-and-paypal`.
- "I lost my work after `git reset --hard`" → reflog recovery; not this skill.

---

## End-to-end smoke test on a synthetic repo

The skill should classify these eight branches/worktrees correctly and produce the expected harmonization. This is the canonical structural smoke test for the skill's classification + harmonization logic.

```bash
# Setup: synthetic repo with all eight scenarios
ROOT=$(mktemp -d /tmp/branch-rationalization-smoke.XXXXXX)
cd "$ROOT"

git init -q -b main
cat > logger.rs <<'EOF'
fn redact_secrets(input: &str) -> String { input.to_string() }
EOF
cat > parser.rs <<'EOF'
fn parse(input: &str) -> Result<Vec<u8>, String> { Ok(input.as_bytes().to_vec()) }
EOF
git add -A && git commit -q -m "initial"
git tag v0.1.0

# Branch 1 — ALREADY-MERGED — landed and merged via squash
git checkout -q -b feature/minor-fix-already-landed
echo "// minor fix" >> parser.rs
git commit -qam "fix: minor parser nit"
git checkout -q main
git merge --squash feature/minor-fix-already-landed
git commit -qm "fix: minor parser nit (squashed)"
# Now branch 1's content is on main as a different SHA — `git cherry -v` should show `-`

# Branch 2 — NOVEL-AND-ACCRETIVE — defensive null-check on logger.rs
git checkout -q -b feature/redact-null-check
cat > logger.rs <<'EOF'
fn redact_secrets(input: &str) -> String {
    if input.is_empty() { return String::new(); }
    input.to_string()
}
EOF
git commit -qam "feat(logger): add defensive null-check to redact_secrets"

# Branch 3 — STALE — touches a file that's about to be renamed
git checkout -q main
git checkout -q -b feature/old-parser-name
echo "// old parser comment" >> parser.rs
git commit -qam "docs(parser): add comment"

# Branch 4 — PARTIALLY-NOVEL — two commits, one already on main, one not
git checkout -q main
git checkout -q -b feature/parser-split
echo "// minor fix" >> parser.rs   # same content as branch 1's already-merged commit
git commit -qam "fix: minor parser nit (partially-novel duplicate)"
echo "fn parse_lenient(input: &str) -> Vec<u8> { input.as_bytes().to_vec() }" >> parser.rs
git commit -qam "feat(parser): add lenient mode"

# Branch 5 — HARMONIZATION-REQUIRED — touches logger.rs with a complementary length-cap
git checkout -q main
git checkout -q -b feature/redact-length-cap
cat > logger.rs <<'EOF'
fn redact_secrets(input: &str) -> String {
    if input.len() > 4096 { return input[..4096].to_string(); }
    input.to_string()
}
EOF
git commit -qam "feat(logger): cap redact_secrets at 4096 chars"

# Branch 6 — HARMONIZATION-REQUIRED — touches logger.rs with a complementary redaction-pattern
git checkout -q main
git checkout -q -b feature/redact-pattern
cat > logger.rs <<'EOF'
fn redact_secrets(input: &str) -> String {
    input.replace("password=", "password=[REDACTED]")
}
EOF
git commit -qam "feat(logger): redact password= patterns"

# Branch 7 — PROTECTED — release line
git checkout -q main
git checkout -q -b release/2.x
echo "RELEASE 2.x" > RELEASE.md
git commit -qam "chore(release): mark 2.x line"

# Worktree A — DIRTY (staged + unstaged + untracked)
git checkout -q main
WT_A="$ROOT-wt-dirty"
git worktree add "$WT_A" main
cat > "$WT_A/logger.rs" <<'EOF'
fn redact_secrets(input: &str) -> String {
    let s: &str = input;          // type-narrowing intent
    s.to_string()
}
EOF
( cd "$WT_A" && git add logger.rs )
echo "// unstaged hint" >> "$WT_A/parser.rs"
echo "test fixture" > "$WT_A/test_fixture.txt"

# Worktree B — abandoned, on a stale branch
WT_B="$ROOT-wt-stale"
git worktree add "$WT_B" feature/old-parser-name

git checkout -q main
git branch -vv && git worktree list
```

Invoke the skill with: "Rationalize the branches and worktrees in /tmp/branch-rationalization-smoke".

Because this repo crosses the Quick-mode threshold (≥5 branches AND ≥2 worktrees), Phase 0 should auto-select Standard mode. Reply "go" to proceed.

### Expected behavior

1. **Phase 0 (INTAKE)**: skill detects 7 non-canonical branches + 2 worktrees; canonical = `main`; auto-protects `release/2.x`; asks user to confirm protection list and rationalization-branch name (`branch-rationalization-<DATE>`); confirms remote-cleanup is out of scope.

2. **Phase 1 (RECONNAISSANCE)**: `project_profile.json` has `canonical_branch=main`, merge-style detected (or "unknown" since the synthetic repo has both squash-merge and merge), test command empty (no Cargo.toml).

3. **Phase 2 (INVENTORY)**: `branches.tsv` has 7 rows; `worktrees.tsv` has 2 rows; `inventory_grouped.md` groups by family (`feature/*`, `release/*`).

4. **Phase 3 (BUNDLE)**: `<bundle>/object-bundle.pack` exists; per-branch directories under `<bundle>/branches/` for all 7 branches; per-worktree directories under `<bundle>/worktrees/` for both worktrees (Worktree A's bundle has staged.diff + unstaged.diff + untracked.tar.gz containing `test_fixture.txt`); `bundle_verification.log` is clean.

5. **Phase 4 (PROTECTION)**: `protected.tsv` lists `main`, `release/2.x`, the active worktree, and any user additions.

6. **Phase 5 (TRIAGE)** classifies:
   - `feature/minor-fix-already-landed` → `already-merged` (cherry shows `-`).
   - `feature/redact-null-check` → `novel-and-accretive` (touches logger.rs).
   - `feature/old-parser-name` → `superseded` or `garbage` (no novel surface).
   - `feature/parser-split` → `partially-novel` (commit 1 already on main, commit 2 novel).
   - `feature/redact-length-cap` → `novel-and-accretive` (touches logger.rs — collision with branch 2 and branch 6).
   - `feature/redact-pattern` → `novel-and-accretive` (touches logger.rs — collision).
   - `release/2.x` → `protected-preserve`.
   - Worktree A → `dirty-worktree-only` (touches logger.rs — also collides).
   - Worktree B → `garbage` or `superseded` (its branch is already classified).

7. **Phase 6 (TRIAGE MERGE)**: decision table presented; user says "go".

8. **Phase 7 (HARMONIZATION)**: `harmonization_plan.md` produced. The variant matrix for `logger.rs` shows four contributing variants (branches 2, 5, 6 + worktree A's staged), each with a different intent (defensive null-check / length-cap / redaction-pattern / type-narrowing). Proposed synthesis:
   ```rust
   fn redact_secrets(input: &str) -> String {
       let s: &str = input;
       if s.is_empty() { return String::new(); }
       let truncated = if s.len() > 4096 { &s[..4096] } else { s };
       truncated.replace("password=", "password=[REDACTED]")
   }
   ```
   With commit message citing all four sources. The user reviews and approves.

9. **Phase 8 (APPLY)**: rationalization branch `branch-rationalization-<DATE>` cut from `main`. Sequential apply:
   - `feature/minor-fix-already-landed` → skipped (already-merged).
   - `feature/parser-split` → split-apply: cherry-pick only the second commit (lenient mode).
   - Harmonized synthesis on `logger.rs` → hand-authored via Edit per `harmonization_plan.md`; cites all four source variants in the commit message; runs gates; commits.
   - `feature/old-parser-name` → skipped (superseded).
   - Re-fingerprint after each apply.

10. **Phase 9 (FRESH-EYES)**: ≥2 clean rounds; gates green.

11. **Phase 10 (CLEANUP, GATED)**: user types verbatim authorization. Order:
    - Worktree A removed first (`git worktree remove --force` because it had dirty state — but only after confirmation that the bundle's captured staged + unstaged + untracked content is intact).
    - Worktree B removed.
    - `git worktree prune` runs to clean residual metadata.
    - Branches deleted in order garbage → superseded → already-merged → novel-stale → applied-keepers (the harmonized one's source branches: `feature/redact-null-check`, `feature/redact-length-cap`, `feature/redact-pattern`).
    - `release/2.x` is NOT deleted.
    - `main` is NOT deleted.
    - Active worktree is NOT removed.
    - `cleanup_authorization.txt` records the verbatim user text and timestamps.

12. **Phase 11 (HANDOFF)**: report shows: 7 branches triaged → 1 harmonized + 1 partial-applied + 5 dropped; 2 worktrees → 2 removed; 1 protected branch preserved. Recovery recipes for each removal/deletion. Push command for `branch-rationalization-<DATE>`.

A run that misclassifies any of the eight scenarios, OR fails to produce a harmonization plan when ≥2 branches collide on `logger.rs`, OR removes a worktree without bundle-archive of its dirty state, OR deletes `release/2.x`, OR pushes the rationalization branch, is a failure for this smoke test.

---

## Smoke test on this skill's static structure

```bash
SKILL_DIR=<repo>/.claude/skills/git-worktree-branch-rationalization

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
bash "$SKILL_DIR/scripts/discover-project.sh" "$SKILL_DIR/../../.." 2>&1 | grep -E 'canonical_branch|test_command'

# Anti-pattern presence: drop-order rule + worktree-first rule
grep -l 'worktree.*first' "$SKILL_DIR"/SKILL.md "$SKILL_DIR"/references/*.md "$SKILL_DIR"/subagents/*.md "$SKILL_DIR"/scripts/*.sh
grep -l 'highest.*index.*first\|in order garbage' "$SKILL_DIR"/SKILL.md "$SKILL_DIR"/references/*.md
```

Expected: no errors, frontmatter has both fields, all references / subagents / scripts present, discover-project produces a profile, the worktree-first rule and the cleanup-bucket-order rule are both visible across multiple files.

---

## Resumption smoke test

```bash
# Run the skill on the smoke test repo; kill mid-Phase 8.
# Re-run on the same repo; verify:
# - Phase 1 re-uses project_profile.json
# - Phase 2 re-runs (cheap)
# - Phase 3 detects existing bundle, re-verifies (skips re-build if intact)
# - Phase 4 re-uses protected.tsv
# - Phase 5 re-runs only un-batched ranges
# - Phase 6 re-presents the table
# - Phase 7 re-uses harmonization_plan.md (or re-presents if any verdict changed)
# - Phase 8 reads apply_log.tsv and skips already-applied keepers
# - No duplicate commits authored on the rationalization branch
```

---

## Idempotence smoke test

```bash
# Run the skill on a repo with 0 non-protected branches and 0 extra worktrees:
ROOT=$(mktemp -d /tmp/empty-repo.XXXXXX)
cd "$ROOT"
git init -q -b main
echo a > a.txt && git add a.txt && git commit -q -m init

# Invoke skill: "Rationalize branches and worktrees in /tmp/empty-repo"
# Expected:
# - Phase 1 produces project_profile.json
# - Phase 2 produces empty branches.tsv + empty worktrees.tsv
# - Phase 3 produces an empty-but-valid bundle (object-bundle.pack contains canonical only)
# - Phase 4 protected.tsv contains canonical only
# - Phases 5–10 short-circuit
# - Phase 11 emits "0 branches triaged, 0 worktrees triaged, 0 commits authored, nothing to rationalize"
# - No commits on the repo
# - No branches deleted
# - No worktrees removed
```

---

## Validation checklist (when forking / extending this skill)

- [ ] Frontmatter starts at line 1 (no blank line before `---`)
- [ ] Description is third-person and includes "Use when" triggers
- [ ] SKILL.md body is reviewable in one sitting (~700 lines is the upper bound for this skill family)
- [ ] Every reference linked from SKILL.md exists
- [ ] Every subagent linked from SKILL.md exists
- [ ] Every script is executable + has a shebang
- [ ] No hardcoded `/data/projects/<example>` references outside the WORKED-EXAMPLES context
- [ ] `git format-patch` is documented as VALID for branches (cross-link to git-stash-janitor's "format-patch is index-only for stashes" footgun so readers don't generalize the wrong rule)
- [ ] Worktree-first cleanup ordering is in: SKILL.md anti-patterns + Polish Bar + PHASES.md Phase 10 + scripts/drop-retire-confirmed.sh + subagents/cleanup-conductor.md
- [ ] Branch deletion order rule (garbage → superseded → already-merged → novel-stale → divergent-refactor (opt-in) → applied-keepers) is in: SKILL.md, ANTI-PATTERNS.md, FAILURE-MODES.md, OPERATOR-LIBRARY.md ⊘ DELETE-BRANCH, scripts/drop-retire-confirmed.sh, subagents/cleanup-conductor.md
- [ ] `git branch -d` preferred over `-D` for merged branches is documented in: SKILL.md axioms + ANTI-PATTERNS.md + FAILURE-MODES.md + scripts/drop-retire-confirmed.sh
- [ ] Remote-cleanup-out-of-scope rule is in: SKILL.md, ANTI-PATTERNS.md, scripts/drop-retire-confirmed.sh
- [ ] Harmonization is documented as the conceptual centerpiece in: SKILL.md (Axiom 1 + ◇ HARMONIZE operator + Phase 7 + harmonization-fidelity polish bar dimension), HARMONIZATION.md, OPERATOR-LIBRARY.md, subagents/harmonization-planner.md, scripts/harmonization-plan.sh
- [ ] The "skill never pushes" rule is in: SKILL.md, anti-patterns, handoff-reporter.md
- [ ] The "active worktree is never removed by the skill" rule is in: SKILL.md, ANTI-PATTERNS.md, FAILURE-MODES.md, scripts/drop-retire-confirmed.sh, subagents/cleanup-conductor.md
- [ ] No mass-delete primitives anywhere in scripts/ or subagents/
