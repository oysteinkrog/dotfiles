---
name: publish-site
description: |
  Publish static content to GitHub Pages (oysteinkrog/sites repo).
  Use when user says "publish site", "deploy to pages", "publish to gh-pages",
  or wants to put static HTML somewhere shareable.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
---

# Publish Static Site to GitHub Pages

Publish a directory of static content to `oysteinkrog/sites` on the `gh-pages` branch.

## Arguments

The user should provide:
- **source**: path to directory containing static content (must have `index.html`)
- **category**: top-level grouping (e.g., `bv`, `docs`, `reports`)
- **slug**: unique name within category (e.g., `bb-bbox`, `my-feature`)

If not provided, infer from context or ask.

## Steps

1. Verify source directory exists and contains `index.html`
2. Clone the sites repo (shallow, gh-pages only):
   ```bash
   git clone --branch gh-pages --single-branch --depth 1 https://github.com/oysteinkrog/sites.git /tmp/sites-repo
   ```
3. Copy content into place:
   ```bash
   mkdir -p /tmp/sites-repo/<category>/<slug>
   cp -r <source>/* /tmp/sites-repo/<category>/<slug>/
   ```
4. Commit and push:
   ```bash
   cd /tmp/sites-repo && git add -A && git commit -m "add <category>/<slug>" && git push origin gh-pages
   ```
5. Report the live URL: `https://oysteinkrog.github.io/sites/<category>/<slug>/`

## Common Patterns

### bv (beads viewer) export
```bash
bv -export-pages ./bv-pages -pages-title "Title"
# then publish with category=bv, slug=<project-slug>
```

### Updating an existing site
Same steps — `cp -r` overwrites the existing directory, commit message: `update <category>/<slug>`.

## Notes
- Each site must be self-contained (all assets relative, own `index.html`)
- No landing page at root — sites are accessed by direct URL
- If `/tmp/sites-repo` already exists from a previous run, `cd` into it and `git pull` instead of re-cloning
