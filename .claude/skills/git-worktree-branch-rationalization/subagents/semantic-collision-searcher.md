---
name: semantic-collision-searcher
description: Phase 7 — alongside `harmonization-planner` in Comprehensive / Council mode. Uses semantic search (via /frankensearch-integration if available; otherwise embedding-based ripgrep fallback) to find collisions that file-path matching misses — e.g., a `redact_secrets` function in `logger.rs` on branch A and a `sanitize_log_line` function in `log_filter.rs` on branch B may be DIFFERENT IMPLEMENTATIONS of the same conceptual feature. Surface to harmonization-planner with high-collision-confidence so the variant matrix doesn't miss them. Output: `semantic_collisions.md` augmenting `harmonization_plan.md`.
---

# Semantic Collision Searcher

Companion to `harmonization-planner`. The harmonization planner builds variant matrices for files touched by ≥2 branches via *file-path* matching. That catches direct collisions: branch A and branch B both modified `src/redact.rs`. But it misses *conceptual* collisions: branch A added a `redact_secrets` function to `src/logger.rs`, and branch B added a `sanitize_log_line` function to `src/log_filter.rs` — different paths, different names, but the same conceptual feature ("filter sensitive data from log output before emission").

If both branches' implementations land independently, the project ends up with two semi-overlapping APIs doing similar things. The semantic collision searcher's job is to surface these conceptual collisions so the harmonization-planner can fold them into a single variant matrix and propose one synthesis instead of two parallel implementations.

The searcher uses semantic search (embedding-based) when `/frankensearch-integration` is available; otherwise falls back to embedding-based ripgrep (a simpler keyword-clustering approach that catches the lower-hanging fruit). Findings augment `harmonization_plan.md`; they don't replace it.

## When invoked

Phase 7, in parallel with `harmonization-planner`. Active by default in Comprehensive and Council modes; opt-in for Standard mode (off by default in Quick mode — the conceptual-collision rate is too low to justify the cost in repos with <30 branches).

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{TRIAGE}` — `<workspace>/triage.tsv` (frozen at Phase 6)
- `{HARMONIZATION_PLAN}` — `<workspace>/harmonization_plan.md` (concurrent — may be partial)
- `{MODE}` — Comprehensive / Council / (Standard with explicit opt-in)
- `{SEARCH_BACKEND}` — `frankensearch` if available, else `ripgrep-fallback`

## Outputs

- `<workspace>/semantic_collisions.md` — human-readable cluster report: one section per detected cluster with `cluster_intent_hypothesis`, members table (branch, file, symbol, similarity), recommended harmonization-plan addition; plus optional Single-branch findings section.
- `<workspace>/semantic_collisions.json` — machine-readable cluster data consumed by `harmonization-planner` when building variant matrices.
- `<workspace>/semantic/<slug>/symbols.jsonl` — per-branch extracted symbols (slug, file_path, symbol_name, symbol_kind, signature, body_excerpt, surrounding_comments).
- `<workspace>/semantic/index/` — frankensearch index when frankensearch backend is used (mv to `.archived/` on cleanup, never `rm`).
- `<workspace>/semantic/cache/<corpus-hash>/results.jsonl` — pairwise-search cache for resume-aware re-runs.
- `<workspace>/semantic/skipped.txt` — written when neither backend is usable; contains skip reason.
- **Side effects:** read-only on source. Disk-space check (refuses to index if free space < 1 GB). Never `rm -rf`s the index — uses `mv` to `.archived/`. Never pushes.
- **Decision contract:** confidence-gated — frankensearch ≥0.65, ripgrep-fallback ≥0.4. Below threshold not surfaced. `harmonization-planner` reads `semantic_collisions.json` and adds clusters to `harmonization_plan.md`; if Phase 7 already approved by user, supplemental clusters trigger `phase7_supplement_authorization.txt` user gate before integration.

## Workflow

### 1. Build the search corpus

For every branch with verdict ∈ {`novel-and-accretive`, `partially-novel`, `divergent-refactor`, `dirty-worktree-only`} in `triage.tsv`, extract function/method/type definitions from its diff:

```bash
# Per branch, dump all introduced symbols with their surrounding context
for SLUG in $(awk -F'\t' 'NR>1 && $V ~ /(novel-and-accretive|partially-novel|divergent-refactor|dirty-worktree-only)/ {print $S}' triage.tsv); do
  # Use language-aware extraction per references/LANGUAGE-PROFILES.md
  ./scripts/extract-introduced-symbols.sh "<bundle>/branches/<slug>/diff-vs-merge-base.diff" \
      --output "<workspace>/semantic/<slug>/symbols.jsonl"
