# Operator Library

Each operator is a reusable cognitive move with explicit triggers, a prompt module, and exit criteria. Adapted from [`operationalizing-expertise`](../../operationalizing-expertise/SKILL.md) Track A.

Agents invoke operators by tag. Every Polish-Bar failure (see [POLISH-BAR.md](POLISH-BAR.md)) maps to exactly one operator.

---

## How to Use This File

1. When designing a phase or polishing a step, walk it against the Polish Bar (see [POLISH-BAR.md](POLISH-BAR.md) and [SKILL.md § Polish Bar](../SKILL.md#the-polish-bar-non-negotiable)).
2. For each failing dimension, find the operator whose tag matches.
3. Paste the operator's *prompt module* into your working context (or inline into a subagent invocation).
4. Do what it says. Exit criteria are in the module.

The conceptual centerpiece of this skill is `◇ HARMONIZE` — the cognitive move stash-janitor doesn't have to make. Read its card most carefully.

---

## Glyph Index — Quick Lookup (35 operators)

Use this as a fresh-agent cheat-sheet: scan the glyph + name + phase, then jump to the card. The phase-by-phase composition table (which order to invoke them in) is at [§ Operator Composition Cheat-Sheet](#operator-composition-cheat-sheet) near the bottom.

**Core 18 (always-on):**

| Glyph | Name | Phase | Card |
|-------|------|-------|------|
| `★` | INVENTORY | 2 | [↓](#-inventory) |
| `🔒` | PROTECT | 0, 4 | [↓](#-protect) |
| `🌳` | WORKTREE-CHECK | 3, 10 | [↓](#-worktree-check) |
| `✦` | FINGERPRINT | 5 | [↓](#-fingerprint) |
| `◐` | VERIFY-ON-CANONICAL | 5 | [↓](#-verify-on-canonical) |
| `⬡` | BUNDLE | 3 (gate) | [↓](#-bundle) |
| `⚠` | CONFIRM | 6, 7, 10 (user gates) | [↓](#-confirm) |
| `◇` | HARMONIZE | 7 (centerpiece) | [↓](#-harmonize--the-conceptual-centerpiece) |
| `✧` | CHERRY-PICK | 8 | [↓](#-cherry-pick) |
| `⊟` | SQUASH-MERGE | 8 | [↓](#-squash-merge) |
| `⊠` | REBASE-AND-MERGE | 8 | [↓](#-rebase-and-merge) |
| `⇄` | SPLIT-COMMITS-HUNKS | 8b | [↓](#-split-commits-hunks) |
| `⊕` | RECOVER | 8 (per-apply gate) | [↓](#-recover) |
| `⊞` | RE-FINGERPRINT | 8 (between applies) | [↓](#-re-fingerprint) |
| `↺` | WORKING-TREE-DRIFT | 8 (every iteration) | [↓](#-working-tree-drift) |
| `⊙` | PRUNE-WORKTREE | 10 (before branch del) | [↓](#-prune-worktree) |
| `⊘` | DELETE-BRANCH | 10 (after wt prune) | [↓](#-delete-branch) |
| `⌘` | HANDOFF | 11 | [↓](#-handoff) |

**Round-3 17 (rigor + operational depth, conditional):**

| Glyph | Name | Phase | Trigger |
|-------|------|-------|---------|
| `👁` | DRY-RUN | 7.5 | `--dry-run` flag OR Comprehensive/Council default |
| `🔬` | PROVENANCE | 8, 11 | Always-on under `apply_log` schema v2 |
| `⏱` | PROFILE | cross-phase | Always-on (passive) |
| `🛡` | AUDIT-AFTER | 9.5 (HARD GATE) | Always-on between Phase 9 and 10 |
| `🧪` | FUZZ | 3, 11 | Comprehensive/Council; opt-in for others |
| `📐` | PROVE | 3, 11 | Always-on (conformance vs BUNDLE-FORMAT-SPEC) |
| `🪞` | METAMORPHIC | 9 round 2+ | Whenever harmonized commits exist |
| `🎯` | CALIBRATE | 5 per-branch | Always-on under decision-theoretic mode |
| `🌐` | SEMANTIC-COLLISION | 7 | Comprehensive/Council |
| `🔍` | REFLOG-DEEP | 5 forensic | `novel-but-stale` / `divergent-refactor` candidates |
| `🔁` | DUEL | 7 | Council always; Comprehensive when ≥3-branch collision |
| `📡` | CI-AWARE | 4 | Whenever CI YAML / install URLs reference branches |
| `🔗` | REMOTE-TOPOLOGY | 1 | Per-worktree at reconnaissance |
| `✍` | SIGN | 8 (post-apply) | `project_profile.json:requires_signing == true` |
| `🆔` | UNBLOCK | 11 | Always-on under handoff augmentation |
| `📦` | EXPORT | 11+ | Cross-machine resume / audit handoff |
| `🪢` | REPLAY | resume | Mid-Phase-8 conflict resolution being replayed |

**Most-load-bearing four** (the ones a fresh agent should master first):
- `⬡ BUNDLE` — Phase 3 irreversibility gate. Without this, no destructive phase runs.
- `◇ HARMONIZE` — Phase 7 conceptual centerpiece. Without this, the skill is just stash-janitor with extra steps.
- `⚠ CONFIRM` — every user gate. Without this, authorization isn't real.
- `🛡 AUDIT-AFTER` — Phase 9.5 HARD GATE blocking Phase 10.

---

## ★ INVENTORY

**Definition:** Capture every branch's identity (ref + sha + merge-base + ahead/behind + cherry-summary + touched-files) AND every worktree's identity (path + branch + dirty-state) into two TSVs that share a join key. The TSVs become the source of truth for the rest of the run.

**Triggers:**
- Phase 2 — once per run
- Resumption mid-run (re-inventory cheaply because a concurrent agent may have created or deleted a branch or moved a worktree)

**Inputs:**
- Project path
- Canonical branch name (from `project_profile.json`)

**Action:** run two passes — Pass A enumerates worktrees, Pass B enumerates branches. Cross-reference via the branch name (which appears in both: `worktrees.tsv:branch` and `branches.tsv:name`).

**Failure modes:**
- Inventorying via `git branch` alone — misses ahead/behind, misses cherry-summary, misses worktree backlinks (cited in [FAILURE-MODES.md § "phantom-keepers"](FAILURE-MODES.md))
- Inventorying via `git worktree list` (human-readable) instead of `--porcelain` — misses locked/prunable flags ([FAILURE-MODES.md § "stale-locks"](FAILURE-MODES.md))
- Inventorying twice from different snapshot points — index drift between the two TSVs; if a concurrent agent creates a branch between Pass A and Pass B, the cross-reference is stale

**Prompt module:**
```
[OPERATOR: ★ INVENTORY]

Pass A — Worktrees:
1) git -C {PROJECT} worktree list --porcelain > {WS}/worktrees.raw
2) For each `worktree <path>` block, capture:
   - path, branch, head_sha, locked (bool), prunable (bool)
   - per-worktree dirty state from inside the worktree:
       (cd <path> && git status --porcelain=v2)
       (cd <path> && git diff --stat)
       (cd <path> && git diff --cached --stat)
       (cd <path> && git ls-files --others --exclude-standard | wc -l)
       (cd <path> && git submodule status)
3) Write worktrees.tsv with columns:
   path, branch, head_sha, locked, prunable, tracked_changed, staged,
   untracked, submodules

Pass B — Branches:
1) git -C {PROJECT} for-each-ref refs/heads/ \
     --format='%(refname:short)|%(objectname)|%(committerdate:iso-strict)|%(authorname)|%(subject)|%(upstream:short)|%(upstream:track)' \
     > {WS}/branches.raw
2) For each branch, capture:
   - merge_base = git merge-base <canonical> <branch>
   - ahead/behind = git rev-list --left-right --count <canonical>...<branch>
   - cherry_summary = git cherry -v <canonical> <branch>  (count `+` and `-` lines)
   - files_touched = git diff --name-only <merge_base> <branch> | wc -l
   - worktree_path = backlink from worktrees.tsv
3) Write branches.tsv with columns:
   name, sha, merge_base, ahead, behind, cherry_pluses, cherry_minuses,
   files_touched, upstream_track, worktree_path

Cross-pass:
4) Group by name-prefix family; emit inventory_grouped.md.

Required: row count of worktrees.tsv == git worktree list --porcelain | grep -c '^worktree '
Required: row count of branches.tsv == git for-each-ref refs/heads --format='%(refname:short)' | wc -l
Output: worktrees.tsv, branches.tsv, inventory_grouped.md, count summary.
```

**Exit criteria:** both TSVs exist with one row per entity; counts match `git worktree list --porcelain` and `git branch` outputs; `inventory_grouped.md` enumerates every name-prefix family.

**Quote-bank anchors:**
- [SKILL.md Axiom 0](../SKILL.md#the-rationalization-kernel-universal-axioms): "Two units of management, one safety story. Inventory each separately."
- [SKILL.md Axiom 17](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git cherry -v` is the canonical 'is this content already on canonical' check."

**Canonical tag:** `inventory`

---

## 🔒 PROTECT

**Definition:** Mark entries as keep-forever; they never enter the rationalization pipeline. Auto-protected entries are the canonical branch, the currently-checked-out branch, branches matching `protected_by_convention_patterns` from `project_profile.json` (`release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`, etc.), the active worktree (the user's CWD), and any worktree whose underlying branch is protected. User-flagged entries from Phase 0 + Phase 4 confirmations are also protected.

**Triggers:**
- Phase 0 (initial protection list from user input)
- Phase 4 (post-inventory confirmation; the load-bearing gate)

**Inputs:**
- `project_profile.json:protected_by_convention_patterns`
- `branches.tsv` + `worktrees.tsv`
- User's initial protection list from Phase 0
- Currently-checked-out branch (from `git branch --show-current`)
- Active worktree path (from CWD)

**Action:** compute the union of auto-protected and user-flagged entries; present to user; capture confirmation; freeze into `protected.tsv`. Protected entries are excluded from Phase 5 triage entirely.

**Failure modes:**
- Auto-protecting via name-pattern alone — misses branches the user knows are still active but don't match a convention regex (e.g., `agent-jeff-active-rewrite`); the user must add these via Phase 4 confirmation
- Forgetting to protect the currently-checked-out branch — git refuses to delete it but the inventory should make this explicit, not rely on git's refusal
- Forgetting to protect the active worktree — the skill enforces this independently; relying on git's refusal is a footgun ([FAILURE-MODES.md § "active-worktree-removal"](FAILURE-MODES.md))
- Auto-protecting `[gone]`-tracking branches — these have unique commits the upstream never saw; triage normally, don't auto-protect ([FAILURE-MODES.md § "gone-upstream-skipped"](FAILURE-MODES.md))

**Prompt module:**
```
[OPERATOR: 🔒 PROTECT]

Inputs: project_profile.json, branches.tsv, worktrees.tsv, user's initial list,
canonical branch name, active worktree path, currently-checked-out branch.

1) Compute auto-protected:
   - The canonical branch
   - The currently-checked-out branch (git branch --show-current in the active worktree)
   - The active worktree path (the user's CWD)
   - Every branch matching project_profile.json:protected_by_convention_patterns
   - Every worktree whose underlying branch is in the auto-protected set
2) Add user's Phase 0 initial list.
3) Display to user as a markdown block:
   ## Auto-protected (will NEVER be deleted or removed)
   - <list with reason for each>
   ## User-flagged at Phase 0
   - <list with reason>
   ## NOT protected (will enter triage)
   - <count> branches, <count> worktrees
4) Ask: "Add anything to the protected list? Remove anything?"
5) Capture user's response into protected.tsv:
   kind, name, reason
6) Re-display the post-confirmation list and wait for explicit user OK.

Required: protected.tsv exists; main agent has explicit user OK; no protected
entry will appear in any later batch_*.tsv triage row.
```

**Exit criteria:** `protected.tsv` reflects user-confirmed protection set; user has typed OK; Phase 5 fan-out can run.

**Quote-bank anchors:**
- [SKILL.md Quickref](../SKILL.md#quickref): "No protected branch ever enters the rationalization pipeline."
- [SKILL.md "Up-Front Confirmations" point 6](../SKILL.md#up-front-confirmations-ask-before-starting): "Initial protection list?"

**Canonical tag:** `protect`

---

## 🌳 WORKTREE-CHECK

**Definition:** Verify each worktree's dirty state (staged + unstaged + untracked) is captured in the bundle before any removal. Re-snapshots the worktree's status immediately before each `git worktree remove` invocation to detect concurrent-agent drift.

**Triggers:**
- Phase 3 — once per worktree, building the bundle
- Phase 10 — immediately before each `git worktree remove` invocation

**Inputs:**
- Worktree path
- `<bundle>/worktrees/<wt-slug>/` directory

**Action:** confirm the bundle has staged.diff + unstaged.diff + `.untracked.list` + untracked.tar.gz (if applicable) + status.txt for this worktree; re-snapshot the worktree's `git status --porcelain=v2`; if it differs from the bundle's status.txt, refuse the removal until the user OKs (the dirty state has changed since Phase 3 capture; concurrent agent may have added new content).

**Failure modes:**
- Trusting Phase 3's capture without re-snapshotting — concurrent agents may have added content between Phase 3 and Phase 10 ([FAILURE-MODES.md § "concurrent-drift-after-bundle"](FAILURE-MODES.md))
- Removing a worktree whose `.untracked.list` + untracked.tar.gz weren't created (the directory had no untracked content at Phase 3, but does now) — silent dirty-state loss
- Running `git worktree remove --force` without 🌳 WORKTREE-CHECK first — bypasses the safety net

**Prompt module:**
```
[OPERATOR: 🌳 WORKTREE-CHECK]

Inputs: worktree path P, bundle path BUNDLE, wt-slug WS.

1) Confirm bundle artifacts exist:
   - {BUNDLE}/worktrees/{WS}/staged.diff
   - {BUNDLE}/worktrees/{WS}/unstaged.diff
   - {BUNDLE}/worktrees/{WS}/status.txt
   - {BUNDLE}/worktrees/{WS}/meta.txt
   - {BUNDLE}/worktrees/{WS}/.untracked.list    (only if untracked content existed at Phase 3)
   - {BUNDLE}/worktrees/{WS}/untracked.tar.gz   (only if untracked content existed at Phase 3)
   Any missing → HALT; surface to user.

2) Re-snapshot the worktree:
   live_status=$(cd P && git status --porcelain=v2)
   bundle_status=$(cat {BUNDLE}/worktrees/{WS}/status.txt)

3) If live_status != bundle_status:
   - The dirty state changed between Phase 3 and now (concurrent agent).
   - Refuse the removal.
   - Surface to user with the diff between live and bundle.
   - Ask: re-capture the dirty state into the bundle and proceed?
   - If yes: re-run Phase 3's worktree-capture step for this worktree.
   - If no: skip this worktree's removal.

4) If live_status == bundle_status:
   - The bundle accurately reflects the worktree's dirty state.
   - Proceed with the removal (per ⊙ PRUNE-WORKTREE operator).

Required: the bundle reflects the worktree's *current* state at the moment
of removal. Never proceed when bundle and live disagree.
```

**Exit criteria:** bundle captures match live state; the `⊙ PRUNE-WORKTREE` invocation that follows is safe.

**Quote-bank anchors:**
- [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git worktree remove` refuses on dirty worktrees — that refusal is a feature."
- [SKILL.md Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms): "Concurrent agents' working-tree changes in any worktree are normal."

**Canonical tag:** `worktree-check`

---

## ✦ FINGERPRINT

**Definition:** Identify the symbols a branch *introduces* — function names, type names, fixture strings, test names, file paths added by the branch (relative to its merge-base with canonical). The fingerprint is the input to VERIFY-ON-CANONICAL.

**Triggers:**
- Phase 5, per-branch, before any "is it on canonical?" check
- Phase 8, between applies (re-fingerprint downstream candidates)

**Inputs:**
- `<bundle>/branches/<slug>/diff-vs-merge-base.diff` (or for worktrees, `staged.diff + unstaged.diff`)
- Project language(s) from `project_profile.json`

**Action:** parse the diff for added symbols using language-aware regex over `+` lines (or AST-grep where a grammar exists); produce a JSON fingerprint with functions, types, tests, fixture-strings, file-paths.

**Failure modes:**
- Fingerprinting only function names — misses test/fixture/string-only branches
- Fingerprinting via `+` line text alone — picks up modified lines as if they were added; false positives
- Treating a moved-but-unchanged function as "introduced" — inflates novelty signal
- Empty fingerprint mistaken for "no signal" — empty fingerprint IS the signal: the branch added no introduceable surface, candidate `garbage`

**Prompt module:**
```
[OPERATOR: ✦ FINGERPRINT]

For diff at {BUNDLE}/branches/{slug}/diff-vs-merge-base.diff (or for a worktree's
{BUNDLE}/worktrees/{wt-slug}/{staged,unstaged}.diff):

1) For each chunk header (^@@), check whether the file is new (`new file mode`)
   or existing. New-file diffs: every `+` line is added. Existing-file diffs:
   only `+` lines that are NOT followed by a corresponding `-` line are added.

2) Extract introduced symbols by language:
   - Rust: ^\+\s*(pub )?(unsafe )?(async )?fn (\w+)
           ^\+\s*(pub )?(struct|enum|trait|type) (\w+)
   - TypeScript/JS: ^\+\s*(export )?(async )?function (\w+)
                    ^\+\s*(export )?(const|let) (\w+) =
                    ^\+\s*(export )?(class|interface|type) (\w+)
   - Python: ^\+\s*(async )?def (\w+)
             ^\+\s*class (\w+)
   - Go: ^\+func (\w+)
         ^\+func \(\w+ \*?\w+\) (\w+)
         ^\+type (\w+) (struct|interface|...)
   - Tests: language-appropriate, e.g.,
            Rust: ^\+\s*#\[test\] then capture next fn (\w+)
            JS: ^\+\s*(it|test)\(['"]([^'"]+)
            Python: ^\+\s*def (test_\w+)
   - Fixture strings: literal strings ≥ 10 chars in `+` lines, deduplicated
   - File paths: every ^diff --git a/(.*) b/

3) Output the fingerprint as a JSON object:
   {
     "files": [...],
     "new_files": [...],
     "functions": [...],
     "types": [...],
     "tests": [...],
     "fixture_strings": [...]
   }

Required: union of all introduced symbols. Empty fingerprint == garbage candidate.
```

**Exit criteria:** fingerprint JSON written to triage worker's batch tsv; consumed by `◐ VERIFY-ON-CANONICAL`.

**Quote-bank anchors:**
- [SKILL.md Operator table](../SKILL.md#operator-library--the-cognitive-moves): "✦ FINGERPRINT — Identify the symbols a branch introduces."
- [TRIAGE-RUBRIC.md § "FINGERPRINT Heuristics"](TRIAGE-RUBRIC.md#fingerprint-heuristics): per-language regex catalogue.

**Canonical tag:** `fingerprint`

---

## ◐ VERIFY-ON-CANONICAL

**Definition:** For each fingerprint symbol, search canonical and decide: is it already there with equivalent semantics? Sample same-signature on at least 3 introduced symbols before concluding `superseded`.

**Triggers:**
- Phase 5, immediately after FINGERPRINT
- Phase 8, between applies (re-verify against the rationalization branch's tip)

**Inputs:**
- Fingerprint JSON from `✦ FINGERPRINT`
- Canonical branch name (or rationalization branch's tip during Phase 8 `⊞ RE-FINGERPRINT`)
- Project language(s) for the same-signature heuristic

**Action:** path-scoped grep first (faster + more accurate); fall back to whole-repo grep when path is gone; record per-symbol `found_on_canonical` + `file:line` + `same_signature`. Aggregate into `fingerprint_coverage` and `file_existence_coverage`.

**Failure modes:**
- Whole-repo grep when a path-scoped grep would suffice — slow + noisy
- Treating "symbol present" as "semantically equivalent" — needs same-signature sample (Axiom 16)
- Ignoring branch-divergence (running grep against `HEAD` instead of `origin/<canonical>`)
- Skipping the same-signature sample on `superseded` candidates — leads to phantom-superseded verdicts that drop a branch which actually had a more-restrictive defensive variant

**Prompt module:**
```
[OPERATOR: ◐ VERIFY-ON-CANONICAL]

Inputs: fingerprint (json), canonical_branch (e.g., "main"), expected file paths.

For each function/type/test name F in fingerprint:
  if F's expected file path P exists on canonical_branch:
    git -C {PROJECT} grep -F 'F' {canonical_branch} -- 'P'
  else:
    git -C {PROJECT} grep -F 'F' {canonical_branch}

  Record per-symbol:
    - found_on_canonical: bool
    - file:line where found (or "n/a")
    - same_signature: bool — quick re-read of the line; does the param list match?

For each fixture_string S:
  git -C {PROJECT} grep -F 'S' {canonical_branch}
  Record found_on_canonical bool.

For each new_file F:
  if git -C {PROJECT} ls-tree {canonical_branch} -- F succeeds: file exists, mark
  file_already_on_canonical.

Same-signature sample (Axiom 16):
  - Pick up to 3 introduced functions with `found_on_canonical=true`.
  - For each: read both signatures (branch's and canonical's).
  - same_signature = true iff parameter list, parameter types, return type
    all match (best-effort by language).
  - If ≥30% of sampled signatures diverge: flip verdict toward
    novel-but-stale or divergent-refactor; do NOT classify as superseded.

Verdict input from this operator (consumed by TRIAGE-RUBRIC):
  - fingerprint_coverage: fraction of symbols found_on_canonical
  - same_signature_ratio: fraction of sampled signatures matching
  - file_existence_coverage: fraction of files referenced still exist on canonical

Output: a json object per branch, written to triage/batch_*.tsv as the
"evidence_on_canonical" + "fingerprint_coverage" + "same_signature_ratio"
columns.
```

**Exit criteria:** every fingerprint symbol has a `found_on_canonical` decision; same-signature sampling done where applicable; aggregate coverages computed; verdict input ready for the rubric.

**Quote-bank anchors:**
- [SKILL.md Axiom 16](../SKILL.md#the-rationalization-kernel-universal-axioms): "Same-name on canonical is not always supersession."
- [TRIAGE-RUBRIC.md § "Same-Signature Verification"](TRIAGE-RUBRIC.md#same-signature-verification).

**Canonical tag:** `verify-on-canonical`

---

## ⬡ BUNDLE

**Definition:** Materialize a complete, byte-equality + bundle-round-trip-verified recovery bundle for every branch AND every worktree *before* any classification or destructive action runs. The irreversibility gate.

**Triggers:**
- Phase 3 — once, the gate

**Inputs:**
- `branches.tsv`, `worktrees.tsv`
- Canonical branch name
- `<bundle>` path

**Action:** for each branch — backup ref + per-branch diff + per-branch format-patch series + meta + commits.tsv. For each worktree — staged.diff + unstaged.diff + `.untracked.list` + untracked.tar.gz (if applicable) + status.txt + meta. Object-bundle.pack over the entire backup namespace. Verify byte-equality + bundle round-trip. Halt on any mismatch.

**Failure modes:**
- Using `git diff` without `--binary` — silently drops binary content (e.g., images, PDFs in fixture dirs)
- Forgetting `--no-renames` on `format-patch` — produces incomplete patches when paths moved between merge-base and branch tip
- Skipping untracked-tarball capture on worktrees — silently drops new-file content (counterpart to git-stash-janitor's third-parent-stash bug)
- Verifying only the diff and not the backup ref — diffs can be regenerated; backup refs cannot if the live branch is deleted first
- Verifying only sample bundles ("we'll just check 10 random ones") — every entry must be verified (Axiom 4)
- Forgetting `git bundle list-heads` round-trip — a malformed pack file passes byte-equality but fails to fetch from
- **Note: `git format-patch` IS valid for branches** — Axiom 7. Do not generalize the stash-janitor "format-patch is wrong" rule.

**Prompt module:**
```
[OPERATOR: ⬡ BUNDLE]

PER BRANCH in branches.tsv (skipping protected ones — they keep their refs but
don't need a backup ref since they're not deleted):

1) slug = slugify_branch "$name" from scripts/project-root.sh
   # Safe prefix plus hash suffix; `feature/a` and `feature_a` must not collide.
   mkdir -p {BUNDLE}/branches/{slug}/format-patch

2) Layer 1 — backup ref:
   git -C {PROJECT} update-ref refs/branch-rationalization-backup/{slug} {sha}

3) Layer 3 — per-branch diff:
   git -C {PROJECT} diff --binary {merge_base}...{sha} \
     > {BUNDLE}/branches/{slug}/diff-vs-merge-base.diff

4) Layer 4 — per-branch format-patch series:
   git -C {PROJECT} format-patch {merge_base}..{sha} \
     -o {BUNDLE}/branches/{slug}/format-patch/ \
     --binary --no-renames

5) Meta + commits.tsv:
   git -C {PROJECT} log -1 --format='%H%n%P%n%ci%n%an%n%s' {sha} \
     > {BUNDLE}/branches/{slug}/meta.txt
   git -C {PROJECT} log {merge_base}..{sha} \
     --format='%H%t%ci%t%an%t%s' \
     > {BUNDLE}/branches/{slug}/commits.tsv

PER WORKTREE in worktrees.tsv:

6) wt_slug = sanitized path
   mkdir -p {BUNDLE}/worktrees/{wt_slug}

7) Status snapshot:
   (cd {wt_path} && git status --porcelain=v2) \
     > {BUNDLE}/worktrees/{wt_slug}/status.txt

8) Staged diff (Layer 1 for worktree dirty state):
   (cd {wt_path} && git diff --binary --cached) \
     > {BUNDLE}/worktrees/{wt_slug}/staged.diff

9) Unstaged diff (Layer 2):
   (cd {wt_path} && git diff --binary) \
     > {BUNDLE}/worktrees/{wt_slug}/unstaged.diff

10) Untracked tarball (Layer 3) — only if untracked content exists:
    (cd {wt_path} && git ls-files --others --exclude-standard -z \
      > {BUNDLE}/worktrees/{wt_slug}/.untracked.list)
    if [[ -s {BUNDLE}/worktrees/{wt_slug}/.untracked.list ]]; then
      (cd {wt_path} && tar --null -czf \
        {BUNDLE}/worktrees/{wt_slug}/untracked.tar.gz \
        -T {BUNDLE}/worktrees/{wt_slug}/.untracked.list)
    fi

11) Meta:
    cat > {BUNDLE}/worktrees/{wt_slug}/meta.txt <<EOF
    path: {wt_path}
    branch: {branch}
    head_sha: {head_sha}
    locked: {locked}
    prunable: {prunable}
    captured_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
    EOF

OBJECT BUNDLE (Layer 2 for branches):
12) git -C {PROJECT} bundle create {BUNDLE}/object-bundle.pack \
      --stdin <<< "refs/branch-rationalization-backup/*"

INDEX + README:
13) Write {BUNDLE}/index.tsv (one row per branch + per worktree).
14) Write {BUNDLE}/README.md with recovery recipes verbatim AND a cross-link to
    Axiom 7 (format-patch IS valid for branches; future readers from
    git-stash-janitor should not assume it's wrong).

VERIFY:
15) For each branch:
    live_sha = git -C {PROJECT} rev-parse refs/heads/{name}
    backup_sha = git -C {PROJECT} rev-parse refs/branch-rationalization-backup/{slug}
    [[ "$live_sha" == "$backup_sha" ]] || HALT "MISMATCH: {name}"

    live_diff_sha = git -C {PROJECT} diff --binary {merge_base}...{live_sha} | sha256sum
    bundle_diff_sha = sha256sum {BUNDLE}/branches/{slug}/diff-vs-merge-base.diff
    [[ same ]] || HALT "DIFF MISMATCH: {name}"

16) Bundle round-trip:
    git bundle list-heads {BUNDLE}/object-bundle.pack | awk '{print $2}' | sort \
      > {BUNDLE}/_bundle_heads.txt
    git -C {PROJECT} for-each-ref refs/branch-rationalization-backup/ \
      --format='%(refname)' | sort \
      > {BUNDLE}/_live_heads.txt
    diff {BUNDLE}/_bundle_heads.txt {BUNDLE}/_live_heads.txt \
      || HALT "BUNDLE HEAD MISMATCH"

Write all results to bundle_verification.log. ANY mismatch HALTS the run.

Required: zero MISMATCH lines in bundle_verification.log. The bundle is the
only thing standing between the user and lost work — treat it like radiation
shielding.
```

**Exit criteria:** every branch has backup ref + diff + format-patch + meta + commits.tsv; every worktree has staged + unstaged + untracked (if applicable) + status + meta; `object-bundle.pack` round-trips; `bundle_verification.log` has zero `MISMATCH` lines.

**Quote-bank anchors:**
- [SKILL.md Axiom 3](../SKILL.md#the-rationalization-kernel-universal-axioms): "Plan for irreversibility first, classification second."
- [SKILL.md Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms): "Beneficiary-style coherence: all five layers tell the same story."
- [SKILL.md Axiom 7](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git format-patch` IS valid for branches; it is NOT for stashes."

**Canonical tag:** `bundle`

---

## ⚠ CONFIRM

**Definition:** Restate the destructive command verbatim, wait for an explicit user-typed authorization in the same message, record the authorization text. From AGENTS.md "Mandatory explicit plan": "even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct."

**Triggers:**
- Phase 6 (gate) — before any commits would be authored
- Phase 7 (gate) — before harmonization-driven mutations
- Phase 8 (mid-phase) — when a manual conflict resolution is needed
- Phase 10 (gate) — before any `git worktree remove` / `git branch -d`/`-D` runs
- Phase 10 (sub-gate) — per-dirty-worktree force-removal authorization

**Inputs:**
- The destructive plan (verbatim commands + counts + what-will-be-affected)
- Any prior authorization text on file (per phase)

**Action:** display the plan as a markdown block; wait for user-typed text containing the authorization phrase; record into `cleanup_authorization.txt` (or analogous file) with UTC timestamp.

**Failure modes:**
- "I'll proceed if you say yes" — implicit; user might say "yes please continue with phase 10" without realizing they authorized 200 destructive operations
- Listing the count but not the verbatim commands — user can't audit what was authorized
- Assuming a prior authorization extends to a changed cleanup plan — if the bucket scope or command list changes, rebuild the plan and re-confirm
- Not restating the verbatim command at execution time (relying solely on the plan-level authorization) — bypasses Layer X5 of the safety model

**Prompt module:**
```
[OPERATOR: ⚠ CONFIRM]

Output to user EXACTLY:

> I'm about to {action}. Here are the verbatim commands in execution order:
>
>   {command_1}
>   {command_2}
>   ...
>
> {What will be affected, in plain English: e.g., "44 worktrees removed (3
>  protected stay); 181 branches deleted (6 protected stay; canonical and
>  rationalization branch stay). Backup refs at refs/branch-rationalization-backup/*
>  and the bundle at {BUNDLE} stay intact."}
>
> To proceed, paste this verbatim:
>   {authorization phrase including a literal command summary, e.g.,
>    "yes I understand and want to remove 44 worktrees and delete 181 branches per the plan above"}

Then WAIT. Do not continue until the user types text that includes the
authorization phrase. If they type something different, REFUSE and re-ask.

On receipt: write the user's exact text + UTC timestamp to
{WORKSPACE}/cleanup_authorization.txt (or _confirmation.txt for non-cleanup
gates).

At execution time (per command): restate the verbatim command immediately
before running it:
  About to run: git worktree remove /data/projects/foo-wt-cc-12
  (worktrees.tsv row: branch=agent-cc-12-feat-parser, dirty=3+1+2)

Required: the authorization file contains the user's literal text. Without
that file, treat the action as un-authorized.
```

**Exit criteria:** the relevant authorization file exists with the user's verbatim text + timestamp; per-command verbatim restatement is logged in `cleanup_log.tsv`.

**Quote-bank anchors:**
- AGENTS.md "Mandatory explicit plan": "Even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct."
- AGENTS.md "Document the confirmation": "If that record is absent, the operation did not happen."
- [SKILL.md Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Canonical tag:** `confirm`

---

## ◇ HARMONIZE — The Conceptual Centerpiece

**Definition:** For every file touched by ≥2 non-protected branches (or by any combination of branches + dirty worktrees), build the variant matrix; identify each variant's intent (defensive, refactor, test, fixture, type-narrowing, error-handling, performance, naming, instrumentation); propose a best-of-all-worlds synthesis on top of canonical's architecture; write it as the harmonization plan; the user reviews BEFORE Phase 8 mutates anything.

**This is the cognitive move that distinguishes this skill from `git-stash-janitor`.** A stash is a single diff: pick or drop. Branches collide on the same files in incompatible ways — picking is the wrong move; harmonizing is the right one.

> **Why:** [SKILL.md Axiom 1](../SKILL.md#the-rationalization-kernel-universal-axioms) — "For any file touched by more than one non-protected branch, the job is NOT to choose between competing variants. The job is to inspect every variant, reason about each part's intent, and synthesize the strongest current implementation on top of canonical's architecture. Output: best-of-all-worlds."

**Triggers:**
- Phase 7 — once, after triage merges and before any apply

**Inputs:**
- `triage.tsv` (filtered to non-protected, non-already-merged, non-garbage entries)
- The bundle's per-branch diffs and per-worktree dirty-state captures
- Canonical branch's current state for each colliding file

**Action:**

### Step 1: Identify colliding-file groups

From `triage.tsv` filtered to non-protected, non-already-merged, non-garbage entries plus dirty-worktree-only entries, build a multi-map: file → set of source-of-content (branch or dirty-worktree) touching that file. Any file with set size ≥ 2 is a colliding-file group.

### Step 2: Per-file variant matrix

For each colliding file, build the variant matrix:

```markdown
## File: src/parser.rs

| Variant            | Source                                        | Touched lines | Intent                                                |
|--------------------|-----------------------------------------------|---------------|-------------------------------------------------------|
| canonical (main)   | abc12 — `Parser::parse` baseline              | 1–500         | current architecture; baseline                        |
| agent-cc-12        | def45 — `Parser::parse_v3`                    | 120–145, 200–218 | introduces v3 parser with proper error handling     |
| agent-cc-77        | 789ab — `Parser::parse_v3_alt`                | 120–145, 250–280 | alternative v3 with stricter validation              |
| agent-cod-3        | f1e2c — `Parser::parse_v2_fix`                | 120–145       | defensive null-check for empty input                  |
| dirty:foo-wt-stale | unstaged — `Parser::parse_v3` + tracing logs  | 120–145, 320  | adds tracing instrumentation for debugging           |

### Intent groups

- **Defensive null-check** (cod-3 lines 120–145) — concrete bug fix; should always land
- **v3 architecture** (cc-12 lines 120–145, 200–218) — the more complete version; the one to base the synthesis on
- **Stricter validation** (cc-77 lines 250–280) — useful additional check, can be grafted onto cc-12's structure
- **Tracing instrumentation** (dirty lines 320) — useful but separable; goes in its own commit OR is dropped if the user doesn't want runtime tracing landed
```

### Step 3: Intent taxonomy

Each variant's contribution falls into one of these intent buckets (the planner uses this to decide what to graft, what to base on, what to drop):

| Intent | Description | Default action |
|--------|-------------|----------------|
| Defensive | Adds a null/bound/length/ownership/overflow check that wasn't there | Always graft |
| Refactor | Restructures existing code; same behavior, different shape | Pick the most complete refactor as the base; graft others' grafts onto it |
| Test | Adds a test case | Always include |
| Fixture | Adds test fixture content (corpus, golden file, mock data) | Always include if non-redundant |
| Type-narrowing | Tightens a type signature | Graft if compatible with the chosen base |
| Error-handling | Improves error path (better error messages, structured errors) | Graft if compatible; flag for user if it changes the public error type |
| Performance | Speeds up a hot path | Graft if benchmarks back the claim; surface to user otherwise |
| Naming | Renames symbols for clarity | Adopt the renames in the synthesis if the project's naming conventions agree |
| Instrumentation | Adds logging / tracing / metrics | Separate commit (often the user wants this gated by a flag, not always-on) |
| Compat-shim | Adds a backwards-compat wrapper | DROP per AGENTS.md "Backwards Compatibility": "We do not care about backwards compatibility" |

### Step 4: Propose a best-of-all-worlds synthesis on top of canonical

```markdown
### Proposed synthesis (lands on branch-rationalization-<DATE> as one focused commit)

  Take cc-12's `Parser::parse_v3` as the structural base.
  Graft cod-3's defensive null-check at line 122–124 (verbatim).
  Graft cc-77's stricter validation block at line 252–262 (re-flowed for v3 error type).
  Drop the tracing instrumentation (separable concern; user can add later).

### Why this beats any single variant

- cc-12 alone is missing cod-3's null-check (concrete bug fix).
- cc-77 alone has the stricter validation but on top of v2's structure (the wrong base).
- cod-3 alone fixes one bug but doesn't bring v3's improved error handling.
- Synthesis combines the strongest current implementation of each concern on top of canonical's architecture.

### Source-branch credit (for the commit message)

  cc-12 (v3 base), cod-3 (defensive null-check), cc-77 (stricter validation),
  rebased onto canonical's tip.
```

### Step 5: Write `harmonization_plan.md`

The full file is a sequence of these per-file blocks, plus a summary table at the top. The document IS the spec for Phase 8.

### Step 6: Present to user; wait for review BEFORE Phase 8 mutates anything

Common overrides:
- "Drop cc-77's stricter validation; that was abandoned for a reason."
- "The tracing instrumentation should land in its own commit on the rationalization branch — keep it."
- "src/auth.rs synthesis is too ambitious; just take cc-44 verbatim."

Capture overrides into `harmonization_plan.md` directly via the Edit tool — the document is the spec for Phase 8.

**Failure modes:**
- Picking instead of harmonizing (the most expensive failure) — reduces this skill to "stash-janitor for branches"
- Picking the wrong base — building the synthesis on canonical's architecture is non-negotiable; never base on a branch's architecture even if it looks "more complete"
- Forgetting to credit source branches in the commit message — the user can't trace where a hunk came from
- Synthesizing via sed/awk/regex transformations — per AGENTS.md "No Script-Based Changes", manual Edit-tool resolution only
- Skipping the user-review gate — Phase 7 IS a gate; the user MUST review before Phase 8 mutates anything
- Trying to harmonize 50 variants in one commit — split into focused per-file commits; one synthesis per colliding-file group

**Prompt module:**
```
[OPERATOR: ◇ HARMONIZE]

Inputs: triage.tsv (non-protected, non-already-merged, non-garbage filter applied),
        bundle path, canonical branch name.

PHASE A — Identify colliding-file groups:
1) Build multi-map: file → set of source-of-content touching it.
2) Filter to set size ≥ 2.

PHASE B — Per-file variant matrix:
For each colliding file:
3) Open canonical's current version (git show canonical:{file}).
4) Open each variant's version (from the bundle's per-branch diff or per-worktree
   staged.diff + unstaged.diff, applied virtually).
5) Diff each variant against canonical; identify the touched-lines ranges.
6) For each touched range, classify the variant's intent per the intent taxonomy
   (defensive, refactor, test, fixture, type-narrowing, error-handling,
   performance, naming, instrumentation, compat-shim).
7) Write the variant matrix table.

PHASE C — Intent grouping + synthesis design:
8) Group the touched ranges by intent (multiple variants may contribute to the
   same intent, e.g., two branches both adding null-checks; pick the strongest
   one or merge them).
9) Pick a base architecture: the variant whose refactor most closely matches
   canonical's direction OR canonical itself if all variants are accretive.
10) Plan the grafts: defensive checks, type-narrowing, tests, fixtures all
    layered onto the base. Drop compat-shims and instrumentation by default
    (instrumentation is separable; surface to user as an opt-in commit).

PHASE D — Write harmonization_plan.md:
11) Top-of-file summary table:
    | File | Variants | Synthesis strategy | Phase 8 strategy |
12) Per-file block:
    - Variant matrix (Step 7)
    - Intent groups (Step 8)
    - Proposed synthesis (Step 10)
    - Why this beats any single variant
    - Source-branch credit (for the commit message)

PHASE E — User review (GATE):
13) Present harmonization_plan.md to the user.
14) Wait for user OK. If the user edits the plan via the Edit tool, the edited
    version IS the spec.
15) If the user disagrees with the synthesis design, capture overrides directly
    into harmonization_plan.md and re-display.

Phase 8 reads harmonization_plan.md and applies each per-file synthesis as a
single focused commit on the rationalization branch via the Edit tool (per
AGENTS.md "No Script-Based Changes", manual Edit-tool resolution only).

Required: harmonization_plan.md exists; user has typed OK (or edited the plan);
every colliding-file group has a per-file block; every block has a synthesis
proposal AND a "why this beats any single variant" section.
```

**Exit criteria:** `harmonization_plan.md` exists, user has reviewed and OK'd (or edited), Phase 8 has its spec.

**Quote-bank anchors:**
- [SKILL.md Axiom 1](../SKILL.md#the-rationalization-kernel-universal-axioms): "Harmonize, don't pick. The cognitive move stash-janitor doesn't have to make."
- [SKILL.md Axiom 6](../SKILL.md#the-rationalization-kernel-universal-axioms): "Land on a rationalization branch, not on canonical."
- AGENTS.md "No Script-Based Changes": "Always make code changes manually, even when there are many instances."
- AGENTS.md "Backwards Compatibility": "We do not care about backwards compatibility... Never create compatibility shims."

**Canonical tag:** `harmonize`

---

## ✧ CHERRY-PICK

**Definition:** Apply a single commit (or small set of commits) from a branch via `git cherry-pick`, with `--no-commit` dry-run first; only on clean dry-run do we actually pick. Per-keeper gates run after.

**Triggers:**
- Phase 8, when `triage.tsv:strategy == cherry-pick`
- Phase 8b, for partial-novel split-commits-hunks (cherry-picks the novel subset)

**Inputs:**
- Branch SHA (or set of SHAs)
- Rationalization branch (the apply target)

**Failure modes:**
- `git cherry-pick` of a merge commit produces an unhelpful first-parent diff — use `-m 1` (or the appropriate parent number); document the choice in the commit message
- `git cherry-pick` of a commit whose changes were squash-merged onto canonical produces "nothing to commit" — `cherry -v` should have flagged this with `-`; classify as `already-merged` and skip; if mid-pick, `git cherry-pick --skip`
- Skipping `--no-commit` dry-run — same end-state as a failed pop in stash-janitor
- Forgetting per-keeper quality gates after the pick — compounding errors slip through (Axiom 13)

**Prompt module:**
```
[OPERATOR: ✧ CHERRY-PICK]

Inputs: branch_sha, rationalization_branch_tip.

1) Apply with `--no-commit` on the rationalization branch:
   git -C {PROJECT} cherry-pick --no-commit {branch_sha}
   - exit 0: clean apply, files staged; commit the staged result with source
     branch credit.
   - exit non-zero: STOP. Engage the conflict-surface flow:
     - Show the user the diff
     - Show the user the affected files' current state on the rationalization branch
     - Hypothesize the cause (refactor / rename / file move)
     - Propose an Edit-tool resolution that preserves the branch's INTENT
     - Wait for explicit OK before proceeding.
     - Abort the failed cherry-pick state with `git cherry-pick --abort` only.

   For merge commits, use `-m 1` (or appropriate parent number) and document why.

2) Run quality gates per ⊕ RECOVER. ALL must exit 0.

3) Commit message: focused, explains the *why*, cites source branch.

Never use `git cherry-pick --allow-empty` to skip cherry-empty rejects;
those are Axiom 17 already-merged signals — flip the verdict to
`superseded-during-apply` and skip.

Required: clean `--no-commit` apply; gates pass; commit message cites source.
```

**Exit criteria:** new commit on rationalization branch; gates passed; `apply_log.tsv` row.

**Quote-bank anchors:**
- [SKILL.md Operator table](../SKILL.md#operator-library--the-cognitive-moves): "✧ CHERRY-PICK — single-commit and small-coherent branches."
- [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms): per-apply gates non-negotiable.
- [FAILURE-MODES.md § "merge-commit-cherry-pick"](FAILURE-MODES.md).

**Canonical tag:** `cherry-pick`

---

## ⊟ SQUASH-MERGE

**Definition:** Squash-merge a branch's content as one focused commit on the rationalization branch. Used when `project_profile.json:merge_style == squash` and the branch is small-coherent enough to be one logical unit.

**Triggers:**
- Phase 8, when `triage.tsv:strategy == squash-merge`

**Inputs:**
- Source branch name
- Rationalization branch (the apply target)

**Failure modes:**
- Squashing a branch with multiple distinct concerns into one commit — loses the per-concern story; the user can't cherry-pick a subset later. If the branch is multi-concern, use rebase-and-merge or split-commits-hunks.
- Forgetting `--no-commit` on the squash — git creates the squash but doesn't commit; the working tree is left staged; the user thinks the merge is done.
- Not authoring a commit message that explains the squashed contents — the source branch's commit history is lost, so the new commit's message must compensate.

**Prompt module:**
```
[OPERATOR: ⊟ SQUASH-MERGE]

Inputs: source_branch, rationalization_branch.

1) Confirm we're on the rationalization branch:
   git -C {PROJECT} symbolic-ref --short HEAD
   # must equal rationalization_branch

2) Squash:
   git -C {PROJECT} merge --squash {source_branch}
   # If conflicts, surface to user (per ⚠ CONFIRM); never auto-resolve.

3) Run quality gates per ⊕ RECOVER. ALL must exit 0.

4) Commit with a focused message that:
   - Starts with a present-tense verb (recover, restore, integrate)
   - Cites the source branch and its commit count
   - Summarizes what the squashed content does (the per-commit history is lost,
     so the new commit's message must compensate)
   - Does NOT include Co-Authored-By unless explicitly requested

Required: clean merge; gates pass; commit message compensates for lost
per-commit history.
```

**Exit criteria:** new squashed commit on rationalization branch; gates passed; `apply_log.tsv:strategy == squash-merge`.

**Quote-bank anchors:**
- [SKILL.md Operator table](../SKILL.md#operator-library--the-cognitive-moves): "⊟ SQUASH-MERGE — for small-coherent branches when the project's preferred merge style is squash."

**Canonical tag:** `squash-merge`

---

## ⊠ REBASE-AND-MERGE

**Definition:** Rebase the branch onto the rationalization-branch tip, surface conflicts, then merge with `--no-ff` (or project style). For large-and-meaningful branches whose per-commit story is worth preserving.

**Triggers:**
- Phase 8, when `triage.tsv:strategy == rebase-and-merge`
- Always for branches with ≥3 commits whose per-commit story is meaningful (each commit is its own logical unit)

**Inputs:**
- Source branch name
- Rationalization branch tip

**Failure modes:**
- Rebasing a branch whose upstream was force-pushed produces nonsense output — inspect the reflog before rebasing; refuse if the upstream's history shows divergent rewrites ([FAILURE-MODES.md § "rebase-after-force-push"](FAILURE-MODES.md))
- Rebasing without `--no-ff` on a project that prefers merge commits — produces fast-forward; the rationalization branch loses the integration commit
- Not running gates per-commit during rebase — compounding errors per Axiom 13

**Prompt module:**
```
[OPERATOR: ⊠ REBASE-AND-MERGE]

Inputs: source_branch, rationalization_branch.

1) Pre-flight: check the source branch's reflog for force-push history.
   If divergent rewrites are present, refuse and surface to user.

2) Stay on the rationalization branch. Do NOT checkout or rebase the source
   branch; another agent may still be using it. Replay the source branch's
   commits in merge-base order onto the rationalization tip:
   git -C {PROJECT} cherry-pick {merge_base}..{source_branch}
   # Conflicts surface here; engage conflict-surface flow per ⚠ CONFIRM.

3) Run per-commit gates after each replayed commit. Any failure surfaces to the
   user with the just-created commit SHA and source branch.

4) Run final quality gates per ⊕ RECOVER on the replayed sequence. ALL must exit 0.

Required: source branch remains byte-identical to its backup ref; replay clean;
per-commit gates pass; final gates pass.
```

**Exit criteria:** rationalization branch advanced by N commits + 1 merge commit; all gates passed; `apply_log.tsv:strategy == rebase-and-merge`.

**Quote-bank anchors:**
- [SKILL.md Operator table](../SKILL.md#operator-library--the-cognitive-moves): "⊠ REBASE-AND-MERGE — for large-and-meaningful branches."
- [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms): per-apply gates.

**Canonical tag:** `rebase-and-merge`

---

## ⇄ SPLIT-COMMITS-HUNKS

**Definition:** For partially-novel branches, identify the subset of commits (or hunks within commits) that are novel; cherry-pick that subset in dependency order; drop the superseded ones.

**Triggers:**
- Phase 8b, per `partially-novel` row in `triage.tsv`

**Inputs:**
- Branch's commit list (`<bundle>/branches/<slug>/commits.tsv`)
- Per-commit verdicts (from `commit_breakdown` sidecar JSON if present, else re-fingerprint per commit)

**Failure modes:**
- Trying to use `git apply --include=<path>` for hunk-level filtering — `--include` is path-level, not hunk-level
- Editing the diff with ad hoc sed/awk/regex transformations — brittle; per AGENTS.md "No Script-Based Changes", manual Edit-tool only. Phase 8b's `partial-splitter` subagent may use exact commit lists, but it does not mechanically rewrite source files.
- Forgetting to run apply-check after each individual cherry-pick — compounding errors

**Prompt module:**
```
[OPERATOR: ⇄ SPLIT-COMMITS-HUNKS]

Inputs: branch_slug, commit_breakdown (per-commit verdicts).

1) From commit_breakdown (or re-fingerprint per commit), identify the novel
   commit subset. Maintain dependency order (novel commit B may depend on
   superseded commit A's content; if so, the dependency is already on canonical
   and the cherry-pick will succeed).

2) Cherry-pick contiguous novel ranges:
   git cherry-pick {start_sha}..{end_sha}
   # Or for scattered:
   git cherry-pick {sha_1} {sha_2} {sha_5}

3) For commits that are partially novel (some hunks novel, some superseded):
   git cherry-pick --no-commit {sha}
   # Use the Edit tool to remove the superseded hunks from the working tree
   # before committing.
   # Per AGENTS.md "No Script-Based Changes": no sed/awk/regex.

4) Run quality gates per ⊕ RECOVER on each commit (`git rebase --exec` if
   cherry-picking a range).

5) Append to partial_split_log.tsv:
   branch_slug, commits_kept, commits_dropped, hunks_kept, hunks_dropped,
   new_commit_shas

6) Commit messages explicitly note "split-apply: novel commits/hunks only;
   superseded portions dropped per triage row":

     recover novel fuzz-corpus additions from agent-cc-44-parser-refactor

     The parser refactor portion of agent-cc-44 already landed via PR #234
     (cherry -v shows commits 1–3 as `-`). This commit recovers only the novel
     fuzz-corpus and overflow test additions (commits 5, 7, 8 of the
     original branch).

     Recovered via: split-apply per partial_split_log.tsv
     Source branch backed up at: refs/branch-rationalization-backup/agent-cc-44

Required: every novel commit applied OR explicitly skipped; gates pass;
commit messages cite the split.
```

**Exit criteria:** every novel commit on the rationalization branch; `partial_split_log.tsv` row; gates passed.

**Quote-bank anchors:**
- [SKILL.md Operator table](../SKILL.md#operator-library--the-cognitive-moves): "⇄ SPLIT-COMMITS-HUNKS — for partially-novel branches."
- AGENTS.md "No Script-Based Changes".

**Canonical tag:** `split-commits-hunks`

---

## ⊕ RECOVER

**Definition:** Run the project's actual quality gates (test + typecheck + lint + UBS) on every Phase 8 apply. Catch compounding errors per-keeper, not at the end.

**Triggers:**
- Phase 8, after every successful apply (cherry-pick / squash-merge / rebase-and-merge / harmonized-synthesis / split-commits-hunks / dirty-state apply)
- Phase 8b, after every successful split-apply

**Inputs:**
- `project_profile.json:test_command`, `:typecheck_command`, `:lint_command`, `:format_command`
- The just-applied commit SHA

**Failure modes:**
- Running gates only at the end of Phase 8 — by the time something fails, you don't know which apply caused it (Axiom 13)
- Running a subset of gates ("we'll skip clippy this time") — UBS or clippy might be the only thing that catches an unwrap that passed the test suite
- Silent fallback when a gate isn't installed — record `skipped` in the log, surface to the user; don't pretend the gate ran
- Bypassing pre-commit hooks (`--no-verify`) — the user's gates exist for a reason ([SKILL.md Anti-Patterns](../SKILL.md#anti-patterns-never-do))

**Prompt module:**
```
[OPERATOR: ⊕ RECOVER]

After every successful apply, in this exact order:

1) {test_command}
2) {typecheck_command}
3) {lint_command}
4) ubs .   # if available
5) Any project-specific gate from project_profile.json (e.g., a regression
   harness, golden-file diff).

Each must exit 0. Capture exit code + duration in apply_log.tsv:gates_status.

If any gate fails:
- Do NOT commit (or, if already committed, surface the failure and ask user
  whether to roll back via git reset --soft HEAD~1).
- Try to reverse only the just-applied content (git reset --soft HEAD~1 if the
  commit hasn't been pushed; never `git reset --hard`).
- Surface to the user with the gate's output and the affected branch.
- Wait for direction.

Required: gates_status == "passed" before considering the apply complete.
No "we'll fix it later". No --no-verify.
```

**Exit criteria:** `apply_log.tsv:gates_status == passed` for every applied row; or, if `pre-existing-ok: <user-text>`, the user's verbatim authorization is captured.

**Quote-bank anchors:**
- [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms): "Per-apply gates are non-negotiable."
- [SKILL.md Anti-Patterns](../SKILL.md#anti-patterns-never-do): "Bypass pre-commit hooks (`--no-verify`)."

**Canonical tag:** `recover`

---

## ⊞ RE-FINGERPRINT

**Definition:** After every successful Phase 8 apply, re-run FINGERPRINT/VERIFY-ON-CANONICAL on downstream keep candidates. Some now flip to `superseded-during-apply` because the just-applied content covers their fingerprint.

**Triggers:**
- Phase 8, between applies

**Inputs:**
- Remaining novel-and-accretive / partially-novel / dirty-worktree-only rows in `triage.tsv`
- The rationalization branch's current tip (the just-applied commit)

**Failure modes:**
- Skipping re-fingerprint — apply two branches that introduce the same symbol, get a duplicate-definition build break ([FAILURE-MODES.md § "duplicate-symbol"](FAILURE-MODES.md))
- Re-fingerprinting against canonical instead of the rationalization branch's HEAD — misses the just-applied content
- Re-fingerprinting against `origin/<canonical>` (which may be ahead of local canonical) — produces stale results

**Prompt module:**
```
[OPERATOR: ⊞ RE-FINGERPRINT]

After committing keeper k, before apply-checking keeper k+1:

For every remaining novel-and-accretive / partially-novel / dirty-worktree-only
row in triage.tsv:
  Run VERIFY-ON-CANONICAL with canonical_branch = HEAD (the rationalization
  branch's tip; NOT origin/canonical).
  If fingerprint_coverage now ≥ 0.8: flip verdict to `superseded-during-apply`.
  Append the flip to apply_log.tsv with a note explaining which prior keeper
  superseded it.

This ensures dependency-ordered duplicates don't both apply.
Required: no two keepers introduce the same fingerprint without explicit
user OK (e.g., the user might want both intentionally).
```

**Exit criteria:** every remaining keeper's verdict reflects the latest rationalization-branch state; no duplicate-definition build break.

**Quote-bank anchors:**
- [SKILL.md Operator table](../SKILL.md#operator-library--the-cognitive-moves): "⊞ RE-FINGERPRINT — After every successful Phase 8 apply, re-run FINGERPRINT/VERIFY-ON-CANONICAL on downstream keep candidates."

**Canonical tag:** `re-fingerprint`

---

## ↺ WORKING-TREE-DRIFT

**Definition:** Re-snapshot `git status` in every active worktree before each Phase 8 apply. If changes appear from concurrent agents, treat as if you made them. Per AGENTS.md "Note for Codex/GPT-5.5": never stash, revert, or overwrite.

**Triggers:**
- Phase 8, every iteration (before each apply)
- Phase 10, before each `git worktree remove` (via `🌳 WORKTREE-CHECK`)

**Inputs:**
- Active worktree paths (from `worktrees.tsv`, post-protection)
- Phase 0 baseline `wt_phase0.txt`

**Failure modes:**
- Asking the user "I see unexpected changes, please advise" — explicitly prohibited by AGENTS.md "Note for Codex/GPT-5.5"
- Stashing concurrent agents' changes "to clean up" — destroys their work
- Running `git checkout -- .` — same destruction with extra steps
- Running `git reset --hard` to "get a clean start" — catastrophic; AGENTS.md "Irreversible Git & Filesystem Actions" forbids it

**Prompt module:**
```
[OPERATOR: ↺ WORKING-TREE-DRIFT]

Before each Phase 8 apply (and before each Phase 10 destructive operation):

1) For each active worktree path P (from worktrees.tsv minus protected.tsv
   minus already-removed-in-Phase-10):
     (cd P && git status --porcelain=v2) > {WS}/wt_pre_apply_{n}_{wt_slug}.txt
     (cd P && git diff --stat) >> {WS}/wt_pre_apply_{n}_{wt_slug}.txt

2) Compare against wt_phase0.txt for the same path.

3) If new files / changes appear that you did not author this iteration:
   - These are concurrent agents' work. Per AGENTS.md, treat as if you made them.
   - DO NOT stash, revert, or overwrite.
   - DO NOT ask the user to "advise on unrelated modified files".
   - Proceed with the apply. The 3-way merge will handle context.
   - Note in apply_log.tsv:pre_apply_drift = "concurrent: <files>".

4) If the apply CONFLICTS with concurrent changes:
   - Surface to the user. Don't auto-resolve; the user knows context you don't.

Required: never disturb concurrent agents' state. Never run any of:
  - git stash
  - git reset --hard
  - git clean -fd
  - git checkout -- .
  - rm -rf
```

**Exit criteria:** `apply_log.tsv:pre_apply_drift` notes any concurrent changes; the apply proceeds without disturbing them.

**Quote-bank anchors:**
- AGENTS.md "Note for Codex/GPT-5.5": "you NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents."
- [SKILL.md Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms).
- AGENTS.md "Irreversible Git & Filesystem Actions": "`git reset --hard`, `git clean -fd`, `rm -rf`, … must never be run."

**Canonical tag:** `working-tree-drift`

---

## ⊙ PRUNE-WORKTREE

**Definition:** Remove a worktree directory via `git worktree remove <path>` (NOT `rm -rf`). Dirty state is archived in the bundle first via `🌳 WORKTREE-CHECK`. Force-remove (`--force`) only after explicit user OK that the dirty state may be lost. After all explicit removals, run `git worktree prune` to clean residual admin metadata for any worktrees deleted out-of-band.

**Triggers:**
- Phase 10 Phase A — per non-protected worktree
- Phase 10 Phase A end — `git worktree prune` for residual metadata

**Inputs:**
- Worktree path
- The worktree's bundle entry (verified by `🌳 WORKTREE-CHECK` immediately prior)

**Failure modes:**
- Using `rm -rf <path>` instead of `git worktree remove <path>` — DCG blocks `rm -rf` AND it doesn't prune `.git/worktrees/<id>/` admin metadata ([SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms))
- Running `git worktree prune` as a substitute for `git worktree remove` — `prune` only cleans admin metadata; doesn't structurally remove a working tree (Axiom 9)
- Force-removing without bundle verification — loses uncommitted work
- Removing the currently-active worktree (the user's CWD) from inside — git refuses; the skill enforces this independently; the active worktree is auto-protected
- Removing a worktree pinned to a branch that's still needed for Phase B (branch deletion ordering); but Phase 10's Phase A → Phase B ordering enforces this — worktrees are removed FIRST so branches are freed for `git branch -d`

**Prompt module:**
```
[OPERATOR: ⊙ PRUNE-WORKTREE]

Inputs: worktree path P, bundle entry verified per 🌳 WORKTREE-CHECK.

1) Confirm 🌳 WORKTREE-CHECK passed for this worktree.

2) Restate verbatim:
   About to run: git worktree remove {P}
   (worktrees.tsv row: branch={branch}, dirty={tracked_changed}+{staged}+{untracked})

3) Try clean removal:
   git -C {PROJECT} worktree remove {P}
   - exit 0: worktree removed AND .git/worktrees/<id>/ pruned. Done.
   - exit non-zero (refuses on dirty worktree): proceed to step 4.

4) If the worktree is dirty AND the bundle has its dirty-state captures:
   - Get a sub-authorization from the user (separate from the plan-level
     Phase 10 authorization):
       This worktree has uncommitted changes:
         {P}   ({tracked_changed} tracked, {staged} staged, {untracked} untracked)
      The dirty state IS captured in the bundle at:
        {BUNDLE}/worktrees/{wt_slug}/{staged.diff,unstaged.diff,.untracked.list,untracked.tar.gz}
       About to run: git worktree remove --force {P}
       To proceed, paste this verbatim:
         yes I understand the dirty state is captured in the bundle and I want to force-remove this worktree
   - On verbatim auth: git worktree remove --force {P}
   - Record in cleanup_log.tsv with `force=true`.

5) Append to cleanup_log.tsv:
   phase=A, kind=worktree, target={P}, verdict={verdict},
   command_run=<actual command>, backup_ref={BUNDLE}/worktrees/{wt_slug},
   timestamp_utc=<now>, notes=<removed|remove-refused>

6) After ALL Phase A removals complete, run:
   git -C {PROJECT} worktree prune
   # Cleans residual admin metadata for any worktrees that were deleted
   # out-of-band before this skill ran.

NEVER:
- rm -rf <P> (DCG blocks; admin metadata persists)
- git worktree prune as a substitute for git worktree remove
- Remove the currently-active worktree from inside (git refuses; respect that)
- Force-remove without bundle verification (the dirty state would be lost
  with no recovery story)

Required: worktree removed; .git/worktrees/<id>/ pruned (either by `remove`
or by the final `prune`); cleanup_log.tsv row written.
```

**Exit criteria:** worktree directory gone; admin metadata pruned; `cleanup_log.tsv` row.

**Quote-bank anchors:**
- [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms): "Worktrees are removed first, branches second."
- [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms): "`rm -rf <worktree-path>` is forbidden; `git worktree remove` is the structured operation."

**Canonical tag:** `prune-worktree`

---

## ⊘ DELETE-BRANCH

**Definition:** The highest-risk individual operation. Delete a branch via `git branch -d <name>` (preferred — refuses to delete unmerged branches) or `git branch -D <name>` (only when the user has explicitly acknowledged the branch as unmerged-and-discardable). Gated on backup ref existence + verbatim authorization. Order: garbage → superseded → already-merged → novel-stale → divergent-refactor (opt-in) → applied-keepers.

**Triggers:**
- Phase 10 Phases B–G, after all Phase A worktree removals complete

**Inputs:**
- Branch name
- Verdict (drives the bucket / phase letter)
- The branch's backup ref under `refs/branch-rationalization-backup/<slug>` (must exist)
- Plan-level cleanup authorization from `cleanup_authorization.txt`

**Failure modes:**
- Using `git branch -D` when `-d` would work — `-d`'s refusal-on-unmerged is a built-in safety check ([SKILL.md Axiom 8](../SKILL.md#the-rationalization-kernel-universal-axioms))
- Deleting an "applied-keeper" branch before its commit lands on the rationalization branch AND the rationalization branch passes Phase 9 — loses content if the apply gets rolled back
- Running `git branch | xargs git branch -D` (or any mass-delete primitive) — bypasses verbatim authorization, can delete protected branches, no per-deletion logging ([SKILL.md Axiom 10](../SKILL.md#the-rationalization-kernel-universal-axioms))
- Running `git branch -d` on the currently-checked-out branch — git refuses; the active branch is auto-protected anyway
- Forgetting to verify the backup ref before deletion — if the backup ref is missing (e.g., deleted out-of-band by a confused agent), the deletion is irreversible from Layer 1

**Prompt module:**
```
[OPERATOR: ⊘ DELETE-BRANCH]

Inputs: branch_name, verdict (= bucket), bundle path, plan-level authorization
from cleanup_authorization.txt.

1) Pre-flight checks:
   - branch_name is NOT in protected.tsv. If it is, REFUSE.
   - branch_name is NOT canonical. If it is, REFUSE.
   - branch_name is NOT the rationalization branch. If it is, REFUSE.
   - branch_name is NOT currently-checked-out. If it is, REFUSE.
   - refs/branch-rationalization-backup/<slug> exists. If not, HALT and surface.
   - Phase A (worktree removal) is complete. If not, HALT.

2) Determine the bucket / phase letter from the verdict:
     garbage              → Phase B
     superseded           → Phase C
     already-merged       → Phase D
     novel-stale          → Phase E (opt-in)
     divergent-refactor   → Phase F (opt-in, off by default)
     applied-keeper       → Phase G

3) Pick the deletion command:
   - If the branch is fully merged into the rationalization branch's tip:
       git -C {PROJECT} branch -d {branch_name}
   - Else, only if the user explicitly acknowledged the branch as
     unmerged-and-discardable OR patch-id/squash-equivalent already present on
     canonical (in cleanup_authorization.txt):
       git -C {PROJECT} branch -D {branch_name}
   - Try `-d` first; if it refuses with "not fully merged", fall back to `-D`
     ONLY when the verdict and authorization make the branch safe to force:
     garbage/novel-stale/divergent-refactor, or already-merged with
     cherry/patched-equivalent evidence.

4) Restate verbatim:
   About to run: git branch -d {branch_name}
   (verdict={verdict}; backup ref refs/branch-rationalization-backup/{slug} exists)

5) Run the deletion. Append to cleanup_log.tsv:
   phase=<letter>, kind=branch, target={branch_name}, verdict={verdict},
   command_run=<actual>, backup_ref=refs/branch-rationalization-backup/{slug},
   timestamp_utc=<now>, notes=<deleted|delete-d-refused-unmerged|delete-D-failed>

6) NEVER:
   - git branch | xargs git branch -D
   - git for-each-ref refs/heads | … -D
   - find /data/projects -name '<pattern>' -exec git branch -D {} \;
   - git update-ref -d refs/branch-rationalization-backup/<slug>
   - Delete the bundle

Required: backup ref still resolves AFTER deletion; cleanup_log.tsv row;
verbatim restatement logged.
```

**Exit criteria:** branch ref gone from `refs/heads/`; backup ref still resolves; `cleanup_log.tsv` row.

**Quote-bank anchors:**
- [SKILL.md Axiom 8](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git branch -d` over `git branch -D` whenever possible."
- [SKILL.md Axiom 10](../SKILL.md#the-rationalization-kernel-universal-axioms): "Mass-delete primitives are forbidden."
- AGENTS.md "RULE NUMBER 1: NO FILE DELETION" (extends to refs as a discipline).

**Canonical tag:** `delete-branch`

---

## ⌘ HANDOFF

**Definition:** Emit the final report with everything the user needs to (a) understand what changed, (b) push the rationalization branch, (c) recover from any deletion or removal they regret.

**Triggers:**
- Phase 11 — once, at end of run

**Inputs:**
- All log files: `apply_log.tsv`, `partial_split_log.tsv`, `cleanup_log.tsv`, `triage.tsv`, `harmonization_plan.md`, `protected.tsv`
- Bundle path
- Rationalization branch name
- Project profile

**Failure modes:**
- Reporting counts only, no SHAs — user can't see what landed
- Forgetting the recovery recipes — user has the bundle but no idea how to use it
- Pushing the rationalization branch — every example skill in this repo treats deployment as the user's call ([SKILL.md "What This Skill Produces"](../SKILL.md#what-this-skill-produces))
- Forgetting to mention the active worktree is the user's responsibility to remove (the skill never removes the user's CWD)
- Forgetting bundle-lifecycle guidance — the user might `rm -rf` the bundle right after the run

**Prompt module:**
```
[OPERATOR: ⌘ HANDOFF]

Read: apply_log.tsv, partial_split_log.tsv, cleanup_log.tsv, triage.tsv,
harmonization_plan.md, protected.tsv.

Emit handoff_report.md with these sections (in order):
  1. Project + run date + mode + rationalization branch + bundle path
  2. Counts per verdict (initial → triaged → applied → removed → final)
     - separate counts for branches and worktrees
  3. Recovered commits table (sha, source(s), strategy, message)
  4. Harmonization summary (file, variants merged, result)
  5. Conflict resolutions (if any) — context paths
  6. Recovery recipes (verbatim per-layer commands, per-branch and per-worktree;
     see RECOVERY-RECIPES.md for the full catalog)
  7. Push instructions: `git push origin {rationalization_branch}`; user pushes.
  8. Active-worktree note: the skill did NOT remove the user's CWD. The user
     removes that themselves from a different working directory if they want to.
  9. Bundle lifecycle: keep for ≥1 release cycle; user manages deletion via
     a regular `mv` (not `rm -rf` — DCG would block it and the skill never
     advises bypassing DCG).

File a beads issue: br create --title "branch+worktree rationalization on
{project} ({W} worktrees, {B} branches)" --type=task --priority=4.
The body links to the report, the bundle, and the rationalization branch.

Update Mail thread (thread_id=branch-rationalization-<run-id>).

If bv available: bv --robot-triage; append summary.

Print the push command verbatim. NEVER push.

Required: handoff_report.md exists with all sections; beads issue filed; user
told the push command.
```

**Exit criteria:** `handoff_report.md` exists; beads issue filed; user has the push command + active-worktree note + bundle-lifecycle guidance.

**Quote-bank anchors:**
- [SKILL.md "The skill never"](../SKILL.md#what-this-skill-produces): "Pushes the rationalization branch — that's the user's call."
- [SKILL.md Axiom 18](../SKILL.md#the-rationalization-kernel-universal-axioms): "Drop the bundle only at the user's pace."

**Canonical tag:** `handoff`

---

## Operator Composition Cheat-Sheet

For each phase, the canonical operator order:

| Phase | Operator sequence |
|-------|-------------------|
| 0 | (intake; no operators) |
| 1 | (profiling; no operators) |
| 2 | `★ INVENTORY` |
| 3 | `⬡ BUNDLE` (the gate; no other operators) |
| 4 | `🔒 PROTECT` (the gate) |
| 5 | `✦ FINGERPRINT` → `◐ VERIFY-ON-CANONICAL` (per branch / dirty-worktree) |
| 6 | `⚠ CONFIRM` (the user gate) |
| 7 | `◇ HARMONIZE` (the conceptual centerpiece) → `⚠ CONFIRM` |
| 8 | `↺ WORKING-TREE-DRIFT` → `⊞ RE-FINGERPRINT` → (one of: `✧ CHERRY-PICK` / `⊟ SQUASH-MERGE` / `⊠ REBASE-AND-MERGE` / `◇ HARMONIZE`-driven Edit / `⇄ SPLIT-COMMITS-HUNKS`) → `⊕ RECOVER` (per keeper) |
| 8b | `⇄ SPLIT-COMMITS-HUNKS` → `⊕ RECOVER` (per partial) |
| 9 | (fresh-eyes; no operators — the prompts are themselves the methodology) |
| 10 | `⚠ CONFIRM` (plan-level gate) → `🌳 WORKTREE-CHECK` → `⊙ PRUNE-WORKTREE` (Phase A, per worktree) → `⊘ DELETE-BRANCH` (Phases B–G, per branch in bucket order) |
| 11 | `⌘ HANDOFF` |
| 12 | (optional user-lens review; no operators) |

Operators are deliberately overlapping — a single Phase 8 apply typically deserves four (`↺`, `⊞`, the strategy-specific operator, `⊕`). When composing, run them in the order above; each consumes the previous one's output.

The conceptual order of dependency:
- `⬡ BUNDLE` (Phase 3) is the irreversibility gate that everything destructive depends on.
- `🔒 PROTECT` (Phase 4) is the keep-forever set that filters Phase 5 input.
- `✦ FINGERPRINT` + `◐ VERIFY-ON-CANONICAL` (Phase 5) produce the verdict input for the rubric.
- `⚠ CONFIRM` (Phases 6, 7, 8, 10) is the user-gate Layer X1 of the safety model.
- `◇ HARMONIZE` (Phase 7) is the conceptual centerpiece that drives Phase 8's harmonized-synthesis applies.
- `↺ WORKING-TREE-DRIFT` (Phase 8) protects concurrent agents per AGENTS.md.
- `⊞ RE-FINGERPRINT` (Phase 8) prevents duplicate-symbol applies.
- `⊕ RECOVER` (Phase 8) catches per-apply regressions.
- `🌳 WORKTREE-CHECK` (Phase 10) confirms bundle currency before each removal.
- `⊙ PRUNE-WORKTREE` (Phase 10 Phase A) frees pinned branches before deletion.
- `⊘ DELETE-BRANCH` (Phase 10 Phases B–G) is the highest-risk individual operation; gated by all prior layers.
- `⌘ HANDOFF` (Phase 11) closes the loop with the user.

---

## Round-3 operators — rigor + operational depth

These 17 operators were added when the skill was extended with rigor / verification / operational-depth references. They compose with the core 18 above. Each card is brief — the deep treatment is in the per-topic reference (e.g., `🛡 AUDIT-AFTER` cards back to [AUDIT-AFTER-RUN.md](AUDIT-AFTER-RUN.md), `🔬 PROVENANCE` to [PROVENANCE-CHAIN.md](PROVENANCE-CHAIN.md), etc.).

### `👁 DRY-RUN`

**Trigger.** User passed `--dry-run`, OR Comprehensive/Council mode kicks it on by default at Phase 7.5.
**Inputs.** `triage.tsv`, `harmonization_plan.md`, `branches.tsv`, `worktrees.tsv`, `protected.tsv`.
**Action.** Predict every Phase 8 + Phase 10 action without executing. Emit `dry_run_report.md` (markdown for user review) and `expected_outcomes.json` (machine-readable for actual-run divergence detection).
**Prompt module.** "For each row in `triage.tsv`, simulate the apply per the strategy column. Produce: predicted commit message, predicted conflict surface (via `git merge-tree`), predicted gate outcome. For each worktree-removal and branch-deletion in Phase 10, produce the verbatim command + protected-status check + disk-freed estimate. Never execute any of the predicted commands."
**Exit criteria.** `dry_run_report.md` covers every triage row + every Phase 10 cleanup row; `expected_outcomes.json` validates against schema; user has reviewed.
**Failure modes.** If the actual Phase 8 produces a SHA, conflict, or commit message different from `expected_outcomes.json`, halt and surface (per AGENTS.md "Mandatory explicit plan").
**Anchor.** [DRY-RUN-MODE.md](DRY-RUN-MODE.md). Per /saas-billing-patterns-for-stripe-and-paypal preview-before-mutate axiom.

### `🔬 PROVENANCE`

**Trigger.** Phase 8 (during apply) and Phase 11 (handoff).
**Inputs.** `apply_log.tsv`, `harmonization_plan.md`, the bundle's `index.tsv`.
**Action.** Record every byte's source — source branch, commit, hunk, intent (for harmonized commits) — in `provenance.json`. Attach `git notes` to each rationalization-branch commit linking back to source(s).
**Prompt module.** "For this Phase 8 commit, the source is {branch + sha + hunk_id}. For harmonized commits, list every variant + intent + line-range. Append to apply_log.tsv:provenance and emit provenance.json."
**Exit criteria.** Every rationalization-branch commit has a provenance row; `provenance-trace.sh <file>:<line>` returns the source in O(1).
**Failure modes.** If `git notes` namespace is already in use by the project, store provenance in a separate file rather than clobber.
**Anchor.** [PROVENANCE-CHAIN.md](PROVENANCE-CHAIN.md). Per /lean-formal-feedback-loop discipline.

### `⏱ PROFILE`

**Trigger.** Cross-phase, automatic.
**Inputs.** Per-script invocation timings.
**Action.** Aggregate per-phase totals + per-script breakdowns + parallelism efficiency; compare against MEASUREMENT.md SLOs; flag regressions; recommend tier adjustments for next run.
**Prompt module.** "Wrap every script invocation with `time`. At Phase 11, roll up per-phase totals. If Phase X is >150% of its SLO, recommend tier change; if <50%, suggest dropping a tier."
**Exit criteria.** `performance_profile.md` exists; bottleneck is identified; a recommendation is on file for the next run.
**Failure modes.** Time skew across NTM panes can produce wrong totals; cross-validate via wall-clock vs. start/stop timestamps.
**Anchor.** [PERFORMANCE-PROFILE.md](PERFORMANCE-PROFILE.md). Per /profiling-software-performance.

### `🛡 AUDIT-AFTER`

**Trigger.** Phase 9.5 — automatic gate between Phase 9 fresh-eyes and Phase 10 cleanup.
**Inputs.** Rationalization-branch tip; project_profile.json's gate commands; harmonized commits' source variants.
**Action.** Run UBS + lint + typecheck + formatter + security scanners + full test suite. For harmonized commits, run each source variant's tests against the synthesis (MR-4). Emit `audit_report.md`. **BLOCK Phase 10 until clean.**
**Prompt module.** "Six dimensions (security, performance, correctness, API consistency, test coverage, commit-message quality). Run each via the project's actual gates. Surface every failure. Phase 10 cannot start until every dimension passes."
**Exit criteria.** All six dimensions PASS; `audit_report.md` is appended to handoff_report.md; Phase 10 unlocked.
**Failure modes.** If a gate is flaky, surface as MANUAL — never auto-pass on retry.
**Anchor.** [AUDIT-AFTER-RUN.md](AUDIT-AFTER-RUN.md). Per /codebase-audit + /multi-pass-bug-hunting.

### `🧪 FUZZ`

**Trigger.** Phase 3 (post-bundle) + Phase 11 (defense-in-depth).
**Inputs.** The bundle directory.
**Action.** Generate transformed copies (tar/untar, fs-copy across mountpoints, simulated bit-flips), run `verify-bundle.sh` against each. Identify "cliff edges" where recovery breaks.
**Prompt module.** "Fuzz target the bundle as a recovery surface. 100 transformations. Each must verify; any failure is a real risk to the user's safety net."
**Exit criteria.** `bundle_fuzz_report.md` exists; zero recovery-breaking transformations; surface any near-miss as a follow-up.
**Failure modes.** A genuinely broken transformation must NOT be silently fixed — surface to user.
**Anchor.** [TESTING-FUZZING.md](TESTING-FUZZING.md). Per /testing-fuzzing.

### `📐 PROVE`

**Trigger.** Phase 3 + Phase 11.
**Inputs.** The bundle + BUNDLE-FORMAT-SPEC.md.
**Action.** Per-spec-section check function. Verifies the bundle satisfies the contract.
**Prompt module.** "For each MUST in BUNDLE-FORMAT-SPEC.md, run the check; for each SHOULD, run the check and warn on miss. Compose into a compliance matrix."
**Exit criteria.** All MUST checks pass; SHOULD warnings are surfaced; `conformance_report.tsv` exists.
**Failure modes.** A failing MUST means the bundle is unsafe — halt the run.
**Anchor.** [TESTING-CONFORMANCE.md](TESTING-CONFORMANCE.md). Per /testing-conformance-harnesses.

### `🪞 METAMORPHIC`

**Trigger.** Phase 9 round 2+ on every harmonized commit.
**Inputs.** Harmonized commit + its source variants.
**Action.** Run the 7 metamorphic relations: Identity, Commutativity, Idempotence, Intent Preservation, No Regression, Fingerprint Coverage, Dependency Closure.
**Prompt module.** "MR-1 through MR-7, each as a separate test invocation. A failing MR is a real synthesis defect; surface to harmonization-planner for revision."
**Exit criteria.** All 7 MRs PASS for every harmonized commit.
**Failure modes.** MR-7 (Dependency Closure) failures are subtle — silent regressions on uncovered code paths. The audit (`🛡 AUDIT-AFTER`) is the secondary check.
**Anchor.** [TESTING-METAMORPHIC.md](TESTING-METAMORPHIC.md). Per /testing-metamorphic.

### `🎯 CALIBRATE`

**Trigger.** Phase 5, per-branch.
**Inputs.** Branch family (prefix), FINGERPRINT, VERIFY-ON-CANONICAL output, cherry-summary.
**Action.** Bayesian update: posterior = prior × likelihood / evidence. Conformal threshold τ=0.85 separates auto-proceed from MANUAL.
**Prompt module.** "Prior = family-based (agent-* → 0.7 garbage / 0.2 superseded / 0.1 novel; feature/* → 0.4 superseded / 0.4 novel / 0.2 partial; ...). Likelihood = evidence. Posterior = prior × likelihood. If posterior < τ, route to MANUAL."
**Exit criteria.** Every triage row's confidence column is a calibrated posterior, not a vibe.
**Failure modes.** Distribution shift (this repo's family mix differs from baseline) — recalibrate priors mid-run via `verdict-stats.sh`.
**Anchor.** [DECISION-THEORY.md](DECISION-THEORY.md). Established decision-theoretic / conformal-prediction framing.

### `🌐 SEMANTIC-COLLISION`

**Trigger.** Phase 7, Comprehensive / Council mode.
**Inputs.** triage.tsv (post-Phase-6); branches with verdict ∈ {novel-and-accretive, partially-novel, divergent-refactor}.
**Action.** Use semantic search to find collisions that file-path matching misses. E.g., `redact_secrets` in `logger.rs` on branch A and `sanitize_log_line` in `log_filter.rs` on branch B may be different implementations of the same conceptual feature.
**Prompt module.** "Index every branch's introduced symbols + their docstrings; find clusters of conceptually-similar symbols across branches; surface to harmonization-planner."
**Exit criteria.** `semantic_collisions.md` augments `harmonization_plan.md`.
**Failure modes.** False positives (two implementations that LOOK semantically similar but actually do different things) — surface to user, never auto-merge.
**Anchor.** Per /frankensearch-integration-for-rust-projects.

### `🔍 REFLOG-DEEP`

**Trigger.** Phase 5, for `novel-but-stale` and `divergent-refactor` candidates.
**Inputs.** Branch's reflog, `git log -g`, `git fsck --lost-found`.
**Action.** Reconstruct full forensic timeline: force-push detection, interactive-rebase artifacts, soft-reset chains, cherry-pick lineage. Drives re-classification.
**Prompt module.** "Read the reflog as a story: when did this branch's tip first appear? Was it ever force-pushed? Are there reset entries that orphaned commits? Did its commits get cherry-picked into another branch?"
**Exit criteria.** `<workspace>/forensic/<slug>-reflog.md` exists; the row's verdict is updated with evidence-citation.
**Failure modes.** Reflog gc'd entries → use `git fsck --lost-found` and the bundle as fallback.
**Anchor.** [REFLOG-DEEP-DIVE.md](REFLOG-DEEP-DIVE.md). Per /lean-formal-feedback-loop forensic discipline.

### `🔁 DUEL`

**Trigger.** Council mode always; Comprehensive when ≥3 branches collide on the same file.
**Inputs.** Variant matrix from harmonization-planner.
**Action.** Run TWO idea-wizards with different system prompts ("preserve every defensive intent" vs. "minimize total surface area"). Each produces a synthesis plan. Adjudicator picks one OR composes.
**Prompt module.** "Wizard A: maximize defensive intent preservation. Wizard B: minimize surface area. Both produce variant-matrix syntheses. Adjudicator reads both + the matrix; picks A, picks B, composes, or escalates as `divergent-refactor`."
**Exit criteria.** `harmonization_plan_duel.md` shows both plans + adjudication; user reviews.
**Failure modes.** Both plans diverge substantially → indicates fundamental ambiguity in the variant matrix. Surface as `divergent-refactor`.
**Anchor.** [DUELING-IDEA-WIZARDS-INTEGRATION.md](DUELING-IDEA-WIZARDS-INTEGRATION.md). Per /dueling-idea-wizards.

### `📡 CI-AWARE`

**Trigger.** Phase 4, after PROTECTION CONFIRMATION.
**Inputs.** triage.tsv + project files (`.github/workflows/*.yml`, `.gitlab-ci.yml`, README, package.json, dockerfile, mergify.yml, dependabot.yml, CHANGELOG.md).
**Action.** Detect references to soon-to-be-deleted branches. Emit `ci_workflow_updates.md` listing each line + suggested update. **Refuse Phase 10 cleanup if CI would break and updates aren't reconciled.**
**Prompt module.** "For every branch in triage.tsv with verdict ∈ {garbage, superseded, already-merged, novel-stale}, grep for references in CI YAML, README, package.json, dependabot.yml. Surface each match."
**Exit criteria.** No deletion in Phase 10 will break CI; the user has reviewed every suggested update; the user has applied them via Edit (the agent never auto-applies per AGENTS.md "No Script-Based Changes").
**Failure modes.** A reference inside a generated file that the user wants to leave untouched — refuse the underlying deletion.
**Anchor.** [CI-WORKFLOW-AWARENESS.md](CI-WORKFLOW-AWARENESS.md). Cass-mined real footgun.

### `🔗 REMOTE-TOPOLOGY`

**Trigger.** Phase 1, per-worktree.
**Inputs.** `git remote -v` output for every worktree.
**Action.** Detect when `origin` points to a local sibling worktree (not the actual upstream). Surface to user with `remote_topology.md`.
**Prompt module.** "For every worktree, list its remotes. For each remote URL, classify as local-path / http / ssh / git. If `origin` is local-path AND another remote like `github`/`gitlab` is non-local-path, surface as a topology issue."
**Exit criteria.** `remote_topology.md` is produced; the Phase 11 push-instruction targets the correct remote, not blindly `origin`.
**Failure modes.** False alarm on legitimate local-clone setups — surface, ask user to confirm.
**Anchor.** [REMOTE-AS-WORKTREE-FOOTGUN.md](REMOTE-AS-WORKTREE-FOOTGUN.md). Cass-mined real footgun (frankensqlite session).

### `✍ SIGN`

**Trigger.** Phase 8 post-apply, when project_profile.json:requires_signing == true.
**Inputs.** Cherry-picked / squash-merged / rebase-merged / harmonized-synthesized commits on the rationalization branch.
**Action.** Detect unsigned commits via `git log --show-signature`; re-sign via `git commit --amend --no-edit -S`. Preserve git notes via `git notes copy`. Each amend logged in apply_log.tsv:resign.
**Prompt module.** "For each Phase 8 commit, check signature. If unsigned and project requires it, re-sign after explicit user authorization (per AGENTS.md 'Mandatory explicit plan')."
**Exit criteria.** Every commit on the rationalization branch is signed (when required).
**Failure modes.** Missing GPG_TTY / unset user.signingkey → surface as a precondition error before any apply.
**Anchor.** [GIT-NOTES-AND-SIGNATURES.md](GIT-NOTES-AND-SIGNATURES.md).

### `🆔 UNBLOCK`

**Trigger.** Phase 11 (handoff augmentation).
**Inputs.** Rationalization-branch commits; pre-rationalization canonical tip.
**Action.** Detect newly-actionable beads via `bv --robot-triage --diff-since`; closed-by-this-commit issues via `bv --robot-history`; PRs whose head branch was rationalized and may now be auto-mergeable; reverse-impact (recovered work invalidates an open beads).
**Prompt module.** "For each recovered commit, search beads + GitHub PRs for: 'newly unblocked by this commit', 'closed by this commit', 'invalidated by this commit'. Optionally invoke /idea-wizard for 5–10 new beads ideas with priority."
**Exit criteria.** `unblocked_work.md` is appended to handoff_report.md.
**Failure modes.** False unblocks — surface to user, never auto-close beads.
**Anchor.** [UNBLOCKED-WORK.md](UNBLOCKED-WORK.md). Per /idea-wizard + /bv.

### `📦 EXPORT`

**Trigger.** Phase 11+, when user wants cross-machine resume / audit / handoff.
**Inputs.** Workspace + recovery bundle.
**Action.** Tar the entire workspace + bundle into a portable `.tar.zst` for cross-machine transport.
**Prompt module.** "Compose `<workspace>` + `<bundle>` into a single archive. Compute checksums. Emit a manifest. Never delete source — only `mv` to .archived if user explicitly opts in (per AGENTS.md RULE NUMBER 1)."
**Exit criteria.** A self-contained archive exists; the user can decompress on a different machine and resume the run via `bundle-import.sh` (TODO if not yet implemented) + `archive-workspace.sh` reverse mode.
**Failure modes.** Disk space — pre-flight check before tarring.
**Anchor.** Implemented via `scripts/workspace-export.sh`.

### `🪢 REPLAY`

**Trigger.** Resume after interruption — when `<workspace>/conflicts/branch_<slug>.context.md` captured a user-confirmed Edit operation that hasn't been applied yet.
**Inputs.** Conflict context file with the user-confirmed Edit operations.
**Action.** Replay the Edit operations against fresh state; run gates; commit. Idempotent.
**Prompt module.** "Read the conflict context. For each recorded Edit operation, apply via the Edit tool. Run gates. Commit with the same message as recorded. Skip if already-applied (idempotence check via apply_log.tsv)."
**Exit criteria.** The conflict's commit lands; the rationalization branch advances; apply_log.tsv updated.
**Failure modes.** The fresh state has changed enough that the Edit no longer applies — surface to user with the diff between expected and actual.
**Anchor.** Implemented via `scripts/conflict-replay.sh`. Per the resumability axiom of every phase boundary.

---

These 17 round-3 operators bring the operator library to **35 total** — 18 core + 17 round-3. The cheat-sheet at the top of this file lists the 18 core operators in their canonical phase order; consult the round-3 cards above for the additional cognitive moves that fire conditionally based on mode (Comprehensive / Council triggers most of them).
