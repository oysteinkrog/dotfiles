# HOOKS-INTEGRATION — Optional Claude Code Hooks for the Gauntlet

> **Where this comes from.** Cross-reference with `/cc-hooks` (Claude Code hook system) + `/dcg` (Destructive Command Guard). This file shows the BILLING-equivalent for gauntlet runs: hook points that wire the gauntlet's discipline into the agent harness so the discipline is enforced automatically, not by reviewer attention.

The gauntlet's mandates (mine the negative ledger before perf work, validate the bead graph before push, prompt for cass-mining before any perf-affecting prompt) are useful only if they actually fire. Hooks make them automatic.

These hooks are OPTIONAL — the gauntlet works without them. But T3+ runs benefit substantially from automation; at T4+ they're effectively required (manual discipline doesn't scale to 30+ days of iteration).

Use these recipes only when `<workspace>/phase0_skill_inventory.json` shows `cc-hooks` available AND the user wants the gauntlet's discipline enforced at the harness level.

---

## Hook inventory

| Hook event | What runs | Why | Tier required |
|---|---|---|---|
| `PreToolUse` (Bash, before perf-touching commit) | `scripts/mine-ledger.sh` | Force ledger-grep before any perf-affecting source mutation | T3+ |
| `PreToolUse` (Bash, before `git push`) | `scripts/bead-graph-validator.sh` | Block push if bead graph has cycles or missing deps | T2+ |
| `UserPromptSubmit` (before perf-related prompts) | Emit reminder to run `cass-miner` first | Force the 60-day mine pre-flight | T3+ |
| `PostToolUse` (artifact-emitting tools) | Emit telemetry event | Run-time observability for the orchestrator | T4+ |
| `Stop` (end of session) | Emit `convergence_tracker.json` summary | Compaction-survival contract | All tiers |
| `SessionStart` (resuming) | Inspect `<workspace>/` state | Resumption discipline | All tiers |

---

## Hook 1 — Pre-commit ledger mine (before perf-touching commits)

**Trigger:** Bash tool call matches `git commit` AND changed files include perf-touching paths.

**Exit-code contract:**
- `exit 0` → allow tool execution; ledger has been freshly mined OR no perf paths touched.
- `exit 2` (non-zero, blocking) → block tool execution; surface the missing-mine evidence + instructions to user.

**`.claude/settings.json` snippet:**

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": {
          "tool_name": "Bash"
        },
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-precommit-ledger-mine.sh"
          }
        ]
      }
    ]
  }
}
```

**`.claude/hooks/gauntlet-precommit-ledger-mine.sh`:**

```bash
#!/usr/bin/env bash
# Reads tool_input from stdin (JSON). Inspects the bash command.
# Blocks `git commit` if perf-touching paths are staged AND ledger mine is stale.

set -euo pipefail
TOOL_INPUT=$(cat)
BASH_CMD=$(echo "$TOOL_INPUT" | jq -r '.command // ""')

# Only fire on git commit
[[ "$BASH_CMD" =~ ^git[[:space:]]+commit ]] || exit 0

