# Auto-Intake (zero-prompt)

> **Branch + workspace policy (fixed; not auto-computed).** The skill **never** creates a new branch — auto-intake records the target's current branch as `target_branch` and commits there. The audit workspace is **always** `<target>/agent_ergonomics_audit/` (in-tree). If a legacy sibling exists, auto-intake migrates it. See SKILL.md callouts for the rationale.

For CI / chained skill invocations / batch runs, use this **deterministic** intake
instead of `intake-prompt.md`. It computes the defaults from inspecting the
target — no human in the loop.

Use this when:
- The skill is being invoked from another skill or `bin/aerg`
- The user explicitly said "skip the intake, use defaults"
- A nightly/CI job is running the audit unattended

**DO NOT** use auto-intake when running interactively. The 8 questions in
`intake-prompt.md` exist because they catch real failure modes (toolchain not
installed, scope guardrails, deprecation policy). Skipping them is fine for the
20th re-run; not for the first.

---

## Defaults computed from the target

Given only `<TARGET>` (a directory or path to a binary), derive every parameter:

| Param | How to compute | Fallback |
|-------|----------------|----------|
| **TARGET_PATH** | `realpath <TARGET>` if dir; else `realpath $(dirname <TARGET>)` | error if not a dir |
| **TARGET_BASENAME** | `basename $(realpath <TARGET>)` | — |
| **WORKSPACE_PATH** | `${TARGET_PATH}/agent_ergonomics_audit` (always in-tree; never a sibling) | — |
| **MODE** | If `--rescore-only` and prior pass exists → `re-score-only`; else default `full` for any "apply" / unspecified intent; only `audit-only` if explicitly requested | `full` |
| **TRIANGULATION** | `peer-claude` (always — single Claude path is too easy to be wrong) | `peer-claude` |
| **CASS** | `skip` for auto-intake (interactive only) | `skip` |
| **SCOPE_GUARDRAILS** | Read `<TARGET>/.aerg-guardrails` if present (one path/glob per line); else empty | empty |
| **BRANCH** | NOT computed. The skill never creates a new branch; commits land on the target's currently checked-out branch (recorded as `target_branch` in the manifest, typically `main`). | `<current branch>` |
| **TOOLCHAIN_CONSENT** | `block` (auto-intake is unattended; never install software unsupervised) | `block` |

## Detection helpers

### Recording the current branch (NOT creating a new one)
```bash
TARGET_BRANCH=$(cd "$TARGET" && git rev-parse --abbrev-ref HEAD)
# That's it — auto-intake never switches off the current branch.
```

### Detecting a legacy sibling workspace (migrate if found)
```bash
TARGET_PARENT="$(dirname "$TARGET_PATH")"
LEGACY_SIBLING="${TARGET_PARENT}/${TARGET_BASENAME}__agent_ergonomics_audit"
if [ -d "$LEGACY_SIBLING" ]; then
  # Migrate contents to in-tree location, preserve manifest history.
  mkdir -p "$WORKSPACE_PATH"
  rsync -a "$LEGACY_SIBLING/" "$WORKSPACE_PATH/"
  # Mark the legacy directory as superseded (rename, do not delete — AGENTS.md rule #1).
  mv "$LEGACY_SIBLING" "${LEGACY_SIBLING}.superseded.$(date -u +%Y%m%dT%H%M%SZ)"
fi
```

### Detecting prior audit workspace (in-tree)
```bash
if [ -d "$WORKSPACE_PATH" ] && [ -f "$WORKSPACE_PATH/audit/manifest.json" ]; then
  PRIOR_PASS=$(jq -r '[.current_pass, ((.passes // []) | map(.pass // 0) | max // 0)] | max // 0' "$WORKSPACE_PATH/audit/manifest.json")
  if [ "$PRIOR_PASS" -gt 0 ]; then
    MODE="re-score-only"
  fi
fi
```

### Detecting archetype (for default depth/timeouts)
```bash
# Heuristic, not authoritative — a real archetype determination requires CLI-ARCHETYPES.md.
if find "$TARGET" -maxdepth 3 -name 'Cargo.toml' | grep -q '^.*$'; then
  ARCH=rust-clap
elif find "$TARGET" -maxdepth 3 -name 'go.mod' | grep -q '^.*$'; then
  ARCH=go-cobra
elif find "$TARGET" -maxdepth 3 -name 'pyproject.toml' -o -name 'setup.py' | grep -q '^.*$'; then
  ARCH=python-click
else
  ARCH=unknown
fi
```

## Resolved manifest stub

```json
{
  "schema_version": 2,
  "skill_version": "1.1.0",
  "intake_mode": "auto",
  "intake_resolved_at": "<UTC ISO8601>",
  "target_path": "<TARGET_PATH>",
  "target_basename": "<TARGET_BASENAME>",
  "workspace_path": "<WORKSPACE_PATH — always TARGET_PATH/agent_ergonomics_audit>",
  "mode": "<MODE>",
  "triangulation": "peer-claude",
  "cass_policy": "skip",
  "scope_guardrails": [],
  "target_branch": "<current branch as recorded; this skill does not switch or create branches>",
  "toolchain_consent": "block",
  "detected_archetype": "<ARCH>",
  "prior_pass_count": 0
}
```

## Failure modes (auto-intake hard-fails on)

1. **Target missing or unreadable**: exit 2.
2. **Target is not a git repo and `mode != audit-only`**: exit 2 (need a git repo to commit applied changes against).
3. **In-tree workspace exists but contains uncommitted artifacts**: exit 2 (refuse to clobber prior partial run; instruct user to commit or stash first).
4. **Toolchain missing for `mode in {full, re-score-only}`**: exit 3 (with `toolchain_consent=block`, we can't install).
5. **Detected archetype is `unknown` and no `--archetype` override**: WARN (proceed with conservative defaults: depth=2, timeout=120s/surface).

Auto-intake never asks the user. It chooses the safe default and logs the choice
to `<SIBLING>/audit/intake_decisions.jsonl`.

## Auditability requirement

Every decision auto-intake made must be reconstructable from
`audit/intake_decisions.jsonl`. Schema:

```json
{
  "decision": "target_branch",
  "value": "main",
  "rationale": "skill never creates a new branch; current branch recorded as-is",
  "timestamp": "2026-05-07T13:42:00Z"
}
```

This file is the auto-intake equivalent of the human's verbal "yes, go ahead" —
without it, the run is non-reproducible.
