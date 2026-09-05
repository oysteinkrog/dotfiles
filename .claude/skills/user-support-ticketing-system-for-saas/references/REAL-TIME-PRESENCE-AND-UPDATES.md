# Real-Time Presence And Updates

The support conversation is real-time the same way a chat is real-time. Customer waiting for reply; admin typing reply; customer adding clarifying message; admin getting page from a colleague — making this loop feel live (not "refresh-and-pray") closes resolution time and reduces double-replies.

This file is the architectural pattern for live updates without overcomplicating the system.

## What "Real-Time" Means Here

Three layers of real-time-ness, in order of cost:

1. **Reactive polling** — TanStack Query refetches at a tuned interval (15s for ticket detail, 30s for queue). Cheap; works everywhere; stale up to interval.
2. **Visibility-aware refetch** — refetch on tab focus + on visibility change. Cheap; reduces stale-on-return.
3. **Push (SSE / WebSocket)** — server pushes when state changes. More infra; truly live.

Most teams should run layers 1+2 by default; add layer 3 only when the data feels noticeably stale despite tuning.

## Layer 1+2 — Polling With Visibility Awareness

### TanStack Query Config

```ts
useQuery({
  queryKey: ["ticket", ticketId],
  queryFn: () => fetchTicketDetail(ticketId),
  staleTime: 15_000,
  refetchInterval: 15_000,           // background poll while tab open
  refetchIntervalInBackground: false, // pause when tab inactive
  refetchOnWindowFocus: true,         // refetch when tab returns
  refetchOnReconnect: true,           // refetch when network returns
});
```

`refetchIntervalInBackground: false` is critical. Otherwise an admin with 50 ticket-detail tabs open burns API calls overnight.

### Server-Side Headers Help Browser Cache

```ts
return NextResponse.json(data, {
  headers: {
    "Cache-Control": "private, max-age=10, must-revalidate",
    ETag: computeETag(data),
  },
});
```

Browser cache + ETag means polling at 15s often returns 304 Not Modified — no payload, just a small headers exchange.

### "Live" Indicator In UI

Show a subtle indicator when data is "fresh":

```tsx
function TicketDetail() {
  const { data, dataUpdatedAt, isFetching } = useSupportTicketDetail(ticketId);
  const ageSeconds = Math.floor((Date.now() - dataUpdatedAt) / 1000);
  return (
    <header>
      <h1>{data?.ticket.subject}</h1>
      <span className="text-xs text-muted">
        {isFetching ? "🔄 Refreshing…" : `Updated ${ageSeconds}s ago`}
      </span>
    </header>
  );
}
```

Reassures admin that they're seeing recent state.

## Layer 3 — Push Updates (SSE Recommended)

SSE (Server-Sent Events) is simpler than WebSocket for ticket-update push: server-to-client only, HTTP-compatible, auto-reconnects. Use for ticket-detail subscribers.

### Server Endpoint

```ts
// /api/support/tickets/[id]/stream
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(req);
  if (!auth.success) return auth.response;
  const { id } = await params;
  const hasAccess = await verifyTicketAccess(id, auth.user.userId);
  if (!hasAccess) return new Response("Not Found", { status: 404 });

  const stream = new ReadableStream({
    async start(controller) {
      const send = (event: string, data: unknown) => {
        controller.enqueue(new TextEncoder().encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
      };
      const subscription = subscribeToTicket(id, (update) => send(update.kind, update.payload));
      send("connected", { ticketId: id });
      const heartbeat = setInterval(() => send("heartbeat", { ts: Date.now() }), 30_000);
      req.signal.addEventListener("abort", () => {
        clearInterval(heartbeat);
        subscription.unsubscribe();
        controller.close();
      });
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      "Connection": "keep-alive",
      "X-Accel-Buffering": "no",   // disable nginx buffering
    },
  });
}
```

### Client Hook

```ts
function useTicketStream(ticketId: string) {
  const queryClient = useQueryClient();
  useEffect(() => {
    const es = new EventSource(`/api/support/tickets/${ticketId}/stream`);
    es.addEventListener("message_added", (e) => {
      const data = JSON.parse(e.data);
      queryClient.setQueryData(["ticket", ticketId], (old: TicketDetail | undefined) => {
        if (!old) return old;
        return { ...old, messages: [...old.messages, data.message] };
      });
    });
    es.addEventListener("status_changed", () => {
      queryClient.invalidateQueries({ queryKey: ["ticket", ticketId] });
    });
    es.addEventListener("typing", (e) => {
      const data = JSON.parse(e.data);
      // surface "support is typing..." in UI
    });
    return () => es.close();
  }, [ticketId, queryClient]);
}
```

