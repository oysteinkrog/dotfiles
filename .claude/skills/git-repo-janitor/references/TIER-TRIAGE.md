# Tier Triage

Repos vary in size by 5+ orders of magnitude (a 12-file skill repo to a 100k-file monorepo). The skill scales depth-of-work by tier; Phase 0 picks one based on `git ls-files | wc -l` plus a complexity overlay.

This is orthogonal to mode (OPERATING-MODES.md). A repo can be `T3 + full` or `T1 + triage-only`, etc.

---

## Tier definitions

| Tier | Tracked file count | Rough characterization | Default orchestration (worker tier, variant) |
|------|--------------------|-----------------------|----------------------------------------------|
| **T1** | <100 | Skill repos, small CLIs, tiny libraries | Solo, Quick variant |
| **T2** | 100–1,000 | Single-language single-purpose repos | Pair, Standard variant |
| **T3** | 1,000–20,000 | Mid-size multi-package projects, mature single repos | Squad, Standard variant |
| **T4** | 20,000–100,000 | Large monorepos, mature platforms | Swarm, Comprehensive variant |
| **T5** | 100,000+ | Industrial monorepos (Google/Facebook scale; rare) | Council + sub-tree partitioning required |

---

## Complexity overlay

Each "+1" pushes the run one tier deeper or doubles the candidate-discovery scope:

| +1 trigger | Why |
|-----------|-----|
| LFS-tracked files present | Bundle smudging adds 30%+ to Phase 3 wall time; LFS pointer mismatches are subtle |
| Submodules present (any) | Submodule pointer triage is a separate phase; rewinds and `-dirty` markers add risk |
| Repo age >5 years | Long history may have legacy patterns (e.g., pre-Cargo.lock) that don't fit modern archetype rules |
| 3+ programming languages | Polyglot increases REFERENCE-GREP scope; smell rules per language compose |
| Vendored dependencies tracked at root | Increases candidate count without being junk; protected_globs need expansion |
| `.gitignore` >200 lines | Pre-existing complexity; SHADOWING-AUDIT will surface more conflicts |
| 2+ recovery branches from prior cleanups | Coordinating with prior runs requires careful resumability |
| Pre-commit hook framework (husky/lefthook/pre-commit) installed | Phase 6/7/8 commits may trigger hooks; coordinate carefully |
| Branch synonyms (main:master mirror) | Push commands double; force-with-lease must succeed on both |
| External-primary-development repo (per AGENTS.md / MEMORY.md) | Treat as read-only; refuse any mutation without explicit override |

A T2 repo with 4 complexity points effectively becomes T4 for orchestration purposes.

---

## Per-tier sizing

### T1 (<100 files)

- **Inventory:** runs in seconds; no batching needed
- **Bundle:** trivial; entire candidate set fits in MB
- **Triage:** single agent, ~5–25 candidates
- **Apply:** sequential per category; gates run in seconds
- **Wall time:** 20–40 minutes including user gates

Typical examples: a Claude skill repo, a small CLI, an internal tool.

### T2 (100–1,000)

- **Inventory:** seconds; can use `--preview` for fast user feedback
- **Bundle:** seconds to minutes
- **Triage:** Pair tier; 2 workers ~30 candidates each
- **Apply:** sequential; gates run in 1–3 minutes per commit
- **Wall time:** 1–4 hours

Typical examples: a single Rust crate, a Python package, a Go CLI.

### T3 (1k–20k)

- **Inventory:** 10s to a couple of minutes; batch the file walk
- **Bundle:** longer due to LFS / large blobs; verify byte-equality in chunks
- **Triage:** Squad tier; 4–6 workers
- **Apply:** sequential; gates run several minutes per commit (incremental cargo, etc.)
- **Wall time:** 2–6 hours

Typical examples: mature single-language repos with many subdirectories, or modest monorepos.

### T4 (20k–100k)

- **Inventory:** minutes; consider partitioning by top-level dir
- **Bundle:** carefully, with LFS smudging in parallel
- **Triage:** Swarm tier; 8–12 workers per subtree
- **Apply:** Sequential per subtree; gates may take 10+ min
- **Wall time:** 4–10 hours; consider running overnight

Typical examples: a polyglot monorepo with 50+ crates, a Next.js + Rust + Python + Go combo.

### T5 (100k+)

