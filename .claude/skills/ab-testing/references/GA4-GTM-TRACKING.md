# GA4 and GTM Tracking for A/B Tests
## Table of Contents
- [Tracking Architecture](#tracking-architecture)
- [GTM Configuration](#gtm-configuration)
- [Event Implementation](#event-implementation)
- [Custom Dimensions](#custom-dimensions)
- [BigQuery Export](#bigquery-export)
- [Debugging and Validation](#debugging-and-validation)

---

## Tracking Architecture

### Data Flow
```
┌─────────────────────────────────────────────────────────────┐
│  User Interaction                                            │
├─────────────────────────────────────────────────────────────┤
│  1. Page Load → Experiment Exposure Event                    │
│  2. User Action → CTA Click / Form Submit Event              │
│  3. Conversion → Sign-up / Purchase Event                    │
├─────────────────────────────────────────────────────────────┤
│                          ↓                                   │
│  Next.js → dataLayer.push() → GTM → GA4                     │
│                          ↓                                   │
│  GA4 → BigQuery (daily export)                               │
│                          ↓                                   │
│  Analysis Dashboard (Supabase + BigQuery)                    │
└─────────────────────────────────────────────────────────────┘
```

### Event Schema
```typescript
// All A/B test events include these parameters
interface ABTestEventParams {
  experiment_id: string;      // Unique experiment identifier
  experiment_name: string;    // Human-readable name
  variant: string;            // A, B, C, etc.
  variant_source: string;     // 'random' | 'rule' | 'bandit'
  user_segment?: string;      // Optional segment info
}

// Event types
type ExperimentEvent =
  | 'experiment_exposure'     // User saw the variant
  | 'experiment_interaction'  // User interacted (click, scroll)
  | 'experiment_conversion'   // User converted (primary goal)
  | 'experiment_goal';        // Secondary goal reached
```

---

## GTM Configuration

### Container Setup
```json
{
  "containerName": "SaaS App - A/B Testing",
  "containers": [
    {
      "type": "web",
      "path": "GTM-XXXXXXX"
    }
  ]
}
```

### Data Layer Variables
Create these variables in GTM:

```
Variable: DLV - Experiment ID
Type: Data Layer Variable
Data Layer Variable Name: experiment_id

Variable: DLV - Experiment Name
Type: Data Layer Variable
Data Layer Variable Name: experiment_name

Variable: DLV - Variant
Type: Data Layer Variable
Data Layer Variable Name: variant

Variable: DLV - Variant Source
Type: Data Layer Variable
Data Layer Variable Name: variant_source

Variable: DLV - Event ID
Type: Data Layer Variable
Data Layer Variable Name: event_id
```

### Custom Event Triggers
```
Trigger: Experiment Exposure
Type: Custom Event
Event Name: experiment_exposure

Trigger: Experiment Conversion
Type: Custom Event
Event Name: experiment_conversion

Trigger: CTA Click - Experiment
Type: Custom Event
Event Name: cta_click
Condition: {{DLV - Experiment ID}} is not undefined
```

### GA4 Event Tags
```
Tag: GA4 - Experiment Exposure
Type: Google Analytics: GA4 Event
Configuration Tag: {{GA4 Configuration}}
Event Name: experiment_exposure
Event Parameters:
  - experiment_id: {{DLV - Experiment ID}}
  - experiment_name: {{DLV - Experiment Name}}
  - variant: {{DLV - Variant}}
  - variant_source: {{DLV - Variant Source}}
Trigger: Experiment Exposure

Tag: GA4 - Experiment Conversion
Type: Google Analytics: GA4 Event
Configuration Tag: {{GA4 Configuration}}
Event Name: experiment_conversion
Event Parameters:
  - experiment_id: {{DLV - Experiment ID}}
  - variant: {{DLV - Variant}}
  - value: {{DLV - Conversion Value}}
Trigger: Experiment Conversion
```

### GA4 Configuration Tag
```
Tag: GA4 Configuration
Type: Google Analytics: GA4 Configuration
Measurement ID: G-XXXXXXXXXX
Configuration Settings:
  Fields to Set:
    - send_page_view: false (we control this manually)
  User Properties:
    - ab_test_variant: {{DLV - Variant}}
```

---

## Event Implementation

### Next.js Integration
```typescript
// lib/analytics.ts
import { sendGTMEvent } from '@next/third-parties/google';

interface ExperimentContext {
  experimentId: string;
  experimentName: string;
  variant: string;
  variantSource: 'random' | 'rule' | 'bandit';
}

// Generate unique event ID for deduplication
function generateEventId(): string {
  return crypto.randomUUID();
}

export function trackExperimentExposure(context: ExperimentContext): void {
  sendGTMEvent({
    event: 'experiment_exposure',
    experiment_id: context.experimentId,
    experiment_name: context.experimentName,
    variant: context.variant,
    variant_source: context.variantSource,
    event_id: generateEventId(),
  });
}

export function trackExperimentConversion(
  context: ExperimentContext,
  conversionType: string,
  value?: number
): void {
  sendGTMEvent({
    event: 'experiment_conversion',
    experiment_id: context.experimentId,
    experiment_name: context.experimentName,
    variant: context.variant,
    conversion_type: conversionType,
    conversion_value: value,
    event_id: generateEventId(),
  });
}

export function trackCTAClick(
  context: ExperimentContext,
  ctaId: string,
  ctaLabel: string
): void {
  sendGTMEvent({
    event: 'cta_click',
    experiment_id: context.experimentId,
    variant: context.variant,
    cta_id: ctaId,
    cta_label: ctaLabel,
    event_id: generateEventId(),
  });
}

export function trackFormSubmit(
  context: ExperimentContext,
  formId: string,
  success: boolean
): void {
  sendGTMEvent({
    event: 'form_submit',
    experiment_id: context.experimentId,
    variant: context.variant,
    form_id: formId,
    form_success: success,
    event_id: generateEventId(),
  });
}
```

### React Hook for Experiment Tracking
```typescript
// hooks/use-experiment-tracking.ts
'use client';

import { useEffect, useRef } from 'react';
import { trackExperimentExposure, ExperimentContext } from '@/lib/analytics';

export function useExperimentTracking(context: ExperimentContext | null) {
  const hasTracked = useRef(false);

  useEffect(() => {
    // Only track once per page load
    if (context && !hasTracked.current) {
      trackExperimentExposure(context);
      hasTracked.current = true;
    }
  }, [context]);

  // Reset on unmount (for SPA navigation)
  useEffect(() => {
    return () => {
      hasTracked.current = false;
    };
  }, []);
}
```

### Page Component Integration
```typescript
// app/landing/page.tsx
import { cookies } from 'next/headers';
import { LandingPageA } from '@/components/landing/variant-a';
import { LandingPageB } from '@/components/landing/variant-b';
import { ExperimentTracker } from '@/components/experiment-tracker';

export default async function LandingPage() {
  const cookieStore = await cookies();
  const variant = cookieStore.get('exp_landing_hero')?.value || 'A';
  const variantSource = cookieStore.get('variant_source')?.value || 'random';

  const experimentContext = {
    experimentId: 'landing_hero_v2',
    experimentName: 'Landing Page Hero Test',
    variant,
    variantSource: variantSource as 'random' | 'rule' | 'bandit',
  };

  return (
    <>
      <ExperimentTracker context={experimentContext} />
      {variant === 'B' ? <LandingPageB /> : <LandingPageA />}
    </>
  );
}

// components/experiment-tracker.tsx
'use client';

import { useExperimentTracking } from '@/hooks/use-experiment-tracking';

export function ExperimentTracker({
  context,
}: {
  context: ExperimentContext;
}) {
  useExperimentTracking(context);
  return null;
}
```

### CTA Button with Tracking
```typescript
// components/cta-button.tsx
'use client';

import { useExperimentContext } from '@/hooks/use-experiment-context';
import { trackCTAClick } from '@/lib/analytics';

interface CTAButtonProps {
  id: string;
  label: string;
  onClick?: () => void;
  children: React.ReactNode;
  className?: string;
}

export function CTAButton({
  id,
  label,
  onClick,
  children,
  className,
}: CTAButtonProps) {
  const experimentContext = useExperimentContext();

  const handleClick = () => {
    // Track CTA click if in experiment
    if (experimentContext) {
      trackCTAClick(experimentContext, id, label);
    }

    onClick?.();
  };

  return (
    <button
      onClick={handleClick}
      className={className}
      data-cta-id={id}
      data-cta-label={label}
    >
      {children}
    </button>
  );
}
```

### Form with Conversion Tracking
```typescript
// components/signup-form.tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useExperimentContext } from '@/hooks/use-experiment-context';
import { trackExperimentConversion, trackFormSubmit } from '@/lib/analytics';

export function SignupForm() {
  const router = useRouter();
  const experimentContext = useExperimentContext();
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setLoading(true);

    const formData = new FormData(e.currentTarget);

    try {
      const response = await fetch('/api/auth/signup', {
        method: 'POST',
        body: JSON.stringify({
          email: formData.get('email'),
          password: formData.get('password'),
        }),
        headers: { 'Content-Type': 'application/json' },
      });

      if (response.ok) {
        // Track successful conversion
        if (experimentContext) {
          trackFormSubmit(experimentContext, 'signup', true);
          trackExperimentConversion(experimentContext, 'signup');
        }

        router.push('/dashboard');
      } else {
        if (experimentContext) {
          trackFormSubmit(experimentContext, 'signup', false);
        }
        // Handle error
      }
    } catch (error) {
      if (experimentContext) {
        trackFormSubmit(experimentContext, 'signup', false);
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <input
        type="email"
        name="email"
        placeholder="Email"
        required
        className="w-full border rounded px-3 py-2"
      />
      <input
        type="password"
        name="password"
        placeholder="Password"
        required
        className="w-full border rounded px-3 py-2"
      />
      <button
        type="submit"
        disabled={loading}
        className="w-full bg-blue-600 text-white py-2 rounded"
      >
        {loading ? 'Creating account...' : 'Sign Up'}
      </button>
    </form>
  );
}
```

---

## Custom Dimensions

### GA4 Custom Dimensions Setup
Configure in GA4 Admin → Custom definitions:

| Dimension Name | Scope | Parameter |
|---------------|-------|-----------|
| Experiment ID | Event | experiment_id |
| Experiment Variant | Event | variant |
| Variant Source | Event | variant_source |
| User Segment | Event | user_segment |
| CTA ID | Event | cta_id |

### User Properties
```typescript
// Set user property on first exposure
function setUserExperimentProperty(variant: string): void {
  sendGTMEvent({
    event: 'set_user_properties',
    user_properties: {
      ab_test_cohort: variant,
      first_experiment_date: new Date().toISOString().split('T')[0],
    },
  });
}
```

### Session-Level Tracking
```typescript
// Track session info for cohort analysis
function trackSessionStart(experiments: Record<string, string>): void {
  sendGTMEvent({
    event: 'session_start_with_experiments',
    active_experiments: Object.keys(experiments).join(','),
    experiment_variants: Object.entries(experiments)
      .map(([exp, variant]) => `${exp}:${variant}`)
      .join(','),
  });
}
```

---

## BigQuery Export

### Enable GA4 → BigQuery Export
1. Go to GA4 Admin → BigQuery Links
2. Create new link to your GCP project
3. Enable daily export (free) or streaming (paid)
4. Select "Export all events"

### Query: Experiment Results
```sql
-- BigQuery: Get conversion rates by experiment and variant
WITH exposures AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'experiment_id') as experiment_id,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'variant') as variant,
    MIN(event_timestamp) as first_exposure_ts
  FROM `project.analytics_XXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'experiment_exposure'
  GROUP BY user_pseudo_id, experiment_id, variant
),

conversions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'experiment_id') as experiment_id,
    MIN(event_timestamp) as conversion_ts
  FROM `project.analytics_XXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'experiment_conversion'
  GROUP BY user_pseudo_id, experiment_id
)

SELECT
  e.experiment_id,
  e.variant,
  COUNT(DISTINCT e.user_pseudo_id) as users_exposed,
  COUNT(DISTINCT c.user_pseudo_id) as users_converted,
  SAFE_DIVIDE(
    COUNT(DISTINCT c.user_pseudo_id),
    COUNT(DISTINCT e.user_pseudo_id)
  ) as conversion_rate
FROM exposures e
LEFT JOIN conversions c
  ON e.user_pseudo_id = c.user_pseudo_id
  AND e.experiment_id = c.experiment_id
  AND c.conversion_ts > e.first_exposure_ts  -- Conversion after exposure
GROUP BY e.experiment_id, e.variant
ORDER BY e.experiment_id, e.variant;
```

### Query: Daily Conversion Trend
```sql
-- BigQuery: Daily conversion rate trend
WITH daily_data AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp)) as date,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'experiment_id') as experiment_id,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'variant') as variant,
    event_name,
    user_pseudo_id
  FROM `project.analytics_XXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260101' AND '20260131'
    AND event_name IN ('experiment_exposure', 'experiment_conversion')
    AND (SELECT value.string_value FROM UNNEST(event_params)
         WHERE key = 'experiment_id') = 'landing_hero_v2'
)

SELECT
  date,
  variant,
  COUNT(DISTINCT CASE WHEN event_name = 'experiment_exposure'
                      THEN user_pseudo_id END) as exposures,
  COUNT(DISTINCT CASE WHEN event_name = 'experiment_conversion'
                      THEN user_pseudo_id END) as conversions,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'experiment_conversion'
                        THEN user_pseudo_id END),
    COUNT(DISTINCT CASE WHEN event_name = 'experiment_exposure'
                        THEN user_pseudo_id END)
  ) as conversion_rate
FROM daily_data
GROUP BY date, variant
ORDER BY date, variant;
```

### Query: Segment Analysis
```sql
-- BigQuery: Conversion by country and variant
WITH experiment_data AS (
  SELECT
    user_pseudo_id,
    geo.country as country,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'experiment_id') as experiment_id,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'variant') as variant,
    event_name
  FROM `project.analytics_XXXXX.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260101' AND '20260131'
    AND event_name IN ('experiment_exposure', 'experiment_conversion')
)

SELECT
  country,
  variant,
  COUNT(DISTINCT CASE WHEN event_name = 'experiment_exposure'
                      THEN user_pseudo_id END) as exposures,
  COUNT(DISTINCT CASE WHEN event_name = 'experiment_conversion'
                      THEN user_pseudo_id END) as conversions,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'experiment_conversion'
                        THEN user_pseudo_id END),
    COUNT(DISTINCT CASE WHEN event_name = 'experiment_exposure'
                        THEN user_pseudo_id END)
  ) as conversion_rate
FROM experiment_data
WHERE experiment_id = 'landing_hero_v2'
GROUP BY country, variant
HAVING exposures >= 100  -- Minimum sample
ORDER BY country, variant;
```

