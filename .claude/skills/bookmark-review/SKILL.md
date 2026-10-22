---
name: bookmark-review
description: Review Oystein's new X bookmarks one by one and say whether to adopt each tool, technique or idea, for Initial Force and for his own repos. Writes a daily review file in the Life vault. Use when the user says "review my bookmarks", "bookmark review", or runs it from /loop (for example `/loop 1h /bookmark-review`).
---

# Bookmark review

Oystein bookmarks posts on X about tools, techniques, research and ideas. This skill
reads each bookmark he has not had reviewed yet, works out what it is, and gives a
clear verdict: should he adopt it, try it, watch it, or skip it. Each verdict says
who it matters for: Initial Force (Swing Catalyst), his own setup and repos, or nobody.

## Pieces

| Piece | What it does |
|---|---|
| `ft-sync.timer` | Syncs bookmarks from X into `~/.ft-bookmarks/` once an hour. |
| `ft-review-queue` | Lists bookmarks not yet reviewed and marks them done. State: `~/.local/state/ft-review/reviewed.txt`. |
| `~/work/life/vault/060-knowledge/bookmark-reviews/YYYY-MM-DD.md` | One review file per day. Append, never rewrite earlier entries. |

## One run

1. `ft-review-queue count`. If 0, say "No new bookmarks" in one line and stop.
   If the sync looks broken (check `systemctl --user status ft-sync.service`; exit 2
   means the X login in the personal Chrome is gone), say so in one line.
2. `ft-review-queue next --limit 10`. Review at most 10 per run so one run stays cheap.
   Work oldest to newest within the batch.
3. For each bookmark:
   - Read what it actually points to. Open linked GitHub repos, papers and articles
     with the `web-fetch` agent (or `gh` for repos: README, stars, last commit,
     license). For a thread, `ft show <id>` has the full text. Do not judge from the
     tweet text alone when there is a link.
   - Skip quickly (one line) when it is clearly personal, humour, politics, or
     otherwise not about tools or work. Still mark it done.
   - For the rest, check fit:
     - **Initial Force.** Search Atlas KB (`kb__search`) for the product area, and
       check the relevant repo when the bookmark touches code: `~/work/desktop`
       (MotionCatalyst desktop monorepo, C#/.NET, WPF, also runs under Wine on Linux),
       `InitialForce/opensim_golf`, `biomech-viz`, `qtm-zero-touch`, `ml-models`,
       `ml-pipelines`, `lake`, `mediapilot`, `portal`, `ifkb`. List others with
       `gh repo list InitialForce`. Never read or name `ifboard` in the review.
     - **Oystein's setup.** `~/.dotfiles` (Claude Code skills, hooks, agents, KDE and
       CachyOS setup), `~/src/localbuilds` (patched Wine, KWin, FrankenTerm, cass),
       `~/work/grove`, `~/work/tasklens`, `~/work/aiolos`, agent tooling (beads,
       agent-mail, cass, heavy-build).
     - Check whether something similar is already in use, so the review can say
       "we already have X, this adds Y" or "this replaces X".
4. Append the entries to today's review file (create it with the frontmatter below).
5. `ft-review-queue done <ids...>` for every bookmark you handled, including skips.
   Mark only after the file is written.
6. Reply in chat with a short digest: one line per bookmark with the verdict, and
   call out any **Adopt** at the top. Nothing else.

## Verdicts

- **Adopt**: clearly worth doing now. Say exactly what to do and where (repo, file,
  skill), and the rough effort.
- **Try**: promising, needs a small test first. Name the test.
- **Watch**: interesting but early, unproven or not needed yet. Say what would change that.
- **Skip**: not relevant, or worse than what we have. One line why.

Be honest about evidence. Say "verified" when you read the repo or paper, "from the
post" when you could only read the tweet. Hype, star counts and like counts are not
evidence that something works. Call out risks: license, security (skills and MCP
servers run code with full access), vendor lock-in, maintenance status.

Never install, clone or run anything from a bookmark during a review. Reviews are
read-only. If a test is worth doing, propose it as a **Try**.

## File format

New file:

```markdown
---
title: X Bookmark Reviews YYYY-MM-DD
domain: knowledge
sources:
  - x-bookmarks
collected: YYYY-MM-DD
confidence: medium
tags:
  - bookmark-review
---

# X Bookmark Reviews YYYY-MM-DD
```

One entry per bookmark:

```markdown
## <Short name of the thing> (Adopt | Try | Watch | Skip)

- **Post:** <url> by @handle, posted YYYY-MM-DD
- **What it is:** one or two plain sentences.
- **For:** Initial Force / Oystein's setup / both / none
- **Verdict:** what to do and why, with repo or file names. Note what we already use.
- **Evidence:** verified (what you read) or from the post.
```

Skipped bookmarks get one line under a `## Skipped` heading at the end of the run's
entries: `- <url> @handle: reason`.

Follow the writing rules in `~/.claude/CLAUDE.md` (plain language, no em dashes, no
hype words). Write in English.

## Backlog

The queue was started on 2026-10-22 with every older bookmark marked done except the
newest 20. To review older bookmarks too, remove their ids from `reviewed.txt`, or
run with a larger `--limit` when Oystein asks for a backlog pass.
