# Desktop panel style

The Agenda and Build Queue Plasma widgets sit side by side and share one look. This file
lists the values both copy. Each widget keeps its own copy of the values under the same
names, so a change here goes into both `main.qml` files.

Both widgets take the Plasma style colours (Sweet here) from their fetch script, so these
rules are written against the Kirigami theme roles, not fixed colours.

## Colours and surfaces

| Token | Value | Use |
|---|---|---|
| window | `tintWithAlpha(background, "black", 0.18)` | Window background, a step darker than the cards |
| `tint(a)` | `tintWithAlpha(background, text, a)` | Neutral surfaces and lines |
| card | `tint(0.045)`, border 1 px `tint(0.11)`, radius 6 | Every block of content |
| header band | `tint(0.07)` | Day headers and other bands inside a card |
| line | `tint(0.11)` | Separators and rules |
| accentText | `tintWithAlpha(accent, "white", 0.35)` | Section titles and the few accent words. The Sweet accent is too dark for text on navy |
| `muted(c)` | `hsla(hue, sat × 0.78, min(light, 0.6))` | Every data colour: busy time, running, ok, failed, home |

Calendar dots in the Agenda keep their Google calendar colours.

## Accent: where it goes

- **Section titles** ("Away today", "Running", "Next up") use accentText, DemiBold, at body size.
- **One hero card per widget**. A card with a 3 px bar on the left and a 0.08 tint of the
  bar colour, not a full fill and no coloured border. In the Agenda, the next meeting has an
  accent bar. In the Build Queue, the gate banner has a bar in its state colour (red, amber or
  green).
- **Primary action button**. Accent fill, radius 4: Join in the Agenda. In the Build Queue,
  a priority stepper gets the accent fill only when that session has a rule set. That marks
  a value the owner chose. The text says the step. A stepper with no rule is a flat tool
  button with a muted "–".
- **Accent text for "now"**. A countdown such as "in 10 min", the row of the next meeting
  (a 3 px bar and a 0.08 tint) and the now line.

Body text, day names, table text and icons stay neutral.

## Type

| Token | Value |
|---|---|
| fs | Plasma font × 1.08 |
| fsRow | fs (the Build Queue uses fs × 0.95 for table rows if a table would clip at fs) |
| fsSmall | Plasma small font |
| title | fs × 1.4, Bold |
| section title | fs, DemiBold, accentText |
| muted text | fsSmall, opacity 0.62 |

## Header row

Both widgets start with the same row: the title, muted date or context, `updatedText` in
relative form ("Updated 1 min ago"), a small status dot (`muted(positive)` when fresh,
neutral when stale or failing), and a refresh or warning icon.

## Spacing

Outer margin `largeSpacing × 1.25`, gap between cards `largeSpacing`, card padding
`smallSpacing × 2.5`.
