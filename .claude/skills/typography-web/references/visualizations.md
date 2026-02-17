# Visualization & Diagram Patterns

Reference for generating diagrams, charts, and interactive visualizations within typography-focused web pages. All visualizations load from CDN and work in self-contained HTML files.

## When to Use What

| Content Type | Tool | Why |
|---|---|---|
| Flowcharts, pipelines | Mermaid | Automatic edge routing |
| Sequence diagrams | Mermaid | Built-in participant lifelines |
| ER diagrams | Mermaid | Relationship notation |
| State machines | Mermaid | Transition syntax |
| Mind maps | Mermaid | Radial auto-layout |
| Architecture (text-heavy) | CSS Grid cards | More control over text content |
| Architecture (topology) | Mermaid | When connections matter more than text |
| Data tables (4+ rows or 3+ cols) | HTML `<table>` | Accessibility, tabular figures |
| Timelines | CSS central-line pattern | Visual flexibility |
| Dashboards, KPIs | CSS Grid + Chart.js | Mixed metrics and charts |
| Bar/line/pie/doughnut/radar charts | Chart.js | Data visualization |
| Complex choreographed animations (10+ elements) | anime.js | Orchestrated entrance sequences |
| Simple staggered entrances | CSS only | No library needed |

## Mermaid.js

### CDN Setup (Basic)

```html
<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
  mermaid.initialize({ startOnLoad: true });
</script>
```

### CDN Setup (With ELK Layout)

ELK provides better positioning for complex diagrams. Use it for anything beyond simple linear flows.

```html
<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
  import elkLayouts from 'https://cdn.jsdelivr.net/npm/@mermaid-js/layout-elk/dist/mermaid-layout-elk.esm.min.mjs';
  mermaid.registerLayoutLoaders(elkLayouts);
  mermaid.initialize({ startOnLoad: true, layout: 'elk' });
</script>
```

### Theming

Use `theme: 'base'` with `themeVariables` for full control. Built-in themes ignore most overrides.

```javascript
const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

mermaid.initialize({
  startOnLoad: true,
  theme: 'base',
  themeVariables: {
    primaryColor: isDark ? '#2a3a4a' : '#e8f0f8',
    primaryBorderColor: isDark ? '#4a6a8a' : '#6a9fd8',
    primaryTextColor: isDark ? '#e0e0e0' : '#2d2d2d',
    secondaryColor: isDark ? '#3a2a2a' : '#f8e8e8',
    secondaryBorderColor: isDark ? '#8a4a4a' : '#d86a6a',
    secondaryTextColor: isDark ? '#e0e0e0' : '#2d2d2d',
    tertiaryColor: isDark ? '#2a3a2a' : '#e8f8e8',
    tertiaryBorderColor: isDark ? '#4a8a4a' : '#6ad86a',
    tertiaryTextColor: isDark ? '#e0e0e0' : '#2d2d2d',
    lineColor: isDark ? '#6a6a6a' : '#888888',
    fontSize: '14px',
    fontFamily: 'var(--font-body)',
    noteBkgColor: isDark ? '#2d2d2d' : '#f5f5f0',
    noteTextColor: isDark ? '#c0c0c0' : '#5a5a5a',
    noteBorderColor: isDark ? '#4a4a4a' : '#ccc',
  }
});
```

### Hand-Drawn Mode

```javascript
mermaid.initialize({
  theme: 'base',
  look: 'handDrawn',
  layout: 'elk'
});
```

### classDef Best Practices

- **Never** set `color:` in classDef — it hardcodes text color and breaks in the opposite theme
- Use semi-transparent fills (8-digit hex): `fill:#b5761433` (subtle), `fill:#b5761455` (prominent)
- Avoid opaque light fills like `fill:#fefce8` — they won't adapt to dark mode

```
classDef highlight fill:#c0503022,stroke:#c05030,stroke-width:2px
classDef secondary fill:#5a7d5f22,stroke:#5a7d5f
```