### Pub/Sub Backend

The `subscribeToTicket(...)` function on the server connects to a pub/sub layer:
- Postgres `LISTEN/NOTIFY` (simplest; works without extra infra)
- Redis pub/sub
- A managed service (Pusher, Ably)

Postgres `NOTIFY 'ticket_updates_<ticketId>'` from triggers on `supportMessages` insert / `supportTickets` update. Server SSE handler `LISTEN`s on the channel.

```sql
CREATE OR REPLACE FUNCTION notify_ticket_update() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('ticket_updates_' || NEW.ticket_id::text, json_build_object(
    'kind', 'message_added',
    'messageId', NEW.id,
    'senderType', NEW.sender_type
  )::text);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER support_messages_notify
AFTER INSERT ON support_messages
FOR EACH ROW EXECUTE FUNCTION notify_ticket_update();
```

NOTIFY payloads are limited to 8KB; emit IDs and let clients fetch the full payload. This avoids stale data and keeps events tiny.

## Typing Indicators

Customer or admin is typing → other side sees "Acme support is typing…" in the UI. Implementation:

1. Debounced client POSTs a typing heartbeat when textarea has activity
2. Client stops POSTing after 5s of no input; server broadcasts `typing-stop`
3. Other side renders the indicator with a 6s timeout (auto-hide if no follow-up event)

```tsx
useEffect(() => {
  if (!textareaValue) return;
  const timer = setTimeout(() => emitTypingStart(), 200);
  return () => clearTimeout(timer);
}, [textareaValue]);
```

Don't ship typing for the customer-facing widget unless you've thought through privacy implications — the customer seeing "support is typing" sets expectations the team must keep.

## Optimistic Updates

When admin sends a reply, the message appears instantly in the UI (before server confirms):

```ts
const addMessageMutation = useMutation({
  mutationFn: (input: AddMessageInput) => addMessage(ticketId, input),
  onMutate: async (input) => {
    await queryClient.cancelQueries({ queryKey: ["ticket", ticketId] });
    const previous = queryClient.getQueryData(["ticket", ticketId]);
    queryClient.setQueryData(["ticket", ticketId], (old: TicketDetail) => ({
      ...old,
      messages: [...old.messages, {
        id: `pending-${randomUUID()}`,
        senderId: "me",
        senderType: "support",
        message: input.message,
        attachments: input.attachments ?? null,
        createdAt: new Date().toISOString(),
        pending: true,                     // UI marker
      }],
    }));
    return { previous };
  },
  onError: (err, input, ctx) => {
    queryClient.setQueryData(["ticket", ticketId], ctx?.previous);
    toast.error("Failed to send. Tap to retry.");
  },
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ["ticket", ticketId] });
  },
});
```

The pending message is rendered with a slight visual indicator (lower opacity + spinner) until the server confirms. On error, revert and show retry.

## Presence: Who Is Looking At This Ticket

For a busy team, "Engineer A is also viewing this ticket" prevents double-replies:

```ts
// /api/support/tickets/[id]/presence/heartbeat
// Called every 15s while ticket detail tab is active
export async function POST(req: Request, { params }) {
  const auth = await requireAdmin(req);
  if (!auth.success) return auth.response;
  const { id } = await params;
  if (!await verifyAdminTicketAccess(id, auth.user.userId)) {
    return new Response("Not Found", { status: 404 });
  }
  await redis.set(`presence:ticket:${id}:${auth.user.userId}`, JSON.stringify({
    name: auth.user.displayName,
    expiresAt: Date.now() + 30_000,
  }), { ex: 30 });
  return NextResponse.json({ ok: true });
}

// /api/support/tickets/[id]/presence (GET)
// Returns current viewers
export async function GET(req, { params }) {
  const auth = await requireAdmin(req);
  if (!auth.success) return auth.response;
  const { id } = await params;
  if (!await verifyAdminTicketAccess(id, auth.user.userId)) {
    return new Response("Not Found", { status: 404 });
  }
  const keys = await scanRedisKeys(`presence:ticket:${id}:*`);  // never KEYS in production
  const viewers = await Promise.all(keys.map(k => redis.get(k)));
  return NextResponse.json({ viewers: viewers.map(v => JSON.parse(v!)) });
}
```

