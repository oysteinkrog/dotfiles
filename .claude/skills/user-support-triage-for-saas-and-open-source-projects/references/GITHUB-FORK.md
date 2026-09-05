# GitHub Fork (OSS Issues + PRs)

For repos where support arrives as GitHub issues / PRs / Discussions. Uses the `gh` CLI.

## Onboarding Inputs (write into 02-channels.md)

- Repo: `owner/name` (from `gh repo view --json nameWithOwner -q .nameWithOwner`)
- Issue templates: `.github/ISSUE_TEMPLATE/*.md|*.yml`
- PR template: `.github/PULL_REQUEST_TEMPLATE.md`
- Code of conduct? `CODE_OF_CONDUCT.md`
- Contributing policy? `CONTRIBUTING.md` — does it accept external PRs?
- Discussions enabled? `gh api repos/OWNER/NAME --jq .has_discussions`
- Labels in use: `gh label list --limit 100 --json name,color,description`
- Saved replies / response macros (org-level, not API-accessible — ask owner)
- Has Sponsors / paid support? `.github/FUNDING.yml`
- CI required for issue triage? `gh run list --limit 5`

## Decision Matrix (Generic OSS — adapt per project)

| Type | Verified | Action |
|---|---|---|
| Bug, confirmed, unfixed | ✓ | Fix, then `gh issue close N -c "Fixed in <SHA>; released in vX.Y.Z."` |
| Bug, already fixed | ✓ | `gh issue close N -c "Fixed in <SHA>. Please upgrade and reopen if it persists."` |
| Bug, can't reproduce | ? | `gh issue comment N -b "<REQUEST-INFO template>"` |
| Bug, pre-2025 / silent for >180 days | ✗ | Close stale: `gh issue close N -c "<STALE template>"` |
| Feature, simple, fits roadmap | ✓ | Implement → close on merge |
| Feature, complex / scope creep | — | **SURFACE to owner** with options |
| Feature, declined | ✗ | Polite decline + link to similar idea or alternative |
| Question / usage help | — | Answer + suggest moving to Discussions if enabled |
| PR (any) | — | **NEVER MERGE without owner approval.** Mine for ideas. If declined, close with reasoning |
| Security report (issue with vuln) | — | **STOP.** Privately email owner; do NOT comment publicly |
| Spam / hostile | ✗ | Close + `gh issue lock N --reason spam` |

## Triage Quickstart

```bash
PROJECT="<project-path>"
REPO=$(jq -r .github_repo "$PROJECT/.claude/support-triage/_detection.json")

# 1. Open items, modern only (recent reports first)
gh issue list -R "$REPO" --state open --json number,title,createdAt,labels,author \
  --jq 'sort_by(.createdAt) | reverse'

# 2. Open PRs (do not merge)
gh pr list -R "$REPO" --state open --json number,title,author,createdAt

# 3. Investigate one
gh issue view 123 -R "$REPO" --comments
gh pr diff 45 -R "$REPO"           # the intel — read every line of an inbound PR

# 4. After owner approves drafts
gh issue comment 123 -R "$REPO" -F /tmp/reply.md
gh issue close 123 -R "$REPO" -c "$(cat /tmp/closing-comment.md)"
gh issue edit 123 -R "$REPO" --add-label "stale,wontfix"
```

## SURFACE FORMAT — Inbound PRs

Most OSS projects do NOT merge external PRs (CLA / no-contributions policy / quality bar). Use this format:

```
🤔 INBOUND PR: owner/repo#42 — "<title>"

Author: @<user> (first contribution? <yes/no>)
Diff: <N> files, +<adds>/-<dels> lines
What it does: <one paragraph>
Quality: <does it match project style? tests? docs?>

Recommended action:
[ ] Cherry-pick the *idea* into a fresh internal commit, close PR with thanks
[ ] Merge as-is (rare; only if CLA passes and quality is high)
[ ] Decline politely with reasoning

Drafts (pick one):
  CLOSE-CHERRYPICK: "Thanks for this — we'll fold the idea into <commit>; closing in favor of that."
  CLOSE-DECLINE:    "Thanks, but this conflicts with <design choice>. Closing — appreciate the thought."
  ACCEPT:           "Thanks! Merging after CI passes."
```

## Stale Issue Closure

```markdown
Closing this as stale — it's been quiet since {{date}}, and the surrounding
code has changed substantially in the meantime. If you're still seeing this
behavior on the latest release, please open a fresh issue with:

- Exact version (`<tool> --version`)
- Reproduction steps
- Full error output

Sorry for the slow response. Thanks for the original report!
```

## Stale Closure Rules (defaults — owner can override)

- Issue silent ≥180 days AND no maintainer comments since open → stale-close
- Pre-2025 issue with no engagement → stale-close
- Issue with `pinned`, `bug:critical`, or `security` label → never auto-stale
- Question with author response within 30 days → leave open

## Response Templates (paste-ready)

See [RESPONSE-TEMPLATES.md](RESPONSE-TEMPLATES.md) — these wrap nicely for `gh issue comment -F`.

## Anti-Patterns (OSS-specific)

- **Merging your own untested fix to close a popular issue.** Reproduce first.
- **Closing-with-no-comment.** Always leave reasoning so future readers (and the original reporter) understand why.
- **Replying without checking duplicates.** Use `gh issue list --search "<keyphrase>"` first.
- **Engaging hostile users.** Lock and move on; don't escalate. Use `gh issue lock` with `reason=too heated`.
- **Public reply to a security report.** STOP — escalate privately.