### CSS Overrides for Mermaid SVGs

```css
.mermaid-wrap {
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1.5rem;
  margin: 2rem 0;
  overflow: hidden;
}

/* Force text colors to respect theme */
.mermaid .nodeLabel { color: var(--text-primary) !important; }
.mermaid .edgeLabel { background: var(--bg-secondary); color: var(--text-secondary); font-size: 0.85rem; }
.mermaid .node rect,
.mermaid .node circle,
.mermaid .node polygon { stroke-width: 1.5px; }
.mermaid .edge-pattern-solid { stroke-width: 1.5px; }

/* Sequence diagrams */
.mermaid .messageText { font-size: 12px; font-family: var(--font-mono); }

/* ER diagrams */
.mermaid .er.entityBox { fill: var(--bg-secondary); stroke: var(--border); }

/* Mind maps */
.mermaid .mindmap-node rect { rx: 8px; }
```

### Zoom & Pan Controls

For complex diagrams, add zoom/pan within a container:

```css
.diagram-container {
  position: relative;
  overflow: hidden;
  cursor: grab;
}

.diagram-container.zoomed { cursor: grabbing; }

.zoom-controls {
  position: absolute;
  top: 0.75rem;
  right: 0.75rem;
  display: flex;
  gap: 0.25rem;
  z-index: 10;
}

.zoom-controls button {
  background: var(--bg-primary);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 0.25rem 0.5rem;
  cursor: pointer;
  font-size: 0.875rem;
  color: var(--text-secondary);
}
```

```javascript
// Zoom & pan for Mermaid diagrams
function initZoomPan(container) {
  let scale = 1, panX = 0, panY = 0, isPanning = false, startX, startY;
  const inner = container.querySelector('.mermaid');
  const MIN_SCALE = 0.3, MAX_SCALE = 5;

  container.addEventListener('wheel', (e) => {
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    const delta = e.deltaY > 0 ? 0.9 : 1.1;
    scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale * delta));
    inner.style.transform = `translate(${panX}px, ${panY}px) scale(${scale})`;
  });

  container.addEventListener('mousedown', (e) => {
    if (scale <= 1) return;
    isPanning = true;
    startX = e.clientX - panX;
    startY = e.clientY - panY;
    container.classList.add('zoomed');
  });

  document.addEventListener('mousemove', (e) => {
    if (!isPanning) return;
    panX = e.clientX - startX;
    panY = e.clientY - startY;
    inner.style.transform = `translate(${panX}px, ${panY}px) scale(${scale})`;
  });

  document.addEventListener('mouseup', () => {
    isPanning = false;
    container.classList.remove('zoomed');
  });
}
```

### Diagram Examples

**Flowchart with decisions:**
```
flowchart TD
    A[Request received] --> B{Authenticated?}
    B -->|Yes| C[Load user context]
    B -->|No| D[Return 401]
    C --> E{Authorized?}
    E -->|Yes| F[Process request]
    E -->|No| G[Return 403]
    F --> H[Return response]
```

**Sequence diagram:**
```
sequenceDiagram
    participant C as Client
    participant G as Gateway
    participant S as Service
    participant D as Database
    C->>G: POST /api/orders
    G->>G: Validate token
    G->>S: Forward request
    S->>D: INSERT order
    D-->>S: Order ID
    S-->>G: 201 Created
    G-->>C: Order confirmation
```

**ER diagram:**
```
erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    LINE_ITEM }o--|| PRODUCT : references
    USER { string id PK string email string name }
    ORDER { string id PK date created_at string status }
    PRODUCT { string id PK string name decimal price }
```

**State diagram:**
```
stateDiagram-v2
    [*] --> Draft
    Draft --> Review : submit
    Review --> Approved : approve
    Review --> Draft : request changes
    Approved --> Published : publish
    Published --> [*]
```

