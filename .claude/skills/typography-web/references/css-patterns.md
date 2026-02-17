# CSS Patterns for Typography-Focused Web Design

A comprehensive reference of reusable CSS patterns for creating beautiful, typography-first web pages. Designed for AI agents to quickly implement professional, accessible designs.

## Theme System

### Complete Custom Property Theme

```css
:root {
  /* Light theme colors */
  --bg-primary: #fafaf7;
  --bg-secondary: #f0efe9;
  --bg-tertiary: #e8e6df;
  --text-primary: #2d2d2d;
  --text-secondary: #5a5a5a;
  --text-tertiary: #8a8a8a;
  --accent: #c05030;
  --accent-hover: #a04020;
  --border: #ddd;
  --border-subtle: #eee;
  --shadow: rgba(0, 0, 0, 0.08);
  --code-bg: #f5f2eb;

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
    --bg-primary: #1a1a1a;
    --bg-secondary: #242424;
    --bg-tertiary: #2d2d2d;
    --text-primary: #e8e6df;
    --text-secondary: #b4b2ab;
    --text-tertiary: #8a8a8a;
    --accent: #e07856;
    --accent-hover: #f08866;
    --border: #3a3a3a;
    --border-subtle: #2d2d2d;
    --shadow: rgba(0, 0, 0, 0.3);
    --code-bg: #242424;
  }
}
```

### Manual Theme Toggle

```css
[data-theme="dark"] {
  --bg-primary: #1a1a1a;
  --bg-secondary: #242424;
  --bg-tertiary: #2d2d2d;
  --text-primary: #e8e6df;
  --text-secondary: #b4b2ab;
  --text-tertiary: #8a8a8a;
  --accent: #e07856;
  --accent-hover: #f08866;
  --border: #3a3a3a;
  --border-subtle: #2d2d2d;
  --shadow: rgba(0, 0, 0, 0.3);
  --code-bg: #242424;
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
  background: color-mix(in srgb, var(--bg-secondary) 50%, transparent);
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
  --bg-primary: #faf8f3;
  --bg-secondary: #f0ede5;
  --bg-tertiary: #e8e3d8;
  --text-primary: #3a2817;
  --text-secondary: #5c4a38;
  --text-tertiary: #8a7d70;
  --accent: #c05030;
  --accent-hover: #a04020;
  --border: #d8cfc0;
  --border-subtle: #e8e3d8;
  --shadow: rgba(58, 40, 23, 0.08);
  --code-bg: #f5f0e8;
}

[data-theme="dark"] {
  --bg-primary: #1a1510;
  --bg-secondary: #241f18;
  --bg-tertiary: #2d2720;
  --text-primary: #e8e3d8;
  --text-secondary: #c4b8a8;
  --text-tertiary: #8a7d70;
  --accent: #e07856;
  --accent-hover: #f08866;
  --border: #3a332a;
  --border-subtle: #2d2720;
  --shadow: rgba(0, 0, 0, 0.3);
  --code-bg: #241f18;
}
```

### Editorial (Cool)

```css
:root {
  --bg-primary: #ffffff;
  --bg-secondary: #f5f7fa;
  --bg-tertiary: #e8ecf1;
  --text-primary: #0a0a0a;
  --text-secondary: #4a4a4a;
  --text-tertiary: #8a8a8a;
  --accent: #2c5aa0;
  --accent-hover: #1e4278;
  --border: #d0d7e0;
  --border-subtle: #e8ecf1;
  --shadow: rgba(44, 90, 160, 0.08);
  --code-bg: #f0f3f8;
}

[data-theme="dark"] {
  --bg-primary: #0f1419;
  --bg-secondary: #1a1f26;
  --bg-tertiary: #242a33;
  --text-primary: #e8ecf1;
  --text-secondary: #b8c0cc;
  --text-tertiary: #8a92a0;
  --accent: #4a8bf5;
  --accent-hover: #6ba0f7;
  --border: #2d3540;
  --border-subtle: #242a33;
  --shadow: rgba(0, 0, 0, 0.4);
  --code-bg: #1a1f26;
}
```

### Modernist (Minimal)

```css
:root {
  --bg-primary: #ffffff;
  --bg-secondary: #f8f8f8;
  --bg-tertiary: #eeeeee;
  --text-primary: #000000;
  --text-secondary: #444444;
  --text-tertiary: #888888;
  --accent: #ff3b30;
  --accent-hover: #d92d23;
  --border: #dddddd;
  --border-subtle: #eeeeee;
  --shadow: rgba(0, 0, 0, 0.08);
  --code-bg: #f5f5f5;
}

[data-theme="dark"] {
  --bg-primary: #000000;
  --bg-secondary: #1a1a1a;
  --bg-tertiary: #2a2a2a;
  --text-primary: #ffffff;
  --text-secondary: #bbbbbb;
  --text-tertiary: #888888;
  --accent: #ff453a;
  --accent-hover: #ff6259;
  --border: #333333;
  --border-subtle: #2a2a2a;
  --shadow: rgba(255, 255, 255, 0.08);
  --code-bg: #1a1a1a;
}
```

### Forest (Natural)

```css
:root {
  --bg-primary: #faf9f5;
  --bg-secondary: #f0ede5;
  --bg-tertiary: #e5e1d5;
  --text-primary: #1f3a2f;
  --text-secondary: #3a5248;
  --text-tertiary: #6b7f75;
  --accent: #5a7d5f;
  --accent-hover: #466348;
  --border: #c8d4cd;
  --border-subtle: #e5e1d5;
  --shadow: rgba(31, 58, 47, 0.08);
  --code-bg: #eef2ee;
}

[data-theme="dark"] {
  --bg-primary: #141a15;
  --bg-secondary: #1c241d;
  --bg-tertiary: #242d25;
  --text-primary: #e5f0e7;
  --text-secondary: #b8c8bb;
  --text-tertiary: #7a8a7d;
  --accent: #7aa37f;
  --accent-hover: #92b897;
  --border: #2d3a2e;
  --border-subtle: #242d25;
  --shadow: rgba(0, 0, 0, 0.3);
  --code-bg: #1c241d;
}
```

### Dusk (Moody)

```css
:root {
  --bg-primary: #f5f3ef;
  --bg-secondary: #e8e3dc;
  --bg-tertiary: #d8d0c5;
  --text-primary: #2d2520;
  --text-secondary: #4a3f38;
  --text-tertiary: #756b60;
  --accent: #d4834f;
  --accent-hover: #b86d3a;
  --border: #c8bcaf;
  --border-subtle: #d8d0c5;
  --shadow: rgba(45, 37, 32, 0.08);
  --code-bg: #ede8e0;
}

[data-theme="dark"] {
  --bg-primary: #1a1715;
  --bg-secondary: #24201d;
  --bg-tertiary: #2d2825;
  --text-primary: #f0ebe3;
  --text-secondary: #c4b8a8;
  --text-tertiary: #8a7d70;
  --accent: #e69760;
  --accent-hover: #f0ab78;
  --border: #3a352f;
  --border-subtle: #2d2825;
  --shadow: rgba(0, 0, 0, 0.4);
  --code-bg: #24201d;
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
