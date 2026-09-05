# TIME-MACHINE-MODE.md — Re-Audit As Of A Historical Commit

<!-- TOC: When to invoke | The two flavors | Implementation | Worked example | Cautions -->

> "If we had run this audit 3 months ago, would it have caught the bug we just shipped?"
> Time-machine mode answers that — re-runs the audit as of a specific commit so you can compare what the audit *would have said* against what actually happened.

---

## When to invoke

| Scenario | Why |
|----------|-----|
| Post-mortem retro | Verify the audit at the time-of-merge would have caught the incident |
| Pre-promotion audit gate | Audit a release candidate at the SHA you'd ship, not at HEAD |
| Hypothesis testing | "Did adding pattern N to FAILURE-MODES.md help? Re-audit 6 months ago with the new rubric." |
| Audit retrospectives | Comparing audit quality across rubric versions |
| Onboarding-mode calibration | Replay the project's history with current rubric to see how false-closed rate evolved |

---

## The two flavors

### Flavor 1 — Code at a historical SHA, audit with current rubric

The most common case. You want to know: "what does today's audit say about the project's state 3 months ago?"

```bash
# 1. Snapshot HEAD so we can return to it.
ORIG_SHA=$(git -C <project> rev-parse HEAD)

# 2. Check out the historical SHA.
git -C <project> checkout <historical-sha>

# 3. Run the audit. Mode=time-machine records the SHA in manifest.json.
~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
  <project> --threshold 700 --policy report-only --mode time-machine \
  --as-of <historical-sha>

# 4. Restore HEAD.
git -C <project> checkout "$ORIG_SHA"
```

The audit dir's pass uses the current rubric. The pass's `manifest.json` records `audit_as_of_sha: <historical-sha>` so it's clear this isn't an audit of HEAD.

### Flavor 2 — Code at HEAD, audit with historical rubric

Rarer. You want to know: "what would the OLD rubric have said about today's project?"

```bash
# 1. Find a prior audit dir's rubric.md
PRIOR_RUBRIC=~/audits/<project>/beads_compliance_audit/passes/2026-01-15T*/rubric.md
# (The rubric.md at the audit dir root tracks the latest; per-pass rubric_sha256 was pinned)

# 2. Bootstrap a fresh audit dir using the historical rubric
mkdir -p /tmp/historical-audit
cp "$PRIOR_RUBRIC" /tmp/historical-audit/rubric.md
~/.claude/skills/.../scripts/bootstrap-audit.sh <project> 700 standard \
  --rubric /tmp/historical-audit/rubric.md
```

The pass's `rubric_sha256` matches the historical rubric. Useful for measuring rubric evolution.

---

## Implementation: `--as-of` flag

`run-pass.sh --as-of <sha>` is implemented as:

```bash
if [ -n "$AS_OF" ]; then
  # Stash any uncommitted changes
  ORIG_SHA=$(git -C "$PROJECT" rev-parse HEAD)
  git -C "$PROJECT" stash push -m "audit time-machine stash" 2>/dev/null || true
  STASH_PUSHED=$?

  # Detached-head checkout to the historical SHA
  git -C "$PROJECT" checkout --detach "$AS_OF"

  # Run all phases as normal
  ...

  # Restore
  git -C "$PROJECT" checkout "$ORIG_SHA"
  if [ "$STASH_PUSHED" -eq 0 ]; then
    git -C "$PROJECT" stash pop || echo "WARNING: stash pop failed; check git stash list" >&2
  fi
fi
```

The bead store at `<project>/.beads/` is also at the historical state — but **only if the bead store is git-tracked** (it usually is via `.beads/issues.jsonl`). If the bead store has changes since the historical SHA, the audit sees the bead state at that time.

---

## What the time-machine audit captures

| Aspect | Time-machined? |
|--------|:--------------:|
| Project source code | ✓ — at the historical SHA |
| Bead inventory (status, close_reason, etc.) | ✓ — from `.beads/issues.jsonl` at SHA |
| Test runner version | ✗ — uses current PATH (`cargo`, `npm`, etc.) |
| Coverage tool version | ✗ — uses current PATH |
| Audit rubric | Configurable: current OR historical (Flavor 1 vs 2) |
| Theater catalog | ✗ — uses current FAILURE-MODES.md |
| Subagent prompts | ✗ — uses current subagents |

The audit is not a perfect time machine — it can't reproduce the test runner's exact behavior at the historical SHA. But the bead state and code are accurate.

---

## Worked example: "did our 2026-Q1 audit miss the CSRF bug?"