# Detect workspace
WORKSPACE_PARENT=$(dirname "$(git rev-parse --show-toplevel)")
WORKSPACE=$(ls -d "$WORKSPACE_PARENT"/*__gauntlet_workspace 2>/dev/null | head -1 || true)
[[ -z "$WORKSPACE" ]] && exit 0  # No gauntlet workspace; not our concern

# Check if staged files touch perf paths
PERF_PATHS=$(git diff --cached --name-only | grep -E '(bench|crates/.*-(e2e|harness)|.bench-history|src/.*\.rs$)' || true)
[[ -z "$PERF_PATHS" ]] && exit 0  # No perf paths; allow

# Check if ledger has been mined in the last hour
LEDGER_FRESH_THRESHOLD=3600  # seconds
RECENT_MINE=$(find "$WORKSPACE/cass_findings/" -name "*.jsonl" -newer "$(date -d '1 hour ago' +%Y-%m-%d)" 2>/dev/null | head -1)

if [[ -z "$RECENT_MINE" ]]; then
  cat >&2 <<EOF
[gauntlet pre-commit] BLOCKED: perf-touching files staged but ledger mine is stale.

Staged perf paths:
$PERF_PATHS

Required before commit:
  $WORKSPACE/scripts/mine-ledger.sh "$WORKSPACE"
  $WORKSPACE/scripts/mine-cass-cross-machine.sh "$WORKSPACE"

This enforces the AGENTS.md mandate paragraph (CC.md lines 479-482).
EOF
  exit 2
fi

exit 0
```

**When to install vs not:**

- **Install** when the project has the gauntlet workspace already set up AND multiple developers / agents are committing concurrently (discipline drift is more likely).
- **Don't install** when running `quick-smoke` or `cass-mine-only` modes (hook would block routine commits unnecessarily).
- **Don't install** for the first 24 hours of a fresh gauntlet run — the workspace is being built up; the hook would fire spuriously.

---

## Hook 2 — Pre-push bead-graph validator

**Trigger:** Bash tool call matches `git push`.

**Exit-code contract:**
- `exit 0` → allow push.
- `exit 2` → block push; surface bead-graph issues to user.

**`.claude/settings.json` snippet:**

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": {
          "tool_name": "Bash"
        },
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-prepush-bead-validator.sh"
          }
        ]
      }
    ]
  }
}
```

**`.claude/hooks/gauntlet-prepush-bead-validator.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
TOOL_INPUT=$(cat)
BASH_CMD=$(echo "$TOOL_INPUT" | jq -r '.command // ""')

# Only fire on git push
[[ "$BASH_CMD" =~ ^git[[:space:]]+push ]] || exit 0

# Run bead-graph validator
WORKSPACE_PARENT=$(dirname "$(git rev-parse --show-toplevel)")
WORKSPACE=$(ls -d "$WORKSPACE_PARENT"/*__gauntlet_workspace 2>/dev/null | head -1 || true)
[[ -z "$WORKSPACE" ]] && exit 0  # No gauntlet workspace

if [[ -x "$WORKSPACE/scripts/bead-graph-validator.sh" ]]; then
  if ! "$WORKSPACE/scripts/bead-graph-validator.sh" "$CLAUDE_PROJECT_DIR" --output-root "$WORKSPACE" 2>&1; then
    cat >&2 <<EOF
[gauntlet pre-push] BLOCKED: bead-graph-validator failed.

Likely causes:
- br dep cycles non-empty
- bv --robot-insights | jq '(.Cycles // []) | length == 0' failed
- Remediation bead missing test/bench/doc dependency

Inspect:
  $WORKSPACE/scripts/bead-graph-validator.sh "$CLAUDE_PROJECT_DIR" --output-root "$WORKSPACE" -vvv

Fix in Phase 13 polish round before re-pushing.
EOF
    exit 2
  fi
fi

exit 0
```

**When to install vs not:**

- **Install** for any T2+ gauntlet run that produces beads (Phase 13 always does).
- **Don't install** for `audit-only` mode (no beads produced).
- **Don't install** for `quick-smoke` mode (no Phase 13).

---

## Hook 3 — UserPromptSubmit reminder for perf-related prompts

**Trigger:** UserPromptSubmit event AND prompt content matches perf-related keywords.

**Exit-code contract:**
- `exit 0` always (this hook is INFORMATIONAL, not blocking).
- stdout: reminder message that becomes part of the agent's context.

**`.claude/settings.json` snippet:**

```jsonc
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": {},
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-userprompt-cass-reminder.sh"
          }
        ]
      }
    ]
  }
}
```

**`.claude/hooks/gauntlet-userprompt-cass-reminder.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
USER_PROMPT=$(cat | jq -r '.prompt // ""')

# Detect perf-related keywords
if echo "$USER_PROMPT" | grep -qiE '(optim|hot.path|bench|perf|profile|throughput|latency|micro.lever|MT8)'; then
  cat <<'EOF'
[gauntlet reminder]
Before touching perf-affecting code, the AGENTS.md mandate requires:
1. Grep docs/progress/perf-negative-results.md for prior closures on this hotspot.
2. Mine 60 days of cass session history across local/css/csd/ts1/ts2:
   scripts/mine-cass-cross-machine.sh <workspace>
3. Check recent commits:
   git log --since='60 days ago' --grep -iE 'perf|optimiz|hot.path|bench|ratchet'

If cass is unavailable or ledger is reserved, RECORD A BLOCKER ENTRY rather than silently skipping.

See references/methodology/CASS-MINING.md for the canonical recipes.
EOF
fi

exit 0
```

**When to install vs not:**

- **Install** for any T3+ gauntlet run where humans interact with the orchestrator (CI dispatch doesn't need the reminder).
- **Don't install** for fully-automated runs (CI / nightly cron); the reminder is wasted context tokens.

---

## Hook 4 — PostToolUse telemetry on artifact-emitting tools

**Trigger:** PostToolUse event when the tool emitted a file that matches the gauntlet's artifact-path patterns.

**Exit-code contract:**
- `exit 0` always (telemetry-only).

**`.claude/settings.json` snippet:**

```jsonc
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": {
          "tool_name": "Write"
        },
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-posttooluse-telemetry.sh"
          }
        ]
      },
      {
        "matcher": {
          "tool_name": "Edit"
        },
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-posttooluse-telemetry.sh"
          }
        ]
      }
    ]
  }
}
```

**`.claude/hooks/gauntlet-posttooluse-telemetry.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
TOOL_OUTPUT=$(cat)
FILE_PATH=$(echo "$TOOL_OUTPUT" | jq -r '.tool_input.file_path // ""')

# Detect gauntlet artifact paths
if echo "$FILE_PATH" | grep -qE '(__gauntlet_workspace|/round_[0-9]+/|/soak/|/remediation/|/certification_bundle/)'; then
  WORKSPACE=$(echo "$FILE_PATH" | grep -oE '.*__gauntlet_workspace' | head -1)
  EVENT_TYPE="artifact_emitted"
  EVENT="{
    \"event_type\": \"$EVENT_TYPE\",
    \"timestamp\": \"$(date -Iseconds)\",
    \"tool\": \"$(echo "$TOOL_OUTPUT" | jq -r '.tool_name')\",
    \"file_path\": \"$FILE_PATH\",
    \"workspace\": \"$WORKSPACE\"
  }"
  mkdir -p "$WORKSPACE/telemetry"
  echo "$EVENT" >> "$WORKSPACE/telemetry/events.jsonl"
fi

exit 0
```

**When to install vs not:**

- **Install** for T4+ runs where multi-week wall time makes run-time observability valuable.
- **Don't install** for short runs (telemetry log overhead is wasted).

The telemetry log is read by `subagents/iteration-coordinator.md` to detect stuck rounds (e.g., a round that hasn't emitted an artifact in >2 hours despite being marked active).

---

## Hook 5 — Stop event: convergence-tracker checkpoint

**Trigger:** Stop event (end of agent session).

**Exit-code contract:**
- `exit 0` always.

**`.claude/settings.json` snippet:**

```jsonc
{
  "hooks": {
    "Stop": [
      {
        "matcher": {},
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-stop-checkpoint.sh"
          }
        ]
      }
    ]
  }
}
```

**`.claude/hooks/gauntlet-stop-checkpoint.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_PARENT=$(dirname "$(pwd)")
WORKSPACE=$(ls -d "$WORKSPACE_PARENT"/*__gauntlet_workspace 2>/dev/null | head -1 || true)
[[ -z "$WORKSPACE" ]] && exit 0

# Re-run convergence-tracker and emit checkpoint
if [[ -x "$WORKSPACE/scripts/convergence-tracker.sh" ]]; then
  CHECKPOINT="$WORKSPACE/checkpoints/$(date +%Y%m%d-%H%M%S).json"
  mkdir -p "$(dirname "$CHECKPOINT")"
  "$WORKSPACE/scripts/convergence-tracker.sh" "$WORKSPACE" >/dev/null 2>&1 || true
  if [[ -f "$WORKSPACE/reports/convergence_tracker.json" ]]; then
    cp "$WORKSPACE/reports/convergence_tracker.json" "$CHECKPOINT"
    echo "[gauntlet checkpoint] $CHECKPOINT" >&2
  else
    echo "[gauntlet checkpoint] convergence tracker not available yet" >&2
  fi
fi

exit 0
```

**When to install vs not:**

- **Install** for all tiers — the checkpoint cost is near-zero and the compaction-survival contract benefits.

---

## Hook 6 — SessionStart: resume detection

**Trigger:** SessionStart event (new agent session begins).

**Exit-code contract:**
- `exit 0` always.
- stdout becomes part of the agent's initial context.

**`.claude/settings.json` snippet:**

```jsonc
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": {},
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-sessionstart-resume.sh"
          }
        ]
      }
    ]
  }
}
```

**`.claude/hooks/gauntlet-sessionstart-resume.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_PARENT=$(dirname "$(pwd)")
WORKSPACE=$(ls -d "$WORKSPACE_PARENT"/*__gauntlet_workspace 2>/dev/null | head -1 || true)
[[ -z "$WORKSPACE" ]] && exit 0

TRACKER="$WORKSPACE/reports/convergence_tracker.json"
if [[ -f "$TRACKER" ]]; then
  ROUNDS=$(jq -r '.round_count // 0' "$TRACKER")
  CLEAN=$(jq -r 'if .clean_last_two then (.required_consecutive_clean // 2) else 0 end' "$TRACKER")
  OPEN=$(jq -r '.open_hypothesis_count // 0' "$TRACKER")
  LAST_PHASE=$(ls -t "$WORKSPACE"/phase*_*.md 2>/dev/null | head -1 | xargs basename || echo "none")

  cat <<EOF
[gauntlet resume] Workspace exists at $WORKSPACE
- Rounds completed: $ROUNDS
- Consecutive clean rounds: $CLEAN
- Open hypotheses: $OPEN
- Last phase artifact: $LAST_PHASE

If resuming a previous gauntlet run, follow the resumption discipline:
1. Read the most recent round_<N>/synthesis.md
2. Check scripts/gauntlet-status.sh <workspace> --json for completed phases and convergence state
3. Resume from the NEXT pending phase
4. Do NOT redo completed phases unless their inputs changed
EOF
fi

exit 0
```

**When to install vs not:**

- **Install** for all tiers — resumption guidance is universally useful.

---

## Composite settings.json

Combining all six hooks:

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": { "tool_name": "Bash" },
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-precommit-ledger-mine.sh" },
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-prepush-bead-validator.sh" }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": {},
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-userprompt-cass-reminder.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": { "tool_name": "Write" },
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-posttooluse-telemetry.sh" }
        ]
      },
      {
        "matcher": { "tool_name": "Edit" },
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-posttooluse-telemetry.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": {},
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-stop-checkpoint.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": {},
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/gauntlet-sessionstart-resume.sh" }
        ]
      }
    ]
  }
}
```

---

## Hook-installation script

Template for a project-local `scripts/install-gauntlet-hooks.sh` (called from Phase 0 at user authorization; not shipped as a generic skill script because hook locations are client-specific):

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${1:-}"
TIER="${2:-T3}"
[[ -z "$WORKSPACE" ]] && { echo "usage: $0 <workspace> [tier]"; exit 2; }

# Determine which hooks to install based on tier
INSTALL_TELEMETRY="false"
INSTALL_USERPROMPT="true"
INSTALL_PRECOMMIT="true"
INSTALL_PREPUSH="true"

case "$TIER" in
  T1) INSTALL_PRECOMMIT="false"; INSTALL_PREPUSH="false"; INSTALL_USERPROMPT="false" ;;
  T4|T5) INSTALL_TELEMETRY="true" ;;
esac

HOOKS_DIR="$(git rev-parse --show-toplevel)/.claude/hooks"
SETTINGS="$(git rev-parse --show-toplevel)/.claude/settings.json"

mkdir -p "$HOOKS_DIR"

# Copy hook scripts from skill assets
for HOOK in precommit-ledger-mine prepush-bead-validator userprompt-cass-reminder posttooluse-telemetry stop-checkpoint sessionstart-resume; do
  cp "$(dirname "$0")/hook-templates/gauntlet-$HOOK.sh" "$HOOKS_DIR/"
  chmod +x "$HOOKS_DIR/gauntlet-$HOOK.sh"
done

# Generate settings.json snippet (with jq, merging into existing if any)
jq --argjson tier_flags "{
  \"telemetry\": $INSTALL_TELEMETRY,
  \"userprompt\": $INSTALL_USERPROMPT,
  \"precommit\": $INSTALL_PRECOMMIT,
  \"prepush\": $INSTALL_PREPUSH
}" '...' "$SETTINGS" > "$SETTINGS.new" && mv "$SETTINGS.new" "$SETTINGS"

echo "Hooks installed to $HOOKS_DIR"
echo "Settings updated at $SETTINGS"
echo "Tier-appropriate hooks: precommit=$INSTALL_PRECOMMIT prepush=$INSTALL_PREPUSH userprompt=$INSTALL_USERPROMPT telemetry=$INSTALL_TELEMETRY"
```

---

## Uninstallation

To remove all gauntlet hooks:

```bash
# First list the hook scripts, then ask the user for explicit deletion approval.
find .claude/hooks -maxdepth 1 -type f -name 'gauntlet-*.sh' -print

# Edit .claude/settings.json to remove gauntlet hook entries
# (manual; use jq or your editor)
```

The skill does NOT automatically uninstall hooks; the user explicitly decides. This prevents accidental disabling of discipline mid-run.

---

## CI integration (alternate to hooks)

If the user prefers CI-level enforcement over agent-harness hooks, the same scripts run in GitHub Actions:

```yaml
# .github/workflows/gauntlet-discipline.yml
name: Gauntlet Discipline Gates

on:
  pull_request:
    paths:
      - 'crates/**'
      - '.bench-history/**'
      - 'docs/progress/**'

jobs:
  ledger-mine-required:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./<workspace>/scripts/mine-ledger.sh <workspace>
      - run: ./<workspace>/scripts/convergence-tracker.sh <workspace> --check
      - run: ./<workspace>/scripts/bead-graph-validator.sh <target> --output-root <workspace>
```

CI enforcement is more authoritative than agent-harness hooks (an agent can disable a hook; CI runs on a controlled machine). Both can coexist.

---

## Common gotchas

- **Hook script must be executable.** `chmod +x .claude/hooks/*.sh` after copying.
- **`$CLAUDE_PROJECT_DIR` is the only reliable env var.** Don't rely on `pwd` or `cd` — Claude Code may invoke hooks from non-obvious working directories.
- **Hook stderr is surfaced to the user.** Use stderr for explanation; stdout for context-injection (UserPromptSubmit, SessionStart).
- **Don't make hooks slow.** Hooks block the tool call; aim for <500ms per hook. The ledger-mine hook can be longer (1-3s) because it runs at commit time; the SessionStart hook should be <200ms.
- **Hooks should fail open by default.** Exit 0 unless you're SURE you want to block. A bad hook that always exits 2 makes the gauntlet unusable.
- **Test hooks in `quick-smoke` mode first.** A broken hook in T4 mode wastes hours; the SELF-TEST scaffold catches issues in minutes.

---

## See also

- [/cc-hooks](../../../cc-hooks/SKILL.md) — the canonical Claude Code hooks skill.
- [/dcg](../../../dcg/SKILL.md) — destructive-command-guard hooks; complementary to gauntlet hooks.
- [SKILL.md § Polish Bar](../../SKILL.md) — the discipline these hooks enforce.
- [CASS-MINING.md § AGENTS.md mandate](CASS-MINING.md) — the mandate the userprompt hook references.
