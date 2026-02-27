# Web Design Principles

## Color (OKLCH)

All colors must use `oklch(lightness chroma hue)`. Never use hex, hsl(), or rgb().

- **Lightness** (0–1): perceptual brightness. L 0.98 = near white, L 0.14 = dark bg, L 0.10 = near black text
- **Chroma** (0–0.4): saturation. 0 = neutral gray, 0.02 = subtle tint, 0.15+ = vivid
- **Hue** (0–360°): color family. Orange ≈ 44, Red ≈ 22, Green ≈ 152, Blue ≈ 255, Purple ≈ 300
- **Alpha**: `oklch(0.70 0.175 44 / 0.5)` for 50% opacity

### OKLCH Design Rules
- Body text: L ≈ 0.10–0.22 (light mode), L ≈ 0.90–0.95 (dark mode) — never pure 0 or 1
- Backgrounds: L ≈ 0.97–0.99 (light), L ≈ 0.13–0.16 (dark)
- Card/surface: background ± 0.04–0.06 L
- Border: background ± 0.08–0.12 L, same H, low C
- Accent: 0.08+ C to be visible; same H family as brand
- Shadows: `oklch(0 0 0 / 0.08)` not `rgba(0,0,0,0.08)`
- Gradients: always use `in oklch` → `linear-gradient(135deg in oklch, ...)`
- `color-mix`: use `in oklch` → `color-mix(in oklch, var(--accent) 20%, transparent)`
- Semantic roles every page needs: `--bg-primary`, `--bg-secondary`, `--bg-tertiary`, `--text-primary`, `--text-secondary`, `--text-tertiary`, `--accent`, `--accent-hover`, `--border`, `--border-subtle`, `--shadow`

## Typography

### Body Text
- Font size: 15–25px (use CSS clamp(): `clamp(1rem, 0.9rem + 0.5vw, 1.25rem)`)
- Line height: 1.3–1.45 (unitless)
- Line length: 45–90 characters per line (`max-width: 65ch`)
- Font: Professional Google Fonts. Avoid Times New Roman, Arial
- Good body fonts: Source Serif 4, Libre Baskerville, Literata, Inter, Source Sans 3

### Headings
- Maximum 3 levels; 2 is preferable
- Minimal size increase from body (body 18px → h2 20–22px → h1 24–28px)
- Space above/below is the primary separator (`margin-top: 2em; margin-bottom: 0.5em`)
- Bold is optional — size + space is often enough
- Never underline headings; suppress hyphenation (`hyphens: none`)
- Don't center headings except in hero/decorative contexts

### Font Selection
- System sans: `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`
- System serif: `Charter, 'Bitstream Charter', 'Sitka Text', Cambria, serif`
- System mono: `'JetBrains Mono', 'Fira Code', 'Source Code Pro', monospace`
- Google Fonts pairings:
  - Editorial: Playfair Display (headings) + Source Serif 4 (body)
  - Clean: Inter (headings + body, different weight)
  - Warm: Libre Baskerville (body) + Montserrat (headings)
  - Technical: IBM Plex Sans (headings) + IBM Plex Serif (body)
  - Developer: Outfit (headings) + Space Mono (code/accent)

### Paragraphs & Spacing
- Single space between sentences (never double)
- Space between paragraphs (`margin-bottom` on `p`) OR first-line indent — never both
- Enable kerning: `font-kerning: normal; text-rendering: optimizeLegibility`

### Emphasis
- Bold OR italic — never both simultaneously
- Never underline except for links
- All caps: only for very short text (labels, buttons) + `letter-spacing: 0.06–0.12em`
- Use sparingly — if everything is bold, nothing is

### Punctuation
- Curly quotes: " " ' ' (not straight)
- Em dash: — (not --)
- En dash: – (for ranges)
- Ellipsis: … (not ...)
- Apostrophe curves downward: '

## Layout & Spacing

### Spacing Scale
Use multiples of 0.5rem for all spacing. Suggested scale:
- `--space-xs: 0.5rem` — tight gaps, badge padding
- `--space-sm: 1rem` — list items, small component padding
- `--space-md: 1.5rem` — section padding, card padding
- `--space-lg: 2rem` — between major elements
- `--space-xl: 3rem` — section gaps
- `--space-2xl: 4–6rem` — hero padding, major section breaks

### Container Widths
- Prose: `max-width: 65ch` or `680px`
- Wide content: `max-width: 960px`
- Full layout: `max-width: 1200–1440px`
- Padding: `clamp(1.5rem, 5vw, 4rem)` for fluid horizontal padding

### Visual Hierarchy
- The squint test: blur your eyes — hierarchy should be readable as shapes and weights
- Use size, weight, and space for hierarchy; color is secondary
- Heavier elements (darker, larger) anchor the eye; lighter elements recede
- Whitespace is active design — use it to group and separate

## Interactivity & Motion

### Hover States
- Interactive elements must have visible hover feedback
- Subtle scale (`scale(1.02)`), shadow increase, or background shift
- Transition duration: 0.15s (fast) to 0.3s (base)

### Theme Toggle
- Every page gets a dark/light toggle (sun/moon icon, fixed top-right)
- Initialize from `localStorage` → fallback to `prefers-color-scheme`
- Persist to `localStorage` on change
- Transition: `background-color 0.3s ease, color 0.3s ease, border-color 0.3s ease`

### Entrance Animations
- CSS-only stagger with `--i` custom property for simple reveals
- anime.js for choreographed sequences with 10+ elements
- Always guard: `@media (prefers-reduced-motion: reduce)` disables all animations

## Tables & Data

- Tabular figures: `font-variant-numeric: tabular-nums` on numeric columns
- Right-align quantities (numbers with units)
- Sticky headers for scrollable tables
- Alternating rows: `color-mix(in oklch, var(--bg-secondary) 50%, transparent)`
- Don't pad with trailing zeros (98, not 98.000)

## Responsive Design

- `clamp()` for fluid typography and spacing
- Reduce margins on small screens, never eliminate
- Stack sidebar layouts to single column below 768px
- Test mentally at 320px, 768px, 1024px, 1440px

## Accessibility

- Minimum contrast ratio 4.5:1 for body text (WCAG AA)
- Minimum 3:1 for large text (≥24px or ≥18.66px bold)
- Use `rem`/`em` not `px` for font sizes
- `prefers-reduced-motion` respected for all animations
- Semantic HTML: real headings, tables, lists — not divs
- Visible focus styles (`outline: 2px solid var(--accent); outline-offset: 2px`)
- Skip links for keyboard navigation
- ARIA labels on icon-only buttons
