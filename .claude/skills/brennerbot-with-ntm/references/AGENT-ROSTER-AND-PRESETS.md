# AGENT-ROSTER-AND-PRESETS.md — Roster Schema, Modes, and Presets

## Table of Contents

- Why a roster
- The schema
- Roster modes
- The 3 edge-case rules
- Roster presets with placeholder names
- Per-tier preset library
- NTM role binding
- Per-role default model preference
- Anti-patterns
- Cross-references

A roster is the explicit mapping from Agent Mail identity names (e.g., `BlueLake`, `PurpleMountain`) to Brenner Protocol roles (`hypothesis_generator`, `test_designer`, `adversarial_critic`). Without explicit mapping, sessions fail in subtle ways: agents receive the wrong prompts; the multi-model triangulation collapses; failures are invisible.

This file specifies the roster schema, the 2 modes, the edge-case rules, and the preset library.

Mined from `/dp/brenner_bot/specs/agent_roster_schema_v0.1.md`.

---

## Why a roster

Three failures of implicit role assignment:

1. **String-match heuristics** ("if name contains 'codex', it's hypothesis_generator") fail for real Agent Mail identities like `BlueLake`
2. **All-agents-same-prompt** loses the multi-model advantage entirely
3. **Silent fallback to default role** masks errors; an unintentional double-Devil's-Advocate session looks normal

Three benefits of explicit roster:

1. **Deterministic role assignment** — explicit; replayable
2. **Multi-model triangulation** preserved — different agents get different role prompts
3. **Validation** — missing mappings fail loudly (not silently)

---

## The schema

```typescript
interface RosterEntry {
  agentName: string;          // Agent Mail identity (REQUIRED)
  role: AgentRole;            // assigned role (REQUIRED)
  program?: "codex-cli" | "claude-code" | "gemini-cli" | string;
  model?: string;             // human-readable model identifier
  notes?: string;             // free-form audit
}

interface Roster {
  entries: RosterEntry[];     // ≥1 entry required
  mode?: "role_separated" | "unified";   // default: "role_separated"
  name?: string;
  createdAt?: string;         // ISO 8601
}

type AgentRole =
  | "hypothesis_generator"    // primary: Codex/GPT
  | "test_designer"           // primary: Opus/Claude
  | "adversarial_critic";     // primary: Gemini
```

The 3 canonical roles map to the 3 dominant model families in brennerbot. Per ROSTER-PLANS.md, this is the canonical role basis; brennerbot-with-ntm extends with `synthesizer` and `adjudicator` for Squad+ tiers.

---

## Roster modes

### Role-separated mode (default)

Each recipient gets a role-specific prompt:

```typescript
const roster: Roster = {
  mode: "role_separated",
  entries: [
    { agentName: "BlueLake", role: "hypothesis_generator", program: "codex-cli" },
    { agentName: "PurpleMountain", role: "test_designer", program: "claude-code" },
    { agentName: "GreenValley", role: "adversarial_critic", program: "gemini-cli" },
  ],
};
```

Use for T3+ sessions. The multi-role differentiation is the whole point.

### Unified mode

All recipients get the same prompt; no role differentiation:

```typescript
const roster: Roster = {
  mode: "unified",
  entries: [
    { agentName: "BlueLake", role: "hypothesis_generator" },  // role ignored in unified mode
    { agentName: "PurpleMountain", role: "hypothesis_generator" },
  ],
};
```

Use for T1-T2 sessions, simple investigations, or single-model setups. The `role` field is still required (validation), but unified mode dispatches the same prompt regardless.

---

## The 3 edge-case rules

### Rule 1: No duplicate agents

Each `agentName` appears at most once in a roster. Duplicate = error.

```typescript
// ERROR: BlueLake appears twice
const invalid: Roster = {
  entries: [
    { agentName: "BlueLake", role: "hypothesis_generator" },
    { agentName: "BlueLake", role: "test_designer" },  // INVALID
  ],
};
```

