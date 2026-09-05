# SKILL-FALLBACKS.md — Inline Behavior When Helper Skills Are Missing

<!-- TOC: Helper skill inventory | Per-skill fallbacks | jsm installation prompts | Inline fallback summary -->

This skill references many adjacent skills as subroutines. When `jsm` is unavailable or a helper skill isn't installed, this file documents the inline fallback behavior so the phase loop never blocks.

---

## Helper skill inventory

`scripts/check-skills.sh` produces `phase0_skill_inventory.json`:

```json
{
  "checked_at": "2026-05-06T19:00:00Z",
  "jsm_available": true,
  "jsm_authenticated": true,
  "skills": {
    "ntm":                      {"installed": true, "via": "jsm", "version": "..."},
    "vibing-with-ntm":          {"installed": true, "via": "jsm"},
    "agent-mail":               {"installed": true, "via": "jsm"},
    "beads-br":                 {"installed": true, "via": "jsm"},
    "beads-bv":                 {"installed": true, "via": "jsm"},
    "cass":                     {"installed": false, "via": null},
    "cass-memory":              {"installed": false},
    "flywheel":                 {"installed": false},
    "multi-model-triangulation":{"installed": true},
    "operationalizing-expertise":{"installed": true},
    "idea-wizard":              {"installed": true},
    "multi-pass-bug-hunting":   {"installed": true},
    "ubs":                      {"installed": false},
    "open-beads-weighted-tmux-agent-sessions": {"installed": false},
    "codebase-archaeology":     {"installed": true},
    "codebase-report":          {"installed": true},
    "reality-check-for-project":{"installed": false},
    "modes-of-reasoning-project-analysis": {"installed": false},
    "fixing-beads-problems":    {"installed": true}
  }
}
```

`scripts/install-referenced-skills.sh` reads this and bulk-installs missing skills via `jsm install`. If `jsm` isn't available, install-referenced-skills.sh prints a summary and exits non-zero — the operator decides whether to install `jsm` first.

---

## Per-skill fallbacks

### `/ntm` missing

**Impact:** Cannot use `--robot-*` flags, can't spawn pipeline, can't manage panes.

**Fallback:** Use raw `tmux` + `tmux send-keys`. Strongly degraded; this skill effectively requires `/ntm` to function.

**Recommendation:** Install `/ntm` before proceeding. Skill exits with hard warning if `/ntm` missing.

### `/vibing-with-ntm` missing

**Impact:** Operator-loop card library unavailable. Stuck-pane recovery is ad hoc.

**Fallback:** This skill ships a minimal subset of operator cards inline (rate-limit probe, stuck-pane ladder, convergence check). Use them.

**Recommendation:** Install `/vibing-with-ntm` for the full 38-card library.

### `/agent-mail` missing

**Impact:** Cannot use MCP macros directly.

**Fallback:** This skill's [AGENT-MAIL-CONVENTIONS.md](AGENT-MAIL-CONVENTIONS.md) covers the primitives we need. The MCP server still works without the skill installed. Or use [AGENT-MAIL-FALLBACKS.md](AGENT-MAIL-FALLBACKS.md) for ntm-inbox mode.

**Recommendation:** Optional — MCP works without the skill.

### `/beads-br` missing

**Impact:** Agents lose the full beads CLI reference, but the `br` binary is still the load-bearing dependency.

**Fallback:** `br` binary is required regardless of skill installation. The skill is just documentation; the CLI is the load-bearing tool. If `br` binary missing: install per https://github.com/Dicklesworthstone/beads_rust.

**Recommendation:** Install `/beads-br` for the full reference; install the `br` binary if missing.

### `/beads-bv` missing

**Impact:** No graph-aware triage.

**Fallback:** Use `br ready --json` directly. Lose PageRank, critical-path, cycles analysis. For Phase 4 H-prioritization, simple confidence-sort works as a substitute.

**Recommendation:** Optional but recommended for Squad+ tier.

### `/cass` missing

**Impact:** Phase 1 prior-session mining unavailable.

**Fallback:** Skip the cass-miner subagent at Phase 1. Use repository history, local notes, direct corpus reads, or manual searches of prior session archives if they are locally available.

**Recommendation:** Optional but high-value for resume/drift checks.

### `/cass-memory` missing

**Impact:** Procedural memory lookups and `cm` playbook guidance are unavailable.

**Fallback:** Continue with the explicit phase loop and CASS mining. Do not block on memory; just note the missing source in the phase proof card.

**Recommendation:** Optional but useful for long-running repeated research programs.

### `/flywheel` missing

**Impact:** N/A — flywheel is referenced for methodology mining (extracting *your own* methodology), not used in-loop.

**Fallback:** None needed.

**Recommendation:** Not used by this skill directly.

### `/multi-model-triangulation` missing

**Impact:** Phase 6 invokes this skill to generate a third independent reconciliation as a cross-check.

**Fallback:** Skip the cross-check. The meta-synthesizer pane produces the only reconciliation. This is *worse* (no third opinion) but still functional.

**Recommendation:** Strongly recommended for Phase 6 quality.

### `/operationalizing-expertise` missing

