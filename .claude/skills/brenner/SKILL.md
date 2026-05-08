---
name: brenner
description: >-
  Brenner Bot CLI for research sessions. Use when in your brenner_bot repo,
  managing hypotheses, searching corpus, or running multi-agent sessions.
---

# Brenner Bot

> **Core Insight:** Exclusion beats confirmation. Design experiments to kill hypotheses, not prove them. A theory that survives elimination is stronger than one with supporting evidence.

## Install

**Repo:** https://github.com/Dicklesworthstone/brenner_bot

**Runtime:** Prebuilt TypeScript binary (compiled with Bun) — no Rust toolchain needed.

### Quick install (Linux x64 / WSL)

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/brenner_bot/main/install.sh?$(date +%s)" \
  | bash -s -- --easy-mode --verify
```

Downloads `brenner-linux-x64` (~93 MB) to `~/.local/bin/brenner` and verifies SHA256. Installer also pulls `ntm`, `cass`, `cm` from their upstream manifests.

### Build from source

```bash
curl -fsSL https://bun.sh/install | bash      # if bun missing
git clone https://github.com/Dicklesworthstone/brenner_bot.git
cd brenner_bot
bun build --compile ./brenner.ts --outfile brenner
cp brenner ~/.local/bin/brenner
```

### Prerequisites

| Requirement | Notes |
|---|---|
| Linux x64 or macOS | WSL1/WSL2 both supported (use Linux x64 binary) |
| `~/.local/bin` in PATH | fish: `fish_add_path ~/.local/bin` |
| Agent Mail server | `am` alias starts it; required for session commands |
| `OPENAI_API_KEY` | Set in env or `.env` in project root |

### Smoke test

```bash
brenner --version
brenner doctor --skip-ntm --skip-cass --skip-cm --json | jq '.status'   # expect "healthy"
```

---

## Table of Contents

[THE EXACT PROMPT](#the-exact-prompt--research-session-workflow) | [When to Use What](#when-to-use-what) | [Critical Constraints](#critical-constraints) | [Artifact Schema](#7-section-artifact-schema) | [Heuristics](#heuristics) | [References](#references)

---

## THE EXACT PROMPT — Research Session Workflow

```
1. Health Check: Verify toolchain before any session
   brenner doctor --skip-ntm --skip-cass --skip-cm --json

2. Corpus Search: Find relevant Brenner transcript sections
   brenner corpus search "model organism"
   brenner corpus search "reduction to one dimension"

3. Build Excerpt: Create cited context (ALWAYS before session)
   brenner excerpt build --sections 58,78,161 > excerpt.md

4. Start Session: Launch multi-agent research thread
   brenner session start \
     --project-key "$PWD" \
     --sender GreenCastle \
     --to BlueLake \
     --thread-id RS-$(date +%Y%m%d)-SLUG \
     --excerpt-file excerpt.md \
     --question "Your research question here"

5. Monitor: Check session progress
   brenner session status --thread-id RS-YYYYMMDD-SLUG
   brenner mail agents --project-key "$PWD"

6. Compile: Merge agent deltas into artifact
   brenner session compile --thread-id RS-YYYYMMDD-SLUG

7. Validate: Lint against 50+ Brenner-style rules
   brenner artifact lint artifact.md
   brenner artifact nudge artifact.md
