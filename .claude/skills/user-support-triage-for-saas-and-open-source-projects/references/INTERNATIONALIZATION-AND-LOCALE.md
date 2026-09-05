# Internationalization & Locale — Beyond Translation

Most "internationalization" in support means running text through Google Translate. That handles ~30% of the work. The remaining 70% is *locale-specific calibration*: apology norms, formality registers, time-zone awareness, jurisdiction-specific privacy obligations, currency display, holidays, working week. This file is the discipline of triaging in a way that doesn't accidentally insult or confuse a customer because of cultural defaults.

> **Core insight:** the same English-translated reply that lands warmly in San Francisco can read as patronising in Tokyo, dismissive in Paris, or insufficiently apologetic in Seoul. Locale awareness is a quality dimension, not a courtesy.

This file complements the existing `🌐 TRANSLATE` operator (which handles the literal language step) and `VOICE-CALIBRATION.md` (which captures brand voice). Together they govern the cross-cultural register.

---

## What "Locale" Includes

| Dimension | Examples |
|---|---|
| **Language** | en-US, fr-FR, ja-JP, pt-BR, zh-CN, etc. |
| **Script direction** | LTR (Latin, Cyrillic), RTL (Arabic, Hebrew), TTB (some Mongolian, vertical Chinese) |
| **Apology / face culture** | Higher in Japan/Korea/Saudi; lower in Netherlands/Sweden |
| **Power distance** | Higher → expect formal honorifics; lower → "Hey, James" works |
| **Time format** | 12h vs 24h; week starts Sun vs Mon vs Sat |
| **Date format** | YYYY-MM-DD vs DD/MM/YYYY vs MM/DD/YYYY |
| **Currency display** | $1,000.00 vs 1.000,00 € vs ¥1,000 |
| **Working week** | Mon-Fri (most), Sun-Thu (Israel/some Gulf), Sat-Wed (Iran) |
| **Holiday calendars** | Different per country, sometimes per region |
| **Jurisdiction-specific privacy** | GDPR (EU), CCPA (CA), LGPD (Brazil), PIPEDA (Canada), POPIA (South Africa), PIPL (China) |
| **Communication norms** | Direct (Germany/Israel) vs Indirect (Japan/UK) vs Relational (Latin America) |

A reply needs to be *correct* on language and *calibrated* on the rest.

---

## The Apology Spectrum Across Cultures

`CUSTOMER-PSYCHOLOGY.md` has the apology spectrum for a single culture (American/Western default). Across cultures the calibration shifts:

| Culture | Apology default | What over-apology reads as | What under-apology reads as |
|---|---|---|---|
| US default | Calibrated to harm | "Lawyering" / weak | Cold / corporate |
| UK | Slightly higher than US | Sycophantic | Rude |
| Germany | Slightly lower than US | Insincere | Acceptable / direct |
| Netherlands | Lower than US | Performative | Acceptable / direct |
| France | Formal apology phrasing matters | Excessive | Disrespectful |
| Japan | Significantly higher than US; formal apology multi-stage | Weak (single short apology) | Severely disrespectful |
| Korea | Higher than US; formal | Acceptable | Disrespectful |
| Brazil | Warmer + more relational | Cold | Aloof |
| India | Higher + relational | Tolerable | Cold |
| Saudi / UAE | Formal honorifics matter; apology framed via face-saving | Acceptable | Disrespectful |
| China | Calibrated; direct fix-focus often valued over apology | Verbose | Acceptable in some contexts |

**Implication for triage:** the "specific apology + responsibility + next step" structure from `COMMUNICATION-CRAFT.md` is the bones; the *length, formality, and framing* of each part flexes by locale.

For a Japan-locale customer with a billing error:
- Three levels of apology rather than one (initial, with-explanation, with-action)
- Use of formal language register (敬語); don't drop into casual mid-reply
- Hierarchical signing (named individual + role/title) rather than just first-name

For a Netherlands-locale customer with the same billing error:
- Single direct apology
- "Here's what happened, here's the fix" structure
- Less honorific framing; the customer wants the answer, not the ceremony

---

## Locale-Specific Privacy Obligations