### Scheduled Query for Dashboard
```sql
-- Create scheduled query to materialize daily results
CREATE OR REPLACE TABLE `project.analytics_dashboard.experiment_daily_summary`
PARTITION BY date
AS
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) as date,
  (SELECT value.string_value FROM UNNEST(event_params)
   WHERE key = 'experiment_id') as experiment_id,
  (SELECT value.string_value FROM UNNEST(event_params)
   WHERE key = 'variant') as variant,
  geo.country,
  device.category as device_type,
  COUNT(DISTINCT CASE WHEN event_name = 'experiment_exposure'
                      THEN user_pseudo_id END) as exposures,
  COUNT(DISTINCT CASE WHEN event_name = 'experiment_conversion'
                      THEN user_pseudo_id END) as conversions
FROM `project.analytics_XXXXX.events_*`
WHERE _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
  AND event_name IN ('experiment_exposure', 'experiment_conversion')
GROUP BY date, experiment_id, variant, country, device_type;
```

---

## Debugging and Validation

### GTM Preview Mode
1. Open GTM and click "Preview"
2. Enter your site URL
3. Trigger experiment events
4. Verify in Tag Assistant:
   - Variables populated correctly
   - Tags firing on correct triggers
   - Event parameters passed to GA4

### GA4 DebugView
1. Enable debug mode in GTM:
   ```javascript
   // Add to GA4 Configuration tag
   debug_mode: true
   ```
