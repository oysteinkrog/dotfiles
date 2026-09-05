# WORKING-SURFACE

Where do the changes go? Confirm with the user before any phase emits a code change.

## Default — feature branch on existing repo

```bash
cd /path/to/saas-repo
git checkout -b seo/initial-pass
```

One PR per logical group (Phase 6 PRs cadence in SKILL.md). PRs targeted at `main` (or the project's default branch). User reviews and merges.

**Use when:** the user already trusts the workflow, the repo is normally healthy, and PR-per-phase is acceptable.

## Alternative 1 — Sibling worktree

```bash
cd /path/to/parent
git worktree add ../saas-repo__seo_pass seo/initial-pass
cd ../saas-repo__seo_pass
```

Or via the Agent tool's `isolation: "worktree"` mode for sub-tasks.

**Use when:** the user wants isolation from in-progress feature work, runs the SEO pass alongside another branch, or wants to A/B compare two SEO branches before deciding which to merge.

## Alternative 2 — Direct commits to a branch (no PR cadence)

**Use when:** the user explicitly authorizes; usually a solo founder or single-engineer team operating fast.

Commit messages still follow conventional format and reference the audit item IDs.

## Alternative 3 — Separate documentation repo / Notion / Linear

For phases that produce *only* documentation (briefs, audit reports, decision cards), the user may want them in a separate place rather than in the SaaS repo. Confirm. Default = `analyses/` and `deliverables/` directories at the repo root, gitignored if the user prefers.

## Decision points to confirm

- [ ] Branch name (default `seo/initial-pass`).
- [ ] PR cadence (default: one per Phase 6 logical group).
- [ ] Required reviewers (CODEOWNERS for `app/`, `next.config.*`, `middleware.*`).
- [ ] CI required to pass before merge (Lighthouse CI, schema validate, build).
- [ ] Are `analyses/` and `deliverables/` directories committed or gitignored?
- [ ] Authorization to push to remote (default: yes for feature branches; never for `main` without explicit per-push confirmation).
- [ ] Authorization to deploy to production (default: never without explicit per-deploy confirmation; prefer `/vercel:deploy prod` invoked by user).

## Per-phase code-change boundaries

| Phase | Touches code? | Touches `main`? |
|---|---|---|
| 1 | No | No |
| 2 | No | No |
| 3 | No | No |
| 4 | Sometimes (CMS or MDX content) | No (PRs only) |
| 5 | Yes (link-graph PR) | No |
| 6 | Yes (most code work) | No (PRs only) |
| 7 | Sometimes (asset publication) | No |
| 8 | Yes (analytics wiring) | No |
| 9 | Yes (experiment infrastructure) | No |
| 10 | No | No |
| 11 | Deploys via user action | Yes (after merge) |
| 12 | No | No |
| 13 | No | No |

Phase 11 is the only phase that ships to production, and it does so via the user's authorized deploy mechanism.

## Beads / issue tracking

If `br` is available and `.beads/` exists, create issues per audit item with `--type=task --priority=2`. Use the issue ID as the PR slug suffix and the Mail thread ID per AGENTS.md conventions.

If no beads, GitHub issues with label `seo` and a milestone per phase.