**Mind map:**
```
mindmap
  root((Project))
    Frontend
      React
      TypeScript
      Tailwind
    Backend
      Node.js
      PostgreSQL
      Redis
    Infrastructure
      Docker
      AWS
      CI/CD
```

### stateDiagram-v2 Limitations

- No `<br/>` support (causes parse error)
- Avoid parentheses in labels
- Multiple colons can break parsing
- For multi-line labels, use `flowchart` with `|"quoted labels"|` instead

## Chart.js

### CDN Setup

```html
<script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
```

### Theme-Aware Configuration

```javascript
const isDark = document.documentElement.getAttribute('data-theme') === 'dark' ||
  window.matchMedia('(prefers-color-scheme: dark)').matches;

const textColor = isDark ? '#b0b0b0' : '#5a5a5a';
const gridColor = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)';
const bgColor = isDark ? '#242424' : '#fafaf7';
```

### Chart Container

```css
.chart-container {
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1.5rem;
  margin: 2rem 0;
  position: relative;
  max-height: 400px;
}

.chart-container canvas {
  max-width: 100%;
}
```

### Example: Bar Chart

```javascript
new Chart(document.getElementById('myChart'), {
  type: 'bar',
  data: {
    labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May'],
    datasets: [{
      label: 'Revenue ($k)',
      data: [12, 19, 8, 15, 22],
      backgroundColor: isDark ? 'rgba(224, 120, 86, 0.6)' : 'rgba(192, 80, 48, 0.6)',
      borderColor: isDark ? '#e07856' : '#c05030',
      borderWidth: 1,
      borderRadius: 4,
    }]
  },
  options: {
    responsive: true,
    maintainAspectRatio: true,
    plugins: {
      legend: { labels: { color: textColor, font: { family: 'var(--font-body)' } } }
    },
    scales: {
      x: { ticks: { color: textColor }, grid: { color: gridColor } },
      y: { ticks: { color: textColor }, grid: { color: gridColor } }
    }
  }
});
```

### Example: Doughnut Chart

```javascript
new Chart(document.getElementById('doughnut'), {
  type: 'doughnut',
  data: {
    labels: ['Frontend', 'Backend', 'DevOps', 'Design'],
    datasets: [{
      data: [40, 30, 20, 10],
      backgroundColor: ['#c05030', '#5a7d5f', '#2c5aa0', '#d4834f'],
      borderColor: isDark ? '#1a1a1a' : '#fafaf7',
      borderWidth: 2,
    }]
  },
  options: {
    responsive: true,
    cutout: '60%',
    plugins: {
      legend: { position: 'bottom', labels: { color: textColor, padding: 16 } }
    }
  }
});
```

## anime.js

### CDN Setup

```html
<script src="https://cdn.jsdelivr.net/npm/animejs@3.2.2/lib/anime.min.js"></script>
```

### When to Use

Only for choreographed entrance sequences with 10+ elements. For simpler staggered reveals, CSS `animation-delay` with `--i` custom property is sufficient.

### Pattern: Staggered Card Reveal

```javascript
// Check for reduced motion preference first
if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  anime({
    targets: '.card',
    opacity: [0, 1],
    translateY: [20, 0],
    delay: anime.stagger(80, { start: 200 }),
    duration: 600,
    easing: 'easeOutCubic'
  });
}
```

### Initial CSS (Prevent Flash)

```css
.node, .card { opacity: 0; }

@media (prefers-reduced-motion: reduce) {
  .node, .card { opacity: 1 !important; }
}
```

### Pattern: Sequential Section Reveal

```javascript
const tl = anime.timeline({ easing: 'easeOutCubic' });

tl.add({ targets: '.hero', opacity: [0, 1], duration: 400 })
  .add({ targets: '.section-title', opacity: [0, 1], translateX: [-20, 0], duration: 300 }, '-=100')
  .add({ targets: '.card', opacity: [0, 1], translateY: [30, 0], delay: anime.stagger(60), duration: 500 }, '-=100');
```

## CSS-Only Patterns (No Library Needed)

