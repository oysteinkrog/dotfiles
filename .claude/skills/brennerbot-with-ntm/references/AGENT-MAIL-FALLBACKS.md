# AGENT-MAIL-FALLBACKS.md — When MCP Agent Mail Is Unavailable

<!-- TOC: What changes | Thread-id discipline | File reservations via beads | Macro substitutions | What you lose | When to escalate back | Operator playbook -->

If MCP Agent Mail server isn't running, this skill can fall back to **NTM pane messages + bead assignees**. That fallback keeps the session moving, but it is degraded: you lose hard reservation visibility, searchable mail threads, and macro-driven coordination. For mutating multi-agent work, degraded Agent Mail is a coordination risk, not a cosmetic warning.

Trigger this fallback when:

- MCP Agent Mail tools are unavailable or `register_agent` / `macro_start_session` cannot reach the server
- `ntm --robot-tools` or `ntm work queue-dry` reports degraded Agent Mail / reservation visibility
- `register_agent` times out twice in Phase 2 bootstrap
- Operator explicitly requests "no Agent Mail" (e.g., constrained environment)

Record the fallback in `phase0_scope_decision.md`:

```markdown
coordination: ntm-inbox-fallback
agent_mail_unavailable_reason: "<why>"
agent_mail_unavailable_at: <ISO-8601>
```

---

## What changes

| Substrate | Agent Mail | ntm-inbox fallback |
|-----------|------------|--------------------|
| Identity | `register_agent` per pane; record returned Agent Mail name in roster | pane id is identity (`p1`, `p2`, ...) |
| Per-thread message | `send_message(thread_id=...)` | `ntm --robot-send=<session> --panes=<N> --msg=$'<subject>\n\n<body>'` (subject prefixed) |
| Inbox check | `fetch_inbox` / `resource://inbox/...` | `ntm --robot-tail=<session> --panes=<N> --lines=200` |
| Acknowledge | `acknowledge_message` | reply with `[<thread-id>] ACK <msg-summary>` in pane |
| File reservation | `file_reservation_paths` exclusive lease | **soft lock** via `br update <H-id> --assignee=<pane-id>` + manual coordination |
| Pre-commit guard | `am guard install` | manual check (operator runs `git diff` for reservation conflicts) |
| Cross-repo handshake | `macro_contact_handshake` | not available — manual file copy + cross-link in beads |

---

## Thread-id discipline (unchanged)

The thread-id schema in [AGENT-MAIL-CONVENTIONS.md](AGENT-MAIL-CONVENTIONS.md) still applies. Subjects still prefix with `[<thread-id>]`. The inbox is just *the pane's own scrollback* now — the operator scans `--robot-tail` for thread-id patterns.

```bash
# Find all messages on a thread:
ntm --robot-tail=brennerbot-event-log --lines=2000 | grep '^\[RS-20260506-event-log-H-005\]'
```

---

## File reservations via beads

Instead of `file_reservation_paths`, use `br update` with the assignee field:

```bash
id_by_ref() {
  br list --all --json \
    | jq -r --arg ref "$1" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' \
    | head -1
}

# Pane 3 claims investigation of H-007:
h_id="$(id_by_ref H-007)"
[ -n "$h_id" ] || { echo "No bead found for public ref H-007" >&2; exit 1; }
br update "$h_id" --assignee=p3 --status=in_progress

# Soft-lock convention: the H-id implies which evidence pack file is being edited.
# H-007 = evidence/packs/EV-pack-H-007.md
# Coordination is by-convention, not enforced.

# Release:
br update "$h_id" --assignee=
```

**Conflict resolution rule** (no automatic guard): if two panes both update `EV-pack-H-007.md`, git will surface the conflict. The operator resolves manually. Investigation panes are instructed in `MO-02-onboarding.md` to:

1. Run `br show "$h_id"` *before* opening the file.
2. If `assignee:` is set to another pane, file a coordination message in `RS-...-INVEST-coord` and pick a different H.
3. Otherwise claim with `br update "$h_id" --assignee=<self>`.

---

## Macro substitutions

| MCP macro | ntm-inbox equivalent |
|-----------|----------------------|
| `macro_start_session` | `ntm --robot-send=<session> --panes=<N> --msg="$(cat MO-02-onboarding.md)"` |
| `macro_prepare_thread` | (just dispatch with subject prefix; no thread setup needed) |
| `macro_file_reservation_cycle` | `br update <H-id> --assignee=<pane> --status=in_progress` followed by message dispatch |
| `macro_contact_handshake` | not available; manual cross-repo coordination |

---

## What you lose with the fallback

1. **Token efficiency** — Agent Mail stores messages in a per-project archive separate from pane context; ntm-inbox messages live in pane scrollback and consume context. Mitigate by: keeping messages terse, periodic context summaries.
2. **File-reservation safety** — git surface conflicts; you don't get pre-commit guarding. Mitigate by: tighter coordination via `RS-...-INVEST-coord` thread, smaller per-pane domains.
3. **Cross-repo coordination** — macros don't exist. Mitigate by: confine the session to one workspace; symlink external corpus.
4. **Searchable thread archive** — Agent Mail makes `search_messages` cheap; ntm-inbox requires `grep` over scrollback. Mitigate by: capture each thread's salient turns into `session-logs/round-N.md` periodically.

---

## When to escalate back

If MCP Agent Mail comes back mid-session, can the swarm re-attach? **Yes, with a re-onboarding pass:**

1. Update `phase0_scope_decision.md` to `coordination: agent-mail-resumed-at: <ISO>`.
2. Dispatch `MO-02-onboarding.md` (re-onboarding variant) to each pane: "Agent Mail is now available; please `register_agent` and reserve your current `H-id` files."
3. Bead-level state survives unchanged — `assignee:` field maps directly to file reservations.
4. From this point forward, prefer `send_message` over `ntm --robot-send` for cross-pane coordination and use `ntm --robot-causality=<session>` to reconcile the degraded interval.

---

## Operator playbook (fallback in flight)

When in fallback:

```bash
# At start of each tick:
ntm --robot-snapshot                                  # pane state + cursor
ntm --robot-attention --attention-session=RS-YYYYMMDD-<slug> --attention-cursor=<cursor>
ntm --robot-tail=RS-YYYYMMDD-<slug> --lines=100        # recent activity per pane
br list --status=in_progress --json | jq             # current claimed work
br list --label=hypothesis --status=open --json | jq # then filter description-level state: active

# To dispatch:
./scripts/dispatch-marching-order.sh MO-04a-investigate \
  --target-pane=3 \
  --target-session=RS-20260506-event-log \
  --PANE_N=3 \
  --H_ID=H-007 \
  --SESSION_ID=RS-20260506-event-log

# To check for collisions:
git status   # if multiple panes are editing the same file, you'll see uncommitted changes from peers
```

The fallback is *operationally possible* — every phase can still be run. It is not equivalent to Agent Mail. If the session is high-stakes or touches shared code, prefer pausing mutating work until reservation visibility is restored.
