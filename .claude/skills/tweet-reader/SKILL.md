---
name: tweet-reader
description: "Fetch and display any X/Twitter tweet by URL or ID. Use when the user shares a tweet link (x.com or twitter.com), asks to read/fetch/see a tweet, or references a tweet ID. Handles text, images, videos, quoted tweets, and embedded links."
---

# Tweet Reader Skill

Read any public X/Twitter tweet using the `xt` CLI tool (`~/bin/xt`).

## When to trigger

- User shares a tweet/X URL (x.com/*/status/*, twitter.com/*/status/*)
- User says "read this tweet", "fetch this tweet", "what does this tweet say"
- User pastes a tweet ID and asks about it
- User asks to download images from a tweet

## Workflow

1. Extract the tweet URL or ID from the user's message
2. Run `xt` to fetch the tweet content
3. If the tweet has images, download them with `xt -d` and use Read to display them
4. Summarize the content — translate if not in English
5. Follow up on any links or context if the user needs it

## Commands

```bash
xt <url-or-id>              # Human-readable output
xt -j <url-or-id>           # JSON output (for structured processing)
xt -d <url-or-id>           # Download images to /tmp/xt/
xt -r <url-or-id>           # Raw API JSON
```

## Examples

```bash
# Fetch a tweet by URL
xt 'https://x.com/indie_maker_fox/status/2043857352282255829'

# Fetch by bare ID
xt 2043857352282255829

# Get JSON for processing
xt -j 'https://x.com/user/status/123456'

# Download and view images
xt -d 'https://x.com/user/status/123456'
# Then use Read tool on /tmp/xt/<id>_0.jpg to display
```

## Guidelines

- Always fetch the tweet first before responding about it
- If the tweet is in a non-English language, provide both the original and a translation
- If the tweet contains images, download and display them using the Read tool
- If the tweet links to a repo, article, or tool, offer to fetch that too
- For threads, the syndication API only returns the linked tweet (not the full thread)
- Works for public tweets only; protected/private tweets will return a 403 error