done
```

Each row in `symbols.jsonl` captures: `slug`, `file_path`, `symbol_name`, `symbol_kind` (function / type / class / module), `signature`, `body_excerpt` (first 20 lines), `surrounding_comments`.

### 2. Embed the corpus

If `{SEARCH_BACKEND}` is `frankensearch` (the project has the integration installed):

```bash
# Build a one-shot index over symbols.jsonl entries
fwc index build \
    --source "<workspace>/semantic/*/symbols.jsonl" \
    --index "<workspace>/semantic/index" \
    --embedder default
```

If `{SEARCH_BACKEND}` is `ripgrep-fallback`: cluster symbols by lexical similarity using:
- Token n-grams over `symbol_name` (catches `redact_secrets` ~ `sanitize_log_line` poorly; catches `redact_secrets` ~ `redactSecrets` ~ `redact-secrets` well)
- Doc-comment keyword overlap (catches "remove sensitive data from logs" ~ "filter sensitive log content" reasonably)
- Combine via Jaccard similarity over the union; keep pairs above threshold 0.4

The fallback is intentionally lower-recall; it catches obvious collisions and surfaces them. The frankensearch backend catches subtler ones via dense embeddings.

### 3. Pairwise search across branches

For every pair (`branch_A`, `branch_B`) in the candidate set, search for cross-branch matches:

For each symbol `S_A` in branch A's symbols.jsonl:
- Query the search index (or fallback cluster) for top-K nearest neighbors restricted to branch B's symbols
- For each match `S_B` with similarity ≥ threshold (0.65 for frankensearch; 0.4 for fallback): record a candidate collision

Record each candidate collision: `branch_A`, `symbol_A`, `file_path_A`, `branch_B`, `symbol_B`, `file_path_B`, `similarity_score`, `matched_via` (`name` / `comment` / `signature` / `body`).

Filter:
- Drop pairs where `file_path_A == file_path_B` (those are already covered by the harmonization-planner's path-based matching)
- Drop pairs where `symbol_kind` differs (a function and a type definition are unlikely conceptual collisions)
- Drop trivial overlaps (e.g., both branches added a `main()` function — uninformative)

### 4. Group candidates into conceptual collision clusters

A collision may involve more than two branches. Build clusters via union-find on the candidate-collision graph:
- Edge: similarity ≥ threshold
- Node: (branch_slug, symbol_name, file_path)

A cluster is a connected component. Each cluster represents one conceptual feature implemented variously across N branches.

For each cluster, compute:
- Cluster `cluster_id` (deterministic — hash of sorted node list)
- `cluster_size` (number of branches involved)
- `cluster_intent_hypothesis` — the conceptual feature in plain English. For frankensearch backend, derive from the centroid embedding's nearest-cluster-label (k-means on doc-comment text). For fallback, use the most common token in symbol names.
- `confidence` — based on max pairwise similarity within the cluster

### 5. Emit `semantic_collisions.md`

```markdown
# Semantic Collision Findings

Generated: <UTC>
Search backend: <frankensearch | ripgrep-fallback>
Clusters detected: <count>
Confidence range: <min>–<max>

## Cluster 1 — log redaction / sanitization (confidence 0.92)

Conceptual feature: filter sensitive data (API keys, secrets, PII) out of log output before emission.

| branch | file | symbol | similarity to centroid |
|---|---|---|---|
| agent-cleanup-pass-3 | src/logger.rs | `redact_secrets()` | 0.96 |
| feature/log-filter | src/log_filter.rs | `sanitize_log_line()` | 0.91 |
| wip/observability | src/observability/scrubber.rs | `scrub_pii()` | 0.85 |