- **`full` mode discouraged** — partition the repo into sub-trees first; run the skill on each sub-tree as a separate T3/T4 run
- **Inventory:** must use `git ls-files <subtree>` not whole-repo
- **Bundle:** per-subtree
- **Triage:** Council tier with multi-model triangulation
- **Apply:** schedule across multiple sessions; use cron-like resumability

Typical examples: industrial monorepos. Rare for individual users.

---

## Per-tier exit-criteria adjustments

### T1: minimal Phase 9
- 1 fresh-eyes round may suffice for a skill repo with 12 candidates
- Polish-bar dimensions 10/11 (idempotence/resumability) may be heuristic

### T2: standard Phase 9
- 2 fresh-eyes rounds
- All polish-bar dimensions checked

### T3: standard Phase 9 + spot-check
- 2 fresh-eyes rounds + a spot-check of 10% of candidates by hand
- All polish-bar dimensions checked

### T4: comprehensive Phase 9
- 3 fresh-eyes rounds with stance variation
- Multi-model triangulation on borderline rows
- Polish-bar dimensions cross-checked by 2 different subagents

### T5: comprehensive Phase 9 + per-subtree
- 3 rounds per subtree
- Council tier (3+ models) for borderline rows
- Polish-bar dimensions verified by automated drift-guards

---

## "Quick / Standard / Comprehensive" mapped to tiers

The original three modes from documentation-website:

| Mode | Default tier | Orchestration | Phase 9 |
|------|--------------|---------------|---------|
| Quick | T1 | Solo | 1 round |
| Standard | T2-T3 | Pair / Squad | 2 rounds |
| Comprehensive | T3-T5 | Squad / Swarm / Council | ≥3 rounds with triangulation |

The user can override at Phase 0: a small repo with Comprehensive (paranoid mode), a large repo with Quick (smoke-test mode).

---

## Tier-specific risks

### T1 risks
- **Over-engineering**: spending 30 minutes on bundle + matrix for a 5-minute manual cleanup
- **Triage worker is overkill**: just classify in-line

### T2 risks
- **Reference rewrites in 1 file are easy**; in 4 files they suddenly aren't
- **First time the user sees the categorical plan**: they may need the most explanation here

### T3 risks
- **Complexity overlay matters most here**: an T3 with 4 complexity points is genuinely T4-tier
- **Build gates start to take real time**: per-commit gates may dominate wall time

### T4 risks
- **Running out of /tmp**: bundle storage + LFS smudge cache; pre-flight `df -h /tmp /var/tmp /home` (cass session B finding)
- **Concurrent agents with their own commits**: the larger the repo, the more concurrent work
- **Reference rewrites cross-package**: may surface 100+ refs needing rewrite

### T5 risks
- **Whole-repo `full` mode is impractical**: 100k files don't fit in a single triage decision table
- **Disk pressure from bundle**: the bundle of a 100k-file repo can be GB
- **Partial-clone interaction**: many T5 repos are partial-cloned; bundle byte-equality checks can fail

---

## Sub-tree partitioning (T5 specific)

For T5 repos, partition the work:

```bash
# Pick a top-level subtree
sub=apps/admin/

# Run the skill scoped to that subtree
PROJECT=/data/projects/big-monorepo SUBTREE=$sub /git-repo-janitor

# Bundle path includes subtree:
# /data/projects/big-monorepo/.repo_janitor_workspace/recovery-bundle-<DATE>/apps-admin/
```

Each subtree gets its own bundle, recovery branch, and handoff. The user runs the skill N times across N subtrees.

The skill detects T5 in Phase 0 and warns: "This is a T5 repo (147k files). Running `full` mode would take 12+ hours and produce a 4GB+ bundle. I recommend partitioning by subtree. Pick one to start with: `apps/`, `services/`, `packages/`, `tools/`, `docs/`, `infra/`?"

---

## When tier scaling is wrong

A T2 repo with 200 candidates can have heavier orchestration than its file count suggests (e.g., a Python project where every `*.py` happens to have a stale import). Adjust by:

- Raising tier (treat as T3 for this run)
- OR raising complexity points (this is the explicit "complexity overlay")
- OR scoping to `triage-only` for a first pass; then `full` after the user reviews

The wills-and-estate-planning-skill calibrates wealth tier from net worth + complexity overlay; we calibrate file tier from file count + complexity overlay.
