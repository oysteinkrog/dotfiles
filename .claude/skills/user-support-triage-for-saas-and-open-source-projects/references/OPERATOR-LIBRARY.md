# Operator Library — Triage Cognitive Moves

Adapted from `/operationalizing-expertise` Track A. Each operator is an atomic cognitive move with explicit triggers, failure modes, and a copy-paste prompt module. Operators compose into pipelines per phase.

## How To Use This File

1. While running the 6-phase loop ([TRIAGE-WORKFLOW.md](TRIAGE-WORKFLOW.md)), match the situation to an operator.
2. Paste the operator's prompt module into your working context.
3. Apply it; check exit criteria.
4. Move on.

The library is intentionally bounded. Don't add operators ad-hoc — the registered ones cover the cycle. If you find a real gap, propose it and run it past the validation checklist.

---

## Phase 0 Operators (Before Ground Truth)

### 🧭 DOMAIN-ADAPT

**Definition**: Translate the universal support loop into the project's actual
support archetype before applying SaaS/GitHub defaults.

**Triggers**:
- First onboarding for a project outside the default SaaS/custom-DB shape
- `_detection.json` includes `email`, `community-manual`,
  `marketplace-or-app-store`, `internal-ops`, or an empty `surfaces` array
- A ticket is really a moderation, marketplace, app-store, employee, client
  services, regulated, or community-governance case

**Failure modes**:
- Forcing every project into "tickets + refunds + SLA" even when the real queue
  is app-store reviews, GitHub, email, a community forum, or internal ops
- Treating public/community replies like private support emails
- Ignoring platform-specific truth sources such as order ids, app build ids,
  contract terms, or employee identity systems

**Prompt module**:
```
[OPERATOR: 🧭 DOMAIN-ADAPT]
1) Read SUPPORT-INTAKE-ROUTER.md > Support Archetypes.
2) Name every archetype that applies to this project.
3) For each archetype, list:
   - primary truth system;
   - customer/requester identity source;
   - public/private boundary;
   - side effects that require owner approval;
   - support evidence that should improve docs/product/ops later.
4) Write those choices into 00-intake.md and 02-channels.md before triage.

Output: a domain-adaptation block in 00-intake.md.
Required: no SaaS/default-stack assumption remains uncited.
```

**Tag**: `domain-adapt`. **Composes with**: ★ ORIENT, ⊞ MULTI-CHANNEL, ⚖ DECIDE.

---

## Phase 1 Operators (Ground Truth)

### ★ ORIENT

**Definition**: For each open item, capture (who, what, urgency, channel, customer tier, age) before any other thought.

**Triggers**:
- New ticket appears in the open list
- A ticket has been re-surfaced after being closed
- An owner says "look at this one" without context

**Failure modes**:
- Skipping orientation → drafting a reply for the wrong customer tier (free vs paid)
- Treating one channel's report as canonical when the customer also wrote on X/Discord (missing correlation)
- Reading just the subject line, not the body

**Prompt module**:
```
[OPERATOR: ★ ORIENT]
1) For each open ticket / issue / DM, write a single line:
     <id> | <user-handle> | tier=<free|paid|enterprise|unknown>
     | channel=<tickets|legacy-form|gh-issue|gh-pr|discord|x-dm|email>
     | age=<Nh> | sla=<ok|at_risk|breached>
     | subject="<first 80 chars>"
2) Read the FULL body of every item, not just the subject.
3) Note any mention of: another ticket id, a tweet, a Slack thread,
   a previous fix attempt, an outage, a refund request, "fraud", a
   regulator/legal threat, or "GDPR"/"DSAR"/"CCPA" — flag for routing.

Output: one ORIENT line per item; flagged items separated for routing.
Required: every line has every field; "unknown" is acceptable for missing data.
```

**Tag**: `orient`. **Composes with**: ⊞ MULTI-CHANNEL.

---

### ⊞ MULTI-CHANNEL

**Definition**: Pull from every channel the project supports before acting on any.

**Triggers**:
- Start of every triage session
- After ANY change to the channels listed in `02-channels.md`
- When the owner mentions a customer they've heard from elsewhere

**Failure modes**:
- Trusting one channel's count as canonical
- Missing a Discord report that clarifies a confusing ticket
- Replying to a ticket while the same user has already escalated on X

**Prompt module**:
```
[OPERATOR: ⊞ MULTI-CHANNEL]
1) Read 02-channels.md. For EACH channel, run the project's documented
   list-open command. Save raw output to /tmp/channel-<name>.json.
2) Build a unified open-items list, deduplicating by user (same email or
   handle ⇒ same person across channels).
3) Note any user with reports on >1 channel — they take priority and
   require single-coordinated reply.
4) Cross-reference statuspage.io / outage history: any active outage that
   could explain spikes?

Output: <workspace>/open-items-<date>.json with unified list +
        flagged "multi-channel" users.
Required: count from EACH channel cited explicitly; no channel skipped.
```

**Tag**: `multi-channel`. **Composes with**: ★ ORIENT (apply ORIENT to each item after).

---

## Phase 2 Operators (Investigate)

### 🔍 REPRO

**Definition**: Reproduce the user's exact path against production — not a proxy, not a `curl` of one endpoint.

**Triggers**:
- Ticket reports a bug
- Admin notes claim "fixed" but customer still sees it
- A previous reply said "should work now" and the user pushed back

**Failure modes**:
- Hitting one endpoint when the user's flow chains 3 (the JSM Feb 2026 incident)
- Reproducing in dev/staging when the bug only appears in production (env vars / region)
- Using your account when the bug is tier-specific (paid bypass works for you)

**Prompt module**:
```
[OPERATOR: 🔍 REPRO]
1) Extract the user's exact path from the ticket: every command run, every
   page visited, every input given, in order.
2) Pin the version: <tool>--version, browser+OS, app version. From
   `06-recurring-issues.md`, map the version to the deployed code commit.
3) Set up a reproduction account that matches their tier (or use a sandbox
   account with the same plan).
4) Run the chain end-to-end against PRODUCTION. Save every response,
   screenshot, error, and logged event ID.
5) If you can't reproduce: explicitly write "could not reproduce; details
   needed: [list]". Do NOT proceed to draft.

Output: a repro log committed to /tmp/repro-<ticket-id>.md with the chain
and outcomes; OR an explicit no-repro statement.
Required: the chain attempted matches the user's chain step-by-step.
```

**Tag**: `repro`. **Composes with**: ✓ VERSION-PIN, ⊕ CORRELATE.

---

### ⊕ CORRELATE

**Definition**: Cluster open reports by hypothesis BEFORE classifying any individually.

**Triggers**:
- ≥2 open items at session start
- An owner says "the same thing is happening to lots of people"
- Time-of-day / version cluster looks suspicious

**Failure modes**:
- Independently classifying items that share one root cause → triple work
- Surface symptom pattern-match without the root-cause check (e.g., "all 401" but actually three causes)
- Forcing items into clusters that don't fit just because the cluster table is symmetric

**Prompt module**:
```
[OPERATOR: ⊕ CORRELATE]
1) For each open item, list its symptom signature: error code, endpoint,
   timestamp, customer's CLI/app version, OS, plan tier, browser.
2) Build a 2D table: symptoms × items. Look for clusters where ≥2 items
   share ≥3 symptom dimensions.
3) For each cluster, propose a single root-cause hypothesis. Test the
   hypothesis with one repro that should explain ALL cluster items.
4) Items not in any cluster: classify individually.

Output: <workspace>/clusters-<date>.md with each cluster, its hypothesis,
the verifying repro, and the items it covers.
Required: every multi-item cluster has a single explaining hypothesis.
```

**Tag**: `correlate`. **Composes with**: 🔍 REPRO, 🔭 ANOMALY.

---

### ✓ VERSION-PIN

**Definition**: Map the user's version → exact commit → fixes shipped.

**Triggers**:
- Ticket includes a CLI / app / SDK version
- A bug fix is suspected to be already shipped
- The user upgraded and the bug appeared (regression)

**Failure modes**:
- Quoting a fix that's in `main` but not yet released (the JSM 0.1.5 incident)
- Confusing the deploy date with the commit date — auto-deploy may be off
- Citing a fix that exists in one binary (CLI) but not another (web)

**Prompt module**:
```
[OPERATOR: ✓ VERSION-PIN]
1) Read the version from the ticket. If absent, ask via REQUEST-INFO.
2) Find the corresponding git tag/commit: `git log --oneline --all | grep <version>`.
3) Run `git log --oneline <ticket-version>..HEAD -- <relevant-paths>` to
   see what's been added since.
4) For each relevant fix in that range, verify it's actually deployed:
   - Compare commit timestamp vs Vercel deployment timestamp
   - Check `vercel.json` auto-deploy setting
   - `curl` a `/api/health` or `/api/version` to confirm what production runs
5) Conclude: "user is on X; fix landed in Y; production is at Z; therefore […]."

Output: a version-pinning paragraph for the draft. Cites SHA, version,
deploy timestamp.
Required: never quote a fix without confirming it's actually deployed.
```

**Tag**: `version-pin`. **Composes with**: 🔍 REPRO.

---

### 🔭 ANOMALY

**Definition**: When a ticket pattern-matches a known category but instinct says no, ask "why is this different from the 50 in the same category?"

**Triggers**:
- Auto-classifier confident, but the ticket text contains an unusual phrase
- A regular user reports something out-of-character for them
- The cluster fits but one item has an outlier signature (different region, different plan)

**Failure modes**:
- Forcing an outlier into a cluster → wrong fix → user comes back angry
- Crying anomaly on every ticket → loses signal

**Prompt module**:
```
[OPERATOR: 🔭 ANOMALY]
1) State the category match in one sentence ("This looks like X").
2) List 3 features that DON'T fit the typical X: e.g., "but timestamp is
   2am UTC", "but user is on enterprise plan", "but error mentions module
   we haven't deployed".
3) Ask: would the standard X fix cover those features? If no, hold the
   classification and re-investigate.

Output: either confirmed classification with anomalies explained, OR a
"hold for re-investigation" flag with the three mismatched features listed.
Required: at least 3 dimensions checked; no rubber-stamping.
```

**Tag**: `anomaly`. **Composes with**: ⊕ CORRELATE, 🪞 SECOND-OPINION.

---

## Phase 3 Operators (Draft)

### ⚖ DECIDE

**Definition**: Apply the project's decision matrix; decide between (a) auto-handle, (b) draft for owner approval, (c) surface as judgment call.

**Triggers**:
- A ticket has been investigated; classification is firm
- Routing rules in `03-decision-matrix.md` apply

**Failure modes**:
- Auto-handling something that needs owner judgment (refunds, security, hostile users)
- Surfacing every decision when many are mechanical (slowing the loop)
- Misreading the matrix because the project has multiple variants per category

**Prompt module**:
```
[OPERATOR: ⚖ DECIDE]
1) Look up the ticket's classification in 03-decision-matrix.md.
2) Identify the action column. If [SURFACE], stop here — it goes to owner.
3) If [AUTO-HANDLE]: confirm none of the always-surface conditions apply
   (refund, security, legal threat, hostile user, plan-tier override,
   regulator inquiry, press inquiry).
4) If [DRAFT]: pick the named template from 04-templates/.
5) Note in the draft bundle: chosen template, classification, surface flag.

Output: per-item decision row. Surface items grouped at top of the bundle.
Required: surface conditions checked explicitly, not implicitly.
```

**Tag**: `decide`. **Composes with**: ✉ DRAFT.

---

### ✉ DRAFT

**Definition**: Produce a customer-facing reply that is specific, evidence-grounded, and minimal.

**Triggers**:
- DECIDE chose a [DRAFT] action
- Owner asked for "a draft I can edit"

**Failure modes**:
- Generic reply — no specifics → reads bot-like
- Speculation without "we believe / pending verification" hedging
- Claiming a fix shipped without VERSION-PIN
- Apologizing too much or too little

**Prompt module**:
```
[OPERATOR: ✉ DRAFT]
1) Open the named template from 04-templates/.
2) Replace ALL placeholders with specific values from the ticket and the
   investigation log:
   - User's actual error message (short paste)
   - Exact version they're on
   - Exact fix commit + release version
   - Specific next-step the user should take
3) Strike any sentence not specific to this user.
4) Length target: 60-180 words. Trim mercilessly.
5) Sign with the team or the owner's first name per `08-voice.md`.

Output: a draft block under the ticket id, ready for VOICE-MATCH.
Required: zero un-replaced {{placeholders}}; at least 2 ticket-specific facts cited.
```

