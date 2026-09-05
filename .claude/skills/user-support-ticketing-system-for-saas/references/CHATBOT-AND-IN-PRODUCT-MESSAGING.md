# Chatbot And In-Product Messaging

The support widget (a button that opens a form) is the floor. The ceiling is real-time chat embedded in the product UI — answer-as-you-type, guided flows, contextual deflection. This file is the architectural pattern for adding chat / chatbot capability without abandoning the structure of the rest of the skill.

## When To Add Chat

Add chat when:

- Customer expectation is real-time (B2C, consumer SaaS, premium B2B)
- Sales conversion benefits from immediate questions ("can it do X?")
- Support volume justifies always-on coverage (enterprise tier)

Skip chat when:

- Team can't staff real-time response; "chat" that gets answered hours later is worse than no chat
- Support is asynchronous-by-design (async-friendly customers prefer it)
- Cost of always-on coverage exceeds benefit

If unsure: start with the static widget. Add chat later if data justifies.

## Three Chat Architectures

### Architecture A — Pure Bot

Automated; no human escalation. Use for: FAQ, hours of operation, simple lookup ("what's my account status").

Cheap. Limited. Customers learn quickly when "chat" can't escalate to humans and stop using it.

### Architecture B — Bot With Escalation

Bot handles common patterns; escalates to a human when uncertain or asked. Use for: most products. Standard pattern.

### Architecture C — Human-Only

Live chat with humans only. Use for: high-touch B2B where every conversation is high-value.

This file primarily covers Architecture B — bot with escalation — since it's the most common and the most architecturally interesting.

## The Chat-To-Ticket Substrate

Chat conversations are *real-time tickets*. The ticket schema reuses:

```ts
// supportTickets gets:
//   source: 'chat' | 'web_form' | 'email' | ...
//   chatStatus: 'active' | 'idle' | 'closed'   (separate from ticket status)
```

A chat that goes idle for 15 min flips to `idle`. Idle for 24h or customer-confirms-resolved → ticket closes. Never auto-close active chats.

This means: every existing pattern (audit, SLA, de-slopify, internal notes, attachments, fan-out) applies. Chat isn't a parallel system; it's a *real-time view* on the same ticketing substrate.

## Real-Time Layer

Use the patterns in [REAL-TIME-PRESENCE-AND-UPDATES.md](REAL-TIME-PRESENCE-AND-UPDATES.md):

- SSE for messages
- Postgres LISTEN/NOTIFY for fan-out
- Optimistic updates on customer side
- Typing indicators

Chat-specific addition: **acknowledgment lag indicator**:

```
You · 2 min ago
  Hi, where do I find the export tool?

(typing...)            ← admin or bot is responding
```

## The Bot Layer

The bot is *just* an admin user with `senderType: "system"` and special permissions. Everything else routes through the same APIs.

```ts
const SUPPORT_BOT_USER_ID = "00000000-0000-0000-0000-000000000bot";

// Bot replies via the same addMessage flow
async function botReplyTo(ticketId: string, body: string) {
  const cleaned = await deslopify(body);                              // bot replies still de-slopified
  await addMessage({
    ticketId,
    senderId: SUPPORT_BOT_USER_ID,
    senderType: "system",                                              // distinct from "support" (human admin)
    message: cleaned,
  });
}
```

Customer-facing UI shows bot replies with a 🤖 indicator and "Bot" label. Honest disclosure beats trying to pass as human.

### Bot Capabilities (Whitelist)

Apply [ADVANCED-AI-FEATURES.md](ADVANCED-AI-FEATURES.md). Bot can:

- Answer from KB (with citation)
- Look up customer's account state ("you're on the Pro plan, billed monthly")
- Check status-page incidents
- Capture intent and route to a human (escalation)

Bot cannot:

- Issue refunds
- Change account state (cancel, downgrade, lock)
- Make any commitment ("we'll fix it by Friday")
- Apologize on behalf of the team for things humans haven't acknowledged

Customer-facing rule: *Bot answers; humans commit.*

### Escalation Triggers

Bot escalates to a human when:

```ts
const ESCALATION_TRIGGERS = [
  "explicit_request",                  // customer says "speak to a human"
  "low_confidence",                    // bot confidence < 0.7 on its answer
  "category_match",                    // categories that always escalate (billing, content_moderation)
  "sentiment_distress",                // customer angry / threatening / harming-themselves
  "third_unresolved_turn",             // bot has tried 3 times without progress
  "payment_action_requested",          // anything money-touching
  "vip_segment",                       // customer is enterprise / design-partner
];

async function shouldEscalate(turn: ChatTurn): Promise<boolean> {
  return ESCALATION_TRIGGERS.some(trigger => triggerMatches(trigger, turn));
}
```

When escalation fires:

1. Bot posts: "I'm pulling in a teammate who can help with this. Hang on a moment."
2. Ticket status updates to `awaiting_support`
3. On-call admin notified (Slack ping + admin queue badge)
4. Conversation history (including bot turns) visible to admin
5. Bot stops responding; humans take over

Don't pretend the bot is still trying. Once escalated, escalated.

## Customer-Facing UI Patterns

### Welcome Sequence

```
👋 Hi! I'm the [Acme] assistant.

I can help with:
  • Looking up account & billing info
  • Finding answers in our docs
  • Connecting you with a human teammate

What's on your mind?

[ Type your question... ]
```

