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

### 2. Bead progress

```bash
echo "=== Open ===" && br list --status open 2>/dev/null | tail -1
echo "=== Closed ===" && br list --status closed 2>/dev/null | tail -1
echo "=== Ready ===" && br ready 2>/dev/null
```

### 3. Recent commits

```bash
git log --oneline -15
```

Verify each commit references a bead ID. Flag any commits that don't.

### 4. Summary

Present:
- Agent states (GENERATING / WAITING / ERROR / STALLED)
- Beads closed since swarm started vs total open
- Any issues: conflicts, stalled agents, missing bead IDs in commits
- What's ready next