**Impact:** N/A — this skill's KERNEL.md and OPERATORS.md already follow the Track A pattern from `/operationalizing-expertise`.

**Fallback:** None needed.

**Recommendation:** Read it for context; not used in-loop.

### `/idea-wizard` missing

**Impact:** Phase 3 hypothesis generation breadth is reduced.

**Fallback:** Each Proposer pane runs MO-03a-propose.md without idea-wizard expansion. Hypothesis generation still happens; just narrower.

**Recommendation:** Recommended for Squad+ tier.

### `/multi-pass-bug-hunting` missing

**Impact:** Phase 7 audit loses the dedicated bug-hunting harness.

**Fallback:** Phase 7 fresh-eyes still runs the verbatim trio. `/ubs` covers most of the bug-hunting surface for code in `deliverables/scripts/`.

**Recommendation:** Optional; useful when `deliverables/` contains nontrivial code.

### `/ubs` missing

**Impact:** Cannot run `ubs` on code in `deliverables/scripts/`. Phase 7 hard-block (F-703) skipped.

**Fallback:** Use language-specific linters: `ruff`, `eslint`, `golangci-lint`, etc. Or skip the code audit and warn the user.

**Recommendation:** Recommended when deliverables contain code.

### `/open-beads-weighted-tmux-agent-sessions` missing

**Impact:** Cannot use the bead-backlog-weighted spawn pattern.

**Fallback:** Use `ntm spawn --cc=N` directly with operator-chosen counts. Skill works fine without it for greenfield sessions.

**Recommendation:** Optional. Mostly useful when resuming a session with existing bead backlog.

### `/codebase-archaeology` missing

**Impact:** Code-investigation mode loses the archaeology subagent for Phase 1.

**Fallback:** Operator manually runs `git log`, `tree`, `cloc`, ripgrep across the target codebase to produce `intake/target_inventory.md`.

**Recommendation:** Strongly recommended for code-investigation mode.

### `/codebase-report` missing

**Impact:** Code-investigation mode lacks the architecture-doc generator.

**Fallback:** `intake/target_inventory.md` is sparser. Operator may write architecture notes by hand.

**Recommendation:** Recommended for code-investigation mode.

### `/reality-check-for-project` missing

**Impact:** Phase 1 cannot run reality-check on the target if it's a project with claimed features.

**Fallback:** Skip; flag in scope_decision.

**Recommendation:** Optional.

### `/modes-of-reasoning-project-analysis` missing

**Impact:** Phase 6 distillations don't have the symbolic-vs-neural / fast-vs-deep mode lens.

**Fallback:** Distillations proceed without this lens. Quality is reduced for theory-heavy questions.

**Recommendation:** Recommended for theoretical questions.

### `/fixing-beads-problems` missing

**Impact:** When F-802 fires (bead drift), no specialized recovery skill.

**Fallback:** Manual recovery: first run `br sync --flush-only`; if that fails, copy `.beads` to `.beads-backup-<ts>` and stop for explicit operator approval before any quarantine/rebuild step. Do **not** run `rm -rf .beads` or replace the bead store automatically; destructive recovery requires the exact user authorization demanded by AGENTS.md.

**Recommendation:** Required if bead drift ever occurs.

---

## `jsm` installation prompts

If `jsm` itself is missing, the skill prompts the user:

```
The brennerbot-with-ntm skill references several helper skills.
You don't have `jsm` installed; without it, those skills must be installed manually
or the skill will use inline fallbacks (degraded quality).

Install jsm? (Linux/macOS):
  curl -fsSL https://jeffreys-skills.md/install.sh | bash
  jsm login

This requires a paid jeffreys-skills.md subscription ($20/month) to install premium skills.
The skill will still run with inline fallbacks if you decline.

Proceed without jsm? [y/N]
```

---

## Inline fallback summary

| Helper skill missing | Severity | Phase impact | Inline fallback |
|----------------------|----------|--------------|-----------------|
| `/ntm` | hard-required | All | install or abort |
| `/beads-br` skill or `br` binary | hard-required binary; recommended skill | All | install binary or abort; use skill docs when available |
| `/agent-mail` (MCP server) | strong | 2, 4, 5, 6 | ntm-inbox fallback |
| `/vibing-with-ntm` | recommended | All | inline cards (subset) |
| `/beads-bv` | recommended | 3, 4 | `br ready --json` |
| `/multi-model-triangulation` | recommended | 6 | skip cross-check |
| `/idea-wizard` | optional | 3 | narrower generation |
| `/cass` | optional | 1 | skip prior-session mining |
| `/cass-memory` | optional | 0, 1, 10 | skip procedural memory lookup |
| `/codebase-archaeology` | recommended (code mode) | 1 | manual archaeology |
| `/codebase-report` | recommended (code mode) | 1 | sparse target inventory |
| `/multi-pass-bug-hunting` | optional | 7 | `ubs` covers most |
| `/ubs` | recommended | 7 | language-specific linters |
| `/fixing-beads-problems` | recommended on F-802 | 8 | manual recovery |
| Others | optional | varies | skip with note |

The skill records every fallback in `phase0_skill_inventory.json § fallbacks_active:` so Phase 10 drift-check can flag if a fallback degraded methodology.
