---
name: fieldtheory
description: Search the user's local X/Twitter bookmarks for content relevant to their current work. Trigger when the user mentions bookmarks, saved tweets, wants to find something they saved, or asks questions their bookmark history could answer.
---

# Field Theory — Contextual Bookmark Search

Search the user's local X/Twitter bookmark archive for content relevant to the current task.

## When to trigger

- User mentions bookmarks, saved tweets, or X/Twitter content they saved
- User asks to find something they bookmarked ("find that tweet about...")
- User asks a question their bookmarks could answer ("what AI tools have I been looking at?")
- User wants bookmark stats, patterns, or insights
- Starting a task where the user's reading history adds context

## Workflow

1. Look at what the user is working on (conversation, open files, branch name)
2. Generate 2-3 targeted search queries
3. Run `ft search <query>` for each
4. Narrow with filters if needed
5. Summarize what you found — highlight relevant bookmarks, note patterns

## Commands

```bash
ft search <query>              # Full-text BM25 search ("exact phrase", AND, OR, NOT)
ft list --category <cat>       # tool, technique, research, opinion, launch, security, commerce
ft list --domain <dom>         # ai, web-dev, startups, finance, design, devops, marketing, etc.
ft list --author @handle       # By author
ft list --after/--before DATE  # Date range (YYYY-MM-DD)
ft stats                       # Collection overview
ft viz                         # Terminal dashboard
ft show <id>                   # Full detail for one bookmark
```

Combine filters: `ft list --category tool --domain ai --limit 10`

## Guidelines

- Start broad, narrow with filters
- Don't dump raw output — summarize and connect findings to the user's current work
- Cross-reference multiple queries to build a complete picture
- Look for recurring authors, topic clusters, and connections between bookmarks
