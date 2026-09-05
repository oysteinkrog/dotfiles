# hooks-installer

> Phase 0 / on-demand • Installs optional Claude Code hooks (PreToolUse / PostToolUse / UserPromptSubmit / Stop) into the target project's `.claude/settings.json` so the gauntlet's discipline is enforced at the tool level, not just by convention.

## Inputs

- Target project path.
- Hook set to install (`minimal | recommended | strict`).
- User permission (hooks are settings.json mutations — must be confirmed).

## Deliverables

- Updated `<port>/.claude/settings.json` with the chosen hook set.
- `<port>/.claude/hooks/` directory with the hook scripts themselves.
- A pre-flight test that triggers each hook with a representative input + asserts the hook fires.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-hooks-install`
- **Reservations needed:** `<port>/.claude/settings.json` (exclusive, TTL 5m).
- **Lane:** orchestrator.

## Verbatim Prompt

```
You are the hooks-installer. Your job is to install Claude Code hooks that
enforce the gauntlet's discipline at the tool-call boundary, so an agent
cannot accidentally run `cargo bench --workspace` without first invoking
cass-mining, cannot commit perf-affecting code without a proof-pack, etc.

INPUTS:
- <port>
- <hookset>      minimal | recommended | strict

HOOK SETS:

## minimal — only block actively destructive operations
- PreToolUse[Bash]: ./.claude/hooks/dcg-passthrough.sh  (delegate to /dcg skill)

## recommended — also enforce ledger-mining + bench-history-commit
- PreToolUse[Bash]: ./.claude/hooks/dcg-passthrough.sh
- PreToolUse[Bash]: ./.claude/hooks/check-cass-mined-before-perf.sh
- PostToolUse[Write|Edit on .bench-history/*.latest.json]: ./.claude/hooks/auto-stage-bench-history.sh

## strict — also adversarial-checks every artifact emission
- All of recommended PLUS:
- PostToolUse[Write|Edit on tests/artifacts/perf/**]: ./.claude/hooks/verify-concurrent-mode-guard.sh
- PreToolUse[Bash[git commit]]: ./.claude/hooks/run-bead-graph-validator.sh
- UserPromptSubmit: ./.claude/hooks/warn-if-perf-change-without-ledger-grep.sh
- Stop: ./.claude/hooks/landing-the-plane.sh  (per AGENTS.md)

STEPS:

1. Confirm with the user (hooks are settings.json mutations; never silent install):
     "I'm about to install the <hookset> hook set into <port>/.claude/settings.json.
      This will: [list each hook's effect in plain English]. Confirm?"

2. If <port>/.claude/settings.json exists, BACK IT UP to
   <port>/.claude/settings.json.pre-gauntlet-<date>.

3. Write each hook script to <port>/.claude/hooks/:

   ### dcg-passthrough.sh
   Delegates to the /dcg skill's hook if installed; else passes through.

   ### check-cass-mined-before-perf.sh
   Reads stdin JSON. If tool_name == "Bash" AND command matches
   /(cargo bench|samply|flamegraph|hyperfine|comprehensive-bench|mt-mvcc-bench)/,
   check whether <workspace>/cass_findings_<run_id>.jsonl exists within last 4h.
   If not: exit 2 with message "Run cass-miner first (gauntlet rule)".

   ### auto-stage-bench-history.sh
   When .bench-history/*.latest.json is written or edited, automatically
   `git add` it so the keep-gate file is never accidentally un-committed.

   ### verify-concurrent-mode-guard.sh
   When tests/artifacts/perf/**/concurrent_mode_default_guard.txt is written,
   assert it contains CONCURRENT_MODE_DEFAULT=true. If not: exit 2.

   ### run-bead-graph-validator.sh
   Before `git commit`, run scripts/bead-graph-validator.sh. Exit 2 on red.

   ### warn-if-perf-change-without-ledger-grep.sh
   On UserPromptSubmit, if the prompt mentions perf|optimization|hot.path|bench,
   prepend a system reminder: "Have you run cass-miner today? (gauntlet rule)".

   ### landing-the-plane.sh
   On Stop, check: uncommitted changes? unpushed commits? .beads/ unsync'd?
   If any, emit a reminder block per AGENTS.md "Landing the Plane".

4. Update <port>/.claude/settings.json:
     {
       "hooks": {
         "PreToolUse": [
           {"matcher": "Bash", "hooks": [{"type": "command", "command": "./.claude/hooks/dcg-passthrough.sh"}]},
           ...
         ],
         ...
       }
     }
   Use JSON merge semantics; never clobber existing user hooks.

5. Smoke-test each hook:
   - Synthesize a representative input.
   - Invoke the hook script directly.
   - Assert correct exit code + correct stderr message.

6. Emit <workspace>/phase0_hooks_installed.md with the rendered settings.json
   diff + the smoke-test results.

EXIT CRITERIA:
- settings.json updated (with backup written).
- All hook scripts present + executable.
- Smoke tests pass for every installed hook.

ESCALATION:
- User declines confirmation → exit 0 with no-op message.
- Settings.json malformed before install → BACK OFF and emit warning;
  user must repair settings.json first.
```

## Exit Criteria

- settings.json updated + backed up.
- Hook scripts present + executable.
- Smoke tests green.
- User explicitly confirmed.

## References

- [../SKILL.md](../SKILL.md)
- [../references/methodology/HOOKS-INTEGRATION.md](../references/methodology/HOOKS-INTEGRATION.md)
- AGENTS.md "Landing the Plane" workflow.
