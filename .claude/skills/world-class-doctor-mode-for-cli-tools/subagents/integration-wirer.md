# subagent: integration-wirer (Phase 8)

**Description.** Wire `<tool> doctor` into pre-commit hooks, CI, and project entry points. Demote any related manual playbook skill to a fallback.

## Inputs

- `{{target}}` — target repo
- `{{tool}}` — binary name
- Related-skill path (e.g., `<your-skills-dir>/fixing-beads-problems/`, where `<your-skills-dir>` is typically `~/.claude/skills/` or your private skills repo's `.claude/skills/`) if Phase 0 identified one
- `/gh-actions` skill (optional reference)

## Outputs

- Updated pre-commit config / hook script
- New CI workflow step (or updated existing one)
- Updated related-skill SKILL.md (per AGENTS.md no-delete: existing playbook content stays, just relabeled as fallback)

## Prompt

```
You are the integration-wirer. Wire `<tool> doctor` into the project's
existing automation surfaces.

STEP 1. Pre-commit hook.

If `.pre-commit-config.yaml` exists, add an entry:

  - id: doctor-quick-check
    name: <tool> doctor --quick
    entry: <tool> doctor --quick --json
    language: system
    pass_filenames: false
    fail_fast: true

If no pre-commit config exists, install a `.git/hooks/pre-commit` shim:

  #!/usr/bin/env bash
  set -euo pipefail
  if ! <tool> doctor --quick --json > /dev/null 2>&1; then
      echo "doctor found findings; run '<tool> doctor --explain' to investigate" >&2
      echo "or '<tool> doctor --fix' to repair" >&2
      exit 1
  fi

The hook MUST be idempotent — re-running the install is a no-op.

STEP 2. CI workflow.

Use the /gh-actions skill if available. Add to .github/workflows/<existing>.yml
or create .github/workflows/doctor.yml:

  name: doctor
  on: [push, pull_request]
  jobs:
    doctor-health:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - run: <build steps>
        - run: <tool> doctor health
        # The doctor's `--json` report names the per-run artifact directory;
        # the scorecard itself lives at `.doctor/runs/<id>/scorecard.json`.
        # Accept exit 0 (healthy) and 1 (findings present) so the regression
        # check can still read the scorecard and emit the useful failure.
        - name: scorecard regression check
          run: |
            doctor_rc=0
            <tool> doctor --json > /tmp/run.json || doctor_rc=$?
            case "$doctor_rc" in 0|1) ;; *) exit "$doctor_rc";; esac
            run_dir=$(jq -r '.run_dir // empty' /tmp/run.json)
            [ -n "$run_dir" ] || { echo "doctor report missing run_dir" >&2; exit 1; }
            scorecard="$run_dir/scorecard.json"
            [ -f "$scorecard" ] || { echo "missing scorecard: $scorecard" >&2; exit 1; }
            curr=$(jq -r '.aggregate.score // .aggregate_score // 0' "$scorecard")
            baseline="<checked-in-baseline-scorecard.json>"
            prev=$(jq -r '.aggregate.score // .aggregate_score // 0' "$baseline")
            delta=$((prev - curr))
            if [ "$delta" -gt 50 ]; then
                echo "FAIL: aggregate dropped $delta pts (was=$prev, now=$curr)" >&2
                exit 1
            fi
            echo "OK: aggregate=$curr (baseline=$prev, delta=-$delta)" >&2
            # Note: this skill's `scripts/scorecard.py compare-against-baseline`
            # provides the same logic plus per-FM detail. Use it locally during
            # development; in CI, prefer the jq fallback so the target repo
            # doesn't depend on the skill being installed in the runner.

STEP 2.5. Claude Code hook (if user has Claude Code installed).

If `~/.claude/` exists (Claude Code installed for the current user) AND the
user's intake permitted hook installation, emit a PreToolUse hook config
that auto-runs `<tool> doctor --quick --json` before any Bash tool call
that looks like a commit. This is a parallel safety layer to the
pre-commit hook in STEP 1 — pre-commit catches `git commit` from any
client; the Claude Code hook catches AI-driven commits even when they
bypass pre-commit (e.g., `git commit --no-verify`, `gh pr create`).

Use the `/cc-hooks` skill (or its inline fallback in SKILL-FALLBACKS.md)
to author the config. Template at `assets/cc-hooks-precommit.json`. Drop
the patched config into `~/.claude/settings.local.json` (NOT the global
settings — keep it scoped to this user's customizations). The hook fires
on Bash commands matching `^git\s+commit|^git\s+push|^gh\s+pr\s+create`
and aborts with exit 1 if `<tool> doctor --quick` returns non-zero.

Do NOT install if the user's intake said "deny hook installs". The hook
adds 1-3s of latency to every commit; users with extreme commit cadence
may decline.

STEP 3. Demote related manual playbook skill (if any).

For each related skill (e.g., fixing-beads-problems):

a) Read its SKILL.md.

b) Update the top of file SO THAT THE FIRST RECOMMENDATION IS:
   "**First, run `<tool> doctor --fix`. If that doesn't help, the steps
    below remain as a fallback for unusual cases.**"

c) Per AGENTS.md no-delete rule, do NOT delete any existing playbook
   content. Add the new recommendation; keep the prior steps intact.

d) Update the description frontmatter to mention the new doctor surface.

e) Commit the change in this skill repo (NOT the target repo) on a separate
   branch named `demote-<related-skill>-to-fallback`.

STEP 4. Verification.

a) Make a small change in a doctor fixture; run pre-commit; assert it
   blocks.
b) Push to a feature branch; assert the GitHub Actions doctor job runs.
c) Run `<tool> doctor health` locally; assert it returns in < 200 ms.

EXIT CRITERIA.
- Pre-commit hook installed and tested.
- CI workflow committed and passing on the feature branch.
- Related skill SKILL.md updated (if any) and committed.
```

## Exit criteria

- Pre-commit hook tested (blocks on a corrupted fixture)
- CI workflow runs on the feature branch
- Related skill demoted (if any)

## Failure modes

- Project has no `.git/hooks/` directory (e.g., bare clone). Skip the local hook; rely on CI.
- Project's CI uses a non-GitHub system (GitLab, Bitbucket). Use the project's existing CI primitives. Use `/gh-actions` skill only if GitHub.
- Related skill's existing playbook is the user's mental model and they don't want it demoted. Escalate; let the user decide. Don't unilaterally rewrite their docs.