UI shows tiny avatars of co-viewers in the ticket header. Hover for names.

Don't track presence client-side from the customer; admin → admin only.

## Handling Reconnection

SSE auto-reconnects with backoff. On reconnect, replay missed events: query the messages endpoint with a `since` filter, merge into client state. This catches up the conversation without polling.

```ts
es.onerror = () => {
  // browser will auto-reconnect; in onopen, fetch since last seen createdAt
};

es.addEventListener("open", () => {
  const lastSeenAt = queryClient.getQueryData<TicketDetail>(["ticket", ticketId])?.messages.at(-1)?.createdAt;
  if (lastSeenAt) {
    fetch(`/api/support/tickets/${ticketId}/messages?since=${lastSeenAt}`)
      .then(r => r.json())
      .then(data => {
        queryClient.setQueryData(["ticket", ticketId], (old: TicketDetail) => ({
          ...old,
          messages: [...old.messages, ...data.messages.filter(m => m.createdAt > lastSeenAt)],
        }));
      });
  }
});
```

## Notification Badges

The browser tab title updates to show unread count: `(3) Support — Acme`. Service-worker push (with permission) can ping admins of P0 SLA breaches even when they're not on the dashboard.

```ts
// Update document.title with unread count
useEffect(() => {
  const unread = computeUnread(tickets);
  document.title = unread > 0 ? `(${unread}) Support — Acme` : "Support — Acme";
}, [tickets]);
```

Push notifications via web push API:

```ts
async function subscribeToPush() {
  const reg = await navigator.serviceWorker.ready;
  const subscription = await reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(env.NEXT_PUBLIC_VAPID_KEY),
  });
  await fetch("/api/admin/support/push-subscribe", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(subscription),
  });
}
```

The subscribe route is admin-authenticated, CSRF-protected, and permission
checked (`support.read` or stricter). Server pushes only for high-priority
events (P0 breaches, mentions in internal notes, your-assignment-here). Don't
push for every status change — that's spam.

## Connection Limits

Each SSE connection holds a Node process / Vercel function alive. With many admins watching, connection count can spike. Mitigations:
- Cap connections per user (max 3 concurrent SSE)
- Cap connections per ticket (max 5; 6th admin uses polling)
- Auto-close after 5 min of no activity (admin presumed AFK)
- Confirm the deployment platform supports long-lived responses; otherwise stop
  at polling/visibility refetch or use a managed push provider.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Polling every 1s "for snappiness" | API cost; client memory; ignores `staleTime` |
| Sending full ticket payload on every NOTIFY | 8KB Postgres limit; stale data; expensive |
| WebSocket for ticket detail when SSE suffices | Adds bidirectional complexity for unidirectional need |
| Optimistic update without rollback on error | Customer thinks message sent; in-progress message persists locally forever |
| Customer-facing typing indicator on widget without thought | Implies team is "live now" expectation when they're not |
| Push notifications on every event | Notification fatigue; desensitizes the high-value alerts |
| No heartbeat → SSE silently dies behind a proxy | Connections appear alive but events stop flowing |
| Presence heartbeat at 1s | API hammer; redis pressure |
| Redis `KEYS presence:*` in production | Blocks Redis under load; use SCAN or a set per ticket |
| No reconnection catch-up | Admin closes laptop, opens 4h later, missed every event |

## Wire Points Checklist

- [ ] TanStack Query polling tuned per surface
- [ ] `refetchIntervalInBackground: false` on long-tail queries
- [ ] `refetchOnWindowFocus: true` on hot surfaces
- [ ] ETag-based 304 responses on poll endpoints
- [ ] SSE endpoint per ticket with auth gate
- [ ] Postgres NOTIFY trigger on relevant tables
- [ ] Heartbeat every 30s on SSE
- [ ] Reconnection catch-up via `?since=` filter
- [ ] Optimistic updates with rollback
- [ ] Typing indicator (admin-side; customer-side optional)
- [ ] Presence (who's viewing) for admin coordination
- [ ] Connection-count caps (3/user, 5/ticket)
- [ ] Browser tab title shows unread count
- [ ] Push notifications gated to high-priority events
- [ ] Auto-close idle SSE after 5 min
