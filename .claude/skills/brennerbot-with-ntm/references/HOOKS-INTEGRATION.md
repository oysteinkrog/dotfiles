# HOOKS-INTEGRATION.md — Optional Claude Code Hooks for Automation

<!-- TOC: When to integrate hooks | Sample hook configurations | Hooks for autonomous orchestration | Hooks for safety | Hooks anti-patterns | Recommended baseline | Disabling hooks for a session | Cross-skill hook coordination -->

This skill works fully without hooks. But for power users who want unattended convergence ticks, automatic invariant checks on commit, and stop-event handoffs, this file documents the hooks integration.

Composes with `/cc-hooks` skill. See `~/.claude/settings.json` for hook configuration.

---

## When to integrate hooks

| Use case | Hook | Why |
|----------|------|-----|
| Auto-tick during Phase 4-7 | Stop or PostToolUse on Bash | Operator agent stops naturally between dispatches; trigger tick.sh on Stop |
| Auto-validate beads on commit | PreToolUse on Bash matching `git commit` | Run audit-bead-invariants.sh before allowing commit |
| Auto-flag F-### codes during work | PostToolUse on Bash | After br update, run audit and flag any new violations |
| Auto-converge check on Phase exit | Stop, conditional on phase_*_complete.flag presence | Trigger convergence-check.sh after operator commits |
| Auto-mine cass when starting new question | UserPromptSubmit | If user prompt mentions "research session" or "brennerbot", offer cass-mining |
| Auto-suggest archetype on user ask | UserPromptSubmit | Match user question to ARCHETYPE-START-PACKS.md and suggest |

---

## Sample hook configurations

### Auto-tick during steady-state

`~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -d \"$WORKSPACE/.brenner_workspace\" ] && [ ! -f \"$WORKSPACE/.brenner_workspace/phase_8_complete.flag\" ]; then $WORKSPACE/scripts/tick.sh \"$WORKSPACE\" 2>&1 | head -40; fi"
          }
        ]
      }
    ]
  }
}
```

(Where `$WORKSPACE` is exported from the operator's session env. The hook fires when Claude Stops.)

### PreToolUse: validate beads before commit

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "if echo \"$TOOL_INPUT\" | grep -qE 'git commit'; then if [ -f \"$WORKSPACE/scripts/audit-bead-invariants.sh\" ]; then \"$WORKSPACE/scripts/audit-bead-invariants.sh\" --workspace=\"$WORKSPACE\" --all 2>&1 || { echo 'Bead invariant violation detected — review before committing'; exit 2; }; fi; fi"
          }
        ]
      }
    ]
  }
}
```

This blocks commits that would leave bead invariants violated. Per AGENTS.md / `/cc-hooks` discipline.

### UserPromptSubmit: archetype suggestion

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "if echo \"$USER_PROMPT\" | grep -qiE 'research session|brennerbot|design space|methodology distillation|root cause|comparison'; then echo 'Hint: this looks like a brennerbot question. Consider /brennerbot-with-ntm. See references/ARCHETYPE-START-PACKS.md for archetype mapping.'; fi"
          }
        ]
      }
    ]
  }
}
```

(Hint surfaces in operator stream; doesn't force action.)

---

## Hooks for autonomous orchestration

For long-running unattended sessions:

### Pattern 1: Cron-style scheduled tick

`/loop` skill OR system cron:

```bash
*/15 * * * * /path/to/workspace/scripts/tick.sh /path/to/workspace
```

Every 15 min during business hours, run a tick. Per `/vibing-with-ntm` cadence.

### Pattern 2: Convergence-gated automation

```bash
# In a control script:
while true; do
  if /path/to/workspace/scripts/convergence-check.sh --phase=4 --workspace=/path/to/workspace; then
    # Phase 4 converged. Dispatch Phase 5.
    /path/to/workspace/scripts/dispatch-marching-order.sh MO-05a-cross-exam --PANE_N=... ...
    break
  fi
  sleep 600  # 10 min
done
```

Or use `/schedule` to manage this declaratively if that slash tool is available.

### Pattern 3: Auto-recover from stuck panes

Compose with `/vibing-with-ntm` autonomous unstick. The operator agent detects stuck panes via tick.sh and dispatches recovery MOs without waiting for human intervention. Hooks can wire this:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$WORKSPACE/scripts/tick.sh $WORKSPACE | grep -qE 'stuck|rate_limited|context_pct.*9[0-9]' && echo 'WARNING: pane recovery may be needed; see /vibing-with-ntm autonomous unstick'"
          }
        ]
      }
    ]
  }
}
```

---

## Hooks for safety

### Block destructive operations

The skill inherits AGENTS.md irreversible-git rules. Hooks can enforce:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "if echo \"$TOOL_INPUT\" | grep -qE 'rm -rf|git reset --hard|git clean -fd'; then echo 'BLOCKED: destructive command in brennerbot workspace requires explicit approval per AGENTS.md'; exit 2; fi"
          }
        ]
      }
    ]
  }
}
```

This composes with `/dcg` (Destructive Command Guard) skill.

### Block edits to source corpus

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "if echo \"$TOOL_INPUT\" | grep -qE 'corpus/ingested/'; then echo 'BLOCKED: corpus/ingested/ is read-only after Phase 1 (per WORKSPACE-LAYOUT.md)'; exit 2; fi"
          }
        ]
      }
    ]
  }
}
```

Prevents corpus drift (F-102) by hard-blocking edits.

---

## Hooks anti-patterns

| ✗ | Why |
|---|-----|
| Auto-dispatch marching orders without operator review | Operator judgment is load-bearing; auto-dispatch can fire wrong MO |
| Hook that auto-flips H state | Methodology decisions are the operator's |
| Hook that triggers Phase 10 drift-check on every commit | Drift-check is end-of-session; running mid-session burns context |
| Hook that silently fixes invariant violations | Should surface to operator, not auto-correct |
| Hook with side effects in PreToolUse on every Bash | Performance; restrict matchers to `git commit` etc |
| Hook that bypasses safety guards | Self-defeating; respect `/dcg`, `/slb` constraints |

---

## Recommended baseline (low-risk integration)

For most users, this minimal hook config:

1. **Stop hook** running `tick.sh` to maintain situational awareness
2. **PreToolUse** running `audit-bead-invariants.sh --all` on `git commit`
3. **No automated dispatching** — operator decides

This gets observability + invariant safety without giving up control. More aggressive automation should be deliberate, with rollback plans.

---

## Disabling hooks for a session

If hooks misbehave OR you want manual control:

```bash
# Temporarily disable hooks for this session
export CLAUDE_HOOKS_DISABLED=1
```

(Or move ~/.claude/settings.json hooks to ~/.claude/settings.json.disabled temporarily.)

This is sometimes useful when:

- Debugging hook syntax errors
- Doing high-judgment phases (1, 9, 10) where automation interferes
- Preparing a clean tick log for Phase 10 drift-check

---

## Cross-skill hook coordination

Multiple skills may register hooks. Compatibility:

- `/dcg` — destructive command guard; complements brennerbot's safety hooks
- `/slb` — two-person rule; compatible
- `/cc-hooks` — reference for writing Claude Code hooks
- `/vibing-with-ntm` — operator-loop hooks (auto-restart, etc); coordinate via shared `Stop` matcher

When two skills conflict on a hook (e.g., both want to run on PostToolUse Bash), order them deliberately. Generally: safety guards FIRST, observability SECOND, automation LAST.
