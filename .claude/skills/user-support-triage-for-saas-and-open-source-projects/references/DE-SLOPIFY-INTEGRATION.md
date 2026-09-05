# `/de-slopify` Integration — How And Why The Skill Calls It

`de-slopify` is the canonical AI-tell remover. Every customer-facing reply produced through this triage skill **must** pass through it before send. This file consolidates how the integration works: the contract, the auto-install path, the operator card, the inline fallback, and the audit-trail expectation.

> **Core insight:** customers can spot AI-generated phrasing from one paragraph. A single unmistakeably-AI reply destroys more brand trust than five slow honest ones. `/de-slopify` exists specifically to remove that fingerprint, and it is one of the two non-negotiable gates before any send (the other being `✓ CONFIRM`).

---

## The Contract

Every customer-facing artifact this skill produces — ticket replies, status-page posts, in-product banners, email outbound, public DM responses, OSS issue comments, OSS PR review comments, KB articles destined for publication — must be run through `/de-slopify` before owner approval is requested.

The pass is required regardless of:

- Pipeline (A through AB; routine through crisis)
- Channel (DB tickets, GitHub, Zendesk, email, X, Discord, status page)
- Severity (FAQ deflection through data-loss apology)
- Length (one-liner ack through multi-paragraph postmortem)
- Locale (English source through any translated target)

The only exception class is *internal-only* artifacts: internal Slack messages, audit-log entries, beads/issue bodies, internal handoff notes. Those don't need `/de-slopify` because they're not seen by customers.

---

## Auto-Install Via `jsm`

`/de-slopify` is marked **REQUIRED** in `scripts/check-skills.sh`. On cold-start of any project's triage workspace:

```bash
WS=<project>/.claude/support-triage/.workspace
mkdir -p "$WS"

# Step 1 — inventory
./scripts/check-skills.sh "$WS"
# Output JSON includes: {"name":"de-slopify","status":"missing","required":true,...}

# Step 2 — install (REQUIRED skills first)
./scripts/install-referenced-skills.sh "$WS"
# Reads inventory, runs `jsm install de-slopify` first,
# then any other missing referenced skills.
```

`install-referenced-skills.sh` installs `de-slopify` *before* any optional skill. If installation fails (no `jsm`, not authenticated, no subscription, network error), it prints a hard-bordered warning that names the failure and reminds the agent that the inline fallback (manual AI-tell removal list) is mandatory until install succeeds.

The installation is **idempotent** — re-running it after `de-slopify` is present is a no-op. Triage-cycle scripts can call check + install at session start with negligible cost.

---

## When De-Slopify Is Not Yet Installed

The skill must still run safely without `de-slopify`. The inline fallback is the union of two lists in [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md):

- §"Banned Phrases (AI-Tells)" — word/phrase-level tells (e.g., "kindly", "leverage", "robust solution", "We value your business", multiple emojis)
- §"AI-Tell Remover Pass" — operational checklist run mechanically before owner review

In addition to those two, the agent must also catch the following **structural** tells that VOICE-CALIBRATION's word-list does not enumerate:

- "I'd be happy to help" / "I'm happy to assist" → delete
- "Unfortunately," → delete the comma+pause; restructure
- "I hope this helps!" → delete
- "Please don't hesitate to..." → delete
- "delve into / navigate the complexities of / a wealth of" → replace with plain verbs
- Em-dashes used decoratively → comma or period
- "It's worth noting that..." → delete the meta-comment
- Triple-spaced bulleted lists where prose would do → flatten
- Sentences ending in "Let me know if you have any questions!" → delete; replace with specific next-action
- Closing with both "Best regards" and a fake-warm sign-off → pick one
- Headers in a 2-paragraph email → flatten
- Numbered lists for ≤2 items → use prose
- "As an AI..." → never; flag for owner
- Lists of synonyms ("clear, transparent, straightforward") → pick one

When the inline fallback is in use, the agent should add a one-line internal note to the audit trail: `de-slopify-mode: inline (skill not installed)`. This makes it visible in `📈 OUTCOME` records when the agent has been operating without the canonical pass.

---

## The 🧹 DE-SLOPIFY Operator

Per [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md), `🧹 DE-SLOPIFY` is the dedicated operator card for the pass. It runs after `🎙 VOICE-MATCH` and before `✓ CONFIRM`. The full prompt module is in OPERATOR-LIBRARY.md; the abridged contract:

| | |
|---|---|
| **Triggers** | Every customer-facing draft, every channel |
| **Inputs** | The voice-matched draft body |
| **Outputs** | The de-slopified body + a one-line "deslop applied" audit note |
| **Failure modes** | Skipping for routine cases; trusting that the model "wouldn't make AI-tells this time" |
| **Composes with** | ✉ DRAFT → 🎙 VOICE-MATCH → 🧹 DE-SLOPIFY → ✓ CONFIRM |

