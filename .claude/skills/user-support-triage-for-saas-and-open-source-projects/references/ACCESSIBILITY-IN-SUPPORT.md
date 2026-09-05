# Accessibility In Support — WCAG-Aware Replies And Channels

Support communications go to customers using screen readers, magnifiers, voice control, switch-access devices, with cognitive disabilities, with low literacy, with limited bandwidth. Treating support as "just text" misses that the *form* of the text — formatting, contrast, density, structure — is part of accessibility. This file is the discipline.

> **Core insight:** the same content that lands fine for a sighted reader on a desktop with a fast connection can be unusable for the same customer on the same day in a different context (commuting, screen reader, low vision, low literacy English-as-second-language). Accessibility is contextual; designing for the worst case improves the average.

This file complements `INTERNATIONALIZATION-AND-LOCALE.md` (different axis: cultural calibration) and the existing `COMMUNICATION-CRAFT.md` (which is about *what* to say). This file is about *how* to format and *which channels* to use.

---

## The Standards Framework

| Standard | Scope |
|---|---|
| **WCAG 2.2 AA** | Web/web-equivalent content; many jurisdictions reference it |
| **ADA Title III** | US private commercial websites; case law extends to web |
| **EN 301 549** | EU procurement-and-public-sector accessibility; rapidly extending to private |
| **Section 508** | US federal procurement (relevant if you sell to US government) |
| **EAA (European Accessibility Act)** | Member-state implementation by 2025; expanding scope |

Most projects don't have the legal obligation, but the *patterns* that satisfy WCAG also satisfy good support communication. Adopt them by default.

---

## Reply-Formatting Patterns (WCAG-Aligned)

### Plain-text-first

Many support emails are read in plain-text-only environments: terminal mail clients, screen readers, low-bandwidth contexts, automated forwarding. Patterns:

| Don't | Do |
|---|---|
| HTML-heavy email with images for buttons | Plain text with explicit URLs in parentheses |
| `<table>` for layout | Linear paragraph structure |
| Decorative emoji as bullets | Hyphens or asterisks for bullets |
| Color-coded text ("the red part") | Words to indicate emphasis or role |
| Inline images of error messages | Quote the error text + describe (alt-text equivalent) |
| Long URLs without explanation | Explanatory text + URL |

A useful test: paste your draft into a plain-text editor. Is it still legible and actionable? If layout falls apart, it's an accessibility risk.

### Structure with semantic headers

For longer replies (>3 paragraphs), use semantic structure:

```
Quick answer: [the TL;DR in one line]

What happened
[paragraph]

What we did
[paragraph]

What you should do
1. [step]
2. [step]

If this doesn't fix it
[escalation path]
```

Semantic headers help screen-reader navigation (jump-by-heading), help busy readers skim, help re-readers find what they came back for. They also signal calm clarity, which is its own communication win.

---

### Sentence and paragraph length

Plain-language guidance for accessibility (and for ESL readers):

- Sentences ≤ 20 words where possible
- Paragraphs ≤ 5 sentences
- Active voice ("We refunded the charge") not passive ("The charge has been refunded")
- One idea per paragraph
- Avoid jargon without explanation; define on first use

The `de-slopify` skill catches the obvious AI-ese; the WCAG/plain-language pass catches density.

### Link descriptions

Don't say "click here". Don't say "this link". Say what's at the link:

| Don't | Do |
|---|---|
| "Click [here] to reset your password." | "Reset your password: [URL]" |
| "Read more [here]." | "Full instructions are in our docs: [URL]" |
| "Update your billing [here]." | "Update billing information at [URL]" |

Screen readers often read out a list of all links in an email. "click here, click here, here, here" is unparsable; descriptive link text is.

### Images and screenshots

If the agent attaches a screenshot:

- Provide alt-text describing what the image shows ("Screenshot of the error: 'API rate limit exceeded' on the integrations page")
- Don't rely on the image alone; quote the text in the image in the body
- For UI walkthroughs, prefer numbered text steps over a series of screenshots

Customer-supplied images: the agent should describe them in the investigation log so a non-visual re-reader can follow.

### Tables in email

Tables in email render unpredictably. If you must use one:
- Use simple HTML tables, not nested tables for layout
- Provide a plain-text equivalent ("In short: $40.00 charged on March 4, refunded today, transaction ref XYZ")
- For data, prefer a list-of-fields ("Charge: $40.00; Date: March 4; Status: Refunded; Ref: XYZ")

---

## Channel Considerations

| Channel | Accessibility considerations |
|---|---|
| **Email** | Most accessible default; supports plain-text fallback |
| **In-app chat widget** | Must be keyboard-navigable, screen-reader-labelled, focus-visible; many widgets fail |
| **Phone** | Hearing-impaired customers cannot use; provide TTY or chat alternative |
| **Video call** | Captions / transcript required; signed-language interpretation if requested |
| **Slack / Discord shared support** | Highly variable accessibility per client; avoid as primary support |
| **In-product modal "support assistant"** | Often the worst offender; modal traps focus; AT support uneven |
| **PDF transcripts / receipts** | Tagged-PDF accessibility is hard to get right; prefer HTML or plain text |

For accessibility-flagged customers (see signals below), default to *email + plain-text alternative*.

---

## Detecting Accessibility-Relevant Signals

The customer may not announce a disability. Signals that change the right format:

| Signal | What it suggests |
|---|---|
| Customer mentions screen reader, JAWS, NVDA, VoiceOver | Use plain-text-friendly formatting |
| "I can't see", "I'm blind", "low vision" | Same |
| Replies extracted from a screen-reader output (voice-typed errors) | Same |
| "I have dyslexia" / "easier in plain language" | Plain-language pass; shorter sentences |
| Cognitive disability mentioned | Sequential structure; one task at a time |
| Reply from TTY service ("USR1 SK [text] GA") | TTY format awareness |
| Customer using switch access (slow, terse replies) | Don't ask for long-form follow-ups; one question at a time |
| Mention of disability accommodations | Often signals broader accessibility needs in the relationship |
| Account flag in `05-policies.md` (project-set accommodation flag) | All replies through accessible-formatted channel |

**Critical**: never ask for "proof" of disability, never gatekeep accessibility accommodations behind verification. The cost of unnecessarily-given accommodation is near-zero; the harm of denied-or-questioned accommodation is significant.

---

## Replying To Accessibility-Specific Tickets

Some tickets ARE about accessibility (the product is inaccessible to the customer). These are high-stakes:

```
[OPERATOR-LOCAL: Accessibility-Issue-Reported]
1) Take it seriously. "It works for me" is the wrong response;
   accessibility regressions are real bugs.
2) Reproduce with at least one assistive technology.
   - Common: macOS VoiceOver, Windows NVDA (free), browser
     keyboard-only navigation
3) Cite specific WCAG criterion if applicable
   ("the modal in question is failing 2.1.2 No Keyboard Trap")
4) Bead with `accessibility` label; treat severity as engineering
   would treat a security finding (high) not a bug (medium).
5) Reply with timeline; don't promise dates that won't ship.
6) Don't apologize-and-do-nothing. Even "we know; here's our
   accessibility roadmap" is better than "we'll look into it".
```

Accessibility tickets have a higher-than-average likelihood of legal escalation. The right answer is to fix the bug, communicate honestly, and credit the reporter.

---

## Cognitive Accessibility / Plain Language

Distinct from screen-reader accessibility but often conflated. Plain-language patterns:

| Patterns | Example |
|---|---|
| Front-load the answer | "Yes, you can have a refund." [reasoning follows] |
| Define unfamiliar terms | "API key (the secret token that authenticates your requests)" |
| Avoid double negatives | "We will refund you" not "we will not deny the refund" |
| Use concrete numbers | "in 3 business days" not "shortly" |
| One concept per sentence | Split compound sentences |
| Active voice | "We charged your card" not "Your card was charged" |
| Examples | "Like when you get a duplicate notification" |

The `de-slopify` skill is adjacent — strips AI-ese — but plain-language goes further: simplifying syntax for cognitive load.

---

## The Format-Test

A useful pre-send check:

```
[OPERATOR-LOCAL: ♿ A11Y format pass]
1) Plain-text version: paste reply into a plain text editor.
   - Does it still flow?
   - Is the structure clear without HTML?
2) Read-aloud test: read first 3 sentences out loud.
   - Does it sound natural?
   - Is the answer in the first sentence?
3) Link audit: every URL has descriptive text?
4) Image audit: any image has both alt-text and a body
   description of its content?
5) Length audit: avg sentence ≤ 20 words?
6) Jargon audit: any technical term is explained on first use?

If any check fails, revise.
```

This adds ~30 seconds to a draft but catches the most common accessibility regressions before send.

---

## Documentation And KB Accessibility

The KB articles that the project links from support replies must themselves be accessible:

- HTML pages with semantic structure (h1 → h2 → h3 hierarchy)
- Alt text on images
- Descriptive link text
- Reading level appropriate to audience (Hemingway score / Flesch-Kincaid)
- Keyboard-navigable
- Sufficient color contrast
- Captioned videos / transcripts
- No information-by-color-alone

If KB pages aren't accessible, support replies that link to them transitively fail. KB authoring (`KB-FEEDBACK-LOOP.md`) should bake the accessibility tests into the publish pipeline.

---

## When Accessibility Issues Become Compliance Issues

Some triggers escalate accessibility tickets to legal:

| Trigger | Why |
|---|---|
| Customer cites WCAG criterion + threats of legal | Likely consulting with disability-rights advocate; route counsel |
| Customer is a federal contractor / public-sector | EAA / Section 508 / EN 301 549 obligations on YOU as supplier |
| Pattern of reports across many users | Class-action-shape risk |
| Customer uses ADA / EAA / accessibility-statute language | Legal-hold mode (per `EVIDENCE-CHAIN-OF-CUSTODY.md`) |

For these, Pipeline U (regulator/legal) applies. The accessibility issue itself still gets fixed, but the comms go through counsel.

---

## How This File Plugs In

| Used by | How |
|---|---|
| ♿ A11Y operator | Pre-send format pass |
| ✉ DRAFT operator | Format hygiene |
| KB-FEEDBACK-LOOP.md | KB accessibility hygiene |
| 04-templates/ | Plain-text-first templates |
| 02-channels.md | Note channel accessibility considerations |
| 05-policies.md | Accommodation flags; counsel-route triggers |

---

## Cross-References

- [COMMUNICATION-CRAFT.md](COMMUNICATION-CRAFT.md) — content patterns
- [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md) — register
- [INTERNATIONALIZATION-AND-LOCALE.md](INTERNATIONALIZATION-AND-LOCALE.md) — orthogonal axis
- [DEFLECTION-AND-SELF-SERVICE.md](DEFLECTION-AND-SELF-SERVICE.md) — KB accessibility
- [EVIDENCE-CHAIN-OF-CUSTODY.md](EVIDENCE-CHAIN-OF-CUSTODY.md) — accessibility-as-legal-issue path
