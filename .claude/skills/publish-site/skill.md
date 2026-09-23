---
name: publish-site
description: |
  Publish static content to GitHub Pages, to either the company repo
  (InitialForce/sites, private) or the personal repo (oysteinkrog/sites, public).
  Use when user says "publish site", "deploy to pages", "publish to gh-pages",
  or wants to put static HTML somewhere shareable.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
---

# Publish a static site to GitHub Pages

## Pick the destination first

**Do this before anything else, and say out loud which one you picked.** Choose by who owns
the content, not by who is typing. Getting it wrong publishes company material on a public
site.

| Repo | Holds | Visibility | Local checkout |
|---|---|---|---|
| `InitialForce/sites` | Company content: anything that speaks for Initial Force AS, or that another person would treat as authoritative. OKRs, board-facing reports, shared dashboards, official docs. | Private Pages, org members only | `/c/work/sites-repo` |
| `oysteinkrog/sites` | Personal content: my own tools, dashboards, notes and experiments. | Public Pages | `/c/work/sites-repo-personal` |

If it speaks for the company, or anyone other than Oystein will reference it, it goes to
`InitialForce/sites`. When the content names customers, staff or unreleased plans, ask before
publishing at all. Writing something yourself does not make it publishable.

The binding company policy is `ifkb/knowledge-base/technical/website-publishing.md`.

**The two checkout paths are easy to mix up. Verify before you push:**

```bash
git -C <checkout> remote -v      # must match the repo you chose
```

## Arguments

- **source**: directory of static content, must contain `index.html`
- **category**: top-level grouping, such as `okrs`, `bv`, `docs`, `reports`
- **slug**: unique name inside the category

Infer from context or ask if not given.

## Steps

Set `REPO` and `CHECKOUT` from the table above, then:

1. Check the source directory exists and has `index.html`.
2. Make sure the checkout exists and is current:
   ```bash
   # First time:
   git clone --branch gh-pages --single-branch https://github.com/<REPO>.git <CHECKOUT>
   # After that:
   git -C <CHECKOUT> pull origin gh-pages
   ```
   If the directory already exists, **check its remote before using it** rather than assuming
   it is the one you want.
3. Copy the content in:
   ```bash
   mkdir -p <CHECKOUT>/<category>/<slug>
   cp -r <source>/* <CHECKOUT>/<category>/<slug>/
   ```
4. Commit and push. Stage and commit only the site directory from step 3:
   ```bash
   git -C <CHECKOUT> add -- <category>/<slug>
   git -C <CHECKOUT> commit -m "add <category>/<slug>" -- <category>/<slug>
   git -C <CHECKOUT> push origin gh-pages
   ```
5. Report the live URL:
   - Company: `https://initialforce.github.io/sites/<category>/<slug>/` (org login needed)
   - Personal: `https://oysteinkrog.github.io/sites/<category>/<slug>/`

Note: `/c/work/sites-repo` may sit on a working branch rather than `gh-pages`. Check with
`git -C /c/work/sites-repo branch --show-current` and switch before publishing.

## Common patterns

### bv (beads viewer) export
```bash
bv -export-pages ./bv-pages -pages-title "Title"
# then publish with category=bv, slug=<project-slug>
```

### Updating an existing site
Same steps. `cp -r` overwrites the existing directory. Commit message: `update <category>/<slug>`.

## Notes
- Each site is self-contained: its own `index.html`, all assets relative.
- No landing page at the root. Sites are reached by direct URL.
