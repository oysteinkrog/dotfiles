# Personalization and Contextual Bandits
## Table of Contents
- [Personalization Spectrum](#personalization-spectrum)
- [Collecting User Attributes](#collecting-user-attributes)
- [Segment Analysis](#segment-analysis)
- [Rules-Based Personalization](#rules-based-personalization)
- [Multi-Armed Bandits](#multi-armed-bandits)
- [Contextual Bandits](#contextual-bandits)
- [Implementation Patterns](#implementation-patterns)

---

## Personalization Spectrum

### From A/B to Full Personalization
```
Level 0: Static Page (no testing)
   ↓
Level 1: A/B Testing (find one winner for all)
   ↓
Level 2: Segment Testing (find winner per segment)
   ↓
Level 3: Rules-Based (manual segment→variant mapping)
   ↓
Level 4: Multi-Armed Bandit (auto-optimize globally)
   ↓
Level 5: Contextual Bandit (auto-personalize per user)
```

### When to Use Each Level
| Level | Traffic Needed | Complexity | Best For |
|-------|---------------|------------|----------|
| 1 | 1,000+/variant | Low | Clear hypothesis testing |
| 2 | 1,000+/segment | Medium | Known audience differences |
| 3 | N/A | Medium | Post-experiment deployment |
| 4 | 500+/variant | Medium | Fast optimization |
| 5 | 10,000+ total | High | Diverse audiences |

---

## Collecting User Attributes

### Available Context Sources

#### From Request (Edge/Middleware)
```typescript
// middleware.ts
import { NextRequest, NextResponse } from 'next/server';
import { geolocation, ipAddress } from '@vercel/functions';

export function middleware(request: NextRequest) {
  // Geographic data
  const geo = geolocation(request);
  const country = geo?.country || 'US';
  const region = geo?.region || 'unknown';
  const city = geo?.city || 'unknown';

  // Device detection
  const ua = request.headers.get('user-agent') || '';
  const isMobile = /mobile|android|iphone/i.test(ua);
  const isTablet = /ipad|tablet/i.test(ua);
  const deviceType = isMobile ? 'mobile' : isTablet ? 'tablet' : 'desktop';

  // Browser
  const isChrome = ua.includes('Chrome');
  const isSafari = ua.includes('Safari') && !isChrome;
  const isFirefox = ua.includes('Firefox');

  // Traffic source
  const referer = request.headers.get('referer') || '';
  const utmSource = request.nextUrl.searchParams.get('utm_source');
  const utmMedium = request.nextUrl.searchParams.get('utm_medium');
  const utmCampaign = request.nextUrl.searchParams.get('utm_campaign');

  // Time-based
  const hour = new Date().getUTCHours();
  const dayOfWeek = new Date().getUTCDay();
  const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

  // Language preference
  const acceptLanguage = request.headers.get('accept-language') || 'en';
  const primaryLanguage = acceptLanguage.split(',')[0].split('-')[0];

  const userContext = {
    country,
    region,
    city,
    deviceType,
    browser: isChrome ? 'chrome' : isSafari ? 'safari' : isFirefox ? 'firefox' : 'other',
    utmSource,
    utmMedium,
    utmCampaign,
    hour,
    isWeekend,
    language: primaryLanguage,
  };

  // Store in cookie for client access
  const response = NextResponse.next();
  response.cookies.set('user_context', JSON.stringify(userContext), {
    httpOnly: false, // Allow client access
    sameSite: 'lax',
    path: '/',
    maxAge: 86400, // 24 hours
  });

  return response;
}
```

#### From User Session/Profile
```typescript
// lib/user-attributes.ts
import { createClient } from '@supabase/supabase-js';

export interface UserAttributes {
  // From session
  userId?: string;
  isAuthenticated: boolean;

  // From profile
  accountAge?: number; // days
  plan?: 'free' | 'starter' | 'pro' | 'enterprise';
  industry?: string;
  companySize?: 'solo' | 'small' | 'medium' | 'large';

  // From behavior
  visitCount: number;
  lastVisit?: Date;
  pagesViewed: number;
  hasConverted: boolean;

  // Derived segments
  isNewVisitor: boolean;
  isReturning: boolean;
  isHighIntent: boolean;
}

export async function getUserAttributes(
  userId?: string,
  cookies?: Record<string, string>
): Promise<UserAttributes> {
  const visitCookie = cookies?.['visit_history'];
  const visits = visitCookie ? JSON.parse(visitCookie) : [];

  const baseAttrs: UserAttributes = {
    isAuthenticated: !!userId,
    visitCount: visits.length + 1,
    pagesViewed: 0,
    hasConverted: false,
    isNewVisitor: visits.length === 0,
    isReturning: visits.length > 0,
    isHighIntent: false,
  };

  if (!userId) return baseAttrs;

  // Fetch profile from Supabase
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!
  );

  const { data: profile } = await supabase
    .from('profiles')
    .select('plan, industry, company_size, created_at')
    .eq('id', userId)
    .single();

  const { data: conversions } = await supabase
    .from('conversions')
    .select('id')
    .eq('user_id', userId)
    .limit(1);

  if (profile) {
    const createdAt = new Date(profile.created_at);
    const accountAge = Math.floor(
      (Date.now() - createdAt.getTime()) / (1000 * 60 * 60 * 24)
    );

    return {
      ...baseAttrs,
      userId,
      accountAge,
      plan: profile.plan,
      industry: profile.industry,
      companySize: profile.company_size,
      hasConverted: (conversions?.length || 0) > 0,
      isHighIntent: visits.length > 3 || accountAge < 7,
    };
  }

  return { ...baseAttrs, userId };
}
```

#### Privacy Considerations
```typescript
// lib/consent.ts
export type ConsentLevel = 'essential' | 'functional' | 'analytics' | 'marketing';

export interface ConsentState {
  essential: true; // Always true
  functional: boolean;
  analytics: boolean;
  marketing: boolean;
}

export function getConsentState(cookies: Record<string, string>): ConsentState {
  const consentCookie = cookies['cookie_consent'];
  if (!consentCookie) {
    // Default: only essential
    return { essential: true, functional: false, analytics: false, marketing: false };
  }
  return JSON.parse(consentCookie);
}

export function canUseAttribute(
  attribute: string,
  consent: ConsentState
): boolean {
  // Essential: variant assignment, basic bucketing
  const essentialAttrs = ['visitCount', 'isNewVisitor', 'isReturning'];
  if (essentialAttrs.includes(attribute)) return true;

  // Functional: device, language, preferences
  const functionalAttrs = ['deviceType', 'language', 'browser'];
  if (functionalAttrs.includes(attribute)) return consent.functional;

  // Analytics: geo, behavior, segments
  const analyticsAttrs = ['country', 'region', 'pagesViewed', 'isHighIntent'];
  if (analyticsAttrs.includes(attribute)) return consent.analytics;

  // Marketing: UTM, campaign data
  const marketingAttrs = ['utmSource', 'utmMedium', 'utmCampaign'];
  if (marketingAttrs.includes(attribute)) return consent.marketing;

  return false;
}
```

---

## Segment Analysis

### Post-Experiment Segmentation
```typescript
// lib/experiment-analysis.ts
import { createClient } from '@supabase/supabase-js';

interface ExperimentResult {
  variant: string;
  segment: Record<string, string | number | boolean>;
  converted: boolean;
  timestamp: Date;
}

interface SegmentAnalysis {
  segment: string;
  segmentValue: string;
  variantA: { conversions: number; total: number; rate: number };
  variantB: { conversions: number; total: number; rate: number };
  lift: number; // B vs A
  significance: number; // chi-square p-value
  winner: 'A' | 'B' | 'inconclusive';
}

export async function analyzeBySegment(
  experimentId: string,
  segmentKey: string
): Promise<SegmentAnalysis[]> {
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_KEY!
  );

  // Fetch all results with segment data
  const { data: results } = await supabase
    .from('experiment_results')
    .select('variant, segment_data, converted')
    .eq('experiment_id', experimentId);

  if (!results) return [];

  // Group by segment value
  const segments = new Map<string, { A: number[]; B: number[] }>();

  for (const result of results) {
    const segmentValue = String(result.segment_data?.[segmentKey] || 'unknown');

    if (!segments.has(segmentValue)) {
      segments.set(segmentValue, { A: [], B: [] });
    }

    const bucket = segments.get(segmentValue)!;
    const converted = result.converted ? 1 : 0;

    if (result.variant === 'A') {
      bucket.A.push(converted);
    } else {
      bucket.B.push(converted);
    }
  }

  // Calculate stats per segment
  const analyses: SegmentAnalysis[] = [];

  for (const [segmentValue, data] of segments) {
    const aConversions = data.A.reduce((a, b) => a + b, 0);
    const bConversions = data.B.reduce((a, b) => a + b, 0);
    const aTotal = data.A.length;
    const bTotal = data.B.length;

    if (aTotal < 30 || bTotal < 30) continue; // Skip small samples

    const aRate = aConversions / aTotal;
    const bRate = bConversions / bTotal;
    const lift = aRate > 0 ? (bRate - aRate) / aRate : 0;

    // Chi-square test
    const significance = chiSquareTest(
      aConversions, aTotal - aConversions,
      bConversions, bTotal - bConversions
    );

    analyses.push({
      segment: segmentKey,
      segmentValue,
      variantA: { conversions: aConversions, total: aTotal, rate: aRate },
      variantB: { conversions: bConversions, total: bTotal, rate: bRate },
      lift,
      significance,
      winner: significance < 0.05
        ? (bRate > aRate ? 'B' : 'A')
        : 'inconclusive',
    });
  }

  return analyses.sort((a, b) => Math.abs(b.lift) - Math.abs(a.lift));
}

function chiSquareTest(a1: number, a2: number, b1: number, b2: number): number {
  const total = a1 + a2 + b1 + b2;
  const rowA = a1 + a2;
  const rowB = b1 + b2;
  const col1 = a1 + b1;
  const col2 = a2 + b2;

  const expected = [
    (rowA * col1) / total,
    (rowA * col2) / total,
    (rowB * col1) / total,
    (rowB * col2) / total,
  ];

  const observed = [a1, a2, b1, b2];

  let chiSquare = 0;
  for (let i = 0; i < 4; i++) {
    chiSquare += Math.pow(observed[i] - expected[i], 2) / expected[i];
  }

  // Approximate p-value for df=1
  return 1 - normalCDF(Math.sqrt(chiSquare));
}

function normalCDF(x: number): number {
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const p = 0.3275911;

  const sign = x < 0 ? -1 : 1;
  x = Math.abs(x) / Math.sqrt(2);

  const t = 1 / (1 + p * x);
  const y = 1 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x);

  return 0.5 * (1 + sign * y);
}
```

### GA4 Segment Analysis Query
```sql
-- BigQuery: Analyze experiment by country
WITH experiment_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'variant') as variant,
    geo.country as country,
    event_name
  FROM `project.analytics_XXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260101' AND '20260131'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'experiment') = 'landing_test_v2'
),

conversions AS (
  SELECT user_pseudo_id, variant, country
  FROM experiment_events
  WHERE event_name = 'sign_up'
),

exposures AS (
  SELECT DISTINCT user_pseudo_id, variant, country
  FROM experiment_events
  WHERE event_name = 'experiment_exposure'
)

SELECT
  e.country,
  e.variant,
  COUNT(DISTINCT e.user_pseudo_id) as users,
  COUNT(DISTINCT c.user_pseudo_id) as conversions,
  SAFE_DIVIDE(COUNT(DISTINCT c.user_pseudo_id), COUNT(DISTINCT e.user_pseudo_id)) as conversion_rate
FROM exposures e
LEFT JOIN conversions c USING (user_pseudo_id, variant, country)
GROUP BY e.country, e.variant
HAVING users >= 100
ORDER BY e.country, e.variant;
```

---

## Rules-Based Personalization

### Configuration Schema
```typescript
// lib/personalization-rules.ts
export interface PersonalizationRule {
  id: string;
  name: string;
  priority: number; // Lower = higher priority
  conditions: RuleCondition[];
  conditionLogic: 'AND' | 'OR';
  variant: string;
  enabled: boolean;
  experiment?: string; // Optional: only apply if in this experiment
}

export interface RuleCondition {
  attribute: string;
  operator: 'eq' | 'neq' | 'gt' | 'lt' | 'gte' | 'lte' | 'contains' | 'in';
  value: string | number | boolean | string[];
}

// Example rules
export const defaultRules: PersonalizationRule[] = [
  {
    id: 'uk-pricing',
    name: 'UK users prefer GBP pricing',
    priority: 1,
    conditions: [
      { attribute: 'country', operator: 'eq', value: 'GB' },
    ],
    conditionLogic: 'AND',
    variant: 'pricing-gbp',
    enabled: true,
  },
  {
    id: 'mobile-simple',
    name: 'Mobile users get simplified CTA',
    priority: 2,
    conditions: [
      { attribute: 'deviceType', operator: 'eq', value: 'mobile' },
    ],
    conditionLogic: 'AND',
    variant: 'cta-simple',
    enabled: true,
  },
  {
    id: 'returning-social-proof',
    name: 'Returning visitors see social proof',
    priority: 3,
    conditions: [
      { attribute: 'visitCount', operator: 'gt', value: 1 },
      { attribute: 'hasConverted', operator: 'eq', value: false },
    ],
    conditionLogic: 'AND',
    variant: 'hero-social-proof',
    enabled: true,
  },
  {
    id: 'high-intent-urgent',
    name: 'High-intent users see urgency messaging',
    priority: 4,
    conditions: [
      { attribute: 'isHighIntent', operator: 'eq', value: true },
      { attribute: 'pagesViewed', operator: 'gte', value: 5 },
    ],
    conditionLogic: 'AND',
    variant: 'cta-urgent',
    enabled: true,
  },
];
```

### Rule Evaluation Engine
```typescript
// lib/rule-engine.ts
import { PersonalizationRule, RuleCondition } from './personalization-rules';

export function evaluateRules(
  rules: PersonalizationRule[],
  context: Record<string, unknown>,
  experimentFilter?: string
): string | null {
  // Sort by priority (lower first)
  const sortedRules = [...rules]
    .filter(r => r.enabled)
    .filter(r => !experimentFilter || r.experiment === experimentFilter)
    .sort((a, b) => a.priority - b.priority);

  for (const rule of sortedRules) {
    if (evaluateRule(rule, context)) {
      return rule.variant;
    }
  }

  return null; // No rule matched
}

function evaluateRule(
  rule: PersonalizationRule,
  context: Record<string, unknown>
): boolean {
  const results = rule.conditions.map(c => evaluateCondition(c, context));

  if (rule.conditionLogic === 'AND') {
    return results.every(r => r);
  } else {
    return results.some(r => r);
  }
}

function evaluateCondition(
  condition: RuleCondition,
  context: Record<string, unknown>
): boolean {
  const contextValue = context[condition.attribute];
  const ruleValue = condition.value;

  switch (condition.operator) {
    case 'eq':
      return contextValue === ruleValue;
    case 'neq':
      return contextValue !== ruleValue;
    case 'gt':
      return typeof contextValue === 'number' && contextValue > (ruleValue as number);
    case 'lt':
      return typeof contextValue === 'number' && contextValue < (ruleValue as number);
    case 'gte':
      return typeof contextValue === 'number' && contextValue >= (ruleValue as number);
    case 'lte':
      return typeof contextValue === 'number' && contextValue <= (ruleValue as number);
    case 'contains':
      return typeof contextValue === 'string' &&
             contextValue.toLowerCase().includes((ruleValue as string).toLowerCase());
    case 'in':
      return Array.isArray(ruleValue) && ruleValue.includes(contextValue);
    default:
      return false;
  }
}
```

### Middleware with Rules
```typescript
// middleware.ts with personalization
import { NextRequest, NextResponse } from 'next/server';
import { evaluateRules } from './lib/rule-engine';
import { defaultRules } from './lib/personalization-rules';

export async function middleware(request: NextRequest) {
  const response = NextResponse.next();

  // Build context from request
  const context = {
    country: request.geo?.country || 'US',
    deviceType: /mobile/i.test(request.headers.get('user-agent') || '') ? 'mobile' : 'desktop',
    visitCount: parseInt(request.cookies.get('visit_count')?.value || '0') + 1,
    isHighIntent: request.cookies.get('high_intent')?.value === 'true',
    pagesViewed: parseInt(request.cookies.get('pages_viewed')?.value || '0'),
    hasConverted: request.cookies.get('converted')?.value === 'true',
  };

  // Check personalization rules first
  const personalizedVariant = evaluateRules(defaultRules, context);

  if (personalizedVariant) {
    response.cookies.set('variant', personalizedVariant, {
      path: '/',
      sameSite: 'lax',
      maxAge: 86400 * 7,
    });
    response.cookies.set('variant_source', 'personalization', {
      path: '/',
      sameSite: 'lax',
    });
  } else {
    // Fall back to random A/B assignment
    const existingVariant = request.cookies.get('variant')?.value;
    if (!existingVariant) {
      const variant = Math.random() < 0.5 ? 'A' : 'B';
      response.cookies.set('variant', variant, {
        path: '/',
        sameSite: 'lax',
        maxAge: 86400 * 7,
      });
      response.cookies.set('variant_source', 'random', {
        path: '/',
        sameSite: 'lax',
      });
    }
  }

  // Update visit count
  response.cookies.set('visit_count', String(context.visitCount), {
    path: '/',
    sameSite: 'lax',
    maxAge: 86400 * 365,
  });

  return response;
}
```

---

## Multi-Armed Bandits

### Thompson Sampling (TypeScript)
```typescript
// lib/thompson-sampling.ts

interface BanditArm {
  name: string;
  alpha: number; // Successes + 1
  beta: number;  // Failures + 1
}

interface BanditState {
  experimentId: string;
  arms: BanditArm[];
  totalPulls: number;
  lastUpdated: Date;
}

// Beta distribution sampling using Box-Muller approximation
function sampleBeta(alpha: number, beta: number): number {
  // Use gamma sampling: Beta(a,b) = Gamma(a,1) / (Gamma(a,1) + Gamma(b,1))
  const gammaA = sampleGamma(alpha);
  const gammaB = sampleGamma(beta);
  return gammaA / (gammaA + gammaB);
}

function sampleGamma(shape: number): number {
  // Marsaglia and Tsang's method
  if (shape < 1) {
    return sampleGamma(1 + shape) * Math.pow(Math.random(), 1 / shape);
  }

  const d = shape - 1/3;
  const c = 1 / Math.sqrt(9 * d);

  while (true) {
    let x: number, v: number;
    do {
      x = normalRandom();
      v = 1 + c * x;
    } while (v <= 0);

    v = v * v * v;
    const u = Math.random();

    if (u < 1 - 0.0331 * (x * x) * (x * x)) {
      return d * v;
    }

    if (Math.log(u) < 0.5 * x * x + d * (1 - v + Math.log(v))) {
      return d * v;
    }
  }
}

function normalRandom(): number {
  const u1 = Math.random();
  const u2 = Math.random();
  return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

export class ThompsonSamplingBandit {
  private state: BanditState;

  constructor(experimentId: string, variants: string[]) {
    this.state = {
      experimentId,
      arms: variants.map(name => ({ name, alpha: 1, beta: 1 })),
      totalPulls: 0,
      lastUpdated: new Date(),
    };
  }

  static fromState(state: BanditState): ThompsonSamplingBandit {
    const bandit = new ThompsonSamplingBandit(state.experimentId, []);
    bandit.state = state;
    return bandit;
  }

  selectArm(): string {
    // Sample from each arm's posterior
    let bestArm = this.state.arms[0];
    let bestSample = -1;

    for (const arm of this.state.arms) {
      const sample = sampleBeta(arm.alpha, arm.beta);
      if (sample > bestSample) {
        bestSample = sample;
        bestArm = arm;
      }
    }

    return bestArm.name;
  }

  recordOutcome(armName: string, success: boolean): void {
    const arm = this.state.arms.find(a => a.name === armName);
    if (!arm) return;

    if (success) {
      arm.alpha += 1;
    } else {
      arm.beta += 1;
    }

    this.state.totalPulls += 1;
    this.state.lastUpdated = new Date();
  }

  getStats(): { name: string; mean: number; samples: number; winProb: number }[] {
    // Monte Carlo to estimate win probabilities
    const samples = 10000;
    const wins = new Map<string, number>();

    for (const arm of this.state.arms) {
      wins.set(arm.name, 0);
    }

    for (let i = 0; i < samples; i++) {
      let bestArm = '';
      let bestValue = -1;

      for (const arm of this.state.arms) {
        const value = sampleBeta(arm.alpha, arm.beta);
        if (value > bestValue) {
          bestValue = value;
          bestArm = arm.name;
        }
      }

      wins.set(bestArm, (wins.get(bestArm) || 0) + 1);
    }

    return this.state.arms.map(arm => ({
      name: arm.name,
      mean: arm.alpha / (arm.alpha + arm.beta),
      samples: arm.alpha + arm.beta - 2, // Subtract priors
      winProb: (wins.get(arm.name) || 0) / samples,
    }));
  }

  getState(): BanditState {
    return { ...this.state };
  }

  shouldExploit(): boolean {
    // Check if any arm has >95% win probability
    const stats = this.getStats();
    return stats.some(s => s.winProb > 0.95);
  }
}
```

### Bandit-Based Assignment
```typescript
// lib/bandit-assignment.ts
import { createClient } from '@supabase/supabase-js';
import { ThompsonSamplingBandit } from './thompson-sampling';

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_KEY!
);

// Cache bandit state in memory (refresh every 5 minutes)
const banditCache = new Map<string, { bandit: ThompsonSamplingBandit; expires: number }>();

export async function getBanditVariant(experimentId: string): Promise<string> {
  const cached = banditCache.get(experimentId);
  if (cached && cached.expires > Date.now()) {
    return cached.bandit.selectArm();
  }

  // Load from database
  const { data: experiment } = await supabase
    .from('experiments')
    .select('id, variants, bandit_state')
    .eq('id', experimentId)
    .single();

  if (!experiment) {
    throw new Error(`Experiment ${experimentId} not found`);
  }

  let bandit: ThompsonSamplingBandit;

  if (experiment.bandit_state) {
    bandit = ThompsonSamplingBandit.fromState(experiment.bandit_state);
  } else {
    bandit = new ThompsonSamplingBandit(experimentId, experiment.variants);
  }

  // Cache for 5 minutes
  banditCache.set(experimentId, {
    bandit,
    expires: Date.now() + 5 * 60 * 1000,
  });

  return bandit.selectArm();
}

export async function recordBanditConversion(
  experimentId: string,
  variant: string,
  converted: boolean
): Promise<void> {
  // Get current state
  const { data: experiment } = await supabase
    .from('experiments')
    .select('bandit_state, variants')
    .eq('id', experimentId)
    .single();

  if (!experiment) return;

  let bandit: ThompsonSamplingBandit;

  if (experiment.bandit_state) {
    bandit = ThompsonSamplingBandit.fromState(experiment.bandit_state);
  } else {
    bandit = new ThompsonSamplingBandit(experimentId, experiment.variants);
  }

  // Update with outcome
  bandit.recordOutcome(variant, converted);

  // Save state
  await supabase
    .from('experiments')
    .update({ bandit_state: bandit.getState() })
    .eq('id', experimentId);

  // Invalidate cache
  banditCache.delete(experimentId);
}
```

---

## Contextual Bandits

### Concept Overview
Contextual bandits extend multi-armed bandits by considering user context when selecting arms. Instead of finding one globally-optimal variant, they learn which variant works best for each type of user.

```
Standard Bandit:
  User → [Select Best Arm] → Variant

Contextual Bandit:
  User + Context → [Model: context → arm] → Personalized Variant
```

### Simple Contextual Bandit (Segment-Based)
```typescript
// lib/contextual-bandit.ts
import { ThompsonSamplingBandit } from './thompson-sampling';

interface ContextualBanditState {
  experimentId: string;
  contextKey: string; // e.g., 'country' or 'deviceType'
  segments: Record<string, ReturnType<ThompsonSamplingBandit['getState']>>;
}

export class SegmentedBandit {
  private experimentId: string;
  private contextKey: string;
  private variants: string[];
  private bandits: Map<string, ThompsonSamplingBandit>;

  constructor(experimentId: string, contextKey: string, variants: string[]) {
    this.experimentId = experimentId;
    this.contextKey = contextKey;
    this.variants = variants;
    this.bandits = new Map();
  }

  private getBanditForSegment(segmentValue: string): ThompsonSamplingBandit {
    let bandit = this.bandits.get(segmentValue);
    if (!bandit) {
      bandit = new ThompsonSamplingBandit(
        `${this.experimentId}_${segmentValue}`,
        this.variants
      );
      this.bandits.set(segmentValue, bandit);
    }
    return bandit;
  }

  selectArm(context: Record<string, unknown>): string {
    const segmentValue = String(context[this.contextKey] || 'default');
    const bandit = this.getBanditForSegment(segmentValue);
    return bandit.selectArm();
  }

  recordOutcome(
    context: Record<string, unknown>,
    armName: string,
    success: boolean
  ): void {
    const segmentValue = String(context[this.contextKey] || 'default');
    const bandit = this.getBanditForSegment(segmentValue);
    bandit.recordOutcome(armName, success);
  }

  getSegmentStats(): Record<string, ReturnType<ThompsonSamplingBandit['getStats']>> {
    const stats: Record<string, ReturnType<ThompsonSamplingBandit['getStats']>> = {};
    for (const [segment, bandit] of this.bandits) {
      stats[segment] = bandit.getStats();
    }
    return stats;
  }

  getState(): ContextualBanditState {
    const segments: Record<string, ReturnType<ThompsonSamplingBandit['getState']>> = {};
    for (const [segment, bandit] of this.bandits) {
      segments[segment] = bandit.getState();
    }
    return {
      experimentId: this.experimentId,
      contextKey: this.contextKey,
      segments,
    };
  }

  static fromState(
    state: ContextualBanditState,
    variants: string[]
  ): SegmentedBandit {
    const bandit = new SegmentedBandit(
      state.experimentId,
      state.contextKey,
      variants
    );

    for (const [segment, banditState] of Object.entries(state.segments)) {
      bandit.bandits.set(
        segment,
        ThompsonSamplingBandit.fromState(banditState)
      );
    }

    return bandit;
  }
}
```

### Multi-Context Bandit
```typescript
// lib/multi-context-bandit.ts
import { ThompsonSamplingBandit } from './thompson-sampling';

// Create composite segment key from multiple context attributes
function createSegmentKey(
  context: Record<string, unknown>,
  contextKeys: string[]
): string {
  return contextKeys
    .map(key => `${key}:${context[key] || 'unknown'}`)
    .join('|');
}

export class MultiContextBandit {
  private experimentId: string;
  private contextKeys: string[];
  private variants: string[];
  private bandits: Map<string, ThompsonSamplingBandit>;
  private fallbackBandit: ThompsonSamplingBandit;
  private minSamplesPerSegment: number;

  constructor(
    experimentId: string,
    contextKeys: string[],
    variants: string[],
    minSamplesPerSegment = 30
  ) {
    this.experimentId = experimentId;
    this.contextKeys = contextKeys;
    this.variants = variants;
    this.bandits = new Map();
    this.fallbackBandit = new ThompsonSamplingBandit(experimentId, variants);
    this.minSamplesPerSegment = minSamplesPerSegment;
  }

  selectArm(context: Record<string, unknown>): string {
    const segmentKey = createSegmentKey(context, this.contextKeys);
    const bandit = this.bandits.get(segmentKey);

    // Use fallback if segment has insufficient data
    if (!bandit || this.getTotalSamples(bandit) < this.minSamplesPerSegment) {
      return this.fallbackBandit.selectArm();
    }

    return bandit.selectArm();
  }

  private getTotalSamples(bandit: ThompsonSamplingBandit): number {
    const state = bandit.getState();
    return state.arms.reduce((sum, arm) => sum + arm.alpha + arm.beta - 2, 0);
  }

  recordOutcome(
    context: Record<string, unknown>,
    armName: string,
    success: boolean
  ): void {
    const segmentKey = createSegmentKey(context, this.contextKeys);

    // Get or create bandit for this segment
    let bandit = this.bandits.get(segmentKey);
    if (!bandit) {
      bandit = new ThompsonSamplingBandit(
        `${this.experimentId}_${segmentKey}`,
        this.variants
      );
      this.bandits.set(segmentKey, bandit);
    }

    // Update both segment and fallback
    bandit.recordOutcome(armName, success);
    this.fallbackBandit.recordOutcome(armName, success);
  }
}
```

---

## Implementation Patterns

### Hybrid: Rules + Bandit
```typescript
// lib/hybrid-personalization.ts
import { evaluateRules, PersonalizationRule } from './rule-engine';
import { SegmentedBandit } from './contextual-bandit';

interface HybridConfig {
  rules: PersonalizationRule[];
  bandit: SegmentedBandit | null;
  banditFallbackProbability: number; // 0-1
}

export function selectVariant(
  config: HybridConfig,
  context: Record<string, unknown>
): { variant: string; source: 'rule' | 'bandit' | 'random' } {
  // 1. Try rules first
  const ruleVariant = evaluateRules(config.rules, context);
  if (ruleVariant) {
    return { variant: ruleVariant, source: 'rule' };
  }

  // 2. Use bandit if available
  if (config.bandit) {
    // Exploration: sometimes fall back to random
    if (Math.random() < config.banditFallbackProbability) {
      const variants = config.bandit.getState().segments;
      const variantNames = Object.keys(variants)[0]
        ? Object.keys(variants)
        : ['A', 'B'];
      const randomIndex = Math.floor(Math.random() * variantNames.length);
      return { variant: variantNames[randomIndex], source: 'random' };
    }

    const banditVariant = config.bandit.selectArm(context);
    return { variant: banditVariant, source: 'bandit' };
  }

  // 3. Pure random fallback
  return {
    variant: Math.random() < 0.5 ? 'A' : 'B',
    source: 'random',
  };
}
```

### Gradual Rollout Pattern
```typescript
// lib/gradual-rollout.ts

interface RolloutStage {
  name: string;
  percentage: number;
  startDate: Date;
  endDate?: Date;
}

interface RolloutConfig {
  experimentId: string;
  stages: RolloutStage[];
  winnerVariant?: string;
}

export function getRolloutPercentage(config: RolloutConfig): number {
  const now = new Date();

  // If winner declared, 100% to winner
  if (config.winnerVariant) {
    return 100;
  }

  // Find active stage
  for (let i = config.stages.length - 1; i >= 0; i--) {
    const stage = config.stages[i];
    if (now >= stage.startDate && (!stage.endDate || now < stage.endDate)) {
      return stage.percentage;
    }
  }

  return 0; // Not yet started
}

// Example rollout plan
const exampleRollout: RolloutConfig = {
  experimentId: 'new-checkout-v2',
  stages: [
    { name: 'internal', percentage: 5, startDate: new Date('2026-01-01') },
    { name: 'early-access', percentage: 20, startDate: new Date('2026-01-08') },
    { name: 'beta', percentage: 50, startDate: new Date('2026-01-15') },
    { name: 'ga', percentage: 100, startDate: new Date('2026-01-22') },
  ],
};
```

### Tracking Personalization Source
```typescript
// Always track how variant was assigned
import { sendGTMEvent } from '@next/third-parties/google';

export function trackExposure(
  experimentId: string,
  variant: string,
  source: 'rule' | 'bandit' | 'random',
  context: Record<string, unknown>
): void {
  sendGTMEvent({
    event: 'experiment_exposure',
    experiment_id: experimentId,
    variant,
    assignment_source: source,
    // Include key context for analysis
    user_country: context.country,
    user_device: context.deviceType,
    is_new_visitor: context.isNewVisitor,
  });
}
```

---

## Key Takeaways

1. **Start simple**: Begin with A/B testing, add personalization as you learn
2. **Segment analysis first**: Analyze by segments before building automated personalization
3. **Rules for known patterns**: Use rules when you have strong evidence (e.g., from past experiments)
4. **Bandits for optimization**: Use bandits when you want to maximize conversions during learning
5. **Contextual for diversity**: Use contextual bandits when your audience is diverse and responds differently
6. **Always track source**: Know why each user got each variant for debugging and analysis
7. **Respect privacy**: Only use attributes user has consented to share
