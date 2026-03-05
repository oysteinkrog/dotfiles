# Swarm Status

Show current swarm progress: agent activity, bead completion, and issues.

## When to activate

Activate when the user says:
- "swarm status" / "check swarm" / "swarm progress"
- "how's the swarm" / "agent status"

## Instructions

### 1. Sessions and agents

```bash
ntm list 2>/dev/null
```

For each active session:

```bash
ntm activity <session> 2>/dev/null
ntm changes <session> 2>/dev/null
ntm conflicts <session> 2>/dev/null
```

### 2. Bead progress (via bv)

```bash
# Quick health overview
bv -robot-triage 2>/dev/null | jq '{
  actionable: .triage.quick_ref.actionable_count,
  blocked: .triage.quick_ref.blocked_count,
  top_picks: [.triage.quick_ref.top_picks[]? | {id, title, unblocks}],
  health: .triage.project_health.status
}'

# Any alerts?
bv -robot-alerts --severity=critical 2>/dev/null | jq '.alerts[:5]'
```

### 3. Recent commits

```bash
git log --oneline -15
```

Verify each commit references a bead ID. Flag any commits that don't.

### 4. Drift check (if baseline exists)

```bash
bv -check-drift 2>/dev/null
```

### 5. Orphaned files check

```bash
git status --short | grep '^??' | head -20
```

Flag any untracked test files — agents often write files but crash before committing.
These need manual build/test/commit rescue.

### 6. Summary

Present:
- Agent states (GENERATING / WAITING / ERROR / STALLED)
- Actionable vs blocked beads, project health status
- Any critical alerts
- Recent commits with bead ID verification
- Orphaned untracked files (if any)
- Next highest-impact bead to work on