Recommended harmonization-plan addition: build a variant matrix grouping these three implementations
under one conceptual feature; propose a single synthesis (likely on top of `src/logger.rs`'s structure
since it's the most central) that subsumes all three.

## Cluster 2 — error envelope wrapping (confidence 0.78)

...

## Single-branch findings (no cross-branch collision; for awareness)

(Optional section — symbols that appeared as outliers in the search but didn't cluster.
Surface as "potentially-novel-without-conflict" so the harmonization-planner doesn't mistakenly
look for collisions that aren't there.)

## How this augments harmonization_plan.md

Each cluster above should be added to `harmonization_plan.md` as a new file row (or a synthetic
"cross-file" row) with the variant matrix populated from the cluster members. The
harmonization-planner will read this file and integrate.
```

### 6. Hand off to harmonization-planner

Write `<workspace>/semantic_collisions.json` (machine-readable) alongside `semantic_collisions.md`. The harmonization-planner reads the JSON when building variant matrices and adds rows for any cluster not already covered by file-path matching.

If the harmonization-planner already finished and the user gate is approved (Phase 7 done), the searcher's findings are routed to a `phase7_supplement_authorization.txt` gate — the user reviews the new clusters and authorizes adding them to the plan, retriggering the relevant slice of harmonization-planner.

## Critical rules

- **Read-only on source.** The searcher reads bundle artifacts and (if frankensearch) builds a one-shot index in the workspace. No source-file mutation.
- **Confidence-gated.** Below 0.65 (frankensearch) / 0.4 (fallback), don't surface. Below those thresholds the noise floor swamps the signal.
- **Don't propose synthesis.** The searcher surfaces clusters; the harmonization-planner builds variant matrices and proposes synthesis. Boundary-respect avoids two subagents racing on the same file.
- **Skip the index build if disk-constrained.** Frankensearch indexes are typically 50–200 MB; check `df` for `<workspace>`'s mount before indexing; surface a "skipped due to disk" recommendation if free space < 1 GB.
- **Don't re-run pairwise search if cached.** Resume-aware: read `<workspace>/semantic/cache/<corpus-hash>/results.jsonl` if present.
- **Skip silently when neither backend is usable.** If frankensearch isn't installed AND ripgrep isn't available, write `<workspace>/semantic/skipped.txt` and exit with `decision: skipped`.
- **Per AGENTS.md "No Script-Based Changes":** never run sed/awk on source files.
- **Per AGENTS.md "Note for Codex/GPT-5.5":** never disturb concurrent agents' working-tree state in any worktree.
- **Per AGENTS.md RULE NUMBER 1:** never delete files without express user permission. The frankensearch index is created in `<workspace>/semantic/index/`; cleanup is `mv` to `.archived` per the no-deletion rule.
- **Never bypass pre-commit hooks** (no commits here).
- **Never run mass-delete primitives.**
- **Never push.** Index + findings stay local.
- **Never run `git push --delete` or force-push.**

## Coordination

- File reservation: `paths=["<workspace>/semantic/**", "<workspace>/semantic_collisions.md", "<workspace>/semantic_collisions.json"]`, `exclusive=true`, `reason="branch-rationalization-semantic-search"`, `ttl_seconds=7200`.
- Thread id: `branch-rationalization-<run-id>`.
- Coordinates with `harmonization-planner`: writes `semantic_collisions.json` which the planner reads when building variant matrices.

## Quality gates

- [ ] `semantic_collisions.md` exists with one section per detected cluster (or a "no clusters detected" notice)
- [ ] Every cluster has ≥2 members
- [ ] Every cluster has a confidence score; below-threshold candidates are filtered out
- [ ] `semantic_collisions.json` is valid JSON; harmonization-planner can ingest it
- [ ] Search backend is recorded (`frankensearch` or `ripgrep-fallback` or `skipped`)
- [ ] No source-file modifications by the searcher
- [ ] If skipped due to disk, the reason is recorded and the harmonization-planner proceeds with file-path matching only

## Exit criteria

`semantic_collisions.md` + `semantic_collisions.json` written. The harmonization-planner integrates the clusters into `harmonization_plan.md` (either during the initial Phase 7 fan-out or via a Phase 7 supplement after the initial user gate). The user sees the augmented plan before Phase 8 mutates anything.
