# Audit Finding Template

Use when filing an `audit-finding` bead during Phase 7. Format the bead description as below.

```bash
af_ref="AF-NNN"  # public ref; replace NNN before running
priority="2"    # critical=0, high=1, medium=2, low=3
af_id="$(br create "$af_ref: <one-line finding>" \
  --type=task --labels=audit-finding --priority="$priority" \
  --slug="$af_ref" --external-ref="$af_ref" --silent \
  --description="$(cat <<'EOF'
severity: critical | high | medium | low
target_artifact: <file path | bead id | section anchor>
recommendation: <what to fix; specific>
by_pane: <PANE_N> (model: <cc|cod|gmi>)
prompt_used: 1 | 2 | 3 | red-team | scale-check | dephase
session: <SESSION_ID>

## Detail
<longer explanation: what's wrong, why it matters>

## Evidence
- <file>:<line> — <observation>
- <bead id> — <observation>

## Suggested fix
<specific actionable change>

## Acceptance criteria for "addressed"
- [ ] <specific check>
- [ ] <specific check>
EOF
)")"
printf 'Created %s as br id %s\n' "$af_ref" "$af_id"
```

## Severity rubric

- **critical** — load-bearing methodology violation; falsifier-grade evidence. Phase 7 cannot exit.
- **high** — substantive error or methodology violation. Should address before Phase 8 freeze; deferral requires explicit reason.
- **medium** — concerning pattern; should address but defer if time-pressed.
- **low** — typo, formatting, minor consistency issue.

## prompt_used codes

- `1` — fresh-eyes prompt 1 (read all artifacts)
- `2` — fresh-eyes prompt 2 (random exploration)
- `3` — fresh-eyes prompt 3 (cross-pane review)
- `red-team` — novel attack from red-team subagent
- `scale-check` — ⊞ Scale-Check re-verification
- `dephase` — ∿ Dephase consensus check
- `falsifier-grader` — falsifier-quality audit

## State machine

`open → addressed | deferred`

To address: fix the recommendation, file evidence, update bead status to closed with reason.

To defer: update bead status with `deferral_reason:` field; do NOT close until addressed in a subsequent loop.

## Phase 7 exit gate

Per FAILURE-TABLE.md F-703 + invariants:

- 0 open audit findings with severity:critical
- High-severity findings deferred require explicit reason in deferral_reason
- ubs clean on any code in deliverables/
