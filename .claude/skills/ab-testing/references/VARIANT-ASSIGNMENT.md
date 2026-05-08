# Variant Assignment

## Table of Contents
- [Why Server-Side](#why-server-side)
- [Basic Assignment](#basic-assignment)
- [Multiple Experiments](#multiple-experiments)
- [Weighted Splits](#weighted-splits)
- [Segment-Based Assignment](#segment-based-assignment)
- [Reading Variants](#reading-variants)
- [Dynamic Config](#dynamic-config)
- [Edge Cases](#edge-cases)

---

## Why Server-Side

| Client-Side | Server-Side (Middleware) |
|-------------|--------------------------|
| Flicker (A→B switch visible) | No flicker (decided before render) |
| Layout shift | Stable layout |
| SEO inconsistency | Consistent content per request |
| Race conditions | Deterministic |
| Easy to bypass | Cookie-based persistence |

**The Rule**: Always assign variants before the response body is sent.

---

## Basic Assignment

```tsx
// middleware.ts
import { NextResponse, type NextRequest } from 'next/server'

export function middleware(request: NextRequest) {
  const response = NextResponse.next()

  const cookieName = 'exp_hero_cta'
  const existingVariant = request.cookies.get(cookieName)?.value

  if (!existingVariant) {
    const variant = Math.random() < 0.5 ? 'A' : 'B'
    response.cookies.set(cookieName, variant, {
      maxAge: 60 * 60 * 24 * 30,  // 30 days
      httpOnly: false,            // Client needs to read
      sameSite: 'lax',
      path: '/',
      secure: process.env.NODE_ENV === 'production'
    })
  }

  return response
}

export const config = {
  matcher: [
    // Skip static files and API routes
    '/((?!api|_next/static|_next/image|favicon.ico|.*\\..*$).*)',
  ],
}
```

---

## Multiple Experiments

```tsx
// middleware.ts
import { NextResponse, type NextRequest } from 'next/server'

interface ExperimentConfig {
  weight: number       // Probability of variant B (0-1)
  enabled: boolean     // Kill switch
  targetPath?: string  // Optional: only run on specific paths
}

const EXPERIMENTS: Record<string, ExperimentConfig> = {
  hero_cta: { weight: 0.5, enabled: true },
  pricing_layout: { weight: 0.5, enabled: true, targetPath: '/pricing' },
  signup_flow: { weight: 0.2, enabled: true, targetPath: '/signup' },
  checkout_upsell: { weight: 0.5, enabled: false }, // Paused
}

export function middleware(request: NextRequest) {
  const response = NextResponse.next()
  const pathname = request.nextUrl.pathname

  for (const [name, config] of Object.entries(EXPERIMENTS)) {
    if (!config.enabled) continue

    // Path targeting
    if (config.targetPath && !pathname.startsWith(config.targetPath)) continue

    const cookieName = `exp_${name}`
    const existing = request.cookies.get(cookieName)?.value

    if (!existing) {
      const variant = Math.random() < config.weight ? 'B' : 'A'
      response.cookies.set(cookieName, variant, {
        maxAge: 60 * 60 * 24 * 30,
        httpOnly: false,
        sameSite: 'lax',
        path: '/'
      })
    }
  }

  return response
}
```

---

## Weighted Splits

### Simple Weights (A vs B)

```tsx
const weight = 0.3  // 30% B, 70% A
const variant = Math.random() < weight ? 'B' : 'A'
```

### Multi-Variant (A/B/C)

```tsx
function assignMultiVariant(weights: number[]): string {
  // weights = [0.33, 0.33, 0.34] for equal 3-way split
  const variants = ['A', 'B', 'C']
  const rand = Math.random()
  let cumulative = 0

  for (let i = 0; i < weights.length; i++) {
    cumulative += weights[i]
    if (rand < cumulative) return variants[i]
  }

  return variants[variants.length - 1]
}

// Usage
const variant = assignMultiVariant([0.33, 0.33, 0.34])
```

### Phased Rollout

```tsx
type RolloutPhase = 'early_access' | 'public_beta' | 'general'

const phaseWeights: Record<RolloutPhase, number> = {
  early_access: 0.1,   // 10% new variant
  public_beta: 0.5,    // 50/50
  general: 1.0         // 100% new (test concluded)
}

// Set this in your config (Supabase, env var, Edge Config)
const currentPhase: RolloutPhase = 'public_beta'
const weight = phaseWeights[currentPhase]
```

---

## Segment-Based Assignment

### By Geography

```tsx
// Vercel provides request.geo in middleware
export function middleware(request: NextRequest) {
  const response = NextResponse.next()
  const country = request.geo?.country || 'US'

  // Different experiment for different regions
  const experimentVariants: Record<string, string> = {
    US: Math.random() < 0.5 ? 'A' : 'B',
    GB: 'B',  // UK always gets B (winner from prior test)
    DE: Math.random() < 0.3 ? 'B' : 'A',  // 30% B for Germany
  }

  const variant = experimentVariants[country] ?? (Math.random() < 0.5 ? 'A' : 'B')
  response.cookies.set('exp_hero', variant, { maxAge: 2592000, path: '/' })

  // Also store segment for analysis
  response.cookies.set('exp_segment', country, { maxAge: 2592000, path: '/' })

  return response
}
```

### By Device Type

```tsx
function getDeviceType(userAgent: string): 'mobile' | 'tablet' | 'desktop' {
  if (/mobile/i.test(userAgent)) return 'mobile'
  if (/tablet|ipad/i.test(userAgent)) return 'tablet'
  return 'desktop'
}

export function middleware(request: NextRequest) {
  const response = NextResponse.next()
  const ua = request.headers.get('user-agent') || ''
  const device = getDeviceType(ua)

  // Mobile-specific experiment
  if (device === 'mobile') {
    if (!request.cookies.get('exp_mobile_nav')) {
      const variant = Math.random() < 0.5 ? 'A' : 'B'
      response.cookies.set('exp_mobile_nav', variant, { maxAge: 2592000, path: '/' })
    }
  }

  return response
}
```

### By Referral Source

```tsx
export function middleware(request: NextRequest) {
  const response = NextResponse.next()
  const referer = request.headers.get('referer') || ''
  const utmSource = request.nextUrl.searchParams.get('utm_source')

  // Different treatment for paid vs organic
  const isPaid = utmSource === 'google_ads' || utmSource === 'facebook'

  if (!request.cookies.get('exp_landing')) {
    // Paid traffic gets more aggressive CTA
    const weight = isPaid ? 0.7 : 0.5
    const variant = Math.random() < weight ? 'B' : 'A'
    response.cookies.set('exp_landing', variant, { maxAge: 2592000, path: '/' })
    response.cookies.set('traffic_type', isPaid ? 'paid' : 'organic', { maxAge: 2592000, path: '/' })
  }

  return response
}
```

---

## Reading Variants

### Server Components (App Router)

```tsx
// app/page.tsx
import { cookies } from 'next/headers'

export default function LandingPage() {
  const cookieStore = cookies()
  const heroVariant = cookieStore.get('exp_hero_cta')?.value || 'A'

  return (
    <main>
      {heroVariant === 'A' ? <HeroA /> : <HeroB />}
    </main>
  )
}
```

### Client Components

```tsx
'use client'
import { useEffect, useState } from 'react'

function getCookie(name: string): string | undefined {
  if (typeof document === 'undefined') return undefined
  const match = document.cookie.match(new RegExp(`(^| )${name}=([^;]+)`))
  return match?.[2]
}

export function useExperiment(experimentName: string, defaultVariant = 'A') {
  const [variant, setVariant] = useState(defaultVariant)

  useEffect(() => {
    const v = getCookie(`exp_${experimentName}`)
    if (v) setVariant(v)
  }, [experimentName])

  return variant
}

// Usage
function HeroSection() {
  const variant = useExperiment('hero_cta')

  return variant === 'A' ? <HeroA /> : <HeroB />
}
```

### Route Rewriting (Separate Pages)

For drastically different variants, use separate pages:

```tsx
// middleware.ts
export function middleware(request: NextRequest) {
  const variant = request.cookies.get('exp_landing')?.value

  if (request.nextUrl.pathname === '/') {
    if (variant === 'B') {
      return NextResponse.rewrite(new URL('/landing-b', request.url))
    }
  }

  return NextResponse.next()
}
```

```
app/
  page.tsx           # Default (variant A)
  landing-b/
    page.tsx         # Variant B
```

---

## Dynamic Config

### Vercel Edge Config

```tsx
// middleware.ts
import { get } from '@vercel/edge-config'

interface ExperimentConfig {
  weight: number
  enabled: boolean
}

export async function middleware(request: NextRequest) {
  const response = NextResponse.next()

  // < 15ms read from edge
  const experiments = await get<Record<string, ExperimentConfig>>('experiments')

  if (experiments) {
    for (const [name, config] of Object.entries(experiments)) {
      if (!config.enabled) continue

      const cookieName = `exp_${name}`
      if (!request.cookies.get(cookieName)) {
        const variant = Math.random() < config.weight ? 'B' : 'A'
        response.cookies.set(cookieName, variant, { maxAge: 2592000, path: '/' })
      }
    }
  }

  return response
}
```

### Supabase Config (with caching)

```tsx
// lib/experiments.ts
let cachedConfig: Record<string, ExperimentConfig> | null = null
let cacheTime = 0
const CACHE_TTL = 60000 // 1 minute

export async function getExperimentConfig(): Promise<Record<string, ExperimentConfig>> {
  const now = Date.now()

  if (cachedConfig && now - cacheTime < CACHE_TTL) {
    return cachedConfig
  }

  const { data } = await supabase
    .from('experiments')
    .select('name, weight, enabled')
    .eq('enabled', true)

  cachedConfig = Object.fromEntries(
    (data || []).map(e => [e.name, { weight: e.weight, enabled: e.enabled }])
  )
  cacheTime = now

  return cachedConfig
}
```

---

## Edge Cases

### User Clears Cookies

They get re-randomized. This is usually fine:
- Overall randomization still valid
- Per-user consistency broken but rare
- Alternative: Use hashed user ID if logged in

```tsx
// Consistent assignment for logged-in users
function getConsistentVariant(userId: string, experimentId: string): 'A' | 'B' {
  const hash = cyrb53(`${userId}:${experimentId}`)
  return hash % 2 === 0 ? 'A' : 'B'
}

function cyrb53(str: string): number {
  let h1 = 0xdeadbeef, h2 = 0x41c6ce57
  for (let i = 0; i < str.length; i++) {
    const ch = str.charCodeAt(i)
    h1 = Math.imul(h1 ^ ch, 2654435761)
    h2 = Math.imul(h2 ^ ch, 1597334677)
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507)
  h2 = Math.imul(h2 ^ (h2 >>> 13), 3266489909)
  return 4294967296 * (2097151 & h2) + (h1 >>> 0)
}
```

### Middleware Not Running

For static pages or edge caching issues:

```tsx
// Client-side fallback (in _app.tsx or layout)
useEffect(() => {
  if (!getCookie('exp_hero_cta')) {
    const variant = Math.random() < 0.5 ? 'A' : 'B'
    document.cookie = `exp_hero_cta=${variant}; max-age=2592000; path=/`
    // Optionally reload to get consistent server render
  }
}, [])
```

### Cookie Consent

If cookies require consent, experiment assignment is "functional" not "analytics":

```tsx
// Can assign before consent (functional cookie for site experience)
// But delay TRACKING until consent given
useEffect(() => {
  if (hasAnalyticsConsent) {
    window.dataLayer?.push({
      event: 'experiment_view',
      experiment_variant: variant
    })
  }
}, [hasAnalyticsConsent, variant])
```

### Bot/Crawler Handling

```tsx
export function middleware(request: NextRequest) {
  const ua = request.headers.get('user-agent') || ''

  // Skip experiments for bots
  if (/bot|crawler|spider|googlebot|bingbot/i.test(ua)) {
    return NextResponse.next() // Serve control (A) to bots
  }

  // Normal experiment assignment...
}
```

---

## Naming Convention

```
exp_{page}_{element}_{test_id}
```

Examples:
- `exp_landing_hero_v1`
- `exp_pricing_cta_q1_2024`
- `exp_signup_form_length`
- `exp_checkout_upsell_modal`

Keep experiment names:
- Lowercase with underscores
- Descriptive but concise
- Include version or date for iterative tests