Set expectations early. Honest about the bot's scope.

### Quick-Suggestion Buttons

Pre-canned prompts for common intents:

```
Common questions:
  [💳 Billing question]  [🔐 Login issue]  [📊 How do I export?]  [👥 Talk to human]
```

Customer clicks → bot enters that flow. Reduces friction.

### Active-Hours Indicator

```
Currently:  🟢 Live agents online (typical reply: 5 min)
After hours:  🌙 Bot only — humans respond next business day at 9am ET
```

Set expectations *before* the customer types. Avoids the "anyone there?" frustration.

## Bot Persona

Pick a clearly-bot persona:

- **Avatar**: distinct from human-admin avatars (e.g., a friendly geometric icon)
- **Name**: "Acme Bot" or "[Acme] Assistant" — never a human-sounding name
- **Voice**: helpful, concise, *clearly* not human (don't fake personality)

Customers building rapport with bots they think are human, then learning otherwise, lose trust faster than they lose trust to known bots that can't help everything.

## Knowledge-Grounded Replies

Bot answers come from KB articles or factual product data, *with citation*:

```ts
async function botAnswer(question: string): Promise<{ answer: string; citations: KbArticle[] }> {
  const relevantArticles = await searchKb(question, { topK: 3, minSimilarity: 0.7 });
  if (relevantArticles.length === 0) return { answer: "I'm not sure about that. Let me connect you with a teammate.", citations: [] };
  const answer = await synthesizeAnswer(question, relevantArticles);   // RAG
  return { answer, citations: relevantArticles };
}
```

UI shows citations:

```
🤖 Bot · 1 sec ago
You can export skills from Settings → Data → Export.
The export will be emailed to you within a few minutes.

📚 Sources:
  • How to export your data
  • Export file formats
```

Citations build trust. Hallucinations get flagged when the citation doesn't actually contain the answer. Run hallucination detection per [ADVANCED-AI-FEATURES.md](ADVANCED-AI-FEATURES.md) Concern Bonus.

## Conversation Memory

Within a single chat session, bot remembers context:

```
Customer: How do I export?
Bot: Click Settings → Data → Export.
Customer: What format?
Bot: ↑ The Export tool offers CSV, JSON, and PDF.    ← knows we're on the export topic
```

Across sessions: bot has access to the customer's account state but not to their previous chat content (unless you explicitly persist + retrieve).

For B2B / power-user contexts, "I asked about X yesterday and now ask about Y" is common — persistent chat history per customer is valuable. Implement with care for privacy.

## Multi-Channel Continuity

Customer starts on chat, finishes on email:

```
Customer's chat session ends with: "Send me the doc when you find it"
Admin (later) replies via the ticket detail UI
The ticket already exists — admin's reply emails the customer
Customer sees the email, replies; reply lands back in the same ticket
```

Same ticket, same audit, same SLA — the channel changed but the conversation is one. Per [INBOUND-WEBHOOK-INGESTION.md](INBOUND-WEBHOOK-INGESTION.md), email-threading via `Message-ID` makes this seamless.

## Agent-Side Chat Inbox

Admin's chat queue is a focused view:

```
LIVE CHAT QUEUE
─────────────────
🟢 ACTIVE (waiting for me)
  • Jane Doe · 2 min · "Cannot export skills"
  • Bob · 5 min · "Billing question"

🟡 IDLE (paused)
  • Sue · 22 min · last said: "let me check"
```

One-click takes admin into a focused chat session with conversation history loaded.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Bot pretending to be human | Trust collapses on disclosure |
| Bot capable of mutation actions | One prompt-injection attempt issues a refund |
| No escalation path | "Chat" without humans is dead-end frustration |
| Escalation without context handover | Admin re-asks what bot already asked |
| Hallucinated answers without citations | Customer follows confidently to a phantom feature |
| Replying in chat = different ticket from email reply | Conversations fragment; admin re-explains 3 times |
| Bot says "we" without authorization | The bot doesn't represent the team's commitments |
| Live indicator showing "agent online" when nobody is | Promise breaks; trust craters |
| Chat with no offline mode | Customers in the wrong timezone left in limbo |
| Bot conversation not in the audit trail | Subpoena reveals "system answers" with no record |
| AI cost not capped on per-chat-session | Long conversations rack up tokens |

## Wire Points Checklist

- [ ] `source: 'chat'` field on tickets; chat-status separate from ticket-status
- [ ] SSE-based real-time delivery
- [ ] Bot user ID with `senderType: "system"` for bot replies
- [ ] Bot capability whitelist (no mutations; no commitments)
- [ ] Escalation triggers configured (low confidence, sentiment, vip, request)
- [ ] Clear bot persona (avatar, name, voice)
- [ ] Quick-suggestion buttons in welcome
- [ ] Active-hours indicator surfaced before customer types
- [ ] Knowledge-grounded answers with citations
- [ ] Hallucination detection on bot output
- [ ] Per-session AI cost cap
- [ ] Idle chat detection (15 min) + auto-close (24h)
- [ ] Multi-channel continuity (chat → email → chat) via same ticket
- [ ] Chat inbox view for admins (active vs idle)
- [ ] Audit captures every bot turn
- [ ] de-slopify applies to bot replies
- [ ] Test: escalation fires when expected; admin sees full history
- [ ] Test: prompt-injection in chat does not trigger any non-whitelist action
- [ ] Test: chat conversation appears in customer's data export
