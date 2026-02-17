---
name: typography-web
description: |
  Generate beautiful, typography-focused web pages and visualizations. Creates
  self-contained HTML with professional typography (Practical Typography rules),
  dark/light themes, Mermaid diagrams, Chart.js charts, KPI dashboards, timelines,
  and responsive layouts. Use when the user asks to create a web page, landing page,
  documentation site, portfolio, diagram, dashboard, or any HTML visualization.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
---

# Typography Web — Generate Beautiful Web Pages

## When to Activate

Activate this skill when the user asks to:
- Create a web page, landing page, or website
- Design a portfolio, blog, or documentation site
- Generate an HTML page for any content
- Build a single-page site or article layout

Also activate when the user mentions: "make it look good", "professional layout", "clean design", "typography", "readable".

Additionally activate for visualization requests:
- Diagrams, flowcharts, architecture overviews
- Data dashboards or KPI displays
- Any table with 4+ rows or 3+ columns (generate HTML, not ASCII)
- Sequence diagrams, ER diagrams, state machines
- Timelines, before/after comparisons
- Charts (bar, line, pie, doughnut)

## Before You Begin

1. **Read the references** — always read these before generating:
   - `references/typography-rules.md` — typographic rules and measurements
   - `references/css-patterns.md` — reusable CSS patterns and palettes
   - `references/visualizations.md` — diagrams, charts, and interactive components (read when the page needs diagrams, data visualizations, architecture overviews, or dashboards)

2. **Choose an aesthetic direction** — don't default to the same look every time. Consider:
   - **Paper & Ink** — warm cream, dark brown, serif body, editorial feel
   - **Editorial** — cool white, deep blue accent, clean sans-serif
   - **Modernist** — high contrast, geometric, single bold accent
   - **Forest** — warm naturals, sage greens, organic feel
   - **Dusk** — dark backgrounds, warm text, amber highlights

   Pick based on the content type: portfolios suit Paper & Ink or Dusk; docs suit Editorial or Modernist; blogs suit Paper & Ink or Forest.

3. **Choose fonts** — pick a Google Fonts pairing. Examples:
   - Playfair Display + Source Serif 4 (editorial/magazine)
   - Inter + Inter (clean/technical, vary by weight)
   - Libre Baskerville + Montserrat (warm/professional)
   - IBM Plex Sans + IBM Plex Serif (technical/structured)
   - Crimson Pro + Manrope (literary/modern)

## Generation Workflow

### Step 1: Plan Structure
Determine the page sections based on content. Common patterns:
- **Article**: hero → body prose → optional sidebar → footer
- **Portfolio**: hero → work grid → about → contact
- **Documentation**: sidebar nav → content area with sections
- **Landing page**: hero → features → testimonials → CTA → footer
- **Architecture/diagram**: hero → diagram(s) → explanatory prose → details
- **Dashboard**: KPI cards → charts → data tables → details

### Step 1b: Choose Visualization Approach (if applicable)
When the page includes diagrams, charts, or data:
- **Flowcharts, sequences, ER, state machines, mind maps** → Mermaid.js (with ELK for complex layouts)
- **Architecture overviews (text-heavy)** → CSS Grid cards with flow arrows
- **Architecture overviews (topology)** → Mermaid for automatic edge routing
- **Data tables (4+ rows or 3+ cols)** → HTML `<table>` with tabular figures
- **Bar/line/pie/doughnut charts** → Chart.js
- **KPI dashboards** → CSS Grid with KPI cards + optional Chart.js
- **Timelines** → CSS central-line pattern
- **Before/after comparisons** → CSS Grid side-by-side panels
- **Complex choreographed animations (10+ elements)** → anime.js
- **Simple staggered entrances** → CSS-only with `--i` delay variable

All visualization libraries load from CDN. Pages remain self-contained.

### Step 2: Generate Self-Contained HTML
Create a single .html file with ALL CSS embedded in a `<style>` tag. No external stylesheets except Google Fonts `<link>`.

Required elements in every page:
```html
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Page Title</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=...&display=swap" rel="stylesheet">
  <style>/* All CSS here */</style>
</head>
```

### Step 3: Implement Typography Rules
Every page MUST follow these non-negotiable rules:
- Body text: 15–25px (use clamp() for fluid)
- Line height: 1.3–1.45 (unitless)
- Line length: max-width 65ch on prose containers
- Text color: dark gray, not pure black (light mode)
- Generous margins and whitespace
- Proper heading hierarchy (max 3 levels, minimal size jumps)
- Curly quotes in all content (" " ' ')
- Proper em dashes (—) and en dashes (–)
- Single space between sentences
- Bold OR italic for emphasis, never both
- font-kerning: normal

### Step 4: Add Theme Toggle
Every page includes a dark/light theme toggle:
- Sun/moon icon button, fixed position (top-right)
- Respects prefers-color-scheme as default
- Persists choice to localStorage
- Smooth transition on toggle (0.3s)

### Step 5: Ensure Responsiveness
- Test mentally at 320px, 768px, 1440px
- Sidebar layouts collapse to single column on mobile
- Margins reduce but never disappear on small screens
- Font sizes scale down slightly on mobile

## Output

Save generated files to `~/.claude/output/web/` with a descriptive filename.

After saving, tell the user the file path and suggest they open it in a browser.

## Quality Checks

Before finishing, verify:

1. **Squint test** — if you blur your eyes, can you perceive the visual hierarchy?
2. **Line length test** — is body text staying within 45–90 characters per line?
3. **Both-theme test** — does the page look good in both light and dark mode?
4. **The "is it generic?" test** — would this page look the same if you swapped in different content? If yes, add more character
5. **Typography audit** — are all quotes curly? Are dashes proper? Is emphasis restrained?

## Anti-Patterns to Avoid

- Pure black text on pure white background
- Body text smaller than 15px
- Lines longer than 90 characters
- Centered body text
- Underlining anything except links
- Bold AND italic together
- All-caps for more than a few words
- More than 3 heading levels
- Heading sizes that jump dramatically (e.g., 18px body → 36px h1)
- Using color for non-clickable text decoration
- Flat, monochrome designs without any accent
- Default browser link styling (bright blue underlined)