### Rule 2: Duplicate roles ARE allowed

Multiple agents may share the same role (for "more brains" mode):

```typescript
// VALID: two hypothesis generators
const valid: Roster = {
  entries: [
    { agentName: "BlueLake", role: "hypothesis_generator" },
    { agentName: "RedSky", role: "hypothesis_generator" },  // OK — diversification
    { agentName: "PurpleMountain", role: "test_designer" },
  ],
};
```

When to use duplicate roles:
- Adversarial-Critic doubled (per ⊕ Cross-Domain) for breadth
- Hypothesis-Generator doubled with different model families (one ⊙ ignorant, one expert)
- Per BRENNER-GAN-MECHANICS.md: ≥2 critics break in-phase reasoning

### Rule 3: Missing mapping = error

If a recipient is in the kickoff `recipients` list but not in the roster, kickoff MUST fail with a clear error. **No silent fallback to a DEFAULT_ROLE.**

```typescript
// ERROR: "GreenValley" in recipients but not in roster
composeKickoffMessages({
  recipients: ["BlueLake", "PurpleMountain", "GreenValley"],
  roster: {
    entries: [
      { agentName: "BlueLake", role: "hypothesis_generator" },
      { agentName: "PurpleMountain", role: "test_designer" },
    ],
  },
});
// → throws: "GreenValley not found in roster"
```

This rule prevents silent failures. If you intend GreenValley as adversarial_critic, the roster MUST say so.

---

## Roster presets with placeholder names

For reusable configurations, use **presets** with placeholder names:

```typescript
interface RosterPreset {
  id: string;                  // unique identifier
  name: string;                // display name
  description?: string;        // when to use
  entries: Omit<RosterEntry, "agentName">[];   // no names yet
  placeholderNames?: string[]; // names get filled in at runtime
}
```

Example preset:

```typescript
const TIER_3_SQUAD_PRESET: RosterPreset = {
  id: "preset-tier3-squad",
  name: "Tier-3 Squad (cc + cod + gmi)",
  description: "Default Squad roster for T3 sessions",
  entries: [
    { role: "hypothesis_generator", program: "codex-cli" },
    { role: "test_designer", program: "claude-code" },
    { role: "adversarial_critic", program: "gemini-cli" },
  ],
};
```

After `bootstrap-session.sh` creates the workspace and seeds `.ntm/pipelines/`, the operator creates the pane roster and records the actual Agent Mail identities returned during onboarding:

```bash
ntm spawn RS-YYYYMMDD-slug --cc=1 --cod=1 --gmi=1
./scripts/register-mail-identities.sh --project-key="$WORKSPACE" --session=RS-YYYYMMDD-slug
# Then record p1 -> BlueLake, p2 -> PurpleMountain, p3 -> GreenValley
# in .brenner_workspace/phase0_scope_decision.md as each pane registers.
```

The preset's roles map onto the agent names in order: BlueLake → hypothesis_generator, PurpleMountain → test_designer, GreenValley → adversarial_critic.

---

## Per-tier preset library

Per ROSTER-PLANS.md, the canonical presets:

| Preset ID | Tier | Composition |
|-----------|------|-------------|
| `preset-solo-cc` | Solo | 1 cc agent, role: hypothesis_generator (unified mode) |
| `preset-pair-cc-cod` | Pair | 2 agents (cc as test_designer + cod as hypothesis_generator) |
| `preset-tier3-squad` | Squad | 3 agents (cod + cc + gmi) — canonical |
| `preset-tier3-squad-double-critic` | Squad+ | 4 agents (cod + cc + 2× gmi for cross-critique) |
| `preset-tier4-swarm` | Swarm | 8-12 agents (multi-model with synthesizer + adjudicator) |
| `preset-tier4-swarm-extended` | Swarm | 12+ with operator-buddy + post-mortem-formalizer |
| `preset-incident-pair` | Incident | 2 agents (cc + cod, time-pressured) |
| `preset-quick-loop-solo` | Quick-loop | 1 agent (single-pane self-debate) |

