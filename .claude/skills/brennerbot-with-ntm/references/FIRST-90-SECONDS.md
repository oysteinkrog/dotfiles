# FIRST-90-SECONDS.md — Operator Bootstrapping in 90 Seconds

## Table of Contents

- Why 90 seconds
- The 90-second flow
- Per-mode 90-second flows
- What you don't do in the first 90 seconds
- Common first-90-second mistakes
- When 90 seconds isn't enough
- Self-check at 90 seconds
- Cross-references

The first 90 seconds after a fresh agent triggers this skill determine whether the session succeeds. This file is the *muscle memory* — exactly what to type, in what order, before reading anything else.

For new operators (per OPERATOR-ONBOARDING-CURRICULUM.md), memorize this. After 5+ sessions, it's reflex.

---

## Why 90 seconds

The agent's response latency is non-zero; the user is watching. If the agent reads SKILL.md fully on first trigger, that's 30+ seconds before the user sees acknowledgment. By 90 seconds they should see specific, evidence-grounded action.

Also: the first action shapes the rest of the session. A botched first 90 seconds (wrong workspace, wrong mode, wrong roster) cascades into wasted hours.

The 90-second discipline forces the operator to:
- Match the user's actual mode (don't assume)
- Verify pre-conditions (composing skills installed, accounts available)
- Commit to a workspace path (don't be ambiguous)
- Set expectations (tier, wall-time)

---

## The 90-second flow

### 0-15 seconds: Acknowledge + classify

```
"I'll set up a brennerbot session. Quick clarifications first:

1. <Read user's message; identify research target type>
2. <If unclear: ask one specific clarification>"
```

The acknowledgment tells the user "I'm operator-mode, not investigator-mode" implicitly. Don't say "I'll investigate X" — that's wrong; the panes investigate.

### 15-45 seconds: Up-Front Confirmations (asked in priority order)

```
"To bootstrap your session, I need:

1. **Research target**: <repeat their request as I parse it>. Confirm?
2. **Workspace path**: I'll create <suggested-path>. Override?
3. **Mode**: <auto-detected>. Override?
4. **Tier**: T<N> based on <stakes signals from their message>. Override?
5. **Roster size + model mix**: <recipe-driven default>. Override?
6. **Robot mode**: default ON (autonomous unstick). Override?

I'll wait for your answers, then run bootstrap-session.sh."
```

Don't ask all 8 questions individually. Pre-fill defaults; user only confirms or overrides.

### 45-75 seconds: Pre-bootstrap checks (in parallel)

While waiting for user's answer:

```bash
# Run in parallel via background processes:
mkdir -p /tmp/.brennerbot-precheck
./scripts/check-skills.sh /tmp/.brennerbot-precheck > /tmp/.brennerbot-precheck/skill-inv.json &
ntm --robot-capabilities > /tmp/.ntm-capabilities.json &
ntm --robot-tools > /tmp/.ntm-tools.json &
caam ls --provider=claude --json > /tmp/.cc-quota.json &
caam ls --provider=codex --json > /tmp/.cod-quota.json &
caam ls --provider=gemini --json > /tmp/.gmi-quota.json &
cass status --json > /tmp/.cass-status.json &
wait
```

Catches account-quota issues, stale CASS, missing NTM robot surfaces, and tool-health problems BEFORE bootstrap fails mid-session. A stale CASS index is usually usable for search; a missing `--robot-pipeline-run`, `--robot-attention`, or `--robot-causality` means the local NTM binary is too old for native BrennerBot orchestration.

### 75-90 seconds: Bootstrap (after user confirms)

```bash
./scripts/bootstrap-session.sh <workspace> "<question>" \
  --mode=<mode> --roster=<pair|squad|swarm|squad-no-mail>

ntm spawn RS-YYYYMMDD-slug --cc=3 --cod=1 --gmi=1
ntm pipeline run <workspace>/.ntm/pipelines/brennerbot-squad.yaml \
  --session RS-YYYYMMDD-slug \
  --var workspace_path=<workspace> \
  --var session_id=RS-YYYYMMDD-slug \
  --var question_of_record_path=intake/question_of_record.md \
  --var mode=<mode> \
  --dry-run
```

Bootstrap is idempotent. The immediate pipeline dry-run is the handoff from "workspace created" to "NTM can actually execute this session." If the session is intentionally Pair/no-mail, use the matching copied YAML.

---

## Per-mode 90-second flows

### Fresh question (most common)

```
0-15s:  Acknowledge + identify target type (string/path/corpus)
15-45s: Ask 6 Up-Front Confirmations (workspace, mode, tier, roster, robot, coord)
45-75s: Pre-flight: caam quota + check-skills.sh + NTM capabilities/tools + CASS status
75-90s: bootstrap-session.sh + NTM pipeline dry-run (await user confirm first)
```

### Resume from RESUME.md

```
0-15s:  Acknowledge + read RESUME.md path
15-30s: ./scripts/resume-session.sh --dry-run --resume <path>
30-60s: Display verification result; ask user to confirm resume mode
60-90s: ./scripts/resume-session.sh --resume <path>; then `ntm --robot-causality=<session> --causality-project=<workspace>`
```

### Code-investigation

```
0-15s:  Acknowledge + verify codebase path is .git repo
15-30s: Compose with /codebase-archaeology to inventory the target
30-60s: Read inventory + frame question with user (FRAMING-WORKBOOK F1-F9 lite)
60-90s: bootstrap-session.sh <workspace> "<codebase path>" --mode=code-investigation
```

### Methodology drift-check (no swarm)

```
0-15s:  Acknowledge + identify target prior session
15-30s: Read ./scripts/dump-session-report.sh on prior workspace
30-60s: Dispatch subagents/drift-auditor.md to a FRESH general-purpose Agent
60-90s: Wait for drift-auditor output → present DRIFT-CHECK.md to user
```

### Incident-investigation (≤60min compressed)

```
0-15s:  Acknowledge + extract incident details (time window, symptoms)
15-30s: Pin logs/metrics with content-hash (per VERIFICATION-FIRST.md)
30-60s: bootstrap-session.sh <workspace> "<incident summary>" --mode=incident-investigation --roster=pair
60-90s: Dry-run `<workspace>/.ntm/pipelines/brennerbot-incident.yaml`; start Phase 1 framing with 5-whys preliminary
```

---

## What you DON'T do in the first 90 seconds

| ✗ | Why |
|---|-----|
| Read all references/ files | 30+ seconds wasted; you don't need them yet |
| Investigate the question yourself | You're the operator; panes investigate |
| Ask 8 separate questions sequentially | User waits 30+ seconds between each; do them in one prompt |
| Skip caam quota check | Mid-session rate-limits cost more than the 5s pre-check |
| Skip NTM robot capability check | You may fall back to stale manual orchestration even though current NTM can run the pipeline |
| Bootstrap before user confirms | Wrong workspace path = orphaned session |
| Default to T3 unconditionally | T1/T2 questions don't need a Squad; over-tiering wastes user's time |
| Compose all available skills "to be thorough" | Each composition adds 30s+ overhead; pick 1-2 most relevant |

---

## Common first-90-second mistakes

### Mistake 1: Operator confuses themselves with a pane

A fresh agent reads SKILL.md and starts to investigate. After 60 seconds they realize they're supposed to delegate. Now they've burned operator-context on the wrong activity.

**Prevention:** Read `SKILL.md` Operator Quickstart first (it explicitly says "you are the operator").

### Mistake 2: Ambiguous workspace path

"I'll create the workspace in ./brennerbot/" → user has 4 brennerbot folders already. Disambiguate.

**Prevention:** Always confirm absolute path; verify it doesn't exist OR explicitly handle the resume case.

### Mistake 3: Wrong mode auto-detection

Agent sees `.git` repo and assumes `code-investigation`, but user is asking a *methodology* question that happens to involve code.

**Prevention:** Ask user to confirm auto-detected mode; show the heuristic that triggered the detection.

### Mistake 4: Quota cliff mid-bootstrap

Bootstrap proceeds, panes spawn, then 60 seconds later one cc account hits the daily limit and the spawn-mix degrades.

**Prevention:** caam quota check BEFORE spawn (in the 45-75 second window).

### Mistake 5: Skipping recipe match

A storage-selection question (R10) gets generic Phase 1 framing instead of the recipe-specific F1-F9 emphasis (workload class, scale envelope).

**Prevention:** During Up-Front Confirmations, identify recipe match; mention it to user.

---

## When 90 seconds isn't enough

Some scenarios genuinely need more pre-bootstrap work:

- **First-time operator using brennerbot**: budget 5-10 min for re-reading the Operator Quickstart, Decision Tree, current Mode Router. Don't apologize; calibration is worth it.
- **T4+ session**: budget 10-30 min for stress-test self-check (per MO-stress-test-self-check.md), corpus pinning, external-reviewer recruitment.
- **Multi-session resume**: budget 5-15 min for cross-session reconciliation context (per RECONCILIATION-OF-PRIOR-SESSIONS.md).
- **Complex compose**: e.g., brennerbot + /codebase-archaeology + /multi-pass-bug-hunting needs sequenced bootstrap.

In each case, communicate with the user upfront: "This will take longer than my standard 90 seconds because [specific reason]."

---

## Self-check at 90 seconds

If you're past 90 seconds and haven't:
- Acknowledged the user
- Asked Up-Front Confirmations OR completed bootstrap

… something's off. Common causes:

- Reading too many references/ files (defer them; they load on-demand)
- Investigating the question yourself (stop; that's the panes' job)
- Ambiguity in user's request (ask ONE specific clarification, not many)

Reset and proceed.

---

## Cross-references

- `SKILL.md` Operator Quickstart — the role-clarity opening
- `OPERATOR-PROMPT-LIBRARY.md` — P1.1-P1.10 framing prompts (used in seconds 15-45)
- `DOMAIN-RECIPE-LIBRARY.md` — recipe match in seconds 0-15
- `WALL-TIME-BUDGET.md` — tier estimation in seconds 15-45
- `/caam` skill — quota check in seconds 45-75