### Architecture Cards with CSS Grid

For text-heavy architecture overviews, CSS Grid with cards gives more control than Mermaid:

```css
.arch-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 1.5rem;
  margin: 2rem 0;
}

.arch-card {
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1.25rem;
}

.arch-card__title {
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-tertiary);
  margin: 0 0 0.75rem;
}

.arch-card__body {
  font-size: 0.95rem;
  color: var(--text-primary);
  line-height: 1.5;
}

/* Flow arrows between cards */
.arch-arrow {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-tertiary);
  font-size: 1.5rem;
  padding: 0.5rem 0;
}
```

### Timeline Pattern

```css
.timeline {
  position: relative;
  padding-left: 2rem;
  margin: 2rem 0;
}

.timeline::before {
  content: '';
  position: absolute;
  left: 0;
  top: 0;
  bottom: 0;
  width: 2px;
  background: var(--border);
}

.timeline-item {
  position: relative;
  padding-bottom: 2rem;
}

.timeline-item::before {
  content: '';
  position: absolute;
  left: -2rem;
  top: 0.4rem;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--accent);
  border: 2px solid var(--bg-primary);
  transform: translateX(-4px);
}

.timeline-item__date {
  font-size: 0.85rem;
  color: var(--text-tertiary);
  font-variant-numeric: tabular-nums;
}

.timeline-item__title {
  font-weight: 600;
  margin: 0.25rem 0;
}

.timeline-item__body {
  color: var(--text-secondary);
  font-size: 0.95rem;
}
```

### KPI Dashboard Cards

```css
.kpi-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 1rem;
  margin: 2rem 0;
}

.kpi-card {
  background: var(--bg-secondary);
  border: 1px solid var(--border-subtle);
  border-radius: 8px;
  padding: 1.25rem;
  text-align: center;
}

.kpi-card__label {
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-tertiary);
  margin-bottom: 0.5rem;
}

.kpi-card__value {
  font-size: 2rem;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
  line-height: 1;
}

.kpi-card__trend {
  font-size: 0.85rem;
  margin-top: 0.5rem;
}

.kpi-card__trend--up { color: #5a7d5f; }
.kpi-card__trend--down { color: #c05030; }
.kpi-card__trend--neutral { color: var(--text-tertiary); }

/* Animated counter (CSS-only, no JS) */
@property --num {
  syntax: '<integer>';
  initial-value: 0;
  inherits: false;
}

.kpi-card__value--animated {
  counter-reset: num var(--num);
  animation: countUp 1.5s ease-out forwards;
}

.kpi-card__value--animated::after {
  content: counter(num);
}

@keyframes countUp {
  from { --num: 0; }
}
```

### Before/After Comparison Panels

```css
.compare {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1.5rem;
  margin: 2rem 0;
}

.compare__panel {
  border: 1px solid var(--border);
  border-radius: 8px;
  overflow: hidden;
}

.compare__header {
  padding: 0.75rem 1rem;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
}

.compare__header--before {
  background: rgba(192, 80, 48, 0.1);
  color: #c05030;
  border-bottom: 2px solid #c05030;
}

.compare__header--after {
  background: rgba(90, 125, 95, 0.1);
  color: #5a7d5f;
  border-bottom: 2px solid #5a7d5f;
}

.compare__body {
  padding: 1.25rem;
}

@media (max-width: 640px) {
  .compare { grid-template-columns: 1fr; }
}
```

### Status Badges

```css
.badge {
  display: inline-block;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  padding: 0.2em 0.6em;
  border-radius: 4px;
}

.badge--success { background: rgba(90, 125, 95, 0.15); color: #5a7d5f; }
.badge--warning { background: rgba(212, 131, 79, 0.15); color: #d4834f; }
.badge--error { background: rgba(192, 80, 48, 0.15); color: #c05030; }
.badge--info { background: rgba(44, 90, 160, 0.15); color: #2c5aa0; }
.badge--neutral { background: var(--bg-tertiary); color: var(--text-secondary); }
```