```

### Why This Workflow Works

- **Doctor first** — Catch toolchain issues before wasting a session
- **Excerpts before sessions** — Corpus context grounds the research
- **Thread ID consistency** — Same ID across Agent Mail, ntm, artifacts
- **Compile frequently** — Don't wait for session end; incremental merges

---

## When to Use What

| You Want | Use | Why |
|----------|-----|-----|
| Start research | `session start` with excerpt | Corpus context grounds everything |
| Find quotes | `corpus search "term"` | 236 sections with §n anchors |
| Check progress | `session status --thread-id` | See agent activity |
| Merge outputs | `session compile` | Deterministic delta merge |
| Validate artifact | `artifact lint` then `nudge` | 50+ Brenner-style rules |
| Debug setup | `doctor --skip-ntm --skip-cass --skip-cm` | Minimal health check |

---

## Critical Constraints

1. **No vendor API calls** — Use CLI tools via ntm, not direct API calls
2. **Thread ID is the join key** — Same ID across Agent Mail, ntm, artifacts, beads
3. **Agent names = adjective+noun** — GreenCastle, BlueLake, RedStone
4. **Always build excerpts first** — Corpus context before session start
5. **Third alternative required** — Every hypothesis slate needs "both could be wrong"

## Thread ID Formats

| Context | Format | Example |
|---------|--------|---------|
| Research sessions | `RS-{YYYYMMDD}-{slug}` | `RS-20260119-cell-fate` |
| Engineering work | Bead ID directly | `brenner_bot-5so.3.4.2` |

## 7-Section Artifact Schema

Research artifacts must contain:

1. **research_thread** — Stable problem statement
2. **hypothesis_slate** — 2-5 hypotheses (must include "both wrong" third alternative)
3. **predictions_table** — Discriminative predictions per hypothesis
4. **discriminative_tests** — Ranked "decision experiments"
5. **assumption_ledger** — Load-bearing assumptions + scale/physics checks
6. **anomaly_register** — Explicitly quarantined exceptions
7. **adversarial_critique** — What would make the whole framing wrong?

## Delta Operations

Agents emit changes via fenced JSON blocks:

```json brenner-delta
{
  "operation": "ADD",
  "target_section": "hypothesis_slate",
  "payload": {
    "id": "H3",
    "statement": "Both mechanisms are wrong",
    "state": "proposed"
  },
  "rationale": "Third-alternative injection per Brenner operator #3"
}
```

| Operation | Behavior |
|-----------|----------|
| `ADD` | Insert new item (no target_id) |
| `EDIT` | Modify existing (requires target_id) |
| `KILL` | Mark as killed (requires target_id) |

## Key Brenner Operators

| # | Operator | Core Insight |
|---|----------|--------------|
| 1 | Model Organism Selection | Choose simplest system preserving phenomenon |
| 2 | Reduction to One Dimension | Strip to A→B→C causal chain |
| 3 | Third Alternative Injection | "Both could be wrong" |
| 4 | Potency Test | Distinguish "didn't" from "couldn't" |
| 5 | Reconstruction Criterion | Build it from primitives or you don't understand |
| 7 | Exclusion Over Confirmation | Design to kill hypotheses, not confirm |

**Full operators**: See [references/OPERATORS.md](references/OPERATORS.md)

## Heuristics

| Signal | Meaning | Action |
|--------|---------|--------|
| Lint fails HYP-002 | Missing third alternative | Add "both wrong" hypothesis |
| `line_number` 1-3 in corpus | Key Brenner quote | Use §n citation format |
| Session status "stalled" | No deltas in 10+ min | Check Agent Mail, nudge agents |
| Artifact >5 hypotheses | Scope creep | Kill or merge hypotheses |
| Anomaly count >3 | Quarantine overload | Review if pattern emerges |
| No potency control (TEST-003) | Uninformative negatives | Add positive control to test |

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| "Missing --question" | Required flag for session start |
| "Missing --sender" | Add `--sender GreenCastle` or set `AGENT_NAME` env |
| "Agent Mail not available" | Start Agent Mail server on localhost:8765 |
| Invalid agent name | Use adjective+noun format (GreenCastle, BlueLake) |
| Lint fails silently | Run with `--json` for detailed rule violations |
| Deltas not merging | Check thread ID matches across all systems |

## References

| Need | Reference |
|------|-----------|
| Brenner's 13 operators | [OPERATORS.md](references/OPERATORS.md) |
| 50+ linting rules | [LINTING-RULES.md](references/LINTING-RULES.md) |
| Delta format details | [DELTA-FORMAT.md](references/DELTA-FORMAT.md) |
| Tribunal personas | [TRIBUNAL.md](references/TRIBUNAL.md) |
| Workflow recipes | [RECIPES.md](references/RECIPES.md) |
| Prediction locks, hypothesis arena | [ADVANCED.md](references/ADVANCED.md) |

---

## Validation

```bash
# Quick health check
brenner doctor --skip-ntm --skip-cass --skip-cm --json | jq '.status'

# Should return: "healthy"
```

If unhealthy, check:
1. Agent Mail server running on localhost:8765
2. Corpus files present in `$BRENNER_ROOT/corpus/`
3. Bun runtime available

---

## Related Skills

- `agent-mail` — Agent Mail coordination
- `ntm` — Multi-agent tmux orchestration
- `cass` — Session archaeology
- `br` — Beads task tracking
