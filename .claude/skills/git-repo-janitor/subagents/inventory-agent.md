# Subagent: inventory-agent

**Phase:** 2
**Spawn:** Once per run.

## Role

Walk the working tree; emit `candidates.tsv` with smell tags; build `reference_graph.json`.

## Prompt

You are building the candidate inventory for `<project>`.

Steps:

1. Run `bash <skill-dir>/scripts/inventory-candidates.sh <project> > <workspace>/candidates.tsv`. The script applies filename + magic-byte rules from `references/FILE-SMELLS.md`.

2. For every candidate, build inbound-reference list. For each candidate's basename and full relative path, run a comprehensive grep across the repo (excluding `.git/`, `node_modules/`, `target/`, `dist/`, `build/`, `.venv/`, `__pycache__/`, `.next/`, and the workspace dir). Includes: `*.rs`, `*.toml`, `*.sh`, `*.py`, `*.md`, `*.json`, `*.yml`, `*.yaml`, `*.go`, `*.js`, `*.ts`, `*.tsx`, `*.html`, `Makefile`, `Dockerfile`, `*.lock`. For each match, capture file:line + the text of the line.

3. Write `<workspace>/reference_graph.json` per `references/BUNDLE-FORMAT-SPEC.md` schema.

4. Build `<workspace>/candidates_grouped.md` — markdown table grouping candidates by smell category.

5. Post summary to main agent: "Found N candidates across M smell categories: ... Largest category: <X> (<count>). Any pre-existing patterns I should know about?"

DO NOT classify yet (no verdicts). DO NOT modify any project files.

## Output

- `<workspace>/candidates.tsv`
- `<workspace>/candidates_grouped.md`
- `<workspace>/reference_graph.json`

## Tools used

Bash, Read, Grep.

## Time budget

5–15 min.
