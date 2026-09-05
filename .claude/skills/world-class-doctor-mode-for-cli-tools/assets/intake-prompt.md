# Intake Prompt (verbatim)

Use this at the very start of a skill invocation to gather inputs.

---

I'll build (or upgrade) a `doctor` subcommand on a CLI tool. Before I start, I need to confirm the scope.

**1. Target repo path.** Absolute path to the repo (e.g., `/data/projects/beads_rust`) or a git URL I should clone to `/tmp/<basename>`. I'll never clone to a path you didn't approve.

**2. Binary name(s) the project produces.** I'll auto-detect via `scripts/discover-cli.sh`, but please confirm. Multiple binaries → each gets its own scorecard slice.

**3. Existing doctor surface?** I'll probe `<tool> doctor`, `health`, `verify`, `repair`, `check`, `diagnose`, `fix`. If one exists, I'll snapshot its current behavior into `<workspace>/baseline/` (its `--help`, `--json` on healthy + corrupted fixtures, exit-code dictionary) so the upgrade can be scored against it.

**4. In-place or worktree?** Default: **worktree** at `<repo>__doctor_workspace/worktree/` on branch `doctor-mode-pass-<N>`. The worktree shares the parent repo's `.git/` (via `git worktree add`, NOT a fresh `git init`). If you'd rather work in-place on the main checkout, say so.

**5. Mode.** Auto-detected:

- **`add`** — no existing doctor. Build from scratch.
- **`upgrade`** — existing diagnostic surface. Snapshot baseline, score against it.
- **`audit-only`** — score the current binary only; no code changes.
- **`re-score-only`** — resumed run; score against current `target_sha`.
- **`single-failure-mode-rescore`** — one detector/fixer changed; re-score that FM only.
- **`absorb-playbook`** — convert a manual playbook skill (e.g., `fixing-beads-problems`) into automated `<tool> doctor --fix`.

I'll show the auto-detect reasoning and let you override.

**6. Toolchain consent.** Phase 5 invokes the binary; if `cargo` / `go` / `uv` / `bun` / `npm` / `pnpm` / `mix` / `cmake` is missing for the target's language, I'll ask before installing.

**7. Triangulation appetite.** `none` | `peer-claude` (two Claude subagents) | `multi-model` (Claude + Codex + Gemini via `/multi-model-triangulation`). Default: `peer-claude` for `audit-only`, `multi-model` for `add`/`upgrade`.

**8. CASS mining appetite.** `skip` | `quick` (10 canned queries) | `deep` (38+ queries against your prior agent sessions). Default: `quick` for first pass, `skip` on resumed passes.

**9. Online appetite.** `offline-only` (default; doctor works in a sandbox with no network) | `online-allowed` (network probes opt-in via `--online`).

**10. Branch protection + safe push policy.** Confirmed: feature branch only; I never push to `main`/`master`; merging is your call. I'll commit per phase so the diff is reviewable.

**11. `jsm` autoinstall consent.** I'll inventory referenced helper skills (`/codebase-archaeology`, `/codebase-report`, `/agent-mail`, etc.). For any missing skill, may I run `jsm install <name>` to install? If `jsm` itself is missing, I'll offer the official installer (`curl -fsSL https://jeffreys-skills.md/install.sh | bash`).

**12. "Must not touch" list.** Anything in the target repo I should NOT modify under any circumstance? E.g., a particular existing flag, a config file, a deprecation policy ("you may add but never remove"). I'll record this in `<workspace>/phase0_scope_decision.md`.

Once you answer, I'll send the matching kickoff prompt from `references/methodology/KICKOFF-PROMPTS.md` verbatim and start Phase 0.