Operators can author custom presets but use canonical ones for cross-session comparability.

---

## NTM role binding

This skill does **not** ship a standalone `brenner` CLI. Use the NTM roster plus the BrennerBot helper scripts; do not copy old cockpit examples from the upstream TypeScript prototype.

```bash
# Spawn the live pane roster first.
ntm spawn RS-YYYYMMDD-slug --cc=3 --cod=1 --gmi=1

# Log per-pane Agent Mail registration instructions.
./scripts/register-mail-identities.sh \
  --project-key="$WORKSPACE" \
  --session=RS-YYYYMMDD-slug

# Run the matching workspace-seeded pipeline against the existing session.
ntm pipeline run "$WORKSPACE/.ntm/pipelines/brennerbot-squad.yaml" \
  --session RS-YYYYMMDD-slug \
  --var workspace_path="$WORKSPACE" \
  --var session_id=RS-YYYYMMDD-slug \
  --var question_of_record_path=intake/question_of_record.md \
  --var mode=fresh-question \
  --dry-run
```

The concrete role map is recorded in `.brenner_workspace/phase0_scope_decision.md` during bootstrap/onboarding. If Agent Mail is unavailable, use `brennerbot-squad-no-mail.yaml`; its `register_assignees` step writes the bead-assignee convention via `scripts/register-assignees.sh`.

---

## Per-role default model preference

Per `/dp/brenner_bot/specs/role_prompts_v0.1.md`:

| Role | Primary model family | Why |
|------|----------------------|-----|
| `hypothesis_generator` | Codex (GPT-5.2 / Codex CLI) | Broad generation; ⊕ Cross-Domain strength |
| `test_designer` | Claude (Opus 4.5 / Claude Code) | Methodological rigor; potency-check discipline |
| `adversarial_critic` | Gemini (Gemini 3 / Gemini CLI) | Adversarial framing; ⊞ Scale-Check rigor |

These defaults are *recommended*, not enforced. Operators can mix model families within roles for breadth (per BRENNER-GAN-MECHANICS.md).

For brennerbot-with-ntm extended roles:

| Role | Primary model family |
|------|----------------------|
| `synthesizer-cc` / `synthesizer-cod` / `synthesizer-gmi` | Matches its own model family |
| `adjudicator` | Claude (judgment-heavy task) |

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip `role-map` and rely on string-match heuristics | Per Rule 3: missing mapping = error |
| Use unified mode for T3+ sessions | Loses multi-model differentiation |
| Same agent name in two role-mapped entries | Per Rule 1: duplicate agents = error |
| Default-fallback to hypothesis_generator if no mapping | Per Rule 3: silent failure |
| Mix preset and `--role-map` simultaneously | Use one or the other |
| Custom presets without versioning | Per cross-session comparability: name + version preset |
| Cross-session role re-assignments without intervention bead | Per OPERATOR-INTERVENTION-RECORDING.md: role_reassignment is a logged intervention |
| Trust a roster preset without checking model availability | Pre-flight check via `caam ls --provider=<family> --json` plus `ntm --robot-snapshot` after spawn |

---

## Cross-references

- `ROSTER-PLANS.md` — per-tier roster strategy
- `MULTI-AGENT-TRIBUNAL-PERSONAS.md` — persona-on-top-of-role
- `BRENNER-GAN-MECHANICS.md` — role pairing strategy
- `OPERATOR-INTERVENTION-RECORDING.md` — role_reassignment audit
- `TAXONOMIES-COMPLETE-CATALOG.md` — role enum values
- `NTM-PIPELINES.md` — pipeline definitions per preset
- /dp/brenner_bot/specs/agent_roster_schema_v0.1.md — original spec
- /dp/brenner_bot/specs/role_prompts_v0.1.md — role-prompt templates
