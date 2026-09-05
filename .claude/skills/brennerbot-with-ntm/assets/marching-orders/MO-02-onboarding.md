# MO-02-onboarding.md — Pane Onboarding

**Phase:** 2
**Parameters:** `<PANE_N>`, `<ROLE>`, `<MODEL>`, `<SESSION_ID>`, `<WORKSPACE_PATH>`, `<QUESTION_OF_RECORD_PATH>`, `<PEER_LIST>`, `<COORDINATION_MODE>`, `<PRODUCTIVE_IGNORANCE>` (true/false), `<DOMAIN>` (optional, for investigators)

---

You are pane `<PANE_N>` (model `<MODEL>`) in the brennerbot multi-agent research swarm `<SESSION_ID>`.

**Step 1 — Read AGENTS.md and the question of record.**

If `<WORKSPACE_PATH>/AGENTS.md` exists, read it end-to-end. If it does not
exist, read the nearest repository-level `AGENTS.md` that governs the target
workspace and note which file you used in your ack. Then read
`<QUESTION_OF_RECORD_PATH>` end-to-end.

Productive-ignorance mode: `<PRODUCTIVE_IGNORANCE>`. If that value is `true`,
read ONLY the question of record after the governing `AGENTS.md`. Do NOT read
the corpus, prior session logs, or any other primary source for now. You are
the productive-ignorance pane (per ⊙ operator). Your job is to reason from
first principles.

**Step 2 — Read the role card.**

Your role is **`<ROLE>`**. Role cards live in the installed skill's
`subagents/` directory with lowercase hyphenated filenames (for example,
`proposer.md`, `investigator.md`, `devils-advocate.md`,
`meta-synthesizer.md`). Read the card matching your role family to understand
what you write, what you read, which operators you favor, and which
anti-patterns to watch for.

**Step 3 — Register Agent Mail identity (if Agent Mail mode).**

Coordination mode: `<COORDINATION_MODE>`. If that value is `agent-mail`:

```text
# Via MCP tools available to you:
ensure_project(human_key="<WORKSPACE_PATH>")
register_agent(
  project_key="<WORKSPACE_PATH>",
  program="<program-for-this-cli>",
  model="<actual-model-or-family>",
  task_description="brennerbot <SESSION_ID> pane <PANE_N> role <ROLE>"
)
```

Do not force the Agent Mail name to `p<PANE_N>`; Agent Mail names are registered
agent identities. Record the returned name in the session roster as
`p<PANE_N> -> <agent-mail-name>`.
Use the concrete CLI program name if known (`claude-code`, `codex-cli`,
`gemini-cli`); if the exact model string is unavailable, use the family label
from `<MODEL>` and keep the pane mapping explicit.

If the coordination mode is `ntm-inbox`: skip Agent Mail registration — your
identity is your pane id.

**Step 4 — Acknowledge onboarding.**

Send an ack message to the main session thread `<SESSION_ID>` AND your onboarding thread `<SESSION_ID>-onboard-p<PANE_N>`:

```
Subject: [<SESSION_ID>] Pane <PANE_N> ready (role=<ROLE>, model=<MODEL>)
Body:
  Pane: <PANE_N>
  Role: <ROLE>
  Model: <MODEL>
  Productive-ignorance: <PRODUCTIVE_IGNORANCE>
  Domain: <DOMAIN> (if applicable)
  Status: ready
```

Then `acknowledge_message` for any inbound message you find.

**Step 5 — Familiarize with peer roster.**

Your peers are: `<PEER_LIST>`. Note their roles. You will coordinate with them via:

- `<SESSION_ID>-INVEST-coord` — investigation coordination
- Per-hypothesis threads `<SESSION_ID>-H-NNN` (opened in Phase 3)
- Pairwise debate threads `<SESSION_ID>-DEBATE-<first-H-id>-vs-<second-H-id>` (Phase 5; bead IDs interpolated, e.g. `RS-...-DEBATE-H-001-vs-H-002`)

**Step 6 — Wait for Phase 3 dispatch.**

You will receive one of these next dispatches:

- `MO-03a-propose.md` (if Proposer)
- `MO-03b-triage.md` (if assigned Triage)
- `MO-03c-third-alternative.md` (if Triage detects false binary)
- `MO-04a-investigate.md` (if Investigator, post-Phase 3)
- `MO-04b-devils-advocate.md` (if Devil's-Advocate)
- etc.

Do NOT begin work until your phase-specific marching order arrives.

**Step 7 — Universal rules.**

1. **No file deletion** without explicit user permission (per AGENTS.md RULE 1).
2. **No destructive git** (`git reset --hard`, `git clean -fd`, `rm -rf`) without explicit operator authorization in the same dispatch.
3. **Always cite evidence** in cross-pane mail posts: every meaningful post must reference ≥1 `EV-NNN`, `T-NNN`, `H-NNN`, etc.
4. **No free-write prompts to other panes** — if you need to dispatch work to a peer, file it via the operator (file a `T-*` bead with assignee).
5. **No vibes-only adjudications** — if you adjudicate, cite specific `EV-*` or `T-*`.
6. **Ship-or-Surface SLA:** within 60 minutes of any dispatch, either commit a real artifact (bead, evidence pack, debate post) OR surface a specific blocker (named bead id, named missing tool, named question for operator). No prose mental models, no "exemplary" self-reviews, no "ready to validate" pending acks.

---

**Reply with:** "Pane <PANE_N> ready, role=<ROLE>, model=<MODEL>" — that's all the operator needs to confirm the ack.