The big ones to know (project-specific obligations belong in `05-policies.md`):

| Regulation | Jurisdiction | Notable triage rule |
|---|---|---|
| GDPR | EU/EEA + UK in spirit | Identity verify before disclosure; 30-day SLA on DSAR; right of erasure with documented exceptions |
| CCPA / CPRA | California residents | "Do Not Sell/Share" is a live concept; affects support ML |
| LGPD | Brazil | Largely GDPR-shaped; Portuguese-language obligations |
| PIPEDA | Canada | Consent + reasonable purpose; provincial overlays |
| POPIA | South Africa | Lower threshold for "processing"; enforcement growing |
| PIPL | China | Cross-border transfer restrictions; many SaaS fail audit |
| PDPA | Singapore | Consent-based; data-protection officer obligations |
| HIPAA | US healthcare-adjacent | If even *touching* PHI, support is in scope |

`runbooks/GDPR-DSAR.md` and `runbooks/CCPA.md` already exist for the two big ones. Locales not covered should at minimum: detect the customer's residency, route DSAR-shaped requests to a counsel-cleared path, and never silently apply California rules to a German customer or vice versa.

---

## Time-Zone Awareness

A real failure mode: customer in Tokyo writes Friday 17:00 JST; SF-based support sees it Friday 00:00 PST and replies Monday 09:00 PST = Tuesday 02:00 JST = customer waited 81 hours wondering. Patterns:

- **Display the customer's timezone explicitly in the ticket.** Not just timestamp; their TZ.
- **For replies that promise an ETA, give it in the customer's timezone.** "By Friday 5pm your time" beats "by EOD" or "by tomorrow".
- **Recognise long-tail timezones.** A customer with timestamps suggesting JST may be on holiday during Golden Week (late April / early May) — don't expect immediate replies.
- **For SLA-bound work, declare the working calendar.** "Business hours" is meaningless without specifying which calendar — Sun-Thu Israeli, Sat-Wed Iranian, Mon-Fri most others.
- **Avoid "by tomorrow" without a date.** Different timezones → different "tomorrow".

The `🚦 PAUSE-SLA` operator should show the SLA in the customer's timezone when promising follow-up timing.

---

## Currency, Number, And Date Formatting

A specific small thing that signals competence:

| Don't | Do |
|---|---|
| "I'll refund $40" to a German customer | "I'll refund 40 € (≈ $43 at today's rate)" if billing was in EUR |
| "March 4" to anyone outside the US | "4 March" or "2026-03-04" |
| "next week" to anyone | "the week of 2026-03-09" |
| "1,000" to a French customer | "1 000" (space) or "1.000" (period) per locale |
| Stripped accents in their name | Their name as they wrote it |

For drafts going to non-en-US locales, a quick formatting pass is part of `🌍 LOCALE-AWARE`. The specifics live in `08-voice.md` per-locale extension.

---

## Right-To-Left Languages

Arabic, Hebrew, Persian, Urdu, and others are RTL. In support contexts:

- The customer may receive support emails through clients that don't render RTL well (especially older webmail). A fallback to plain RTL Unicode + clear paragraph breaks is safer than HTML-formatted bullets.
- If your support tooling has any UI that displays the conversation, RTL must reflow correctly. RTL-bug screenshots in tickets are a strong signal that engineering hasn't tested.
- Mixing LTR/RTL in the same paragraph (e.g., English brand name in Arabic sentence) needs Unicode bidi marks or it renders confusingly.
- When the customer is using a name that contains both scripts, copy-paste verbatim; do not "normalise".

---

## Translation Mechanics And Their Failures

Common mistakes when running drafts through translation:

| Mistake | Result | Mitigation |
|---|---|---|
| Translating English idioms literally | "Bouncing off Tom for review" → garbled | Strip idioms before translating |
| Trusting machine translation for legal-flavored text | Subtly wrong meaning in jurisdiction-specific contract phrasing | Counsel-cleared phrasing per locale |
| Single-shot translate without round-trip | No quality check | Translate to target → translate back → does it match? |
| Auto-detection guessing wrong language | Reply in Spanish to a Portuguese-speaking Brazilian | Explicitly capture locale during signup; don't infer from text |
| Polite formal English → polite-flat target | Loses the careful register | Pre-mark the register in the prompt; verify post-translation |
| Long English email → long target email | Some languages take ~30% more or fewer words | Allow length variation; don't force parity |

