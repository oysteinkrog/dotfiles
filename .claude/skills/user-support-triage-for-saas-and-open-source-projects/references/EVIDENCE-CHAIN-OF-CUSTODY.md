# Evidence Chain Of Custody — Preservation Discipline For Legal, Regulatory, And Press Cases

The triage skill's normal artifacts (drafts, audit logs, beads, outcome records) are operational. When a case crosses into legal / regulatory / press territory, the same evidence has to be preserved to a higher standard: *unaltered*, *authenticated*, *complete*, and *traceable*. This file specifies the chain-of-custody rules that the runbooks (`SECURITY-DISCLOSURE`, `GDPR-DSAR`, `CCPA`, `HOSTILE-USER` legal-flagged, `OUTAGE-COMMS` major-incident) all assume.

> **Core insight:** the discipline of evidence preservation is not "keep extra copies." It is *immutability* (can the record be changed after the fact?), *completeness* (is there a gap?), and *traceability* (can a third party verify the chain back to a known-trustworthy origin?). The default support workflow is not designed for this; this file is what the support workflow upgrades to when stakes require it.

---

## The Five Properties Evidence Must Have

| Property | Means | Default support workflow |
|---|---|---|
| **Immutability** | Can't be altered without detection | ❌ markdown files are mutable; logs are appendable |
| **Completeness** | All material communications captured | ⚠️ relies on manual logging |
| **Authenticity** | Provable origin (who, when, what tool) | ⚠️ git history helps but isn't airtight |
| **Privilege protection** | Counsel-protected discussions stay protected | ❌ default chat is discoverable |
| **Retention** | Held for the legally-required period | ❌ ad hoc |

For legal/regulator cases the workflow has to be upgraded along all five.

---

## The Triggers (When To Switch Modes)

Activate chain-of-custody mode when ANY of these fire:

| Trigger | Examples |
|---|---|
| Customer or counterparty references litigation | "I will pursue legal action," subpoena, demand letter |
| Regulator inquiry | Letter from a national / state agency, formal request |
| Disclosed (or near-disclosed) data breach | Personal data exposed to unauthorized party |
| Security disclosure under embargo | Researcher reports CVE-shaped issue |
| Press / journalist with deadline | Reporter asks substantive questions, especially under deadline |
| Contractual SLA dispute > $X | Material disagreement over service-level credit |
| Insurance claim being filed | Cyber-insurance, BI insurance, etc. |
| Internal investigation by HR/comms/legal | Even if not customer-driven |

Once any trigger fires, the case enters chain-of-custody mode. Switching back ("we don't think they'll really sue") is owner-and-counsel-only.

---

## The Mode-Switch Checklist

```
[OPERATOR-LOCAL: ⛓ EVIDENCE-CHAIN — activation]
1) Identify the case scope: which threads, accounts, tickets are in scope?
2) Notify owner + counsel (real or interim). Mark the ticket(s) as legal-hold.
3) Suspend any automated deletion / pruning that could reach in-scope artifacts:
     - Stale-bot exemptions on related issues
     - Email retention exemptions
     - Slack export / retention exemptions
     - Audit-log retention extensions
4) Snapshot the current state of in-scope artifacts:
     - Ticket history (export to immutable JSON / WARC)
     - Customer messages (export including headers)
     - Internal Slack / chat threads on the topic
     - Database records relevant to the case
     - Code / config that materially shaped the incident
5) Hash the snapshot (SHA-256 of the bundled archive) and record the hash + timestamp in:
     - The case-specific evidence index
     - A separate timestamped repo (or notarised somewhere external)
6) Tag every subsequent artifact with the case ID; route through privileged channels
   (counsel-included or counsel-only)
7) Stop drafting customer-facing replies on this topic without counsel sign-off
   (Pipeline U overrides Pipeline B/C/D etc. once activated)
```

This is the "before you do anything else" gate. The first hour after activation matters more than the next two weeks.

---

## The Evidence Index

Every legal-hold case has its own evidence index, stored in `<project>/.claude/support-triage/legal-holds/<case-id>/`:

```
<case-id>/
├── README.md                  ← case summary; counsel contact; status
├── triggers.md                ← what triggered activation; date; who decided
├── snapshots/
│   ├── 2026-04-27-T1430Z/     ← snapshot directory; immutable after creation
│   │   ├── tickets.jsonl
│   │   ├── messages.jsonl
│   │   ├── slack.jsonl
│   │   ├── db-extracts.jsonl
│   │   ├── code-state.tar.gz  ← git bundle of relevant repos
│   │   └── SHA256SUMS         ← checksum of every file in this snapshot
│   └── 2026-04-29-T0900Z/
├── communications/            ← inbound + outbound after activation
│   ├── 2026-04-28-customer-reply.eml
│   ├── 2026-04-28-counsel-memo.txt
│   └── ...
├── chain-of-custody.log       ← append-only; every access / handoff logged
└── retention-clock.md         ← required retention window; review dates
```

The directory is git-tracked but with a *separate* commit policy: signed commits, restricted reviewers, and ideally a separate repo from the main project.

### The chain-of-custody log format

```
2026-04-27T14:30:00Z  ACTIVATED  by:owner@project  trigger:lawyer-letter
                      scope:tickets [T-431, T-447] + slack #incident-431
2026-04-27T14:35:00Z  SNAPSHOT   sha256:a3b...c91  by:agent  size:14.2MB
2026-04-27T14:42:00Z  ACCESS     by:counsel@firm  reason:initial-review
2026-04-28T09:15:00Z  RECEIVED   from:customer@example.com  to:tickets/T-431
                      hash:5ee...23a  thread-position:14
2026-04-28T11:00:00Z  RESPONSE   from:counsel@firm  to:customer@example.com
                      reviewed-by:owner@project  approved-at:10:55Z
                      hash:8f4...7ba
2026-04-30T13:00:00Z  REVIEW     by:owner@project  status:active  next:2026-05-07
```

Every event is timestamped, attributed, hashed where applicable. This log is the answer to "what did you know, when did you know it, and what did you do?"

---

## The Privileged Channel

Counsel-protected discussions need to be on a channel that supports the privilege claim. Options ranked by strength:

| Channel | Privilege strength | Caveats |
|---|---|---|
| In-person + counsel + no recording | Highest | Can't be reviewed for accuracy later |
| Counsel-attended call + notes by counsel | High | Notes are work-product |
| Email *to/from* counsel, with explicit "Privileged" header | High | Marking is necessary but not sufficient |
| Slack channel with counsel and clear "for privileged communications" naming | Medium | Logs persist; not all jurisdictions accept |
| Standard internal Slack with "off the record" comments | Very low | Routinely admitted |

**Practical rule**: anything you would not want to read aloud in a courtroom does not belong in a Slack channel without counsel. The triage skill's draft-bundler subagent does *not* mediate privileged communications; pipelines that touch legal-hold cases route through counsel-attended channels manually.

---

## What NOT To Do (Common Mistakes)

| Mistake | Consequence |
|---|---|
| Delete a customer thread "to clean up" after activation | Spoliation; can be sanctioned |
| Edit prior internal Slack messages | Spoliation; modification logs persist |
| Copy snapshot data to a personal machine | Custody chain broken; access uncontrolled |
| Discuss the case publicly (X, blog, conf talk) | Privilege waiver; press inflamation |
| Email customer with "we don't believe we have liability here" | Admission against interest if read another way |
| Run the case through the same triage automation as routine tickets | Auto-replies routed to legal-hold subjects; chain-of-custody compromised |
| Tell affected customers more than legal cleared | Statements become discoverable |
| Reset / reformat / image a system "to fix the underlying issue" before forensics | Forensic evidence destroyed |
| Promise the customer specific information privately that contradicts the public posture | Inconsistency is the easiest cross-examination |
| Apologize specifically before counsel approves | Admission |

The discipline is uncomfortable for the support agent who wants to *help fix it*. The temporary prioritization is "preserve the record so we can fix it correctly" over "get this resolved fast."

