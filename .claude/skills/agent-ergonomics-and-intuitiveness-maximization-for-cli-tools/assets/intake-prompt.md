# Intake Prompt

Use this verbatim at the start of a skill invocation. Adjust only the placeholders.

> **Branch policy (read first; do NOT ask the user about this).** This skill never creates a feature branch and never asks about branch names. All applied changes commit directly to the currently checked-out branch of the target repo (typically `main`). If the user explicitly says "use branch X" in their prompt, honor that — otherwise stay on the current branch. The intake below has **no branch question**; do not improvise one.
>
> **Workspace policy (also read first; do NOT ask the user about this).** The audit workspace is a folder inside the target repo at `<target>/agent_ergonomics_audit/`. Never a sibling directory. Never `/tmp/`. Never a separate `git init`. The folder gets committed to the same branch as the code changes. The intake below has **no workspace-location question**; do not improvise one.

---

I'll run an agent-ergonomics audit on `<TOOL>`. Before starting, I need to confirm a few things.

**1. Target.** Is the tool repo at `<TARGET_PATH>`? (If you'd rather I clone a GitHub URL, paste it.)

**2. Audit workspace (FYI, not a question).** I'll write all measurement artifacts (scorecards, surface inventories, recommendations, transcripts) to `<TARGET_PATH>/agent_ergonomics_audit/` — INSIDE the target repo, committed to the same branch as the code changes. No sibling directory. No separate `git init`. If a legacy sibling `<TARGET_BASENAME>__agent_ergonomics_audit/` exists from an old run, I'll migrate its history into the in-tree folder.

**3. Mode.**
- `audit-only` — score every surface; produce recommendations; **no code changes**. Use this only if you explicitly want a review without implementation.
- `full` — **the default.** Audit + apply top recommendations + re-score + write tests + agent-in-the-loop simulation + Ambition Bar self-prompt before declaring done.
- `re-score-only` — only available if a prior pass exists; recompute scores against current HEAD.
- `simulate-only` — fresh-context agent attempts canonical tasks; produces transcripts only.
- `single-surface-rescore` — re-score one named surface.

For any "apply / improve / harden / make agent-friendly" intent, default is `full` regardless of how big the CLI is. (Large tools just have a longer ranked-recommendations list; Phase 4 picks the top-N to actually ship.) Default I'll use unless you say otherwise: `<RECOMMENDED_MODE>`.

**4. Triangulation.**
- `none` — single-agent throughout.
- `peer-claude` — two Claude subagents on key Phase 4 / Phase 7 steps (default).
- `multi-model` — Claude + Codex + Gemini (requires `/multi-model-triangulation`).

**5. CASS mining.** Mine your prior agent sessions for patterns relevant to this tool?
- `skip` — no mining.
- `quick` — 10 canned queries (~30s).
- `deep` — 38+ targeted queries (~3–5min).

Default: `quick` for first pass; `skip` on resumes.

**6. Scope guardrails.** Anything I should NOT touch?
- features you don't want refactored
- deprecation policies (e.g. "you may add but never remove")
- config files that must remain backwards-compatible

**7. Toolchain consent.** If `<TOOL>`'s build toolchain isn't installed (Rust/Go/Python/etc.), should I ask before installing? (default: yes — always ask first)

**8. Ambition.** In `full` mode I aim for ≥ 10 substantive landed changes for a non-trivial CLI (≥ 5 for a tiny one), covering ≥ 3 of the 11 scoring dimensions, plus at least one mega-command / capabilities-or-robot-docs / `--json` / error-rewrite / intent-inference handler when missing. If after Phase 5 I'm short of that bar, I'll auto-run a "That's it??" self-prompt and try one more apply round before Phase 10. Anything you want to cap or push higher?

---

After you answer, I'll send the matching kickoff prompt and start Phase 0.

If any helper skills are missing (`/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/multi-pass-bug-hunting`, `/multi-model-triangulation`, `/ubs`, `/dcg`, `/agent-mail`, `/beads-br`, `/beads-bv`, `/cass`, `/idea-wizard`), and you have `jsm` installed + authenticated, I can offer to `jsm install <name>` for each. Or I can use the inline fallbacks documented in `references/methodology/SKILL-FALLBACKS.md`. Either way, the pass continues.