For `🌐 TRANSLATE` with high-stakes content (refund decline, legal-flavoured), the workflow should include: (a) machine translate, (b) human native-speaker review where available, (c) round-trip back-translation as a sanity check. For volume routine content, machine translate + clear "machine-translated; please reply with corrections" disclaimer is acceptable.

---

## Native-Speaker QA

Where possible, support replies in non-default languages should be reviewed by a native speaker before send for the first 50 sends per template per locale. After that, the template is "calibrated" and machine translation is OK for new instances. Calibration is per-template, not per-language — a template might calibrate fine for Japanese but need re-review for Korean despite both being grouped as "East Asian" in some product taxonomies.

For projects without native-speaker support staff:
- Hire freelance reviewers per high-volume locale (Upwork / Fiverr / native communities)
- Open-source: ask the contributor community for native-speaker review of release-note translations
- Worst case: clearly disclose "machine-translated" and provide an English fallback with "reply in English if my translation is unclear"

---

## Cultural Misfires To Avoid

Specific patterns observed from real support corpora:

| Misfire | Locale | What to do instead |
|---|---|---|
| First-naming a customer in Japan / Korea | JP, KR | Use surname + honorific (-san, -씨) until invited otherwise |
| "Cheers" sign-off in non-UK English | DE, FR, NL, etc. | "Best regards" or locale-appropriate equivalent |
| Excessive emoji 🙏✨🎉 | DE, JP-business, formal contexts | Strip; tone is the wrong register |
| US-style direct decline ("No, we can't do that") | JP, KR, IN | Frame in terms of capacity ("we are not able to at this time") |
| US-style breezy positivity ("Awesome!") | DE, NL | Sounds insincere; trim |
| References to "the holidays" assuming Christmas | global | Be explicit ("end of year", "December break") |
| Time references like "Monday morning" without zone | global | Always zone-explicit |
| Currency assumed USD | non-US customers | Always currency-explicit |
| Address format assumed US | global | Don't request "state and zip"; request locale-appropriate fields |

---

## When Locale Affects Compensation

The four-dial frame from `COMPENSATION-CALCULUS.md` works across locales, but the *currency* of compensation calibrates:

- **Cash refunds in customer's currency**, never converted "for convenience" without saying so
- **Credit denominated in their plan's billing currency**
- **Plan upgrades**: same regardless of locale
- **Goods (swag, etc.)**: shipping international can erase value; consider equivalent local options
- **Apology weight (band): often higher** for collective-cultures / high-power-distance contexts

A useful rule: if you would offer a 1-month credit to a US customer, offer the *same duration* (not the same dollar value) to an international customer. Duration scales right; converted-and-rounded dollar amounts often feel arbitrary.

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🌍 LOCALE-AWARE operator | The pre-send calibration |
| 🌐 TRANSLATE operator | The literal language step (existing) |
| 🎙 VOICE-MATCH operator | Per-locale voice extension to `08-voice.md` |
| 🎁 GOODWILL operator | Currency / duration calibration |
| Pipeline F (GDPR DSAR) | Imports per-locale privacy obligations |
| 05-policies.md | Per-locale routing, honorifics, working calendar |
| 08-voice.md | Per-locale extensions |

---

## Cross-References

- [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md) — base brand voice
- [COMMUNICATION-CRAFT.md](COMMUNICATION-CRAFT.md) — apology / decline structure
- [CUSTOMER-PSYCHOLOGY.md](CUSTOMER-PSYCHOLOGY.md) — apology calibration baseline
- [COMPENSATION-CALCULUS.md](COMPENSATION-CALCULUS.md) — compensation currency
- [runbooks/GDPR-DSAR.md](runbooks/GDPR-DSAR.md)
- [runbooks/CCPA.md](runbooks/CCPA.md)
- [ACCESSIBILITY-IN-SUPPORT.md](ACCESSIBILITY-IN-SUPPORT.md) — orthogonal but related
