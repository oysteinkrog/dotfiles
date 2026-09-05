# SLOP-CHECKLIST

Use `/de-slopify` if installed. Otherwise, run drafts through this checklist.

## Banned phrases

- "In today's fast-paced digital landscape…"
- "In an ever-evolving world of…"
- "In the realm of…"
- "Whether you're a [X] or a [Y]…"
- "It's worth noting that…"
- "Look no further."
- "Dive into…"
- "Unlock the power of…"
- "Game-changer / game-changing"
- "Cutting-edge"
- "Revolutionary"
- "Robust" (used vaguely)
- "Seamless / seamlessly"
- "Leverage" (used as a verb of "use")
- "Empower / empowering"
- "Streamline / streamlined"
- "Plethora"
- "Furthermore" / "Moreover" (especially > 1× per section)

## Banned structures

- Conclusion paragraph that restates the introduction.
- Three-of-a-kind generic adjectives ("efficient, scalable, reliable").
- Paragraphs that open with "When it comes to…".
- Bullet lists where every item starts with the same verb-of-the-month.
- TL;DR that is longer than the first paragraph it summarizes.
- Section header followed immediately by a "What is X" definition that re-explains the page topic.
- Links named "click here" or "this article".

## Markers of generated text

- Stacked superlatives.
- Vague hedging ladders ("may help", "can be", "might offer").
- Symmetric or even-paragraph rhythm (every paragraph the same length).
- Citations that read plausibly but go to wrong sources.
- Statistics without dates / units / sources.
- "Studies show…" without naming the study.
- Specific year claims that don't match real publication dates.
- "According to recent research…" with no link.

## What to do instead

| Slop pattern | Replacement |
|---|---|
| "In today's fast-paced digital landscape…" | Drop the whole sentence. Start with the answer. |
| Three-of-a-kind adjectives | Pick one specific claim with proof. |
| Hedging ladder | A direct claim or no claim. |
| "Leverage" | "Use." |
| "Robust" | A measurable property — "handles 10k req/s", "passes SOC 2". |
| "Game-changing" | Show the change with numbers. |
| Conclusion that restates intro | Drop the conclusion. End with the next action. |
| "Studies show…" without link | Name the study and link or remove. |

## Brand-voice checks

- Does the draft sound like the rest of the site?
- Does the draft sound like a specific human wrote it?
- Does the draft sound like the company would say in person?
- Are there original anecdotes, screenshots, or first-hand observations?
- Does the draft cite the SaaS's own product / data / customer evidence?

## Workflow

1. Generate / write draft.
2. Run search for banned phrases (`grep -iE '(seamlessly|game-changing|leverage)'`).
3. Read aloud — anywhere it sounds too smooth is suspect.
4. Verify three-plus unique data points are real, dated, and sourced.
5. Have another human (or `subagents/fresh-eyes-cross-review.md`) read for slop.
6. Re-edit until at least every paragraph carries specific information that another writer could not have produced without the same evidence.

## When the draft is fine

A useful test: print one paragraph and show it to someone in the company who didn't write it. Can they tell:
- What the company does?
- What this page is for?
- One specific claim with evidence?

If yes, ship. If no, edit.