2. Or use Chrome extension: Google Analytics Debugger
3. Open GA4 → Admin → DebugView
4. Trigger events and verify:
   - Event names correct
   - Parameters populated
   - Custom dimensions registered

### Console Debugging
```typescript
// lib/analytics.ts - Add debug mode
const DEBUG = process.env.NODE_ENV === 'development';

export function trackExperimentExposure(context: ExperimentContext): void {
  const eventData = {
    event: 'experiment_exposure',
    experiment_id: context.experimentId,
    experiment_name: context.experimentName,
    variant: context.variant,
    variant_source: context.variantSource,
    event_id: generateEventId(),
  };

  if (DEBUG) {
    console.log('[Analytics] Experiment Exposure:', eventData);
  }

  sendGTMEvent(eventData);
}
```

### Data Layer Inspector
```typescript
// Add to layout for debugging
'use client';

import { useEffect } from 'react';

export function DataLayerInspector() {
  useEffect(() => {
    if (process.env.NODE_ENV !== 'development') return;

    // Monitor dataLayer changes
    const originalPush = window.dataLayer?.push;
    if (originalPush && window.dataLayer) {
      window.dataLayer.push = function(...args: unknown[]) {
        console.log('[DataLayer]', ...args);
        return originalPush.apply(this, args);
      };
    }
  }, []);

  return null;
}
```