---

## Specific Patterns Per Trigger Class

### Security disclosure under embargo

- All communications via secure channel (encrypted email, Signal, dedicated PGP)
- No detail in public ticket; the public-facing ticket says "we're in touch privately"
- CVE timeline tracked in evidence index
- Patch development on a private branch; commits squashed before public push to avoid early signal
- Disclosure letter to the researcher reviewed by counsel + comms

### GDPR / DSAR

- Identity verification step recorded in evidence index (with hash of identity proof, not the proof itself)
- Export / erasure operations executed against the evidence-locked DB extract, not live DB
- Confirmation receipt to user has a stable case ID
- 30-day clock tracked explicitly
- Audit-log entry stays for 7 years even if user account is deleted

### Litigation / demand letter

- Litigation hold notification emailed to all internal personnel with relevant access
- Specific named custodians acknowledge receipt
- Backup retention extended to "until released"
- Document review for production goes through counsel-managed platform, not Google Drive

### Regulator inquiry

- Acknowledgement email to regulator within target SLA (often 5-10 business days)
- All public statements paused on the topic
- "Holding statement" if asked publicly comes from comms-lead, not from the queue

### Major incident with potential class-action exposure

- Postmortem reviewed by counsel before publication
- Compensation offered to affected users coordinated with counsel (avoid creating an admission)
- Customer outreach goes through approved scripts; deviations logged

---

## Retention Periods

These are starting points; counsel will set actual retention per jurisdiction and case type.

| Case type | Retention from case-close |
|---|---|
| Routine support ticket | 1-3 years |
| Refund / billing dispute | 7 years (tax-record-aligned) |
| GDPR / DSAR | 7 years (including identity-verification proof minimisation) |
| Security disclosure | 7 years; CVE record permanent |
| Litigation | Per legal hold; often 7+ years |
| Regulator inquiry | Per regulator requirement; often 7-10 years |
| Major incident postmortem | Permanent (public archive) |
| Hostile-user / ban | 3-7 years; longer if litigation possible |
| Press inquiry record | 3 years |

`12-gap-dispositions.md` records project-specific retention. Retention can only be *extended*, never silently *shortened*, after activation.

---

## Hand-Off To Counsel

When counsel takes over substantive case management, the triage skill's role narrows to:
1. Continuing to log inbound / outbound (read-only mode)
2. Maintaining the chain-of-custody log
3. Producing snapshots on request
4. Refusing automated actions on the topic without counsel approval

The owner explicitly tells the triage agent: "case [ID] is in counsel-led mode; agent is read-only on this topic." That mode persists until counsel returns control.

---

## How This File Plugs In

| Used by | How |
|---|---|
| ⛓ EVIDENCE-CHAIN operator | Activation + chain-of-custody log |
| 🛡 ESCALATE operator | Routing into legal-hold mode |
| Pipeline D (Security disclosure) | Imports embargo + privilege rules |
| Pipeline F (GDPR / DSAR) | Imports identity-verification + retention |
| Pipeline T (Press inquiry) | Imports holding-statement + counsel-coordination |
| Pipeline U (Compliance / regulator) | The home pipeline for this file |
| 05-policies.md | Project-specific retention and counsel contact |
| 12-gap-dispositions.md | Per-gap retention overrides |

---

## Cross-References

- [runbooks/SECURITY-DISCLOSURE.md](runbooks/SECURITY-DISCLOSURE.md)
- [runbooks/GDPR-DSAR.md](runbooks/GDPR-DSAR.md)
- [runbooks/CCPA.md](runbooks/CCPA.md)
- [runbooks/HOSTILE-USER.md](runbooks/HOSTILE-USER.md) — legal-flagged paths
- [CRISIS-COMMS.md](CRISIS-COMMS.md) — public-facing side
- [AI-AUTO-RESPONSE-GOVERNANCE.md](AI-AUTO-RESPONSE-GOVERNANCE.md) §T4 — agent restrictions
- [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md) — retro under privileged conditions