### Collapsible Sections

```css
details {
  border: 1px solid var(--border);
  border-radius: 8px;
  margin: 1rem 0;
  overflow: hidden;
}

summary {
  padding: 1rem 1.25rem;
  cursor: pointer;
  font-weight: 600;
  background: var(--bg-secondary);
  list-style: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

summary::after {
  content: '+';
  font-size: 1.25rem;
  color: var(--text-tertiary);
  transition: transform 0.2s;
}

details[open] summary::after {
  content: '−';
}

summary::-webkit-details-marker { display: none; }

details > :not(summary) {
  padding: 1.25rem;
}
```

## Responsive Section Navigation (Scroll Spy)

For multi-section pages (docs, reviews, dashboards), use a sticky sidebar TOC that collapses to a horizontal scrolling bar on mobile.

### Desktop: Sticky Sidebar TOC

```css
.toc {
  position: sticky;
  top: 1.5rem;
  max-height: calc(100vh - 3rem);
  overflow-y: auto;
}

.toc a {
  display: block;
  padding: 0.4rem 0.75rem;
  font-size: 0.85rem;
  color: var(--text-secondary);
  border-left: 2px solid transparent;
  transition: all 0.15s;
}

.toc a.active {
  color: var(--accent);
  border-left-color: var(--accent);
  font-weight: 600;
}
```

### Mobile: Horizontal Scroll Bar

```css
@media (max-width: 1000px) {
  .toc {
    position: sticky;
    top: 0;
    z-index: 50;
    background: var(--bg-primary);
    border-bottom: 1px solid var(--border);
    display: flex;
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
    scrollbar-width: none;
    padding: 0.5rem 1rem;
    gap: 0.5rem;
  }

  .toc::-webkit-scrollbar { display: none; }

  .toc a {
    white-space: nowrap;
    border-left: none;
    border-bottom: 2px solid transparent;
    padding: 0.5rem 0.75rem;
  }

  .toc a.active {
    border-bottom-color: var(--accent);
    border-left: none;
  }
}
```

### Scroll Spy JavaScript

```javascript
const sections = document.querySelectorAll('section[id]');
const tocLinks = document.querySelectorAll('.toc a');

const observer = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      tocLinks.forEach(link => link.classList.remove('active'));
      const active = document.querySelector(`.toc a[href="#${entry.target.id}"]`);
      if (active) {
        active.classList.add('active');
        // Auto-scroll TOC on mobile
        if (window.innerWidth <= 1000) {
          active.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' });
        }
      }
    }
  });
}, { rootMargin: '-10% 0px -80% 0px' });

sections.forEach(section => observer.observe(section));
```

## Google Fonts Pairings

### Loading Pattern

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">
```

### Recommended Pairings

| Heading | Body/Mono | Vibe |
|---|---|---|
| Outfit | Space Mono | Clean, modern |
| Instrument Serif | JetBrains Mono | Editorial |
| Sora | IBM Plex Mono | Technical |
| DM Sans | Fira Code | Friendly developer |
| Fraunces | Source Code Pro | Warm |
| Libre Franklin | Inconsolata | Classic |
| Manrope | Martian Mono | Soft contemporary |
| Playfair Display | Roboto Mono | Elegant contrast |
| Bricolage Grotesque | Fragment Mono | Bold |
| Crimson Pro | Noto Sans Mono | Scholarly |
| Red Hat Display | Red Hat Mono | Cohesive family |
| Plus Jakarta Sans | Azeret Mono | Rounded, approachable |

### Aesthetic Variety

Don't default to one look. Choose fonts that match the content:
- **Technical docs**: Sora, IBM Plex, DM Sans
- **Editorial/blog**: Instrument Serif, Playfair Display, Crimson Pro
- **Portfolio**: Outfit, Manrope, Bricolage Grotesque
- **Data/dashboard**: Red Hat Display, Libre Franklin, Plus Jakarta Sans