### Validation Checklist
```markdown
## Pre-Launch Checklist

### GTM Setup
- [ ] All Data Layer Variables created
- [ ] Experiment triggers configured
- [ ] GA4 tags linked to correct triggers
- [ ] Tag firing order correct (config before events)

### Event Flow
- [ ] Exposure event fires on page load
- [ ] Exposure fires only once per page
- [ ] Variant parameter populated correctly
- [ ] Experiment ID matches database

### Conversion Tracking
- [ ] Conversion event fires on success only
- [ ] Conversion linked to correct experiment
- [ ] Value parameter included if applicable
- [ ] Deduplication (event_id) working

### GA4 Configuration
- [ ] Custom dimensions created
- [ ] Conversion event marked
- [ ] BigQuery export enabled
- [ ] DebugView shows correct data

### Production Verification
- [ ] GTM container published
- [ ] Events visible in GA4 Realtime
- [ ] Data flowing to BigQuery
- [ ] No console errors
```

### Common Issues and Fixes
```typescript
// Issue: Events not firing
// Fix: Ensure GTM is loaded before tracking
import { useEffect, useState } from 'react';

function useGTMReady(): boolean {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const checkGTM = () => {
      if (typeof window !== 'undefined' && window.dataLayer) {
        setReady(true);
      } else {
        setTimeout(checkGTM, 100);
      }
    };
    checkGTM();
  }, []);

  return ready;
}

// Issue: Duplicate events
// Fix: Use ref to track if already fired
const hasFired = useRef(false);
useEffect(() => {
  if (!hasFired.current) {
    trackExperimentExposure(context);
    hasFired.current = true;
  }
}, []);

// Issue: Wrong variant in events
// Fix: Read from cookie, not state
function getVariantFromCookie(experimentId: string): string {
  if (typeof document === 'undefined') return 'A';
  const match = document.cookie.match(new RegExp(`exp_${experimentId}=([^;]+)`));
  return match?.[1] || 'A';
}
```

---

## Key Takeaways

1. **Event ID for deduplication**: Always include unique event_id
2. **Fire exposure once**: Use refs to prevent duplicate tracking
3. **Conversion after exposure**: Ensure conversion timestamp > exposure
4. **Custom dimensions**: Register in GA4 before analysis
5. **BigQuery for flexibility**: GA4 UI is limited; use SQL for complex analysis
6. **Debug before launch**: Validate every event in DebugView