The operator is non-bypassable. Agents that skip it generate Confirmation-Rule violations on the audit log per [AI-AUTO-RESPONSE-GOVERNANCE.md](AI-AUTO-RESPONSE-GOVERNANCE.md).

---

## Audit Trail

Every send's audit row (per `📤 SEND` in OPERATOR-LIBRARY.md) records `de-slopify-status`:

| Status | Meaning |
|---|---|
| `passed` | `/de-slopify` ran clean — no issues found |
| `revised` | `/de-slopify` flagged issues; revision applied; re-checked clean |
| `inline-passed` | inline fallback used (skill not installed); no issues found |
| `inline-revised` | inline fallback used; revision applied |
| `skipped` | NOT ALLOWED — this is a Confirmation-Rule violation; surfaces as a process incident |

QA review (per `🧪 QA-SAMPLE`) samples a percentage of `passed` and `inline-passed` outcomes weekly to verify the pass actually caught what it should have. Any sampled drift triggers retraining of the AI-tell list per [QA-SHADOW-REVIEW.md](QA-SHADOW-REVIEW.md).

---

## What `/de-slopify` Catches That The Operator Library Doesn't

The operator library's `🎙 VOICE-MATCH` enforces brand-voice fit (per `08-voice.md`). `/de-slopify` catches a different layer — the *AI-fingerprint*, which is invariant across brands:

- Word-frequency tells (overuse of "delve", "navigate", "ensure", "leverage")
- Structural tells (numbered lists for trivial enumerations, gratuitous headers, em-dash-heavy prose)
- Rhetorical tells (excessive hedging, redundant intros, marketing-flavored closures)
- Sentence-shape tells (consistent same-length sentences, "additionally," / "furthermore," chains)
- Pseudo-warmth tells ("Hope this helps!" closures, exclamation-point inflation)

A reply can be perfectly voice-matched and still have AI fingerprints; conversely it can be free of AI fingerprints but voice-mismatched. Both passes are needed.

---

## How `/de-slopify` Is Invoked

Inside a draft-bundler agent context:

```
[OPERATOR: 🧹 DE-SLOPIFY]
1) Take the voice-matched draft body.
2) Invoke the /de-slopify skill on it (or apply the inline fallback
   if /de-slopify is not present).
3) If revisions came back: replace the draft body with the revised
   version. Re-invoke /de-slopify on the revised version.
4) Repeat (max 3 iterations) until clean.
5) Record `de-slopify-status` in the audit row.
6) Hand off to ✓ CONFIRM with the de-slopified body.

Output: clean body + audit row entry.
Required: zero AI-tells in final body; status recorded; max-iter cap honored.
```

---

## What "Customer-Facing" Includes

Sometimes the skill is unsure whether something is customer-facing. The default is yes, with explicit exceptions:

| Artifact | Customer-facing? |
|---|---|
| Reply email body | Yes |
| Reply email subject line | Yes |
| In-product modal copy | Yes |
| Status-page incident description | Yes |
| Tweet / X reply | Yes |
| OSS issue comment (you replying) | Yes |
| OSS PR review comment | Yes |
| KB article body destined for publication | Yes |
| Postmortem published to public site | Yes |
| Newsletter / changelog entry | Yes |
| Internal Slack ping to your team | No |
| Internal ticket note (admin-side only) | No |
| Bead body (br/beads) | No |
| Triage workspace artifacts (drafts, working notes) | No |
| Audit-log entries | No |
| AI-agent's own scratch reasoning | No |

When in doubt: run `/de-slopify`. The cost of running it on something internal is one extra second; the cost of *not* running it on something customer-facing is permanent trust damage.

---

## Cross-References

- [SKILL.md](../SKILL.md) §"The Confirmation Rule" — the parallel non-negotiable gate
- [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) — the 🧹 DE-SLOPIFY operator card
- [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md) — inline fallback list of AI-tells
- [COMMUNICATION-CRAFT.md](COMMUNICATION-CRAFT.md) — voice-aware phrasing templates
- [AI-AUTO-RESPONSE-GOVERNANCE.md](AI-AUTO-RESPONSE-GOVERNANCE.md) — agent auto-send tier rules
- [SKILL-INSTALLATION.md](SKILL-INSTALLATION.md) — full bootstrap flow including jsm
- [QA-SHADOW-REVIEW.md](QA-SHADOW-REVIEW.md) — QA sampling that verifies the pass actually fired
- `scripts/check-skills.sh` — REQUIRED-flag enforcement
- `scripts/install-referenced-skills.sh` — installs REQUIRED before optional
