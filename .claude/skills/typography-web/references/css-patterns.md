# CSS Patterns for Typography-Focused Web Design

A comprehensive reference of reusable CSS patterns for creating beautiful, typography-first web pages. Designed for AI agents to quickly implement professional, accessible designs.

## Theme System

### OKLCH Color Space

All palettes use [OKLCH](https://oklch.fyi/) — a perceptually uniform color model with the syntax `oklch(lightness chroma hue)`:

- **Lightness**: 0–1 (0 = black, 1 = white)
- **Chroma**: 0–0.4+ (0 = gray, higher = more saturated)
- **Hue**: 0–360° (same as HSL hue angle)
- **Alpha**: `/0.5` suffix for transparency

Key advantages over hex/HSL: identical lightness values look visually equal across hues, gradients don't muddy through gray, and chroma can access P3 display gamut on modern screens.

### Complete Custom Property Theme

```css
:root {
  /* Light theme colors — OKLCH */
  --bg-primary: oklch(0.98 0.008 85);
  --bg-secondary: oklch(0.95 0.010 80);
  --bg-tertiary: oklch(0.91 0.013 78);
  --text-primary: oklch(0.22 0.032 55);
  --text-secondary: oklch(0.41 0.025 55);
  --text-tertiary: oklch(0.60 0.018 58);
  --accent: oklch(0.54 0.155 32);
  --accent-hover: oklch(0.46 0.145 32);
  --border: oklch(0.88 0.012 78);
  --border-subtle: oklch(0.93 0.010 80);
  --shadow: oklch(0.22 0.03 55 / 0.08);
  --code-bg: oklch(0.96 0.010 82);

  /* Spacing */
  --space-xs: 0.5rem;
  --space-sm: 1rem;
  --space-md: 1.5rem;
  --space-lg: 2rem;
  --space-xl: 3rem;
  --space-2xl: 4rem;

  /* Typography */
  --font-body: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --font-heading: Georgia, "Times New Roman", serif;
  --font-mono: "SF Mono", Consolas, "Liberation Mono", Menlo, monospace;

  /* Transitions */
  --transition-theme: background-color 0.3s ease, color 0.3s ease, border-color 0.3s ease;
  --transition-fast: 0.15s ease;
  --transition-base: 0.3s ease;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg-primary: oklch(0.15 0.012 50);
    --bg-secondary: oklch(0.19 0.012 50);
    --bg-tertiary: oklch(0.23 0.013 50);
    --text-primary: oklch(0.91 0.012 80);
    --text-secondary: oklch(0.74 0.016 68);
    --text-tertiary: oklch(0.58 0.018 58);
    --accent: oklch(0.67 0.130 36);
    --accent-hover: oklch(0.73 0.120 36);
    --border: oklch(0.28 0.012 50);
    --border-subtle: oklch(0.23 0.012 50);
    --shadow: oklch(0 0 0 / 0.30);
    --code-bg: oklch(0.19 0.012 50);
  }
}
```

### Manual Theme Toggle

```css
[data-theme="dark"] {
  --bg-primary: oklch(0.15 0.012 50);
  --bg-secondary: oklch(0.19 0.012 50);
  --bg-tertiary: oklch(0.23 0.013 50);
  --text-primary: oklch(0.91 0.012 80);
  --text-secondary: oklch(0.74 0.016 68);
  --text-tertiary: oklch(0.58 0.018 58);
  --accent: oklch(0.67 0.130 36);
  --accent-hover: oklch(0.73 0.120 36);
  --border: oklch(0.28 0.012 50);
  --border-subtle: oklch(0.23 0.012 50);
  --shadow: oklch(0 0 0 / 0.30);
  --code-bg: oklch(0.19 0.012 50);
}
```

## Base Typography Reset

```css
*,
*::before,
*::after {
  box-sizing: border-box;
}

html {
  font-size: 100%;
  -webkit-text-size-adjust: 100%;
}

body {
  margin: 0;
  font-family: var(--font-body);
  font-size: clamp(1rem, 0.95rem + 0.25vw, 1.125rem);
  line-height: 1.6;
  color: var(--text-primary);
  background: var(--bg-primary);
  font-kerning: normal;
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  transition: var(--transition-theme);
}

h1, h2, h3, h4, h5, h6 {
  margin: 2em 0 0.5em;
  font-family: var(--font-heading);
  font-weight: 600;
  line-height: 1.2;
  color: var(--text-primary);
  transition: color 0.3s ease;
}

h1:first-child,
h2:first-child,
h3:first-child {
  margin-top: 0;
}

h1 {
  font-size: clamp(2rem, 1.5rem + 2vw, 3rem);
  letter-spacing: -0.02em;
}

h2 {
  font-size: clamp(1.5rem, 1.25rem + 1vw, 2rem);
}

h3 {
  font-size: clamp(1.25rem, 1.125rem + 0.5vw, 1.5rem);
}

h4, h5, h6 {
  font-size: 1.125rem;
}

p {
  margin: 0 0 1.5em;
  max-width: 65ch;
}

a {
  color: var(--accent);
  text-decoration: none;
  transition: color var(--transition-fast);
}

a:hover {
  color: var(--accent-hover);
  text-decoration: underline;
}

a:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
  border-radius: 2px;
}

ul, ol {
  margin: 0 0 1.5em;
  padding-left: 2em;
}

li {
  margin-bottom: 0.5em;
}

blockquote {
  margin: 2em 0;
  padding-left: 1.5em;
  border-left: 4px solid var(--accent);
  font-style: italic;
  color: var(--text-secondary);
}

blockquote p:last-child {
  margin-bottom: 0;
}

hr {
  border: none;
  border-top: 1px solid var(--border);
  margin: 3em 0;
}

img {
  max-width: 100%;
  height: auto;
  display: block;
}

figure {
  margin: 2em 0;
}

figcaption {
  margin-top: 0.5em;
  font-size: 0.875rem;
  color: var(--text-tertiary);
  text-align: center;
}
```

## Layout Patterns

### Single Column Prose

```css
.container {
  max-width: 680px;
  margin: 0 auto;
  padding: 2rem clamp(1.5rem, 5vw, 4rem);
}

.container--wide {
  max-width: 960px;
}

.container--narrow {
  max-width: 540px;
}
```

### Sidebar + Content Layout

```css
.layout-sidebar {
  display: grid;
  grid-template-columns: 240px 1fr;
  gap: 3rem;
  max-width: 1200px;
  margin: 0 auto;
  padding: 2rem;
}

.sidebar {
  position: sticky;
  top: 2rem;
  height: fit-content;
  max-height: calc(100vh - 4rem);
  overflow-y: auto;
}

.sidebar nav ul {
  list-style: none;
  padding: 0;
  margin: 0;
}

.sidebar nav li {
  margin-bottom: 0.5rem;
}

.sidebar nav a {
  display: block;
  padding: 0.5rem 0.75rem;
  border-radius: 4px;
  transition: background-color var(--transition-fast);
}

.sidebar nav a:hover {
  background: var(--bg-secondary);
  text-decoration: none;
}

.sidebar nav a.active {
  background: var(--bg-tertiary);
  color: var(--accent);
  font-weight: 600;
}

@media (max-width: 768px) {
  .layout-sidebar {
    grid-template-columns: 1fr;
    gap: 0;
  }

  .sidebar {
    position: static;
    max-height: none;
    margin-bottom: 2rem;
    padding-bottom: 2rem;
    border-bottom: 1px solid var(--border);
  }
}
```

### Card Grid

```css
.card-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 2rem;
  margin: 2rem 0;
}

.card-grid--dense {
  gap: 1rem;
}

.card-grid--loose {
  gap: 3rem;
}
```

## Component Patterns

### Navigation

```css
.nav-top {
  position: sticky;
  top: 0;
  background: var(--bg-primary);
  border-bottom: 1px solid var(--border);
  z-index: 100;
  transition: var(--transition-theme);
}

.nav-top__inner {
  max-width: 1200px;
  margin: 0 auto;
  padding: 1rem 2rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.nav-top__brand {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--text-primary);
}

.nav-top__links {
  display: flex;
  gap: 2rem;
  list-style: none;
  margin: 0;
  padding: 0;
}

.nav-top__links a {
  color: var(--text-secondary);
  font-weight: 500;
}

.nav-top__links a:hover {
  color: var(--text-primary);
  text-decoration: none;
}

.nav-top__links a.active {
  color: var(--accent);
}
```

### Hero/Header Section

```css
.hero {
  padding: clamp(3rem, 8vw, 6rem) clamp(1.5rem, 5vw, 4rem);
  background: var(--bg-secondary);
  border-bottom: 1px solid var(--border-subtle);
  transition: var(--transition-theme);
}

.hero--full-bleed {
  background: linear-gradient(135deg, var(--bg-secondary) 0%, var(--bg-tertiary) 100%);
}

.hero__inner {
  max-width: 680px;
  margin: 0 auto;
}

.hero__title {
  margin-top: 0;
  margin-bottom: 0.5em;
}

.hero__subtitle {
  font-size: clamp(1.125rem, 1rem + 0.5vw, 1.5rem);
  color: var(--text-secondary);
  margin: 0;
  line-height: 1.4;
}
```

### Pull Quotes

```css
.pullquote {
  font-size: clamp(1.5rem, 1.25rem + 1vw, 2rem);
  font-style: italic;
  font-family: var(--font-heading);
  line-height: 1.4;
  color: var(--text-secondary);
  text-align: center;
  max-width: 600px;
  margin: 3em auto;
  padding: 0 2rem;
  position: relative;
}

.pullquote::before {
  content: '"';
  position: absolute;
  left: 0;
  top: -0.2em;
  font-size: 3em;
  color: var(--accent);
  opacity: 0.3;
}

.pullquote--bordered {
  border-left: 4px solid var(--accent);
  text-align: left;
  padding-left: 2rem;
}

.pullquote--bordered::before {
  display: none;
}
```

### Drop Caps

```css
.drop-cap::first-letter {
  float: left;
  font-size: 3.5em;
  line-height: 0.8;
  padding-right: 0.1em;
  margin-top: 0.05em;
  font-weight: 700;
  color: var(--accent);
  font-family: var(--font-heading);
}
```

### Code Blocks

```css
code {
  font-family: var(--font-mono);
  font-size: 0.9em;
  background: var(--code-bg);
  padding: 0.2em 0.4em;
  border-radius: 3px;
  transition: background-color 0.3s ease;
}

pre {
  background: var(--code-bg);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1.5rem;
  overflow-x: auto;
  margin: 2rem 0;
  transition: var(--transition-theme);
}

pre code {
  background: none;
  padding: 0;
  font-size: 0.875rem;
  line-height: 1.6;
}

.code-block--with-line-numbers {
  counter-reset: line;
}

.code-block--with-line-numbers code {
  display: block;
}

.code-block--with-line-numbers code::before {
  counter-increment: line;
  content: counter(line);
  display: inline-block;
  width: 2em;
  margin-right: 1em;
  text-align: right;
  color: var(--text-tertiary);
  user-select: none;
}
```

### Data Tables

```css
.table-wrapper {
  overflow-x: auto;
  margin: 2rem 0;
  border: 1px solid var(--border);
  border-radius: 8px;
}

table {
  width: 100%;
  border-collapse: collapse;
  font-variant-numeric: tabular-nums;
}

thead {
  background: var(--bg-secondary);
  position: sticky;
  top: 0;
}

th {
  padding: 1rem;
  text-align: left;
  font-weight: 600;
  color: var(--text-primary);
  border-bottom: 2px solid var(--border);
}

th.numeric {
  text-align: right;
}

td {
  padding: 0.875rem 1rem;
  border-bottom: 1px solid var(--border-subtle);
}

td.numeric {
  text-align: right;
}

tbody tr:hover {
  background: var(--bg-secondary);
}

tbody tr:nth-child(even) {
  background: var(--bg-secondary);
  background: color-mix(in oklch, var(--bg-secondary) 50%, transparent);
}

tbody tr:nth-child(even):hover {
  background: var(--bg-secondary);
}

tbody tr:last-child td {
  border-bottom: none;
}
```

### Cards with Depth

```css
.card {
  background: var(--bg-primary);
  border: 1px solid var(--border-subtle);
  border-radius: 8px;
  padding: 1.5rem;
  transition: var(--transition-theme), box-shadow var(--transition-base), transform var(--transition-base);
}

.card--elevated {
  box-shadow: 0 4px 12px var(--shadow);
}

.card--elevated:hover {
  box-shadow: 0 8px 24px var(--shadow);
  transform: translateY(-2px);
}

.card--recessed {
  background: var(--bg-secondary);
  box-shadow: inset 0 1px 3px var(--shadow);
}

.card__title {
  margin-top: 0;
  font-size: 1.25rem;
}

.card__content > *:last-child {
  margin-bottom: 0;
}

.card--link {
  cursor: pointer;
}

.card--link:hover {
  border-color: var(--accent);
}
```

### Theme Toggle Button

```css
.theme-toggle {
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 0.5rem 0.75rem;
  cursor: pointer;
  transition: var(--transition-theme), transform var(--transition-fast);
  font-size: 1.25rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.theme-toggle:hover {
  background: var(--bg-tertiary);
  transform: scale(1.05);
}

.theme-toggle:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
}

.theme-toggle__icon--sun {
  display: block;
}

.theme-toggle__icon--moon {
  display: none;
}

[data-theme="dark"] .theme-toggle__icon--sun {
  display: none;
}

[data-theme="dark"] .theme-toggle__icon--moon {
  display: block;
}
```

```javascript
// Theme toggle implementation
const themeToggle = document.querySelector('.theme-toggle');
const root = document.documentElement;

// Initialize theme from localStorage or system preference
const getInitialTheme = () => {
  const stored = localStorage.getItem('theme');
  if (stored) return stored;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
};

const setTheme = (theme) => {
  root.setAttribute('data-theme', theme);
  localStorage.setItem('theme', theme);
};

// Set initial theme
setTheme(getInitialTheme());

// Toggle on click
themeToggle?.addEventListener('click', () => {
  const current = root.getAttribute('data-theme') || 'light';
  setTheme(current === 'light' ? 'dark' : 'light');
});
```

## Animations

### Entrance Animations

```css
@keyframes fadeUp {
  from {
    opacity: 0;
    transform: translateY(20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-fade-up {
  animation: fadeUp 0.6s ease-out backwards;
}

.stagger-children > * {
  animation: fadeUp 0.6s ease-out backwards;
  animation-delay: calc(var(--i, 0) * 0.1s);
}

/* Example usage: add style="--i: 0", style="--i: 1", etc. to children */

@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

### Smooth Transitions

```css
/* Apply to all theme-aware elements */
.theme-aware {
  transition: var(--transition-theme);
}

/* Smooth hover states */
.interactive {
  transition: background-color var(--transition-fast),
              color var(--transition-fast),
              transform var(--transition-fast),
              box-shadow var(--transition-base);
}
```

## Responsive Breakpoints

```css
/* Mobile-first approach */

/* Base styles: < 640px (mobile) */

@media (min-width: 640px) {
  /* Tablet and up */
  body {
    font-size: 1.0625rem;
  }
}

@media (min-width: 1024px) {
  /* Desktop and up */
  body {
    font-size: 1.125rem;
  }
}

/* Prefer clamp() for fluid values */
.fluid-text {
  font-size: clamp(1rem, 0.95rem + 0.25vw, 1.125rem);
  padding: clamp(1rem, 2vw, 2rem);
}

/* Container queries for component-level responsiveness */
.card-container {
  container-type: inline-size;
}

@container (min-width: 400px) {
  .card {
    padding: 2rem;
  }
}
```

## Aesthetic Palettes

### Paper & Ink (Warm)

```css
:root {
  --bg-primary: oklch(0.98 0.008 87);
  --bg-secondary: oklch(0.94 0.013 85);
  --bg-tertiary: oklch(0.90 0.017 82);
  --text-primary: oklch(0.22 0.044 46);
  --text-secondary: oklch(0.37 0.038 48);
  --text-tertiary: oklch(0.55 0.024 56);
  --accent: oklch(0.52 0.155 32);
  --accent-hover: oklch(0.44 0.143 32);
  --border: oklch(0.85 0.016 74);
  --border-subtle: oklch(0.90 0.013 80);
  --shadow: oklch(0.22 0.044 46 / 0.08);
  --code-bg: oklch(0.96 0.012 82);
}

[data-theme="dark"] {
  --bg-primary: oklch(0.14 0.018 46);
  --bg-secondary: oklch(0.18 0.018 46);
  --bg-tertiary: oklch(0.22 0.018 46);
  --text-primary: oklch(0.90 0.013 80);
  --text-secondary: oklch(0.75 0.018 68);
  --text-tertiary: oklch(0.56 0.022 56);
  --accent: oklch(0.65 0.130 36);
  --accent-hover: oklch(0.71 0.118 36);
  --border: oklch(0.27 0.016 46);
  --border-subtle: oklch(0.22 0.016 46);
  --shadow: oklch(0 0 0 / 0.30);
  --code-bg: oklch(0.18 0.018 46);
}
```

### Editorial (Cool)

```css
:root {
  --bg-primary: oklch(1.00 0 0);
  --bg-secondary: oklch(0.97 0.006 248);
  --bg-tertiary: oklch(0.93 0.010 245);
  --text-primary: oklch(0.09 0 0);
  --text-secondary: oklch(0.35 0 0);
  --text-tertiary: oklch(0.60 0 0);
  --accent: oklch(0.42 0.138 258);
  --accent-hover: oklch(0.32 0.126 258);
  --border: oklch(0.87 0.012 242);
  --border-subtle: oklch(0.93 0.008 245);
  --shadow: oklch(0.42 0.138 258 / 0.08);
  --code-bg: oklch(0.95 0.010 248);
}

[data-theme="dark"] {
  --bg-primary: oklch(0.14 0.018 252);
  --bg-secondary: oklch(0.19 0.016 250);
  --bg-tertiary: oklch(0.24 0.016 248);
  --text-primary: oklch(0.93 0.010 245);
  --text-secondary: oklch(0.77 0.016 242);
  --text-tertiary: oklch(0.60 0.014 244);
  --accent: oklch(0.64 0.160 258);
  --accent-hover: oklch(0.72 0.140 258);
  --border: oklch(0.27 0.016 250);
  --border-subtle: oklch(0.24 0.016 248);
  --shadow: oklch(0 0 0 / 0.40);
  --code-bg: oklch(0.19 0.016 250);
}
```

### Modernist (Minimal)

```css
:root {
  --bg-primary: oklch(1.00 0 0);
  --bg-secondary: oklch(0.97 0 0);
  --bg-tertiary: oklch(0.94 0 0);
  --text-primary: oklch(0.00 0 0);
  --text-secondary: oklch(0.33 0 0);
  --text-tertiary: oklch(0.60 0 0);
  --accent: oklch(0.58 0.220 27);
  --accent-hover: oklch(0.50 0.210 27);
  --border: oklch(0.90 0 0);
  --border-subtle: oklch(0.94 0 0);
  --shadow: oklch(0 0 0 / 0.08);
  --code-bg: oklch(0.96 0 0);
}

[data-theme="dark"] {
  --bg-primary: oklch(0.00 0 0);
  --bg-secondary: oklch(0.14 0 0);
  --bg-tertiary: oklch(0.22 0 0);
  --text-primary: oklch(1.00 0 0);
  --text-secondary: oklch(0.77 0 0);
  --text-tertiary: oklch(0.60 0 0);
  --accent: oklch(0.62 0.220 27);
  --accent-hover: oklch(0.68 0.210 27);
  --border: oklch(0.26 0 0);
  --border-subtle: oklch(0.22 0 0);
  --shadow: oklch(1.00 0 0 / 0.08);
  --code-bg: oklch(0.14 0 0);
}
```

### Forest (Natural)

```css
:root {
  --bg-primary: oklch(0.98 0.008 100);
  --bg-secondary: oklch(0.94 0.012 92);
  --bg-tertiary: oklch(0.90 0.016 92);
  --text-primary: oklch(0.24 0.062 152);
  --text-secondary: oklch(0.38 0.058 152);
  --text-tertiary: oklch(0.56 0.032 152);
  --accent: oklch(0.50 0.085 152);
  --accent-hover: oklch(0.41 0.080 152);
  --border: oklch(0.83 0.024 148);
  --border-subtle: oklch(0.90 0.016 100);
  --shadow: oklch(0.24 0.062 152 / 0.08);
  --code-bg: oklch(0.94 0.020 148);
}

[data-theme="dark"] {
  --bg-primary: oklch(0.15 0.022 152);
  --bg-secondary: oklch(0.19 0.022 152);
  --bg-tertiary: oklch(0.23 0.022 152);
  --text-primary: oklch(0.92 0.018 140);
  --text-secondary: oklch(0.77 0.022 145);
  --text-tertiary: oklch(0.56 0.022 150);
  --accent: oklch(0.62 0.095 152);
  --accent-hover: oklch(0.69 0.088 148);
  --border: oklch(0.27 0.022 150);
  --border-subtle: oklch(0.23 0.022 152);
  --shadow: oklch(0 0 0 / 0.30);
  --code-bg: oklch(0.19 0.022 152);
}
```

### Dusk (Moody)

```css
:root {
  --bg-primary: oklch(0.97 0.009 78);
  --bg-secondary: oklch(0.92 0.015 72);
  --bg-tertiary: oklch(0.87 0.020 70);
  --text-primary: oklch(0.22 0.032 46);
  --text-secondary: oklch(0.35 0.028 46);
  --text-tertiary: oklch(0.52 0.020 53);
  --accent: oklch(0.63 0.128 48);
  --accent-hover: oklch(0.54 0.122 46);
  --border: oklch(0.81 0.020 68);
  --border-subtle: oklch(0.87 0.017 70);
  --shadow: oklch(0.22 0.032 46 / 0.08);
  --code-bg: oklch(0.93 0.013 72);
}

[data-theme="dark"] {
  --bg-primary: oklch(0.14 0.015 46);
  --bg-secondary: oklch(0.18 0.015 46);
  --bg-tertiary: oklch(0.22 0.015 46);
  --text-primary: oklch(0.94 0.010 74);
  --text-secondary: oklch(0.77 0.018 66);
  --text-tertiary: oklch(0.57 0.018 56);
  --accent: oklch(0.72 0.118 52);
  --accent-hover: oklch(0.78 0.108 52);
  --border: oklch(0.28 0.015 46);
  --border-subtle: oklch(0.22 0.015 46);
  --shadow: oklch(0 0 0 / 0.40);
  --code-bg: oklch(0.18 0.015 46);
}
```

## Accessibility Checklist

### Color Contrast Requirements

- **Body text**: Minimum 4.5:1 contrast ratio (WCAG AA)
- **Large text** (18pt+ or 14pt+ bold): Minimum 3:1 contrast ratio
- **UI components**: Minimum 3:1 contrast ratio for interactive elements

Test all palette combinations with a contrast checker.

### Motion & Animation

```css
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

### Dark Mode

```css
@media (prefers-color-scheme: dark) {
  /* Automatic dark mode styles */
}

/* Override with manual toggle */
[data-theme="dark"] {
  /* Manual dark mode styles */
}
```

### Focus Styles

```css
*:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
  border-radius: 2px;
}

/* Remove default outline, rely on focus-visible */
*:focus:not(:focus-visible) {
  outline: none;
}
```

### Semantic HTML

Always use semantic elements:
- `<header>`, `<nav>`, `<main>`, `<article>`, `<section>`, `<aside>`, `<footer>`
- `<h1>`-`<h6>` in proper hierarchy
- `<button>` for interactive elements (not `<div>` with click handlers)
- `<a>` for navigation
- `<label>` for form inputs
- `<table>` for tabular data

### ARIA Labels

```html
<button aria-label="Toggle dark mode" class="theme-toggle">
  <span class="theme-toggle__icon--sun" aria-hidden="true">☀️</span>
  <span class="theme-toggle__icon--moon" aria-hidden="true">🌙</span>
</button>

<nav aria-label="Main navigation">
  <!-- Navigation links -->
</nav>

<input type="search" aria-label="Search articles" />
```

### Skip Links

```css
.skip-link {
  position: absolute;
  top: -40px;
  left: 0;
  background: var(--accent);
  color: white;
  padding: 8px 16px;
  text-decoration: none;
  z-index: 1000;
}

.skip-link:focus {
  top: 0;
}
```

```html
<a href="#main-content" class="skip-link">Skip to main content</a>
```

---

## Quick Start Template

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Document Title</title>
  <style>
    /* Include theme system and base typography reset */
    /* Add layout and component styles as needed */
  </style>
</head>
<body>
  <a href="#main" class="skip-link">Skip to main content</a>

  <header>
    <nav class="nav-top" aria-label="Main navigation">
      <!-- Navigation -->
    </nav>
  </header>

  <main id="main">
    <div class="container">
      <!-- Content -->
    </div>
  </main>

  <footer>
    <!-- Footer content -->
  </footer>

  <script>
    // Theme toggle script
  </script>
</body>
</html>
```