**Tag**: `draft`. **Composes with**: 🎙 VOICE-MATCH.

---

### 🎙 VOICE-MATCH

**Definition**: Tune the draft to match `08-voice.md` so it sounds like the team, not like a generic AI.

**Triggers**:
- After DRAFT
- When the owner has flagged tone in past reviews

**Failure modes**:
- Over-applying a voice quirk (every reply starts with "Hey there!")
- Mixing voices — some templates formal, others casual — within the same bundle
- AI-tells: "I'd be happy to help", "Unfortunately", em-dashes everywhere, "delve", "navigate the complexities"

**Prompt module**:
```
[OPERATOR: 🎙 VOICE-MATCH]
1) Read 08-voice.md: register (warm/formal/terse), opener, closer, banned
   phrases, signature.
2) Strike from the draft any phrase in the banned list.
3) Adjust opener and closer to match.
4) Read aloud: does it sound like the 5+ historical reply samples?
   If not, edit until yes.
5) Run the AI-tell remover (see VOICE-CALIBRATION.md):
   - delete "I'd be happy to help"
   - delete "Unfortunately,"
   - replace "delve into" with "look at"
   - replace em-dashes with comma or period where appropriate
   - delete sentences ending in "Let me know if you have any questions!"

Output: the polished draft, replacing the prior version in the bundle.
Required: at least 3 voice patterns from 08-voice.md visible in the result.
```

**Tag**: `voice-match`. **Composes with**: ✉ DRAFT.

---

### 🪄 EMPATHIZE

**Definition**: Use one grounded mirror or label to lower the customer's threat response before giving facts.

**Triggers**:
- Customer has waited through multiple replies or delays and sounds unheard
- Refund, access, data-loss, or outage harm is emotionally loaded
- The reply needs to preserve dignity for a power user, buyer, researcher, or contributor
- The ticket is in stage 3+ of the rage cycle from [CUSTOMER-PSYCHOLOGY.md](CUSTOMER-PSYCHOLOGY.md)

**Failure modes**:
- Using empathy moves on routine tickets, which reads as performative
- Saying "I understand how you feel" without naming the actual situation
- Mirroring an insult/slur or stacking multiple labels in one reply
- Using empathy as a substitute for action

**Prompt module**:
```
[OPERATOR: 🪄 EMPATHIZE]
1) Classify the emotional state: friction, cost, helplessness, or identity threat.
2) Pick ONE move from TACTICAL-EMPATHY.md:
   - Mirror: restate 1 concrete phrase/situation from the customer.
   - Label: name the situation that would make a reasonable person react this way.
3) Immediately pair the move with a concrete action, owner, or ETA.
4) Delete the empathy line if the ticket is routine and the customer only needs the answer.

Output: one revised opener for the draft.
Required: one specific situation named; no generic "I understand"; action follows empathy.
```

**Tag**: `empathize`. **Composes with**: ✉ DRAFT, 🎙 VOICE-MATCH, 🪜 LADDER.

---

### 🪜 LADDER

**Definition**: Move a hostile or identity-threatened conversation down one escalation level before facts, declines, or enforcement.

**Triggers**:
- Hostile-user runbook level L0-L3 and the user still has a solvable issue
- Public complaint says "scam", "ghosted", "nobody is listening", or similar
- Customer demands a manager because prior replies felt dismissive
- Contributor hostility appears tied to PR/issue policy ambiguity rather than immediate danger

**Failure modes**:
- Arguing facts before restoring agency
- Treating threats of violence, doxxing, CSAM, terrorism, regulator letters, or counsel notices as de-escalation cases
- Performing therapy-style language instead of short operational acknowledgement
- Overriding the hostile-user runbook's lock/ban/counsel path

**Prompt module**:
```
[OPERATOR: 🪜 LADDER]
1) Check hard exclusions first:
   physical threat, doxxing, CSAM, terrorism, regulator/legal, press.
   If any fire: use 🛡 ESCALATE, not LADDER.
2) Identify current level: L0 frustrated, L1 insults, L2 pattern, L3 targeted.
3) Use the three-layer reply:
   - accusation audit: name the worst reasonable frame lightly;
   - label: name the specific situation/harm;
   - fact + action: one fact, one next step, one owner/ETA.
4) If behaviour is L2+, include the boundary from runbooks/HOSTILE-USER.md.

Output: de-escalation draft section plus routing level.
Required: hard exclusions checked; boundary/action visible; no debate about tone.
```

**Tag**: `ladder`. **Composes with**: 🛡 ESCALATE, 🪄 EMPATHIZE, ⚖ DECIDE.

---

### 🎁 GOODWILL

**Definition**: Convert harm, fault, customer value, and public-risk signals into a consistent refund/credit/extension/upgrade recommendation for owner approval.

**Triggers**:
- Refund request, duplicate charge, outage harm, data loss, or paid-user blocker
- Owner asks "what should we offer?"
- Public complaint or champion customer needs a relationship-saving remedy
- A runbook points at [COMPENSATION-CALCULUS.md](COMPENSATION-CALCULUS.md)

**Failure modes**:
- Issuing or promising compensation without owner approval
- Over-paying the loudest customer while under-paying quieter customers with the same harm
- Treating a refund owed by law/provider error as "goodwill"
- Using hard-coded dollar bands when the project policy says otherwise

**Prompt module**:
```
[OPERATOR: 🎁 GOODWILL]
1) Collect dials from COMPENSATION-CALCULUS.md:
   Harm H1-H5, Fault F1-F5, Customer value L1-L5, Public/context risk V1-V5.
2) Check 05-policies.md and legal/provider constraints first.
3) Recommend a shape:
   apology only, service extension, credit, plan upgrade, refund, or owner-led remedy.
4) Write "owner approval required" beside every money/access/credit action.
5) Log the dials in the draft bundle and, after action, in 📈 OUTCOME.

Output: compensation recommendation with dials, policy citation, and approval line.
Required: no customer-visible promise and no external side effect before ✓ CONFIRM.
```

**Tag**: `goodwill`. **Composes with**: ⚖ DECIDE, 🪞 SECOND-OPINION, ✓ CONFIRM.

---

### 🧹 DE-SLOPIFY

**Definition**: Run the voice-matched draft through the canonical `/de-slopify` skill (or its inline fallback) to remove AI-tells before owner review. **Mandatory** for every customer-facing artifact, every channel, every pipeline. Full integration contract in [DE-SLOPIFY-INTEGRATION.md](DE-SLOPIFY-INTEGRATION.md).

**Triggers**:
- A voice-matched draft is staged and ready for owner review (every customer-facing artifact)
- Drafts going to: ticket reply, status-page post, in-product banner, outbound email, public DM, OSS issue/PR comment, KB article, postmortem, newsletter, changelog entry
- Translated reply has been produced — run `/de-slopify` on the translated body too (AI-tells appear in every language)

**Failure modes**:
- Skipping for "routine" cases — AI-tells appear in routine drafts most often
- Trusting that the model "wouldn't make AI-tells this time"
- Running once but not re-running after revisions (revisions can re-introduce slop)
- Running on the English source but not on the translated target
- Treating outbound email as internal (catastrophic) or internal Slack as customer-facing (waste)
- Marking `de-slopify-status: skipped` in the audit row — that is a Confirmation-Rule violation

**Prompt module**:
```
[OPERATOR: 🧹 DE-SLOPIFY]
1) Take the voice-matched draft body.
2) If `/de-slopify` skill is installed:
     - Invoke /de-slopify on the draft body
     - Receive cleaned version + flagged-issues list
3) If NOT installed (jsm install failed or skipped):
     - Apply inline fallback: AI-tell list from VOICE-CALIBRATION.md
       plus DE-SLOPIFY-INTEGRATION.md §"When De-Slopify Is Not Yet
       Installed".
     - Strip: "I'd be happy to help", "Unfortunately,", "delve",
       "navigate the complexities of", em-dash decoration,
       "Hope this helps!", "Please don't hesitate to", "As an AI...",
       triple-bulleted-trivia, exclamation inflation.
4) If revisions came back, replace draft body with revised version
   and re-invoke (max 3 iterations).
5) Record `de-slopify-status` in the audit row:
     passed | revised | inline-passed | inline-revised | skipped (NEVER)
6) Hand off to ✓ CONFIRM with the cleaned body.

Output: clean body + audit-row entry.
Required: zero AI-tells in final body; status recorded; never `skipped`.
```

**Tag**: `de-slopify`. **Composes with**: 🎙 VOICE-MATCH (just before), ✓ CONFIRM (just after). **Required**: `de-slopify` skill installed via jsm, OR inline fallback applied with audit-row marker `inline-passed` / `inline-revised`.

---

## Phase 4 Operators (Owner Review)

### ✓ CONFIRM

**Definition**: Show every customer-facing draft to the owner; obtain explicit Y/n on each.

**Triggers**:
- A draft bundle is ready
- Any single high-stakes draft (refund, security, legal)