In Q2 we shipped a CSRF bypass (per [POST-MORTEM-MODE.md](POST-MORTEM-MODE.md) example). The audit at the time scored `bd-csrf-mw-impl` 850/1000 — passes threshold.

After the post-mortem, we tightened the rubric to add Pattern 31 (non-constant-time comparison). Question: had we used the new rubric in Q1, would the audit have caught it?

```bash
# 1. Find the SHA at which Q1 audit ran
Q1_SHA=$(jq -r .project_git_sha_at_pass_start \
  ~/audits/myproject/beads_compliance_audit/passes/2026-01-15T*/manifest.json)

# 2. Time-machine audit with current (post-incident) rubric
~/.claude/skills/.../scripts/run-pass.sh /data/projects/myproject \
  --threshold 700 --policy report-only --mode time-machine \
  --as-of "$Q1_SHA"

# 3. Read the result
cat /data/projects/myproject/beads_compliance_audit/passes/<new-UTC>/beads/bd-csrf-mw-impl/scorecard.md
```

If the new audit scores `bd-csrf-mw-impl` at 580 (below threshold), the answer is yes — the new rubric would have flagged the bead pre-incident. We can confidently keep Pattern 31 in the catalog as a high-value addition.

If the new audit still scores it at 850, then the new rubric isn't catching the gap either. The pattern needs further tightening or the bead's body is too thin to verify.

---

## Comparing time-machine to non-time-machine passes

The audit dir's `trends.md` distinguishes time-machine passes:

```markdown
| Pass | Bead | Score | Notes |
|------|------|------:|-------|
| 2026-04-20T10-00-00Z | bd-csrf-mw-impl | 850 | original audit |
| 2026-05-01T15-30-00Z (time-machine as-of abc1234) | bd-csrf-mw-impl | 580 | new rubric on Q1 code |
| 2026-05-01T16-00-00Z | bd-csrf-mw-impl | 580 | post-incident audit on HEAD |
```

The time-machine pass's row is annotated so future trend analysis doesn't confuse historical re-audits with forward progress.

---

## Cautions

### 1. Working tree dirtiness

If you have uncommitted changes, time-machine mode stashes them. **Always verify the stash pop succeeded** when the audit returns:

```bash
git -C <project> stash list
# If you see "audit time-machine stash" still present, run:
git -C <project> stash pop
```

### 2. The bead store may not match exactly

If `.beads/issues.jsonl` was modified since the historical SHA but not committed, the time-machine audit sees the *committed* bead state, not what the developer was actually looking at then.

Workaround: ensure `.beads/` is committed before time-machine.

### 3. Test runners drift

A test that passed in Q1 might fail today due to dependency drift (new lints, new compiler version). The time-machine audit reports today's verdict; this is a real signal but not directly a comment on Q1's quality.

### 4. Subagent prompts have improved

If the current subagents are tighter than the Q1 ones, the time-machine pass may catch theater that Q1's audit genuinely missed even with the same rubric. The improvement is in the audit, not in the project.

### 5. Don't time-machine over branch merges

If the historical SHA is on a branch that was later squashed/rebased, the audit may see partial state. Time-machine works best on linear `main` history.

---

## CI integration

For pre-merge audits on a release candidate:

```yaml
# .github/workflows/release-candidate-audit.yml
on:
  push:
    branches: [release-*]

jobs:
  audit:
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Audit at release candidate SHA
        run: |
          ~/.claude/skills/.../scripts/run-pass.sh . \
            --threshold 700 --policy report-only \
            --mode time-machine --as-of "${{ github.sha }}"
      - name: Block merge if false-closed
        run: |
          FC=$(jq '.bead_counts.false_closed // 0' beads_compliance_audit/manifest.json)
          [ "$FC" -gt 0 ] && exit 1 || exit 0
```

The release branch is gated on its own audit verdict — even though the audit infrastructure runs against the latest tools, the *judgment* is about that specific SHA.

---

## Bonus: continuous time-machine

For projects with monthly releases, configure a monthly tripwire that time-machines back to the previous release tag:

```bash
PREV_RELEASE=$(git -C <project> describe --tags --abbrev=0 HEAD~1)
~/.claude/skills/.../scripts/run-pass.sh <project> \
  --mode time-machine --as-of "$PREV_RELEASE" \
  --threshold 700 --policy report-only
```

The output: "what does today's audit say about the previous release's bead-graph state?" — a continuous calibration check on whether the audit's tightening is producing different verdicts pass-over-pass on the same SHA.