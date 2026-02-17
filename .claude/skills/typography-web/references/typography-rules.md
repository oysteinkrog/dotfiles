# Typography Rules for Web Design

## Body Text
- Font size: 15–25px (use CSS clamp() for fluid: clamp(1rem, 0.9rem + 0.5vw, 1.25rem))
- Line height: 120–145% of font size (unitless CSS values: 1.3–1.45)
- Line length: 45–90 characters per line (max-width: 65ch is a good default)
- Font: Use professional or high-quality system fonts. Avoid Times New Roman, Arial
- Recommended Google Fonts for body: Source Serif 4, Libre Baskerville, Literata, Inter, Source Sans 3
- Text color: Use dark gray (#2d2d2d to #3d3d3d) not pure black on screens
- Background: Warm off-white (#fafaf7 to #f5f5f0) not pure white

## Headings
- Maximum 3 levels; 2 is preferable
- Minimal size increase from body (if body is 18px, h2 might be 20-22px, h1 24-28px)
- Use space above and below as primary visual separator (margin-top: 2em, margin-bottom: 0.5em)
- Bold is optional, not required; size + space is often enough
- Never underline headings
- Suppress hyphenation in headings (hyphens: none)
- Don't center headings (except rare cases)

## Margins & Whitespace
- Generous margins are essential — they enforce proper line length
- Web pages need big margins too — text should never touch viewport edges
- Container max-width: 680px for single-column prose (yields ~65 chars at 18px)
- Padding: minimum 1.5rem on sides, more on larger screens
- Bottom margins slightly larger than top for visual balance

## Color
- Body text: dark gray, never pure black on screens
- Reserve color for links (and sparingly)
- When everything is emphasized, nothing is emphasized
- Don't use color on non-clickable text
- Light/dark mode: define semantic CSS custom properties
- For dark mode: light gray text (#e0e0e0) on dark background (#1a1a1a to #222)

## Font Selection
- System font stack: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif
- Serif stack: Charter, 'Bitstream Charter', 'Sitka Text', Cambria, serif
- Monospace: 'JetBrains Mono', 'Fira Code', 'Source Code Pro', 'Cascadia Code', monospace
- Google Fonts pairings:
  - Editorial: Playfair Display (headings) + Source Serif 4 (body)
  - Clean: Inter (headings) + Inter (body, different weight)
  - Warm: Libre Baskerville (body) + Oswald or Montserrat (headings)
  - Technical: IBM Plex Sans (headings) + IBM Plex Serif (body)

## Paragraphs & Spacing
- Single space between sentences (never double)
- First-line indent (1–4x font size) OR space between paragraphs (0.5–1em) — never both
- For web: space between paragraphs is standard (margin-bottom on p)
- Use nonbreaking spaces where needed (&nbsp;)
- Enable kerning: font-kerning: normal; text-rendering: optimizeLegibility

## Emphasis
- Bold OR italic — never both simultaneously
- Never underline except for links
- All caps: only for very short text (labels, buttons), add letter-spacing: 0.05–0.12em
- Small caps: use font-variant: small-caps with slight letter-spacing
- Use emphasis sparingly — if everything is bold, nothing is

## Punctuation
- Use curly quotes (" " ' ') not straight quotes
- Use proper em dash (—) not double hyphens
- Use proper en dash (–) for ranges
- Use proper ellipsis (…) not three periods
- Apostrophes curve downward (')

## Tables & Data
- Use tabular (monospace) figures in data columns: font-variant-numeric: tabular-nums
- Right-align quantities (numbers with units)
- Align at decimal points
- Include commas in all numbers within a column for consistency
- Sticky headers for scrollable tables
- Alternating row backgrounds (subtle: 2-3% opacity difference)
- Don't pad measurements with trailing zeros (98 lbs, not 98.000 lbs)

## Responsive Design
- Use clamp() for fluid typography
- Reduce margins on small screens but never eliminate them
- Stack sidebar layouts to single column below 768px
- Adjust heading sizes proportionally on small screens
- Test at 320px, 768px, 1024px, 1440px viewports

## Accessibility
- Minimum contrast ratio 4.5:1 for body text (WCAG AA)
- Minimum contrast ratio 3:1 for large text (>= 24px or >= 18.66px bold)
- Use rem/em not px for font sizes (allows user scaling)
- Respect prefers-reduced-motion for animations
- Semantic HTML: real headings, real tables, real lists
- Focus styles for keyboard navigation