**Failure modes**:
- Sending without confirm because "they always say yes" → eventually one slips through wrong
- Asking individually instead of as a bundle (slows owner down)
- Treating silence as approval (it isn't)

**Prompt module**:
```
[OPERATOR: ✓ CONFIRM]
1) Build the bundle output (see TRIAGE-WORKFLOW.md Phase 3 format):
   per-item header + draft block + proposed action.
2) Surface owner-judgment items at the TOP, not the bottom.
3) Ask explicitly:
   "Approve all? Edits? Hold any? (Y / 'edit <id>' / 'hold <id>' / 'all hold')"
4) Wait for explicit response. Treat silence as "hold all" — DO NOT send.
5) If the owner edits a draft, re-show the edited version for final ack
   before send.

Output: a list of approved items + a list of held/edited items.
Required: zero items sent without an explicit Y or owner-edit-then-Y.
```

**Tag**: `confirm`. **Composes with**: 📤 SEND.

---

## Phase 5 Operators (Act + Verify)

### 📤 SEND

**Definition**: Execute approved replies via the surface's API; update statuses; record audit notes.

**Triggers**:
- CONFIRM returned approved items

**Failure modes**:
- Sending a reply but forgetting the status update (ticket stays "open")
- Sending the same reply twice (no idempotency check)
- Wrong endpoint (e.g., posting to a closed ticket)

**Prompt module**:
```
[OPERATOR: 📤 SEND]
For each approved item:
1) Confirm idempotency: has this exact draft already been sent? Check
   <project>/.claude/support-triage/.workspace/sent-<date>.log.
2) Use the surface's documented send API:
   - SaaS-custom: POST /api/admin/support/tickets/{id}/messages
   - GitHub: gh issue comment / gh pr comment
   - Zendesk: POST /api/v2/tickets/{id}/comments
   - Intercom: POST /conversations/{id}/reply
   - Plain: GraphQL replyToThread
3) Capture the response (message-id, delivery status). Log to sent-<date>.log.
4) Update ticket status per the project's lifecycle rules.
5) Note in audit: actor=triage-skill, ticket-id, action, draft-hash, approver.

Output: per-item send result row.
Required: zero double-sends; every status update happens; audit row written.
```

**Tag**: `send`. **Composes with**: 🔁 VERIFY.

---

### 🔁 VERIFY

**Definition**: Re-fetch the open list; confirm count + items match expectations; close the loop.

**Triggers**:
- After SEND on the last approved item
- End of session

**Failure modes**:
- Skipping verify → leaving an item half-handled (status updated but reply didn't go)
- Trusting the response of SEND without confirming receipt
- Ending session before bead-filing for confirmed bugs

**Prompt module**:
```
[OPERATOR: 🔁 VERIFY]
1) Re-run scripts/list-open-items.sh.
2) Compare against this session's expected state:
   - Items resolved this session should no longer be in "open"
   - Items acknowledged should show acknowledged + SLA paused
   - New items since session start should be flagged for next session
3) For each confirmed bug from this session: file a bead via `br create`
   (or open a GitHub issue if br absent).
4) Update <workspace>/session-<date>.log with:
   open-at-start: N
   resolved-this-session: M
   replied-this-session: K
   beads-filed: [...]
   next-action-for-owner: <if any>
5) Hand off summary to owner (1-2 sentences).

Output: session log + 1-2 sentence summary.
Required: re-fetch performed; deltas explained.
```

**Tag**: `verify`. **Composes with**: 🐞 BEAD.

---

### 🐞 BEAD

**Definition**: File a tracking issue for any confirmed bug that needs follow-up.

**Triggers**:
- VERIFY confirmed a bug; fix didn't ship in the same session
- Owner asked to "track this for later"
- A failure-mode catalog entry was hit (see [FAILURE-MODES.md](FAILURE-MODES.md))

**Prompt module**:
```
[OPERATOR: 🐞 BEAD]
1) Title: "<symptom> — <component>" (≤80 chars).
2) Body: include reproduction steps, customer ticket id(s), version,
   suspected root cause, suggested fix shape.
3) Priority:
   p0 — site down, data loss, security
   p1 — paid users blocked
   p2 — annoying but workaroundable
   p3 — cosmetic / nice-to-have
4) Label by domain: auth / billing / cli / admin / email / cron / etc.
5) Link to the customer ticket as `Customer-Visible-Id: <id>` so future
   triage can re-correlate.

Output: bead id created; logged in session-<date>.log.
Required: every p0/p1 bead has a customer ticket link.
```

**Tag**: `bead`. **Composes with**: 🔁 VERIFY.

---

## Risk-Tier Operators (Use When Specific Conditions Fire)

### 🛡 ESCALATE

**Definition**: Move out of the public/customer channel into private/legal-appropriate channel.

**Triggers**:
- Security disclosure (CVE-shape report)
- Legal threat (lawsuit / regulator / DMCA)
- Hostile or abusive user beyond first warning
- Press inquiry
- A user says "I'm a journalist" or "I'm working with a regulator"

**Prompt module**:
```
[OPERATOR: 🛡 ESCALATE]
1) STOP drafting a public reply. Do not post to the public channel.
2) Identify the right private channel from 05-policies.md:
   - security: security-team@ or owner directly
   - legal: counsel@ or owner directly
   - press: comms@ or owner directly
   - hostile user: trust-and-safety@ or owner
3) Hand off the verbatim original message + a 3-line summary + your
   recommendation to that channel.
4) Update the public-facing ticket (if one exists) with a neutral
   placeholder ("Thanks — we're in touch privately"); never the substance.
5) Log the escalation in the ticket's internal notes. Pause the SLA.

Output: ticket marked escalated; private channel notified; no public
disclosure of substance.
Required: nothing public until owner unholds.
```

**Tag**: `escalate`. **Composes with**: ✓ CONFIRM (any unhold needs owner Y).

---

### 🚦 PAUSE-SLA

**Definition**: Set status to `awaiting_customer` to legitimately pause the clock; only when we genuinely need their input.

**Triggers**:
- Investigation requires user-side data (logs, version, exact error)
- Refund needs the user's PayPal email or bank confirmation
- We've shipped a fix and need user confirmation it works

**Failure modes**:
- Pausing to game the SLA when we're actually still investigating
- Forgetting we're paused — ticket sits 30 days waiting on us
- Pausing without a clear ask in the reply ("more info please" → user can't comply)

**Prompt module**:
```
[OPERATOR: 🚦 PAUSE-SLA]
1) Confirm: the ONLY way to advance is data from the user.
2) The reply MUST contain a numbered list of EXACT items to send back:
   "1) Run X and paste the output. 2) Send the URL of the failing page.
   3) Tell me what time you saw it (in your timezone)."
3) After SEND, transition status to `awaiting_customer` (not "open").
4) Set a 7-day timer. If no response, send a single follow-up. After
   14 days no response, close with a "we'll happily reopen if you
   send the info above" note.

Output: status transitioned correctly; user has clear actionable list.
Required: every paused ticket has a numbered ask.
```

**Tag**: `pause-sla`. **Composes with**: ✉ DRAFT.

---

### 🌐 TRANSLATE

**Definition**: Route non-English replies through translation; show the original alongside.

**Triggers**:
- The customer's message is not in your team's language
- A team member is replying to a French/German/Japanese/etc. user

**Prompt module**:
```
[OPERATOR: 🌐 TRANSLATE]
1) Detect language: use `franc` (Node) or any small classifier; confirm
   non-English.
2) Translate to English for triage; keep the original at the top of the
   investigation note.
3) DRAFT in English.
4) Before SEND: translate the draft to the customer's language. Keep BOTH:
   "[en] ... \n\n [original-language] ..." OR send only translated +
   include "Original message in English available on request."
5) If the team has no native speaker for QA, label the reply
   "machine-translated; if anything is unclear, please reply with corrections."

Output: bilingual draft.
Required: no machine translation sent without the disclaimer.
```

**Tag**: `translate`. **Composes with**: ✉ DRAFT.

---

### 🪞 SECOND-OPINION

**Definition**: Run hard cases through `/multi-model-triangulation` (Codex + Gemini + Grok) before drafting; or, if that skill isn't installed, do a structured deep-think.

**Triggers**:
- Refund > $X (project-defined threshold; default $200)
- Security-flavored
- Legal threat or regulator inquiry
- A pattern that seems suspicious but isn't yet identified
- An owner has flagged a recurring class of mistake to triple-check

**Prompt module (with `/multi-model-triangulation`)**:
```
[OPERATOR: 🪞 SECOND-OPINION]
1) Package the case: ticket id, user message, your investigation log,
   your draft conclusion, and the proposed action.
2) Invoke /multi-model-triangulation:
   triangulate "<case-package>" --models codex,gemini,grok --question \
     "Should we [proposed action]? What am I missing?"
3) Read all 3 responses. For each, note:
   - Does it agree with the proposed action?
   - Does it surface a risk I missed?
   - Does it propose a different action?
4) If 2+ models flag the same risk → reconsider. If they all agree → high
   confidence; proceed.

Output: triangulation report committed to <workspace>/triangulation-<id>.md.
Required: at least 3 distinct models considered.
```

**Prompt module (fallback, no multi-model-triangulation skill)**:
```
[OPERATOR: 🪞 SECOND-OPINION — fallback]
Self-question pass:
1) "What's the most uncharitable interpretation of this ticket?"
2) "What would a hostile reviewer say about my proposed action?"
3) "What 3 facts could change my mind, and have I checked them?"
4) "What's the worst-case outcome if I'm wrong?"
5) Re-read the ticket as if you've never seen it.
Make at least 2 changes to the draft before sending.

Output: revised draft + 5-line reasoning log.
Required: at least 2 substantive changes from the first draft.
```

**Tag**: `second-opinion`. **Composes with**: ⚖ DECIDE, ✉ DRAFT.

---

## Demand, Broadcast, and Capacity Operators

### 📚 KB-SUGGEST

**Definition**: Decide whether a ticket should produce a KB/docs/in-app-help improvement instead of recurring forever.

**Triggers**:
- Three or more users ask the same question in a short window
- A ticket's root cause is "the user could not find/understand the answer"
- An inline error message or empty state caused the ticket
- [DEFLECTION-AND-SELF-SERVICE.md](DEFLECTION-AND-SELF-SERVICE.md) says the surface, not the reply, should change

**Failure modes**:
- Deflecting high-risk categories that must stay human-routed
- Writing a generic FAQ article instead of fixing the product/error message
- Creating docs without a searchable title in the customer's words

**Prompt module**:
```
[OPERATOR: 📚 KB-SUGGEST]
1) Check exclusion list: refund, security, account access, data loss,
   legal/privacy, hostile, cancellation. If excluded, no deflection.
2) Identify the best surface: inline error, in-app help, status page, KB/docs.
3) Write the customer-question title and the first 50-word answer.
4) Capture evidence: ticket ids, theme tag, search terms, failed current docs.
5) Add proposal to 📈 OUTCOME; do not silently publish docs as policy.

Output: KB/docs/product-help proposal with evidence and destination.
Required: high-risk exclusions checked; surface chosen; title uses customer language.
```

**Tag**: `kb-suggest`. **Composes with**: 🏷 TAG-CONSISTENCY, 📈 OUTCOME.

---

### 🪧 BROADCAST

**Definition**: Replace many near-duplicate incident replies with one coordinated status-page/product-banner/customer-update thread.

**Triggers**:
- 3+ reports share a fingerprint within 60 minutes
- Status page, synthetic monitor, deploy, or provider outage confirms a mass event
- Individual replies would contradict or lag behind the incident truth

**Failure modes**:
- Broadcasting before correlation proves a shared root
- Status page and in-product banner disagreeing
- Continuing per-ticket bespoke replies during a mass incident
- Publicly over-sharing private customer/account details

**Prompt module**:
```
[OPERATOR: 🪧 BROADCAST]
1) Confirm shared incident fingerprint via ⊕ CORRELATE.
2) Pick the source of public truth: status page, in-product banner, GitHub issue,
   or owner-approved public thread.
3) Draft one update: what is affected, current state, next update time, contact path.
4) Link individual tickets to the broadcast; do not invent bespoke facts per ticket.
5) After resolution, verify the public truth surface and then send loopback/follow-up.

Output: broadcast draft + affected-item list + next-update timer.
Required: owner approval for publish; one source of truth; cadence stated.
```

**Tag**: `broadcast`. **Composes with**: ⊕ CORRELATE, 🛡 ESCALATE, ✓ CONFIRM, 🔁 LOOPBACK.

---

### 🩹 PROACTIVE

**Definition**: Reach out to affected or at-risk customers before they file, when logs/themes prove a concrete friction or harm.

**Triggers**:
- Incident blast radius identifies affected customers who did not write in
- VoC theme cluster reveals a silent cohort
- Product analytics show activation failure, churn risk, integration breakage, or plan-limit surprise
- [PROACTIVE-SUPPORT.md](PROACTIVE-SUPPORT.md) lists a matching cohort

**Failure modes**:
- Turning support outreach into a marketing campaign
- Asking the customer to verify work the team should verify
- Reaching out without a fix, workaround, or concrete help offer
- Sending too many proactive touches to one customer

**Prompt module**:
```
[OPERATOR: 🩹 PROACTIVE]
1) Define the cohort and evidence: log query, theme tag, analytics rule, or ticket ids.
2) Answer the ethics check: why this cohort, why now, what help, unsubscribe path.
3) Choose channel: named email, in-app, status page, phone, or DM.
4) Draft with specific account impact and the verified fix/help offer.
5) Route through ✓ CONFIRM before any customer-visible send.

Output: cohort list, outreach draft, channel, and measurement plan.
Required: concrete help offer; no broad marketing list; owner approval before send.
```

**Tag**: `proactive`. **Composes with**: 🏷 TAG-CONSISTENCY, ✓ CONFIRM, 📈 OUTCOME.

---

### 📐 EISENHOWER

**Definition**: Allocate triage effort by urgency and consequence, not by queue order alone.

**Triggers**:
- Queue is large enough that not everything can get bespoke attention
- Ticket has long-tail signals from [PARETO-AND-LONG-TAIL.md](PARETO-AND-LONG-TAIL.md)
- Owner asks "what should we work on first?"
- A routine-looking ticket may carry high renewal, press, legal, or trust risk

**Failure modes**:
- Treating consequential tail tickets like head-volume tickets
- Letting one loud low-consequence ticket consume owner attention
- Spending all capacity on urgent queue work and none on compounding fixes

**Prompt module**:
```
[OPERATOR: 📐 EISENHOWER]
1) Place each item in urgency x consequence:
   urgent/head, urgent/tail, nonurgent/noise, nonurgent/compound.
2) Promote any item with security, data loss, legal, press, enterprise renewal,
   public-trust, or repeated ignored-feeling signal.
3) Assign strategy: template/deflect, owner-led deep work, batch, or scheduled compounding.
4) State the time budget and owner involvement for each quadrant.

Output: triage allocation table for the session.
Required: high-consequence items visible at top; compounding work not erased.
```

**Tag**: `eisenhower`. **Composes with**: ★ ORIENT, ⚖ DECIDE, 🎁 GOODWILL.

---

### 🔮 PREDICT

**Definition**: Forecast near-term support demand and capacity risk before the queue exceeds SLA buffers.

**Triggers**:
- Launch, pricing change, migration, outage recovery, marketing push, or seasonal event is coming
- Queue depth is growing over days
- SLA breaches approach the project's error budget
- Volume unexpectedly drops to zero on a normally active project

**Failure modes**:
- Forecasting from memory instead of last 90 days / actual channel counts
- Treating 100% support utilization as sustainable
- Ignoring channel failure when volume suddenly goes quiet
- Skipping pre-staged templates/content before a high-friction launch

**Prompt module**:
```
[OPERATOR: 🔮 PREDICT]
1) Gather last 90 days daily tickets by channel, active-user trend, spike events,
   SLA breach rate, and known upcoming events.
2) Compute a simple forecast: rolling median + weekday adjustment + known-event bump.
3) Compare forecast to capacity with 15-25% slack.
4) If utilization >85% or spike >0.5x weekly capacity, pre-stage templates,
   broadcast/status content, and extra coverage.
5) If volume is unexpectedly zero, verify intake plumbing.

Output: forecast, capacity comparison, and pre-staged support plan.
Required: actual counts cited; capacity action chosen; intake-zero checked when relevant.
```

**Tag**: `predict`. **Composes with**: 📐 EISENHOWER, 🪧 BROADCAST, 🩹 PROACTIVE.

---

## 🧪 FIRE-DRILL — Rehearse The Workflow Before Trusting It

**Definition**: Run a synthetic adapter-contract fixture through the real triage
workflow to prove routing, grounding, and no-send safety.

**Triggers**:
- New project onboarding is almost complete
- A new high-risk runbook was added or changed
- `scripts/list-open.sh` was added for a new provider
- A prior live session exposed a routing or confirmation-gate failure
- The owner wants scheduled/autonomous triage later

**Failure modes**:
- The drill uses a toy fixture and misses real-world messiness
- The draft text looks good but the confirmation gate is absent
- The fixture validates but does not exercise the intended runbook
- The drill asserts exact wording instead of structure and safety

**Prompt module**:
```
[OPERATOR: 🧪 FIRE-DRILL]
1) Select a fixture from FIRE-DRILL-HARNESS.md.
2) Validate it:
   python3 <skill>/scripts/validate-adapter-output.py <fixture.json>
3) Run no-send triage:
   SUPPORT_TRIAGE_FIXTURE=<fixture.json> <skill>/scripts/triage-cycle.sh <project>
4) Inspect the draft bundle:
   - pipeline selected
   - runbook named
   - evidence cited
   - owner confirmation required before send
   - TBD-OWNER used instead of guessed policy
5) Write drill result into the session/outcome record.

Output: fire-drill result with pass/fail per structural assertion.
Required: zero customer-visible sends; adapter validator passed.
```

**Tag**: `fire-drill`. **Composes with**: ★ ORIENT, ⚖ DECIDE, ✓ CONFIRM.

---

## 📈 OUTCOME — Convert Support Work Into Durable Learning

**Definition**: Write the Phase 6 record that captures what happened, what
worked, what failed, and what should improve next.

**Triggers**:
- End of every live triage session
- End of every fire drill
- Owner rejected or heavily edited a draft
- A missing policy, template, adapter field, or runbook slowed the session
- A support ticket became an engineering/product issue

**Failure modes**:
- Session ends after sends with no learning artifact
- Outcome record silently rewrites policy without owner approval
- Only ticket counts are recorded, not friction or missed evidence
- Product bugs are described but not filed as beads/issues

**Prompt module**:
```
[OPERATOR: 📈 OUTCOME]
1) Re-fetch the open queue and verify the final state.
2) Write <project>/.claude/support-triage/outcomes/YYYY-MM-DD-<slug>.md.
3) Include:
   - open/closed/replied counts
   - owner-approved sends
   - code fixes and beads/issues
   - rejected or rewritten drafts
   - KB/template/runbook gaps
   - adapter or provider friction
4) Turn unresolved gaps into proposals, not silent policy changes.

Output: outcome record path + one-paragraph owner handoff.
Required: follow-up bugs filed; no customer-visible send without owner approval.
```

**Tag**: `outcome`. **Composes with**: 🔁 VERIFY, 🐞 BEAD, 🧬 EVOLVE.

---

## Product Intelligence Operators

### 🏷 TAG-CONSISTENCY

**Definition**: Apply a controlled, owner-approved vocabulary to themes, personas, and outcomes before closing a session.

**Triggers**:
- The project uses VoC mining or monthly product/support synthesis
- A ticket closes with a product/docs/UX signal
- A new theme name is tempting but a similar one already exists
- The support map has `vocabularies/themes.md`

**Failure modes**:
- Synonym drift (`billing.duplicate-charge` vs `payments.double-bill`)
- Adding one-off tags for every ticket
- Letting LLM categories become the vocabulary without owner review
- Losing the customer persona/register signal that explains why the same bug hurt different users differently

**Prompt module**:
```
[OPERATOR: 🏷 TAG-CONSISTENCY]
1) Open vocabularies/themes.md if present; otherwise propose tags in OUTCOME only.
2) Select 1-3 existing theme tags per resolved item.
3) Add optional persona/register tag from 08-voice.md:
   engineer, manager, solo, enterprise, hobbyist, researcher, unknown.
4) If no existing tag fits, write "tag proposal:" in the outcome record;
   do not silently create policy vocabulary.

Output: item -> theme tags/persona tags table.
Required: existing vocabulary preferred; new tags are proposals until owner-approved.
```

**Tag**: `tag-consistency`. **Composes with**: 📈 OUTCOME, 🧬 EVOLVE.

---

### 💎 KEEPER

**Definition**: Preserve unusually useful praise, objections, or verbatims as evidence for product, marketing, docs, or roadmap work, with consent where needed.

**Triggers**:
- Promoter NPS/verbatim, public praise, detailed cancellation reason, or crisp feature objection
- A customer describes the product's value better than the team does
- A support reply produces unusually clear "yes, that solved it" evidence

**Failure modes**:
- Quoting private ticket text publicly without consent
- Paraphrasing away the phrase that made the verbatim valuable
- Saving praise but ignoring detractor evidence
- Mixing marketing usage with product-research usage without labeling the destination

**Prompt module**:
```
[OPERATOR: 💎 KEEPER]
1) Classify the verbatim destination:
   product hypothesis, docs wording, sales objection, testimonial, case study.
2) Preserve the exact quote in the outcome record, redacted as needed.
3) If public/marketing use is possible, mark consent_required=true.
4) If no consent exists, keep it internal-only.

Output: keeper entry with destination, quote, source id, consent status.
Required: no public reuse without explicit consent.
```

**Tag**: `keeper`. **Composes with**: 📈 OUTCOME, 🧬 EVOLVE.

---

### 🔁 LOOPBACK

**Definition**: Notify the people who reported a theme when the fix, doc, or product improvement finally ships.

**Triggers**:
- A bug, KB gap, UX fix, or requested feature ships after being reported by customers
- A VoC synthesis names customers/tickets under a resolved theme
- A public issue/PR/discussion was closed by a later release

**Failure modes**:
- Broadcasting vague marketing updates instead of specific "you reported X; Y shipped"
- Sending loopback without verifying the fix or doc is live
- Reopening old wounds for customers who churned because the message is defensive
- Forgetting OSS contributors whose reports helped shape the fix

**Prompt module**:
```
[OPERATOR: 🔁 LOOPBACK]
1) Gather the affected reporter list from outcomes/theme tags/issues.
2) Verify the shipped artifact is live: release tag, deploy SHA, docs URL, or changelog.
3) Draft a short note:
   "You reported <specific thing>. We shipped <specific fix>. Here's how to use/verify it."
4) Route through ✓ CONFIRM before sending.
5) Mark loopback_sent_at and artifact link in the outcome/theme record.

Output: loopback draft bundle and final sent/held state.
Required: shipped artifact verified; customer-facing send approved.
```

**Tag**: `loopback`. **Composes with**: 🔁 VERIFY, ✓ CONFIRM, 📈 OUTCOME.

---

## 🧬 EVOLVE — Promote Repeated Evidence Into Better Operators

**Definition**: Turn repeated, evidence-backed support friction into a bounded
proposal for docs, templates, runbooks, adapters, or operators.

**Triggers**:
- Same outcome-record friction appears in 3+ sessions
- One high-risk fire drill fails
- Same owner edit recurs across drafts
- Same `TBD-OWNER` question blocks multiple sessions
- Same adapter validation gap appears across providers

**Failure modes**:
- One anecdote becomes universal doctrine
- New operator duplicates an existing one under a different name
- Provider-specific workaround becomes a generic rule
- Proposal lacks a fire-drill fixture or evidence anchor

**Prompt module**:
```
[OPERATOR: 🧬 EVOLVE]
1) Gather evidence anchors: outcomes, owner edits, fire-drill failures,
   ticket ids, code paths, or provider docs.
2) Decide the smallest useful change:
   - project policy
   - template
   - runbook
   - adapter field
   - operator proposal
3) Write an Operator Proposal Card if changing this library.
4) Rehearse with FIRE-DRILL before trusting the new path.
5) Ask owner approval before making policy changes.

Output: bounded improvement proposal with evidence and validation plan.
Required: no removal of existing useful content without explicit owner approval.
```

**Tag**: `evolve`. **Composes with**: 📈 OUTCOME, 🧪 FIRE-DRILL.

---

## Extended Operators (Cognitive & Strategic Layer)

The operators below were added after the original library. They cover the *psychology / strategy / governance* dimensions that the original operators assumed but did not name. Use them on top of the base operators, never instead of.

---

### 🪄 EMPATHIZE — Name The Situation Before Naming The Fix

**Definition**: Apply a Mirror or Label move from [TACTICAL-EMPATHY.md](TACTICAL-EMPATHY.md) so the customer feels heard before any technical content lands.

**Triggers**:
- Rage-cycle stage 2+ detected (see [CUSTOMER-PSYCHOLOGY.md](CUSTOMER-PSYCHOLOGY.md))
- Customer's tone is loaded, ambiguous, or escalating
- Repeat ticket in same thread (third reply or later)
- Hostile / sarcastic / "I want to speak to your manager" framing
- Reply will deliver bad news (decline, can't repro, partial fix)

**Failure modes**:
- Performative empathy ("I understand how frustrating this must be") — generic, ungrounded; use the situation, not the emotion-word
- Stacking labels ("It seems like... it sounds like...") — therapy-bot
- Empathy applied to a routine bug — over-applied, reads as condescending

**Prompt module**:
```
[OPERATOR: 🪄 EMPATHIZE]
1) Read the customer's last message in full. Identify ONE of:
   - Their loudest specific complaint
   - The hardest thing they had to do
   - The worst thing they're afraid is true
2) Pick a move from TACTICAL-EMPATHY.md:
   - Mirror their last clause if their words are vivid
   - Label the situation if you can name it
3) Format: 1 short opener line that names the situation +
   the rest of the reply (substance).
4) Hard rule: do NOT include the emotion-word ("frustrated",
   "annoyed", "upset"). Name the situation, not the feeling.
5) If the ticket is rage-cycle stage 1 (mild friction), SKIP this operator.

Output: a 1-2 line opener that delivers the customer feels heard.
Required: zero emotion-words; zero AI tells; under 40 words.
```

**Tag**: `empathize`. **Composes with**: ✉ DRAFT, 🪜 LADDER.

---

### 🪜 LADDER — De-escalation In Steps, Not Leaps

**Definition**: For an escalating customer, apply the Accusation Audit + Label moves to *step* the conversation back down before substance lands.

**Triggers**:
- Customer has explicitly threatened: lawyer, regulator, press, public posting
- Tone has worsened across consecutive replies
- Hostile-user runbook L1-L3 (HOSTILE-USER.md scale)
- Public posting visible alongside the inbound ticket
- Customer's reply contains a personal accusation of bad faith

**Failure modes**:
- Mirroring tone (matching anger with anger; or matching politeness when politeness is being weaponized)
- Capitulation dressed as de-escalation (giving in for peace; trains the behaviour)
- Skipping the audit and going to facts (customer reads facts as defensiveness)
- One-shot ladder (problem dropped after one rung)

**Prompt module**:
```
[OPERATOR: 🪜 LADDER]
1) Inventory the customer's worst-case frame ("they're stalling
   me on purpose"; "they think I'm stupid"; "they're a scam").
2) Open the reply with an Accusation Audit (TACTICAL-EMPATHY.md §3):
   name the worst frame in their voice; concede the appearance;
   pivot to facts.
3) Use a Label (TACTICAL-EMPATHY.md §2) on the underlying situation.
4) Deliver one fact + one named action + one ETA.
5) If hostility is L3+ (per HOSTILE-USER.md), 🛡 ESCALATE first;
   ladder applies AFTER the case is escalated and counsel-cleared.

Output: a structured reply: [audit] + [label] + [fact + action + ETA].
Required: tone is calm-formal; no mirroring of customer's heat;
zero defensive justifications; never argue about WHO is right.
```

**Tag**: `ladder`. **Composes with**: 🪄 EMPATHIZE, 🛡 ESCALATE, ✉ DRAFT.

---

### 🎁 GOODWILL — Compensation By Calculus, Not By Volume

**Definition**: Apply the four-dial frame from [COMPENSATION-CALCULUS.md](COMPENSATION-CALCULUS.md) to convert "should we comp something?" into a structured decision with a defensible band.

**Triggers**:
- Refund / credit / extension is being considered
- Customer named harm and is implicitly or explicitly asking for redress
- Outage that breached SLA
- Heavy-apology case (data loss, billing error, multiple-failed-replies)
- The agent is tempted to "throw in" something to make the ticket go away

**Failure modes**:
- Anchoring on the customer's specific dollar number (corrupts later cases)
- Over-paying for loud customers and under-paying for silent valuable ones (the bias COMPENSATION-CALCULUS exists to prevent)
- Cash refund when a credit / extension would land equally well at lower cost
- Compensation without a paired specific apology — money without acknowledgement reads as hush

**Prompt module**:
```
[OPERATOR: 🎁 GOODWILL]
1) Score the four dials (Harm 1-5, Fault 1-5, LTV 1-5, Virality 1-5).
2) Sum and read the band (4-7 / 8-11 / 12-15 / 16-18 / 19-20).
3) Apply the "avoidable-incident" multiplier if POST-INCIDENT-RETRO
   shows known-cause / prior-similar / ignored-alert.
4) Pick the currency from the ranking (service extension > plan
   upgrade > credit > refund > goods).
5) Produce the proposed comp + the matching specific-apology paragraph.
6) Surface to ✓ CONFIRM with the dials shown so the owner sees
   the reasoning, not just the offer.

Output: a comp proposal with: dials, band, currency, amount, rationale,
plus the specific apology language.
Required: comp + apology travel together; dials are visible to the
owner; no menu-of-options offered to customer.
```

**Tag**: `goodwill`. **Composes with**: ⚖ DECIDE, ✉ DRAFT.

---

### 🪧 BROADCAST — One Public Update Beats N Private Replies

**Definition**: When ≥3 customers are affected by the same root cause, replace per-ticket replies with a single coordinated public broadcast (status page + in-product banner + email cohort), then individually link.

**Triggers**:
- 3+ tickets with the same fingerprint within a sliding 1-hour window
- Active outage (Pipeline E)
- Mass-event recovery
- A bug-with-public-impact-thread is forming (HN / X / Reddit)
- Pattern-driven proactive outreach to a cohort (per [PROACTIVE-SUPPORT.md](PROACTIVE-SUPPORT.md))

**Failure modes**:
- Triaging individually during an outage (per-ticket cost is ~10x; signal scattered)
- Status page silent while N customer replies say different things → contradiction
- Broadcast too vague ("we're investigating") with no time-bounded follow-up
- Broadcast posted, individual ticket replies forgotten (customer reads broadcast but their personal ticket has zero acknowledgement)

**Prompt module**:
```
[OPERATOR: 🪧 BROADCAST]
1) Confirm the cohort: list every customer ticket / public mention
   sharing the fingerprint.
2) Draft the one canonical message (per CRISIS-COMMS.md cadence
   T+15/T+30/T+60/T+240/T+24h).
3) Stage on the right surface(s):
   - Status page (always)
   - In-product banner (if logged-in users affected)
   - Email cohort (if known-affected list)
   - X / public reply (if public posting visible)
4) Publish per AI-AUTO-RESPONSE-GOVERNANCE.md (T1/T2/T4).
5) Reply to each individual ticket with: short personal acknowledgement
   + link to the broadcast + the ticket-specific impact.
6) Maintain cadence: every promised update goes out on time.

Output: a broadcast plan listing surfaces, message, cadence, cohort.
Required: every individual ticket linked back; cadence honored;
no contradictions across surfaces.
```

**Tag**: `broadcast`. **Composes with**: 🩹 PROACTIVE, 🛡 ESCALATE, 🐞 BEAD, 🔁 VERIFY.

---

### 🩹 PROACTIVE — Reach The Silent Cohort

**Definition**: Identify customers who were affected but didn't file a ticket; reach out before they decide your product is "kind of unreliable."

**Triggers**:
- A bug fix shipped that affected a definable cohort
- VoC theme detection identifies a cohort experiencing same friction
- Behavioral signal (per [PROACTIVE-SUPPORT.md](PROACTIVE-SUPPORT.md)) predicts churn
- Outage post-recovery: known-affected users beyond those who reported
- Quarterly silent-cohort sweep

**Failure modes**:
- Vague "transparency" emails with no specific harm named
- Marketing-flavoured framing ("our ongoing commitment to...")
- Outreach without a real fix or help offer ("FYI") — reads as fishing
- Missing the unsubscribe path
- Reaching out to customers in active billing dispute (compounds friction)

**Prompt module**:
```
[OPERATOR: 🩹 PROACTIVE]
1) Define the cohort with a precise rule (e.g., "users in plan X
   who triggered endpoint Y between [date] and [date]").
2) Verify the cohort: count, sample 5 records, confirm the rule
   identifies the right people.
3) Choose the channel from PROACTIVE-SUPPORT.md table.
4) Draft the message with: specific event, specific customer
   record, fix, optional compensation, direct contact path.
5) ✓ CONFIRM with owner BEFORE send (T2/T3 per
   AI-AUTO-RESPONSE-GOVERNANCE.md).
6) Send batched-from-named-sender; do NOT send from a generic
   noreply@.
7) Track reach rate + reverse-CSAT (per PROACTIVE-SUPPORT.md).

Output: cohort definition + per-customer message variants + send plan.
Required: every message specific to the customer; no generic blast;
named sender; valid unsubscribe path.
```

**Tag**: `proactive`. **Composes with**: 🪧 BROADCAST, 🎁 GOODWILL, 🔁 LOOPBACK.

---

### 🔬 5-WHY — Root-Cause Iteration For Recurring Themes

**Definition**: When a theme has appeared 3+ times in 30 days, walk it through five whys to find the structural cause, not the proximate one.

**Triggers**:
- Same theme tag appears 3+ times in 30d (per VoC mining)
- Same incident root cause recurs after a "fix" was shipped
- Customer reports a regression on a previously-resolved issue
- A bug fix is shipping that addresses the symptom; check whether it addresses the cause
- Postmortem investigation

**Failure modes**:
- Stopping at "human error" — that's never the root cause; ask why the system allowed the human error
- Stopping at "our code had a bug" — ask why our test suite didn't catch it
- Loop runs 5 layers but conclusion is ungrounded (each "why" must be defensible)
- The fix proposed addresses layer 5 but layer 1 still ships — ineffective

**Prompt module**:
```
[OPERATOR: 🔬 5-WHY]
1) State the symptom in one sentence.
2) Ask "why" five times, each time grounding the answer in
   a specific code path / config / process / human decision.
3) Layer 5 should typically be a structural answer
   (org / process / architecture / incentives), not a
   point-fix.
4) For each layer, propose a fix.
5) Compare: which fix lowest in the stack actually prevents
   the recurrence?

Example:
  Symptom:  Customer's webhook fired twice for one event.
  Why 1:    Idempotency guard didn't catch the retry.
  Why 2:    Guard keyed on event_id, but Stripe sends a new event_id on retry.
  Why 3:    We'd seen this with PayPal but didn't generalise the test.
  Why 4:    Per-provider integration tests, no cross-provider abstraction.
  Why 5:    No "duplicate-prevention" interface; each provider hand-rolled.
  Layer-5 fix: extract DuplicatePrevention trait; make all providers implement
              it with a shared test suite.

Output: a 5-why chain + a recommended fix at the lowest defensible layer.
Required: every "why" cites evidence (commit / config / docs / interview);
proposed fix must address the bottom layer chosen.
```

**Tag**: `5-why`. **Composes with**: ⊕ CORRELATE, 🐞 BEAD, 🧬 EVOLVE.

---

### 📐 EISENHOWER — Quadrant Allocation For The Queue

**Definition**: Place each open ticket on the urgency × consequence matrix from [PARETO-AND-LONG-TAIL.md](PARETO-AND-LONG-TAIL.md); apply the right strategy per quadrant.

**Triggers**:
- Triage session start (after ★ ORIENT, before ⚖ DECIDE)
- Queue depth growing
- Mix-tier session (free + paid + enterprise in same queue)
- Owner asks "what should I look at first?"

**Failure modes**:
- Treating all tickets as urgent (capacity collapse; routine queue starves)
- Treating consequential tickets as routine (long-tail damage)
- Skipping the not-urgent / high-consequence quadrant (compounding work crowded out)
- Mis-classifying virality risk (under-treating a customer with public reach)

**Prompt module**:
```
[OPERATOR: 📐 EISENHOWER]
For each ticket from ★ ORIENT:
1) URGENCY: is the SLA clock burning? (yes if at_risk / breached;
   yes if customer is mid-call / mid-launch / mid-deadline)
2) CONSEQUENCE: any of the long-tail signals from
   PARETO-AND-LONG-TAIL.md §"Tail signals"?
3) Place in quadrant:
   - Urgent + low consequence:  HEAD strategy (template + batch)
   - Urgent + high consequence: TAIL strategy (drop other work)
   - Not urgent + low consequence: NOISE (deflect / batch / KB-suggest)
   - Not urgent + high consequence: COMPOUND (schedule for weekly compounding)
4) Write the per-ticket allocation row to the session log.

Output: a quadrant-grouped open-items list.
Required: every ticket placed; tail items surfaced at top of bundle;
compound-quadrant items reserved for the weekly 10% time budget.
```

**Tag**: `eisenhower`. **Composes with**: ★ ORIENT, ⚖ DECIDE.

---

### 🩻 X-RAY — See The Underlying Need, Not The Stated Complaint

**Definition**: For ambiguous or oddly-shaped tickets, look beyond what the customer literally asked for to what would actually solve their problem.

**Triggers**:
- Customer asks for X but X is unusual / misaligned / off-roadmap
- The fix "as requested" would create new problems
- Repeated tickets where each individual ask makes sense but the cluster doesn't
- Feature request with "I'll do it myself" workaround that suggests the real need is elsewhere
- Refund request paired with "I'd actually prefer if [Y] worked"

**Failure modes**:
- Building/responding to the wrong abstraction (give them a faster horse instead of a car)
- Telling the customer "what you really want is..." when they actually do want what they asked for
- X-ray-as-condescension (treating the customer as not knowing their own job)
- Skipping the calibrated question and inferring the underlying need

**Prompt module**:
```
[OPERATOR: 🩻 X-RAY]
1) Restate the literal ask in one sentence.
2) Ask: what is the customer trying to ACCOMPLISH (the job)?
   Not "what did they ask for" but "why did they ask for it"?
3) Generate 3 alternative interpretations of the underlying need.
4) If any alternative is plausible, ask the customer a calibrated
   question (TACTICAL-EMPATHY.md §4) to confirm before responding.
5) Once confirmed, address the underlying need; reference the
   literal ask so the customer sees you read what they wrote.

Output: an underlying-need hypothesis + a calibrated question OR
a confirmed reply addressing the right problem.
Required: never override customer's stated ask without confirmation;
the calibrated question is open-ended ("what / how", not "why").
```

**Tag**: `x-ray`. **Composes with**: 🪞 SECOND-OPINION, 🚦 PAUSE-SLA.

---

### 🔁 LOOPBACK — Close The Loop When The Fix Ships

**Definition**: When a bug, feature, or theme that customers reported gets resolved, notify the customers who reported. The single highest-leverage trust deposit available.

**Triggers**:
- A bead / GitHub issue closed that has Customer-Visible-Id references
- A theme drops below threshold post-fix (per [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md))
- A roadmap item ships that was driven by support tickets
- A KB article was authored in response to specific tickets and the underlying issue is now fixed
- Quarterly — sweep stale tickets and close the loop on any whose root cause has shipped

**Failure modes**:
- The fix ships; customers never hear (most common; the loop never closes)
- Mass email reading like marketing ("introducing webhooks!") without the personal "you asked about this on [date]"
- Notifying without testing the fix actually works for the customer's specific case
- Notifying once, no follow-up if the customer hits a related issue

**Prompt module**:
```
[OPERATOR: 🔁 LOOPBACK]
1) For each closed bead / theme / issue:
   - Pull the list of customer tickets referencing it
     (Customer-Visible-Id field per 🐞 BEAD)
2) For each customer:
   - Verify the fix works for THEIR specific case (re-run their
     repro against production)
   - Draft a short, personal note: "you mentioned this on [date];
     it's fixed; here's how to use it / verify it"
   - Include one specific detail that proves you remembered them
3) ✓ CONFIRM (T2; this is customer-touch).
4) Send batched from named sender.
5) Log responses; promote enthusiastic ones to 💎 KEEPER candidates.

Output: per-customer loopback list with tested-for-them confirmation.
Required: every notification cites the customer's original report;
the fix has been verified for their case; named sender, not noreply@.
```

**Tag**: `loopback`. **Composes with**: 🐞 BEAD, 💎 KEEPER, 📈 OUTCOME.

---

### 💎 KEEPER — Save The Excellent Customer Comments

**Definition**: When a customer's reply, NPS verbatim, or public mention is genuinely excellent, capture it (with consent) for case-study / social-proof / onboarding-copy use.

**Triggers**:
- NPS verbatim is unusually specific and positive
- Customer reply contains a quotable line about value delivered
- Public mention (X, HN, blog) is favourable and detailed
- A long-running customer relationship reaches a milestone (renewal, expansion, public reference)
- Promoter-class verbatim (NPS 9-10)

**Failure modes**:
- Quoting without consent (legal + ethical fail)
- Paraphrasing (dilutes; the customer's exact words are the value)
- Auto-publishing to marketing without owner approval
- Cherry-picking out of context (later embarrassment if customer's relationship sours)

**Prompt module**:
```
[OPERATOR: 💎 KEEPER]
1) Identify the keeper-candidate quote (verbatim, in the customer's
   words).
2) Tag the source: ticket id, NPS wave, public URL.
3) Get explicit consent before any publication:
   "Hey — that line you wrote about [thing] really resonates. Mind
    if we share it (with your name / anonymously / with attribution
    to [role])?"
4) Store the approved quote in the keeper bank with consent record.
5) Periodically pass to marketing / onboarding / case-study team.

Output: a consented quote + provenance + use-permissions.
Required: never publish without recorded consent; verbatim quote;
clear opt-out for any future use.
```

**Tag**: `keeper`. **Composes with**: 📈 OUTCOME, 🔁 LOOPBACK.

---

### 🧮 COSTABLE — What Does Getting This Wrong Cost?

**Definition**: Before high-stakes replies, estimate the cost of getting it wrong. The cost frames the right level of investigation effort.

**Triggers**:
- Refund decision over the project's threshold
- Decline of a paying customer's reasonable request
- Public reply on X / HN / public ticket
- Reply to enterprise account
- Reply to known voice (>5k followers) or press-adjacent
- Any reply that, if wrong, would be hard to walk back

**Failure modes**:
- Skipping the cost estimate; treating a high-cost reply with a low-cost effort
- Over-investing in low-cost replies because they "feel" important
- Estimating cost only in dollars; ignoring trust / reputation / churn cascade

**Prompt module**:
```
[OPERATOR: 🧮 COSTABLE]
Estimate the *expected* cost of being wrong, in three dimensions:

1) DIRECT COST: refund / churn / SLA credit dollars at risk
2) REPUTATION COST: virality risk (followers × likelihood of public post)
3) PRECEDENT COST: if 50 other customers see this answer, would the
   precedent damage future cases?

Then map effort to cost (project's actual thresholds override these
illustrative bands; tune in 05-policies.md):

   <$100 + V1 + no precedent      → routine effort, head strategy
   $100-$1k OR V2 OR mild precedent → standard pipeline + 🪞 SECOND-OPINION
   $1k-$10k OR V3 OR strong precedent → tail pipeline + multi-model + owner
   >$10k OR V4-V5 OR existential   → tail + owner + counsel + comms

Output: a cost estimate + recommended investigation tier.
Required: estimate is written down; tier is matched; no rounding to zero
because "we don't know."
```

**Tag**: `costable`. **Composes with**: 🪞 SECOND-OPINION, 📐 EISENHOWER, ⚖ DECIDE.

---

### 🏷 TAG-CONSISTENCY — Vocabulary Discipline At Close

**Definition**: At ticket close, apply theme tags from the project's controlled vocabulary, in the canonical naming, so VoC mining downstream is meaningful.

**Triggers**:
- Every ticket close (mandatory)
- Onboarding (initial vocabulary import)
- Quarterly vocabulary review
- Cross-project triage (consistency across multiple projects in the skill)

**Failure modes**:
- Inventing new tags ad-hoc instead of using the vocabulary
- Using the vocabulary inconsistently ("auth-sso" vs "auth.sso" vs "SSO")
- Skipping tag application when triage is rushed
- Tags that conflate symptom and cause (mining downstream becomes muddy)

**Prompt module**:
```
[OPERATOR: 🏷 TAG-CONSISTENCY]
At close:
1) Read <project>/.claude/support-triage/vocabularies/themes.md.
2) Pick 1-3 tags that match the ticket's substance.
3) Use the canonical form (no variants).
4) If no existing tag fits exactly:
   - Don't invent silently; propose one in the outcome record
   - Owner approves additions during weekly review
5) For ambiguous tickets, prefer the broader category over a too-specific tag.

Output: 1-3 canonical-form tags applied to the closed ticket.
Required: zero new vocabulary entries without owner approval;
no synonyms; no variants.
```

**Tag**: `tag-consistency`. **Composes with**: 🔁 VERIFY (close-time), 📈 OUTCOME, 🧬 EVOLVE.

---

### ⛓ EVIDENCE-CHAIN — Switch To Legal-Hold Mode

**Definition**: Activate immutable, complete, authenticated, retained-per-jurisdiction evidence preservation when a case crosses legal / regulatory / press triggers.

**Triggers**:
- Customer or counterparty references litigation
- Regulator inquiry received
- Disclosed (or near-disclosed) data breach
- Security disclosure under embargo
- Press / journalist with deadline
- SLA dispute > project's threshold
- Insurance claim being filed

**Failure modes**:
- Activating late ("we don't think they'll really sue") — evidence already lost
- Activating without notifying counsel — privilege not properly engaged
- Snapshotting incompletely — gaps invite spoliation claims
- Allowing automated deletion / pruning to continue on in-scope data
- Discussing case publicly after activation (privilege waiver)

**Prompt module**:
```
[OPERATOR: ⛓ EVIDENCE-CHAIN]
Per EVIDENCE-CHAIN-OF-CUSTODY.md activation checklist:
1) Identify scope (which threads, accounts, tickets).
2) Notify owner + counsel.
3) Mark in-scope tickets `legal-hold`.
4) Suspend automated deletion on related artifacts.
5) Snapshot current state; SHA-256 the bundle; record in
   <project>/.claude/support-triage/legal-holds/<case-id>/.
6) Switch agent to read-only mode for related topics; route
   substantive replies through counsel.
7) Append every event to chain-of-custody.log.

Output: legal-hold case directory with snapshot + log.
Required: zero further customer-facing replies on the topic until
counsel-cleared; chain-of-custody log appendable-only.
```

**Tag**: `evidence-chain`. **Composes with**: 🛡 ESCALATE, ⛔ RED-FLAGS.

---

### 📚 KB-SUGGEST — Promote Solved Tickets Into KB Articles

**Definition**: When a ticket's resolution is a clean answer-to-a-recurring-question, propose it as a KB article so the next 50 customers self-serve.

**Triggers**:
- Theme volume hits "rule of three" (3+ in 7d) per [DEFLECTION-AND-SELF-SERVICE.md](DEFLECTION-AND-SELF-SERVICE.md)
- A reply was unusually specific and well-written; would generalise cleanly
- Customer asked a "how do I X?" question that has no current KB article
- Onboarding ticket — most are KB-candidates with product-side fixes
- A FAQ workaround for a known bug

**Failure modes**:
- Authoring KB articles that paper over real bugs (the right fix is the bug, not the doc)
- Generic articles that don't match the customer's specific question
- Stale articles that survive after the underlying answer changes
- KB article in the wrong location (no in-app search; only on /docs)

**Prompt module**:
```
[OPERATOR: 📚 KB-SUGGEST]
1) Determine: is the answer general enough to apply to 10+ future
   customers? If no, skip.
2) If yes, write the proposed KB article using the three quality tests
   (DEFLECTION-AND-SELF-SERVICE.md §"KB Article Quality Bar"):
   - Title is the customer's question
   - First 50 words deliver the core answer
   - Cites exact UI path / copy-paste command
3) Cross-link from related existing articles.
4) Stage in the KB authoring queue; not auto-published.
5) Track: did the next 30d show theme volume drop?

Output: a draft KB article + suggested cross-links + theme to track.
Required: not a duplicate of existing article; passes 3 quality tests.
```

**Tag**: `kb-suggest`. **Composes with**: 📈 OUTCOME, 🧬 EVOLVE, 🔬 5-WHY.

---

### ⛔ RED-FLAGS — Phrases That Halt Drafting

**Definition**: A controlled list of inbound phrases that, when detected, must immediately halt the standard pipeline and route to escalation.

**Triggers**: any of these in the customer's message:

| Phrase class | Examples | Route |
|---|---|---|
| Legal | "lawyer", "litigation", "subpoena", "court", "attorney", "demand letter", "cease and desist" | Pipeline U + ⛓ EVIDENCE-CHAIN |
| Regulator | "FTC", "GDPR", "Data Protection Authority", "SEC", "regulator", "complaint to [agency]" | Pipeline U + ⛓ EVIDENCE-CHAIN |
| Press / journalist | "I'm a journalist", "I'm working on a story", "press@", "for publication" | Pipeline T |
| Security | "vulnerability", "CVE", "exploit", "PoC", "responsible disclosure" | Pipeline D + ⛓ EVIDENCE-CHAIN |
| Self-harm signals | any explicit self-harm reference | Out-of-scope; route to crisis resource immediately; do not draft |
| Threats of violence | any explicit threat | Trust-and-safety / authorities; do not engage |
| Mass exposure threat | "I'll post this", "going to my followers", "writing a blog" | 🪞 SECOND-OPINION + 🪜 LADDER + 🧮 COSTABLE |
| Account compromise indicator | "someone got into my account", "I didn't make that change", "compromised" | Account-recovery + security review |

**Failure modes**:
- Auto-replying through standard pipeline despite a red-flag phrase
- Treating the phrase as bluster ("they don't really mean lawyer")
- Detecting only literal phrases; missing paraphrases ("my counsel will be in touch")
- Adding to the list without owner approval (the list is policy, not flair)

**Prompt module**:
```
[OPERATOR: ⛔ RED-FLAGS]
1) On every inbound, scan for red-flag phrases (literal + common
   paraphrases).
2) On detection, HALT the standard pipeline. Do not draft a customer
   reply through normal channels.
3) Route to the corresponding pipeline:
   - Legal / Regulator → Pipeline U + ⛓ EVIDENCE-CHAIN
   - Press → Pipeline T
   - Security → Pipeline D + ⛓ EVIDENCE-CHAIN
   - Self-harm / violence → out-of-scope; provide crisis-resource
     pointer; surface to owner immediately
   - Mass-exposure threat → 🧮 COSTABLE → 🪜 LADDER (don't capitulate)
   - Account compromise → freeze + verify identity per ACCOUNT-RECOVERY
4) Log the detection and route in the audit trail.

Output: pipeline route + log entry; no standard-pipeline reply sent.
Required: zero customer-facing replies through normal channels until
the right pipeline approves.
```

**Tag**: `red-flags`. **Composes with**: 🛡 ESCALATE, ⛓ EVIDENCE-CHAIN, all crisis pipelines.

---

### 🔮 PREDICT — Forecast The Next 7 Days

**Definition**: Apply the simple forecast model from [SUPPORT-FORECASTING.md](SUPPORT-FORECASTING.md) to anticipate next-week volume; pre-stage capacity / templates / proactive outreach.

**Triggers**:
- Weekly planning window (run once per week)
- Pre-launch (feature release, marketing push, plan-change)
- Spike anticipated (incident yesterday; integration partner outage; etc.)
- Vacation / break planned (capacity will dip)

**Failure modes**:
- Forecasting in a vacuum (no calibration against actuals)
- Treating routine variance as signal (fortnightly cycles look like trends if you only have 14 days of data)
- Forecasting without a capacity check (volume estimate is useless without "do we have capacity?")
- Stale forecast left up while reality diverges

**Prompt module**:
```
[OPERATOR: 🔮 PREDICT]
1) Pull last 90d daily counts per channel.
2) Compute: rolling 28d weekday-adjusted median × seasonality
   × known events.
3) Compare next-7-day forecast to capacity (per
   SUPPORT-FORECASTING.md capacity formula).
4) If forecast > capacity: surface the gap to owner; propose
   one of (capacity, demand, per-ticket-time intervention).
5) If forecast < capacity: reserve the surplus for compounding
   work (per PARETO-AND-LONG-TAIL.md 70/20/10).
6) Re-check forecast vs actuals at the end of next week;
   feed the deltas back into the model.

Output: 7-day forecast + capacity check + recommended action.
Required: forecast cites the model inputs; capacity check is honest
about current utilisation; recommendation is named, not abstract.
```

**Tag**: `predict`. **Composes with**: 📐 EISENHOWER, 🩹 PROACTIVE.

---

## Frontier Operators (Safety, Org, And Specialised Routing)

The operators below were added in a third pass to cover safety-critical, organisational, and specialised-domain dimensions the prior layers assumed but did not name.

---

### 🛟 RESCUE — Crisis-Flagged Inbound Handling

**Definition**: Recognise crisis-level disclosure (self-harm, abuse, violence, child endangerment) and switch to the dedicated trauma-informed protocol per [TRAUMA-INFORMED-SUPPORT.md](TRAUMA-INFORMED-SUPPORT.md).

**Triggers**:
- Self-harm / suicide reference detected
- Domestic-violence / coercive-control language
- Stalking-via-product disclosure
- Active third-party threat
- Mention of minor at risk
- Disclosed acute mental-health crisis

**Failure modes**:
- Treating disclosure as routine ticket → catastrophic
- Agent generates "supportive" reply with own words → high-variance harm
- Asking follow-up questions to "understand better" → re-traumatising
- Hidden in a daily-bundle for owner to read alongside refunds → wrong cognitive context

**Prompt module**:
```
[OPERATOR: 🛟 RESCUE]
1) STOP standard pipeline. Mark ticket lifecycle state crisis-hold.
2) Notify owner immediately, out-of-band; do NOT include in routine bundle.
3) For self-harm/suicide signals: send the owner-pre-approved
   crisis-resource pointer (NEVER agent-generated) within project's
   crisis-SLA (often <1h).
4) Suspend all automation that would re-contact this customer.
5) Internal note: "crisis-flag detected; standard process suspended;
   awaiting specialist."
6) Move disclosure detail to privileged-retention per
   EVIDENCE-CHAIN-OF-CUSTODY.md.

Output: routed to specialist; no agent-generated substantive reply.
Required: zero standard-pipeline replies; owner notified out-of-band;
disclosure not retained in clear-text ticket history.
```

**Tag**: `rescue`. **Composes with**: ⛔ RED-FLAGS, 🛡 ESCALATE, ⛓ EVIDENCE-CHAIN.

---

### 🕵 FRAUD-CHECK — Score Risk Signals Before Sensitive Action

**Definition**: Apply the multi-signal risk scoring from [FRAUD-AND-ABUSE-DETECTION.md](FRAUD-AND-ABUSE-DETECTION.md) before any refund execution, recovery flow, or sensitive change.

**Triggers**:
- Refund / recovery / sensitive-action ticket
- New account (<30d) requesting refund or change
- Account previously suspended; new ticket from same fingerprint
- "I forgot which email" / multi-factor-loss claims
- Customer cites previous agent or bypass

**Failure modes**:
- Skipping the score; relying on "feels OK"
- Capitulating to chargeback threat (rewards future abuse)
- Wrongly accusing legitimate customer (permanent reputation loss)
- Agent processing customer-provided "evidence" of authorisation

**Prompt module**:
```
[OPERATOR: 🕵 FRAUD-CHECK]
1) Compute risk score (account, content, adversarial signals).
2) Score < 4: standard pipeline.
3) Score 4-5: deeper review; verify via independent channel before action.
4) Score ≥ 6: freeze account; route to Pipeline X (Fraud/ATO).
5) Document signals + score in internal note; aggregate to monthly review.
6) For ATO-shape: NEVER change auth factors solely on possession-of-account.

Output: risk score + recommendation + audit trail.
Required: every authoritative claim anchored in project records, not
customer-provided text; verification factor on a channel customer
does not control.
```

**Tag**: `fraud-check`. **Composes with**: ⚖ DECIDE, 🪞 SECOND-OPINION, 🛡 ESCALATE.

---

### 📊 OBSERVE — Telemetry-Joined Triage

**Definition**: Join the ticket with error-tracking / logging / RUM telemetry per [OBSERVABILITY-DRIVEN-TRIAGE.md](OBSERVABILITY-DRIVEN-TRIAGE.md). Three modes: anticipate (alerts → expected tickets), correlate (this ticket → which errors), reverse-correlate (errors → silent cohort).

**Triggers**:
- Any bug-report ticket where telemetry could disambiguate
- Error spike alert before tickets land
- Post-fix outreach to silent-cohort users
- "Is it just me?" question

**Failure modes**:
- Guessing without checking telemetry
- Joining on email instead of stable user_id
- Quoting raw stack traces verbatim to customer
- Errors retained too short to correlate with later tickets

**Prompt module**:
```
[OPERATOR: 📊 OBSERVE]
For correlate mode (most common):
1) From the ticket, extract user_id (or email), timestamp, action.
2) Query error tracking + logs around the timestamp.
3) Cite specific evidence in investigation log: stack snippet,
   trace ID, request URL + status, deploy version.
4) Use evidence to sharpen the reply ("I see your sync failed at
   [time] with a 504 on [endpoint]; cause was [...]").
5) For anticipate / reverse-correlate modes, see
   OBSERVABILITY-DRIVEN-TRIAGE.md.

Output: evidence-anchored draft; or pre-staged response cohort
for anticipated spike.
Required: the customer's "is it just me?" gets a data-anchored
answer, not speculation.
```

**Tag**: `observe`. **Composes with**: 🔍 REPRO, 🩹 PROACTIVE, 🔮 PREDICT.

---

### 🌍 LOCALE-AWARE — Cultural Calibration Beyond Translation

**Definition**: Apply locale-specific calibration (apology weight, register, formatting, currency, timezone) per [INTERNATIONALIZATION-AND-LOCALE.md](INTERNATIONALIZATION-AND-LOCALE.md).

**Triggers**:
- Customer's locale is non-default (project's default in `08-voice.md`)
- Customer wrote in a non-default language
- Reply involves money / dates / time / formal decline
- Cross-jurisdiction privacy implications (GDPR vs CCPA vs LGPD vs PIPL)

**Failure modes**:
- Translation-only without register calibration
- US conventions for currency/dates assumed
- "by tomorrow" / "next week" without a date
- Apology weight mis-calibrated (over or under for locale)
- First-naming a customer where locale prefers honorifics

**Prompt module**:
```
[OPERATOR: 🌍 LOCALE-AWARE]
1) Identify locale (language + region + jurisdiction).
2) Look up project's per-locale extension in 08-voice.md.
3) Calibrate:
   - Apology weight (locale-specific scale)
   - Register (formal/casual; honorifics)
   - Time/date/currency in customer's locale
   - Working week / holidays for promised timing
   - RTL formatting if applicable
4) For high-stakes content: native-speaker review for first 50 sends
   per template per locale.
5) Add machine-translated disclaimer for non-reviewed sends.

Output: locale-calibrated draft + flag if native-speaker review needed.
Required: zero locale-mismatched commitments (e.g., promising US
business hours to a JP customer in CET-formatted dates).
```

**Tag**: `locale-aware`. **Composes with**: 🌐 TRANSLATE, 🎙 VOICE-MATCH, 🎁 GOODWILL.

---

### ♿ A11Y — Accessibility Pre-Send Pass

**Definition**: Verify the reply is accessible (plain-text-friendly, semantic structure, descriptive links, alt-text on attachments) per [ACCESSIBILITY-IN-SUPPORT.md](ACCESSIBILITY-IN-SUPPORT.md).

**Triggers**:
- Customer signals screen-reader / low-vision / cognitive-accessibility need
- Account has accommodation flag in `05-policies.md`
- Reply contains attachments / images / tables
- KB article being authored (must be accessible)

**Failure modes**:
- "Click here" link text
- HTML tables-for-layout
- Images of error messages without text quote
- Color-coded emphasis ("the red part")
- Long sentences / dense paragraphs / unexplained jargon

**Prompt module**:
```
[OPERATOR: ♿ A11Y]
1) Plain-text test: paste reply into plain-text editor; still legible?
2) Read-aloud test: read first 3 sentences out loud; sounds natural?
3) Link audit: every URL has descriptive text?
4) Image audit: alt-text + body-text description?
5) Length audit: avg sentence ≤ 20 words?
6) Jargon audit: technical terms explained on first use?

If any fails: revise. ~30s pass; catches the most common regressions.

Output: pass/fail + revisions if needed.
Required: zero accessibility-fails sent to flagged customers.
```

**Tag**: `a11y`. **Composes with**: ✉ DRAFT, 🎙 VOICE-MATCH, 🌍 LOCALE-AWARE.

---

### 🎚 LIFECYCLE-STATE — Right State At The Right Moment

**Definition**: Maintain ticket lifecycle state correctly per [TICKET-LIFECYCLE-STATES.md](TICKET-LIFECYCLE-STATES.md): not just open/closed but `awaiting_customer`, `awaiting_engineering`, `awaiting_external`, `snoozed`, `watching`, `legal-hold`, `crisis-hold`, `closed-unresolved`.

**Triggers**:
- Every state transition during triage
- New message arrives on closed ticket (reopen logic)
- Bug confirmed → bead filed (state change)
- Customer asked for data; awaiting them
- Counsel engaged → legal-hold

**Failure modes**:
- "open" while truly waiting on customer (corrupts SLA)
- "closed" while customer never confirmed (false-positive resolution)
- Reopen on tangential reply ("thanks!") starts SLA clock unnecessarily
- Hidden hand-off (engineering takes it; customer not told)
- `closed-unresolved` never used; quality signal lost

**Prompt module**:
```
[OPERATOR: 🎚 LIFECYCLE-STATE]
On each transition decision:
1) What state best matches reality? (canonical list in
   TICKET-LIFECYCLE-STATES.md)
2) Will the customer know what state we're in (transparent
   transitions)?
3) Is the SLA clock correctly running or paused?
4) For new message in closed ticket:
   - Tangential reply ("thanks!") → keep closed; no SLA reset
   - New issue → file new ticket; link to original
   - Continuation of original → reopen → investigating
5) For close: distinguish closed (resolved) from closed-unresolved
   (didn't help / customer gave up).

Output: correct state + customer notification if state-change
is customer-relevant.
Required: zero state mismatches; reopen-on-thanks bug not present.
```

**Tag**: `lifecycle-state`. **Composes with**: 🚦 PAUSE-SLA, 📤 SEND, 🐞 BEAD, 🔁 LOOPBACK.

---

### 🔀 SPLIT — Fork A Multi-Issue Ticket

**Definition**: When one ticket contains two or more distinct issues, split into separate tickets so each gets correct routing, SLA, and resolution.

**Triggers**:
- Customer reports 2+ unrelated issues in one message
- A bug-report ticket also contains a refund request
- A how-to question piggybacked on an outage report
- Sub-issues have different severity / pipeline / owner

**Failure modes**:
- Single resolution closes the ticket while one of N issues is unresolved
- Wrong pipeline applied to a sub-issue (e.g., security-shape sub-issue inside routine bug)
- Customer has to keep repeating "but you didn't address X"

**Prompt module**:
```
[OPERATOR: 🔀 SPLIT]
1) Identify each distinct issue: who/what/severity per sub-issue.
2) Decide: split or combined?
   - Combined OK: same pipeline, same severity, same owner
   - Split required: different pipelines, different severity, or
     would block resolution of one on resolution of another
3) For split:
   - File child ticket(s); link parent
   - Carry context forward (the customer's quoted text, account
     info, history) to each child
   - Notify customer in the parent that you've split
   - Each child runs its own pipeline
4) Parent ticket lifecycle: closed-but-watched until all children
   resolve; then closed.

Output: child tickets created with full context; customer notified.
Required: customer never has to re-explain the sub-issue context.
```

**Tag**: `split`. **Composes with**: ⚖ DECIDE, 🐞 BEAD.

---

### 🔗 MERGE — Combine Duplicates

**Definition**: When the same customer's tickets describe the same issue, or two tickets share a root cause, merge so resolution doesn't fragment.

**Triggers**:
- Same customer files multiple tickets on same issue (re-files because no quick reply)
- Duplicate detection within a customer's history
- Cross-customer same-incident tickets (handle differently — link, don't merge)
- Same root-cause cluster identified by ⊕ CORRELATE

**Failure modes**:
- Lost context from the older ticket (missed customer history)
- Customer feels heard once, ignored on the duplicates
- Two tickets resolve at different speeds, customer confused

**Prompt module**:
```
[OPERATOR: 🔗 MERGE]
1) Identify duplicates: same customer + same issue signature OR
   verified-by-customer "yes, same thing".
2) Decide canonical ticket (usually the oldest with most history).
3) For merge:
   - Move context (timeline, prior replies, internal notes) to canonical
   - Mark non-canonical as `closed-merged`; link to canonical
   - Notify customer in canonical: "I've combined your messages here
     to keep this in one place"
4) For cross-customer same-cause: do NOT merge (different customers
   need separate communications); LINK via incident ID and use
   🪧 BROADCAST.

Output: one canonical ticket with full history; clean closure of duplicates.
Required: zero customer history lost; customer told about the merge.
```

**Tag**: `merge`. **Composes with**: ⊕ CORRELATE, 🪧 BROADCAST.

---

### ⚡ SWARM — Multi-Specialist Burst On A Hard Case

**Definition**: For complex tail tickets, pull 1-3 specialists for short bursts (15-30 min) under one customer-facing senior owner, per [MULTI-TIER-SUPPORT-ORG.md](MULTI-TIER-SUPPORT-ORG.md).

**Triggers**:
- Complex case beyond L1/L2 capability
- Multi-domain expertise needed (e.g., billing + security + product)
- High-stakes (Pipeline C / D / E / Q / T / U)
- Time-pressured (SLA tight, customer waiting)

**Failure modes**:
- Multiple specialists each replying to customer (broken telephone)
- Senior synthesises poorly; customer gets contradictions
- Specialists in the loop without full case frame

**Prompt module**:
```
[OPERATOR: ⚡ SWARM]
1) Senior owner sets the case frame (3 lines: what / who / stakes).
2) @-mention 1-3 specialists with the case frame.
3) Specialists contribute to a shared case file (NOT customer-facing).
4) Senior consolidates; runs 🎙 VOICE-MATCH; ✓ CONFIRM.
5) ONE customer-facing reply, from senior, with consolidated answer.
6) Specialists' contributions logged; not customer-visible.

Output: single high-quality reply; multi-specialist input visible
internally only.
Required: zero specialists replying directly to customer; one voice.
```

**Tag**: `swarm`. **Composes with**: 🪞 SECOND-OPINION, ✉ DRAFT.

---

### 🧪 QA-SAMPLE — Sample-Based Quality Review

**Definition**: Random-sample sent replies and score against the rubric per [QA-SHADOW-REVIEW.md](QA-SHADOW-REVIEW.md). Catches systemic drift across many sends.

**Triggers**:
- Weekly QA review window
- Volume crosses ~50 sends/week (otherwise spot-check suffices)
- Post-template-update verification
- Quarterly calibration session
- Suspicion of agent regression / template aging

**Failure modes**:
- Reviewer marks "OK" without reading
- No calibration; scores incomparable across reviewers
- Findings discussed but never converted to changes
- QA used as individual-performance KPI (destroys honest review)
- Sampling biased to known-bad days

**Prompt module**:
```
[OPERATOR: 🧪 QA-SAMPLE]
1) Random-stratified sample: 5-10% of sends, capped 30/week.
2) For each, score 6 dimensions (0/1/2 each, 0-12 total):
   - Factual accuracy
   - Customer-effort minimisation
   - Voice match
   - Empathy calibration
   - Operator/runbook compliance
   - Evidence anchoring
3) Note specific findings per ticket: what to do differently.
4) Aggregate weekly; trend over weeks.
5) Convert findings to template / runbook / operator updates.

Output: scores + findings per ticket + aggregate score; specific
proposed changes.
Required: rubric applied honestly; findings have owners + deadlines.
```

**Tag**: `qa-sample`. **Composes with**: 📈 OUTCOME, 🧬 EVOLVE.

---

### ☠ EOL — Deprecation / Sunset Comms Discipline

**Definition**: When a feature, endpoint, plan, or product is being deprecated, run the comms cadence per [DEPRECATION-AND-SUNSET-COMMS.md](DEPRECATION-AND-SUNSET-COMMS.md): per-affected-customer specific impact, generous lead time, migration tooling, post-removal recovery path.

**Triggers**:
- Project plans to deprecate something customer-visible
- A deprecation already announced; customer asks about it
- Post-deprecation customer hits the removed thing
- Enterprise customer with contract terms affected by the deprecation

**Failure modes**:
- Lead time too short (legal-shape risk; reputation damage)
- Generic blog-post-only announcement (customers don't read)
- Enterprise customers learn from public blog before AE called them
- No migration tooling; burden falls per-customer
- "We've improved [thing] by removing it" framing
- No post-removal recovery for customers who missed deadline

**Prompt module**:
```
[OPERATOR: ☠ EOL]
1) Identify scope: what's removed, when, what replaces it.
2) For project's lead-time defaults (or owner-specific): does it meet?
3) Identify affected cohort precisely (per OBSERVE/PROACTIVE):
   for each, what's specifically at risk?
4) Plan cadence per DEPRECATION-AND-SUNSET-COMMS.md (T-Xmo
   announcements; T-2wk reminders; T-day-of removal note).
5) Write per-account-impact email (specific, named risk + steps).
6) Migration tooling: do we have it? If not, build it before announcing.
7) For enterprise: check contracts; counsel-led negotiation BEFORE
   public announce.
8) Post-removal: recovery path documented for missed-deadline customers.

Output: deprecation plan + per-cohort messages + migration tools list.
Required: specific (not generic); generous lead time; enterprise
respected; post-removal recovery exists.
```

**Tag**: `eol`. **Composes with**: 🩹 PROACTIVE, 🪧 BROADCAST, 🏛 ENTERPRISE.

---

### 🏛 ENTERPRISE — Enterprise-Tier Register And Process

**Definition**: Switch to enterprise-shape register and process per [ENTERPRISE-PLAYBOOKS.md](ENTERPRISE-PLAYBOOKS.md): formal language, evidence-trail discipline, account-team coordination, contract-aware responses.

**Triggers**:
- Customer has signed MSA + Order Form (not click-through)
- Customer's CSM/AE is named on their side
- Customer's ARR > project's enterprise threshold
- DPA inbound / security questionnaire / custom MSA / SOC2 ask
- Enterprise SLA breach calculation needed

**Failure modes**:
- Treating enterprise ticket like consumer (template + close)
- Promising terms in support that aren't in the contract
- Generic "we apologize for any inconvenience" to a CISO
- Routing security questionnaire to L1
- Auto-issuing credit beyond contracted amount
- Forgetting they have an AE/CSM

**Prompt module**:
```
[OPERATOR: 🏛 ENTERPRISE]
1) Confirm enterprise status (per project's threshold in 05-policies.md).
2) Pull customer-side context: AE/CSM name; contract terms relevant
   to this ticket; prior account history.
3) Switch register: formal-restrained; full names/titles; cite
   contract clauses where they apply.
4) Coordinate with account team: notify if substantive (don't act
   unilaterally on relationship-affecting cases).
5) Evidence trail: every legal/contract exchange goes to
   per-customer evidence repo per EVIDENCE-CHAIN-OF-CUSTODY.md.
6) For specific inbounds (DPA, security questionnaire, MSA redlines,
   SOC2): route per ENTERPRISE-PLAYBOOKS.md operator-locals.

Output: enterprise-calibrated reply or routing; account-team coordinated.
Required: never freelance contract-shape commitments; evidence retained.
```

**Tag**: `enterprise`. **Composes with**: 🎁 GOODWILL, ⛓ EVIDENCE-CHAIN, ⚡ SWARM.

---

### 🪦 SUCCESSION — Deceased User / Estate / Account Inheritance

**Definition**: Handle deceased-user inbounds with the verification + privacy + grief-tone discipline per [DECEASED-USER-AND-SUCCESSION.md](DECEASED-USER-AND-SUCCESSION.md).

**Triggers**:
- Family / executor notifies of account-holder death
- Business co-owner needs ownership transfer after partner death
- Estate executor with court documents seeks legal access
- Memorialisation request

**Failure modes**:
- Auto-handling (catastrophic; high-stakes verification needed)
- Treating disclosure with marketing register
- Skipping cool-down windows
- Documents retained in clear-text ticket history (PII violation)
- Refusing without offering a path
- Falling for social-engineered fake-death scams

**Prompt module**:
```
[OPERATOR: 🪦 SUCCESSION]
1) Recognise inbound class (family / executor / business co-owner /
   memorialisation).
2) Match verification tier (A: cancel/refund; B: data export;
   C: ownership transfer; D: memorialisation).
3) Reply with grief-calibrated tone (per CUSTOMER-PSYCHOLOGY.md
   apology spectrum, heavy-end + grief modulation).
4) State path forward + required documents + timeline.
5) Cool-down window per tier.
6) Documents retained per EVIDENCE-CHAIN-OF-CUSTODY.md (hash + privileged).
7) For Tier C / suspicious cases: counsel review.

Output: path forward + verification-document request + grief-calibrated
reply.
Required: never auto-handle; never use disclosure for marketing;
documents in privileged retention.
```

**Tag**: `succession`. **Composes with**: 🪜 LADDER (grief register), ⛓ EVIDENCE-CHAIN, 🕵 FRAUD-CHECK (verify).

---

## Operator Composition Pipelines

These are the standard chains per phase:

```
Phase 1 — Ground Truth:
  ⊞ MULTI-CHANNEL → ★ ORIENT (per item)
  (large queues may run 📐 EISENHOWER after orientation)

Phase 2 — Investigate:
  🔍 REPRO → ✓ VERSION-PIN → ⊕ CORRELATE → 🔭 ANOMALY (if instinct disagrees)
  → 🪞 SECOND-OPINION (high-stakes only)

Phase 3 — Draft:
  ⚖ DECIDE → ✉ DRAFT → 🎙 VOICE-MATCH
  (special routes: 🛡 ESCALATE bypass, 🚦 PAUSE-SLA bypass, 🌐 TRANSLATE wraps;
   emotionally loaded routes may insert 🪄 EMPATHIZE, 🪜 LADDER, or 🎁 GOODWILL)

Phase 4 — Owner Review:
  ✓ CONFIRM (always)

Phase 5 — Act + Verify:
  📤 SEND (per approved) → 🔁 VERIFY (once at end) → 🐞 BEAD (per confirmed bug)

Phase 6 — Outcome:
  🏷 TAG-CONSISTENCY → 📈 OUTCOME → 🧬 EVOLVE
  (use 📚 KB-SUGGEST, 💎 KEEPER, 🩹 PROACTIVE, and 🔁 LOOPBACK when evidence justifies them)

Onboarding / validation:
  🧪 FIRE-DRILL after adapter validation and before trusting high-risk runbooks
  (pre-launch or high-volume periods may run 🔮 PREDICT first)
```

## Validation Checklist

For each new operator added to this library:
- [ ] Has symbol, name, canonical tag
- [ ] Definition is one sentence
- [ ] At least 3 triggers
- [ ] At least 2 failure modes (specific, not generic)
- [ ] Prompt module is complete and copy-paste ready
- [ ] Output and Required lines present
- [ ] Composition with neighboring operators noted
- [ ] Tested in at least one real triage session before adding
