# Admin Dashboard for A/B Testing
## Table of Contents
- [Dashboard Architecture](#dashboard-architecture)
- [Database Schema](#database-schema)
- [API Routes](#api-routes)
- [Experiment Management UI](#experiment-management-ui)
- [Results Visualization](#results-visualization)
- [Real-Time Updates](#real-time-updates)

---

## Dashboard Architecture

### Stack Overview
```
┌─────────────────────────────────────────────────────────────┐
│                    Admin Dashboard                           │
├─────────────────────────────────────────────────────────────┤
│  Next.js 16 App Router                                       │
│  ├── /admin/experiments (list, create)                       │
│  ├── /admin/experiments/[id] (details, results)              │
│  ├── /admin/experiments/[id]/rules (personalization)         │
│  └── /admin/segments (audience analysis)                     │
├─────────────────────────────────────────────────────────────┤
│  API Layer                                                   │
│  ├── /api/admin/experiments (CRUD)                           │
│  ├── /api/admin/results (analytics)                          │
│  └── /api/webhooks/conversion (event ingestion)              │
├─────────────────────────────────────────────────────────────┤
│  Data Layer                                                  │
│  ├── Supabase (experiments, results, rules)                  │
│  ├── Vercel Edge Config (fast reads for middleware)          │
│  └── GA4 BigQuery (analytics queries)                        │
└─────────────────────────────────────────────────────────────┘
```

### Protected Routes Setup
```typescript
// middleware.ts - Admin protection
import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

export async function middleware(request: NextRequest) {
  // Only protect /admin routes
  if (!request.nextUrl.pathname.startsWith('/admin')) {
    return NextResponse.next();
  }

  // Check authentication
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!,
    {
      global: {
        headers: { cookie: request.headers.get('cookie') || '' },
      },
    }
  );

  const { data: { session } } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  // Check admin role
  const { data: profile } = await supabase
    .from('profiles')
    .select('role')
    .eq('id', session.user.id)
    .single();

  if (profile?.role !== 'admin') {
    return NextResponse.redirect(new URL('/unauthorized', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/admin/:path*', '/api/admin/:path*'],
};
```

---

## Database Schema

### Supabase Tables
```sql
-- Experiments table
CREATE TABLE experiments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'running', 'paused', 'completed')),

  -- Variant configuration
  variants JSONB NOT NULL DEFAULT '["A", "B"]'::jsonb,
  variant_weights JSONB NOT NULL DEFAULT '{"A": 50, "B": 50}'::jsonb,

  -- Targeting
  target_pages TEXT[] DEFAULT ARRAY[]::TEXT[],
  target_segments JSONB DEFAULT '{}'::jsonb,

  -- Scheduling
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,

  -- Goals
  primary_goal TEXT NOT NULL DEFAULT 'conversion',
  secondary_goals TEXT[] DEFAULT ARRAY[]::TEXT[],

  -- Analysis settings
  analysis_method TEXT DEFAULT 'bayesian' CHECK (analysis_method IN ('frequentist', 'bayesian', 'bandit')),
  min_sample_size INTEGER DEFAULT 1000,
  confidence_level NUMERIC DEFAULT 0.95,

  -- Bandit state (for MAB experiments)
  bandit_state JSONB,

  -- Metadata
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Winner (set when experiment concludes)
  winner_variant TEXT,
  winner_declared_at TIMESTAMPTZ
);

-- Experiment events table
CREATE TABLE experiment_events (
  id BIGSERIAL PRIMARY KEY,
  experiment_id UUID REFERENCES experiments(id) ON DELETE CASCADE,

  -- User identification
  user_id UUID,
  visitor_id TEXT NOT NULL, -- Anonymous ID from cookie

  -- Event data
  variant TEXT NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('exposure', 'conversion', 'goal')),
  goal_name TEXT, -- For secondary goals

  -- Context at time of event
  context JSONB DEFAULT '{}'::jsonb,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Deduplication
  UNIQUE(experiment_id, visitor_id, event_type, goal_name)
);

-- Index for fast queries
CREATE INDEX idx_experiment_events_lookup
ON experiment_events(experiment_id, variant, event_type);

CREATE INDEX idx_experiment_events_time
ON experiment_events(experiment_id, created_at);

-- Personalization rules table
CREATE TABLE personalization_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  experiment_id UUID REFERENCES experiments(id) ON DELETE CASCADE,

  name TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 100,
  enabled BOOLEAN DEFAULT true,

  -- Conditions
  conditions JSONB NOT NULL,
  condition_logic TEXT DEFAULT 'AND' CHECK (condition_logic IN ('AND', 'OR')),

  -- Result
  variant TEXT NOT NULL,

  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Edge Config sync table (for tracking what's synced)
CREATE TABLE edge_config_sync (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  synced_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS policies
ALTER TABLE experiments ENABLE ROW LEVEL SECURITY;
ALTER TABLE experiment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE personalization_rules ENABLE ROW LEVEL SECURITY;

-- Admins can do everything
CREATE POLICY admin_experiments ON experiments
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY admin_events ON experiment_events
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Public can insert events (for tracking)
CREATE POLICY public_insert_events ON experiment_events
  FOR INSERT WITH CHECK (true);
```

### TypeScript Types
```typescript
// types/experiments.ts
export interface Experiment {
  id: string;
  name: string;
  description?: string;
  status: 'draft' | 'running' | 'paused' | 'completed';
  variants: string[];
  variantWeights: Record<string, number>;
  targetPages: string[];
  targetSegments: Record<string, unknown>;
  startDate?: Date;
  endDate?: Date;
  primaryGoal: string;
  secondaryGoals: string[];
  analysisMethod: 'frequentist' | 'bayesian' | 'bandit';
  minSampleSize: number;
  confidenceLevel: number;
  banditState?: BanditState;
  createdBy: string;
  createdAt: Date;
  updatedAt: Date;
  winnerVariant?: string;
  winnerDeclaredAt?: Date;
}

export interface ExperimentEvent {
  id: number;
  experimentId: string;
  userId?: string;
  visitorId: string;
  variant: string;
  eventType: 'exposure' | 'conversion' | 'goal';
  goalName?: string;
  context: Record<string, unknown>;
  createdAt: Date;
}

export interface PersonalizationRule {
  id: string;
  experimentId: string;
  name: string;
  priority: number;
  enabled: boolean;
  conditions: RuleCondition[];
  conditionLogic: 'AND' | 'OR';
  variant: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface RuleCondition {
  attribute: string;
  operator: 'eq' | 'neq' | 'gt' | 'lt' | 'gte' | 'lte' | 'contains' | 'in';
  value: string | number | boolean | string[];
}

export interface BanditState {
  arms: { name: string; alpha: number; beta: number }[];
  totalPulls: number;
  lastUpdated: Date;
}
```

---

## API Routes

### Experiments CRUD
```typescript
// app/api/admin/experiments/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { syncToEdgeConfig } from '@/lib/edge-config';

export async function GET(request: NextRequest) {
  const supabase = await createClient();

  const { searchParams } = new URL(request.url);
  const status = searchParams.get('status');

  let query = supabase
    .from('experiments')
    .select('*')
    .order('created_at', { ascending: false });

  if (status) {
    query = query.eq('status', status);
  }

  const { data, error } = await query;

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ experiments: data });
}

export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const body = await request.json();

  const { data: { user } } = await supabase.auth.getUser();

  const { data, error } = await supabase
    .from('experiments')
    .insert({
      name: body.name,
      description: body.description,
      variants: body.variants || ['A', 'B'],
      variant_weights: body.variantWeights || { A: 50, B: 50 },
      target_pages: body.targetPages || [],
      target_segments: body.targetSegments || {},
      primary_goal: body.primaryGoal || 'conversion',
      secondary_goals: body.secondaryGoals || [],
      analysis_method: body.analysisMethod || 'bayesian',
      min_sample_size: body.minSampleSize || 1000,
      confidence_level: body.confidenceLevel || 0.95,
      created_by: user?.id,
    })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ experiment: data }, { status: 201 });
}

// app/api/admin/experiments/[id]/route.ts
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const supabase = await createClient();

  const { data, error } = await supabase
    .from('experiments')
    .select(`
      *,
      personalization_rules (*)
    `)
    .eq('id', id)
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 404 });
  }

  return NextResponse.json({ experiment: data });
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const supabase = await createClient();
  const body = await request.json();

  // Map camelCase to snake_case
  const updates: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };

  if (body.name) updates.name = body.name;
  if (body.description !== undefined) updates.description = body.description;
  if (body.status) updates.status = body.status;
  if (body.variants) updates.variants = body.variants;
  if (body.variantWeights) updates.variant_weights = body.variantWeights;
  if (body.targetPages) updates.target_pages = body.targetPages;
  if (body.startDate) updates.start_date = body.startDate;
  if (body.endDate) updates.end_date = body.endDate;
  if (body.winnerVariant) {
    updates.winner_variant = body.winnerVariant;
    updates.winner_declared_at = new Date().toISOString();
    updates.status = 'completed';
  }

  const { data, error } = await supabase
    .from('experiments')
    .update(updates)
    .eq('id', id)
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  // Sync to Edge Config if status changed to running
  if (body.status === 'running') {
    await syncToEdgeConfig(data);
  }

  return NextResponse.json({ experiment: data });
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const supabase = await createClient();

  const { error } = await supabase
    .from('experiments')
    .delete()
    .eq('id', id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return new NextResponse(null, { status: 204 });
}
```

### Results API
```typescript
// app/api/admin/experiments/[id]/results/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { calculateBayesianResults, calculateFrequentistResults } from '@/lib/statistics';

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const supabase = await createClient();

  // Get experiment config
  const { data: experiment } = await supabase
    .from('experiments')
    .select('*')
    .eq('id', id)
    .single();

  if (!experiment) {
    return NextResponse.json({ error: 'Experiment not found' }, { status: 404 });
  }

  // Get aggregated stats
  const { data: stats } = await supabase
    .rpc('get_experiment_stats', { exp_id: id });

  // Calculate statistical results based on method
  let analysis;
  if (experiment.analysis_method === 'bayesian') {
    analysis = calculateBayesianResults(stats, experiment.variants);
  } else {
    analysis = calculateFrequentistResults(stats, experiment.confidence_level);
  }

  // Get time series data
  const { data: timeSeries } = await supabase
    .rpc('get_experiment_time_series', {
      exp_id: id,
      bucket_size: '1 day',
    });

  return NextResponse.json({
    experiment,
    stats,
    analysis,
    timeSeries,
  });
}

// Supabase function for stats aggregation
/*
CREATE OR REPLACE FUNCTION get_experiment_stats(exp_id UUID)
RETURNS TABLE (
  variant TEXT,
  exposures BIGINT,
  conversions BIGINT,
  conversion_rate NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.variant,
    COUNT(DISTINCT CASE WHEN e.event_type = 'exposure' THEN e.visitor_id END) as exposures,
    COUNT(DISTINCT CASE WHEN e.event_type = 'conversion' THEN e.visitor_id END) as conversions,
    CASE
      WHEN COUNT(DISTINCT CASE WHEN e.event_type = 'exposure' THEN e.visitor_id END) > 0
      THEN COUNT(DISTINCT CASE WHEN e.event_type = 'conversion' THEN e.visitor_id END)::NUMERIC /
           COUNT(DISTINCT CASE WHEN e.event_type = 'exposure' THEN e.visitor_id END)
      ELSE 0
    END as conversion_rate
  FROM experiment_events e
  WHERE e.experiment_id = exp_id
  GROUP BY e.variant;
END;
$$ LANGUAGE plpgsql;
*/
```

### Edge Config Sync
```typescript
// lib/edge-config.ts
import { createClient } from '@vercel/edge-config';

const edgeConfig = createClient(process.env.EDGE_CONFIG);

export async function syncToEdgeConfig(experiment: Experiment): Promise<void> {
  // Only sync running experiments
  if (experiment.status !== 'running') return;

  const configKey = `experiment_${experiment.id}`;
  const configValue = {
    id: experiment.id,
    variants: experiment.variants,
    weights: experiment.variantWeights,
    targetPages: experiment.targetPages,
    targetSegments: experiment.targetSegments,
    startDate: experiment.startDate,
    endDate: experiment.endDate,
  };

  // Use Vercel API to update Edge Config
  const response = await fetch(
    `https://api.vercel.com/v1/edge-config/${process.env.EDGE_CONFIG_ID}/items`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${process.env.VERCEL_API_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        items: [{ operation: 'upsert', key: configKey, value: configValue }],
      }),
    }
  );

  if (!response.ok) {
    console.error('Failed to sync to Edge Config:', await response.text());
  }
}

export async function getActiveExperiments(): Promise<ExperimentConfig[]> {
  const allItems = await edgeConfig.getAll<Record<string, ExperimentConfig>>();

  return Object.entries(allItems || {})
    .filter(([key]) => key.startsWith('experiment_'))
    .map(([, value]) => value)
    .filter((exp) => {
      const now = new Date();
      if (exp.startDate && new Date(exp.startDate) > now) return false;
      if (exp.endDate && new Date(exp.endDate) < now) return false;
      return true;
    });
}
```

---

## Experiment Management UI

### Experiments List Page
```typescript
// app/admin/experiments/page.tsx
import { createClient } from '@/lib/supabase/server';
import Link from 'next/link';

export default async function ExperimentsPage() {
  const supabase = await createClient();

  const { data: experiments } = await supabase
    .from('experiments')
    .select('*')
    .order('created_at', { ascending: false });

  return (
    <div className="max-w-6xl mx-auto p-6">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold">Experiments</h1>
        <Link
          href="/admin/experiments/new"
          className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
        >
          Create Experiment
        </Link>
      </div>

      <div className="bg-white rounded-lg shadow overflow-hidden">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Name
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Status
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Variants
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Created
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {experiments?.map((exp) => (
              <tr key={exp.id} className="hover:bg-gray-50">
                <td className="px-6 py-4">
                  <Link
                    href={`/admin/experiments/${exp.id}`}
                    className="text-blue-600 hover:underline font-medium"
                  >
                    {exp.name}
                  </Link>
                  {exp.description && (
                    <p className="text-sm text-gray-500 truncate max-w-xs">
                      {exp.description}
                    </p>
                  )}
                </td>
                <td className="px-6 py-4">
                  <StatusBadge status={exp.status} />
                </td>
                <td className="px-6 py-4 text-sm text-gray-600">
                  {exp.variants.join(' / ')}
                </td>
                <td className="px-6 py-4 text-sm text-gray-500">
                  {new Date(exp.created_at).toLocaleDateString()}
                </td>
                <td className="px-6 py-4 text-right">
                  <ExperimentActions experiment={exp} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const colors = {
    draft: 'bg-gray-100 text-gray-800',
    running: 'bg-green-100 text-green-800',
    paused: 'bg-yellow-100 text-yellow-800',
    completed: 'bg-blue-100 text-blue-800',
  };

  return (
    <span
      className={`px-2 py-1 text-xs font-medium rounded-full ${colors[status as keyof typeof colors]}`}
    >
      {status}
    </span>
  );
}
```

### Create Experiment Form
```typescript
// app/admin/experiments/new/page.tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export default function NewExperimentPage() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    variants: ['A', 'B'],
    variantWeights: { A: 50, B: 50 },
    targetPages: [] as string[],
    primaryGoal: 'conversion',
    analysisMethod: 'bayesian' as const,
    minSampleSize: 1000,
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      const response = await fetch('/api/admin/experiments', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData),
      });

      if (!response.ok) throw new Error('Failed to create experiment');

      const { experiment } = await response.json();
      router.push(`/admin/experiments/${experiment.id}`);
    } catch (error) {
      console.error(error);
      alert('Failed to create experiment');
    } finally {
      setLoading(false);
    }
  };

  const addVariant = () => {
    const nextLetter = String.fromCharCode(65 + formData.variants.length);
    const newVariants = [...formData.variants, nextLetter];
    const newWeights = { ...formData.variantWeights };

    // Redistribute weights evenly
    const weightPerVariant = Math.floor(100 / newVariants.length);
    newVariants.forEach((v, i) => {
      newWeights[v] = i === 0 ? 100 - weightPerVariant * (newVariants.length - 1) : weightPerVariant;
    });

    setFormData({ ...formData, variants: newVariants, variantWeights: newWeights });
  };

  return (
    <div className="max-w-2xl mx-auto p-6">
      <h1 className="text-2xl font-bold mb-6">Create New Experiment</h1>

      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Name */}
        <div>
          <label className="block text-sm font-medium mb-1">Name</label>
          <input
            type="text"
            required
            value={formData.name}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
            className="w-full border rounded px-3 py-2"
            placeholder="e.g., Landing Page Hero Test"
          />
        </div>

        {/* Description */}
        <div>
          <label className="block text-sm font-medium mb-1">Description</label>
          <textarea
            value={formData.description}
            onChange={(e) => setFormData({ ...formData, description: e.target.value })}
            className="w-full border rounded px-3 py-2"
            rows={3}
            placeholder="What are you testing and why?"
          />
        </div>

        {/* Variants */}
        <div>
          <label className="block text-sm font-medium mb-2">Variants</label>
          <div className="space-y-2">
            {formData.variants.map((variant) => (
              <div key={variant} className="flex items-center gap-4">
                <span className="w-8 font-mono">{variant}</span>
                <input
                  type="range"
                  min={0}
                  max={100}
                  value={formData.variantWeights[variant]}
                  onChange={(e) => {
                    const newWeight = parseInt(e.target.value);
                    const otherVariant = formData.variants.find((v) => v !== variant)!;
                    setFormData({
                      ...formData,
                      variantWeights: {
                        ...formData.variantWeights,
                        [variant]: newWeight,
                        [otherVariant]: 100 - newWeight,
                      },
                    });
                  }}
                  className="flex-1"
                />
                <span className="w-12 text-right">{formData.variantWeights[variant]}%</span>
              </div>
            ))}
          </div>
          {formData.variants.length < 4 && (
            <button
              type="button"
              onClick={addVariant}
              className="mt-2 text-sm text-blue-600 hover:underline"
            >
              + Add variant
            </button>
          )}
        </div>

        {/* Target Pages */}
        <div>
          <label className="block text-sm font-medium mb-1">Target Pages (optional)</label>
          <input
            type="text"
            value={formData.targetPages.join(', ')}
            onChange={(e) =>
              setFormData({
                ...formData,
                targetPages: e.target.value.split(',').map((s) => s.trim()).filter(Boolean),
              })
            }
            className="w-full border rounded px-3 py-2"
            placeholder="/landing, /pricing"
          />
          <p className="text-xs text-gray-500 mt-1">
            Comma-separated paths. Leave empty to run on all pages.
          </p>
        </div>

        {/* Analysis Method */}
        <div>
          <label className="block text-sm font-medium mb-1">Analysis Method</label>
          <select
            value={formData.analysisMethod}
            onChange={(e) =>
              setFormData({
                ...formData,
                analysisMethod: e.target.value as 'frequentist' | 'bayesian' | 'bandit',
              })
            }
            className="w-full border rounded px-3 py-2"
          >
            <option value="bayesian">Bayesian (Recommended)</option>
            <option value="frequentist">Frequentist</option>
            <option value="bandit">Multi-Armed Bandit</option>
          </select>
        </div>

        {/* Min Sample Size */}
        <div>
          <label className="block text-sm font-medium mb-1">Minimum Sample Size</label>
          <input
            type="number"
            min={100}
            value={formData.minSampleSize}
            onChange={(e) =>
              setFormData({ ...formData, minSampleSize: parseInt(e.target.value) })
            }
            className="w-full border rounded px-3 py-2"
          />
          <p className="text-xs text-gray-500 mt-1">
            Per variant. Experiment won&apos;t auto-conclude until this is reached.
          </p>
        </div>

        {/* Submit */}
        <div className="flex gap-4">
          <button
            type="submit"
            disabled={loading}
            className="bg-blue-600 text-white px-6 py-2 rounded hover:bg-blue-700 disabled:opacity-50"
          >
            {loading ? 'Creating...' : 'Create Experiment'}
          </button>
          <button
            type="button"
            onClick={() => router.back()}
            className="px-6 py-2 border rounded hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </form>
    </div>
  );
}
```

---

## Results Visualization

### Results Dashboard
```typescript
// app/admin/experiments/[id]/page.tsx
import { createClient } from '@/lib/supabase/server';
import { calculateBayesianResults } from '@/lib/statistics';
import { ResultsChart } from '@/components/admin/results-chart';
import { VariantComparison } from '@/components/admin/variant-comparison';

export default async function ExperimentDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: experiment } = await supabase
    .from('experiments')
    .select('*')
    .eq('id', id)
    .single();

  const { data: stats } = await supabase.rpc('get_experiment_stats', { exp_id: id });

  const analysis = calculateBayesianResults(stats, experiment?.variants || []);

  return (
    <div className="max-w-6xl mx-auto p-6">
      {/* Header */}
      <div className="flex justify-between items-start mb-6">
        <div>
          <h1 className="text-2xl font-bold">{experiment?.name}</h1>
          <p className="text-gray-600">{experiment?.description}</p>
        </div>
        <ExperimentStatusControl experiment={experiment} />
      </div>

      {/* Key Metrics */}
      <div className="grid grid-cols-3 gap-4 mb-6">
        {stats?.map((s: { variant: string; exposures: number; conversions: number; conversion_rate: number }) => (
          <div key={s.variant} className="bg-white rounded-lg shadow p-4">
            <div className="text-sm text-gray-500">Variant {s.variant}</div>
            <div className="text-3xl font-bold">{(s.conversion_rate * 100).toFixed(2)}%</div>
            <div className="text-sm text-gray-500">
              {s.conversions.toLocaleString()} / {s.exposures.toLocaleString()}
            </div>
          </div>
        ))}
        <div className="bg-white rounded-lg shadow p-4">
          <div className="text-sm text-gray-500">Winner Probability</div>
          <div className="text-3xl font-bold text-green-600">
            {(analysis.winProbabilities[analysis.winner] * 100).toFixed(1)}%
          </div>
          <div className="text-sm text-gray-500">
            {analysis.winner} is likely best
          </div>
        </div>
      </div>

      {/* Charts */}
      <div className="grid grid-cols-2 gap-6 mb-6">
        <div className="bg-white rounded-lg shadow p-4">
          <h3 className="font-medium mb-4">Conversion Over Time</h3>
          <ResultsChart experimentId={id} />
        </div>
        <div className="bg-white rounded-lg shadow p-4">
          <h3 className="font-medium mb-4">Posterior Distributions</h3>
          <PosteriorChart analysis={analysis} />
        </div>
      </div>

      {/* Variant Comparison */}
      <VariantComparison stats={stats} analysis={analysis} />

      {/* Winner Declaration */}
      {experiment?.status === 'running' && analysis.confidence > 0.95 && (
        <WinnerDeclarationCard
          experimentId={id}
          winner={analysis.winner}
          confidence={analysis.confidence}
        />
      )}
    </div>
  );
}
```

### Posterior Distribution Chart
```typescript
// components/admin/posterior-chart.tsx
'use client';

import { useEffect, useRef } from 'react';

interface PosteriorChartProps {
  analysis: {
    posteriors: Record<string, { alpha: number; beta: number }>;
    variants: string[];
  };
}

export function PosteriorChart({ analysis }: PosteriorChartProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = canvas.width;
    const height = canvas.height;

    // Clear
    ctx.clearRect(0, 0, width, height);

    // Colors for each variant
    const colors = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444'];

    // Draw each posterior
    analysis.variants.forEach((variant, i) => {
      const { alpha, beta } = analysis.posteriors[variant];

      ctx.beginPath();
      ctx.strokeStyle = colors[i % colors.length];
      ctx.lineWidth = 2;

      // Plot beta PDF
      for (let x = 0; x <= width; x++) {
        const p = x / width;
        const y = betaPDF(p, alpha, beta);
        const canvasY = height - (y / 20) * height; // Scale

        if (x === 0) {
          ctx.moveTo(x, canvasY);
        } else {
          ctx.lineTo(x, canvasY);
        }
      }

      ctx.stroke();

      // Fill under curve with transparency
      ctx.lineTo(width, height);
      ctx.lineTo(0, height);
      ctx.closePath();
      ctx.fillStyle = `${colors[i % colors.length]}20`;
      ctx.fill();
    });

    // Draw x-axis labels
    ctx.fillStyle = '#666';
    ctx.font = '12px sans-serif';
    ctx.fillText('0%', 5, height - 5);
    ctx.fillText('50%', width / 2 - 10, height - 5);
    ctx.fillText('100%', width - 30, height - 5);

    // Legend
    analysis.variants.forEach((variant, i) => {
      ctx.fillStyle = colors[i % colors.length];
      ctx.fillRect(width - 80, 10 + i * 20, 12, 12);
      ctx.fillStyle = '#333';
      ctx.fillText(`Variant ${variant}`, width - 62, 20 + i * 20);
    });
  }, [analysis]);

  return <canvas ref={canvasRef} width={400} height={200} className="w-full" />;
}

// Beta PDF approximation
function betaPDF(x: number, alpha: number, beta: number): number {
  if (x <= 0 || x >= 1) return 0;

  const B = gamma(alpha) * gamma(beta) / gamma(alpha + beta);
  return Math.pow(x, alpha - 1) * Math.pow(1 - x, beta - 1) / B;
}

// Stirling approximation for gamma function
function gamma(n: number): number {
  if (n === 1) return 1;
  if (n === 0.5) return Math.sqrt(Math.PI);

  // Stirling approximation
  return Math.sqrt(2 * Math.PI / n) * Math.pow(n / Math.E, n);
}
```

---

## Real-Time Updates

### Supabase Realtime
```typescript
// hooks/use-experiment-updates.ts
'use client';

import { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase/client';

export function useExperimentUpdates(experimentId: string) {
  const [stats, setStats] = useState<ExperimentStats | null>(null);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);

  useEffect(() => {
    const supabase = createClient();

    // Initial fetch
    supabase.rpc('get_experiment_stats', { exp_id: experimentId }).then(({ data }) => {
      setStats(data);
      setLastUpdate(new Date());
    });

    // Subscribe to changes
    const channel = supabase
      .channel(`experiment_${experimentId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'experiment_events',
          filter: `experiment_id=eq.${experimentId}`,
        },
        async () => {
          // Refetch stats on new event
          const { data } = await supabase.rpc('get_experiment_stats', {
            exp_id: experimentId,
          });
          setStats(data);
          setLastUpdate(new Date());
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [experimentId]);

  return { stats, lastUpdate };
}
```

### Live Dashboard Component
```typescript
// components/admin/live-dashboard.tsx
'use client';

import { useExperimentUpdates } from '@/hooks/use-experiment-updates';
import { calculateBayesianResults } from '@/lib/statistics';

export function LiveDashboard({ experimentId }: { experimentId: string }) {
  const { stats, lastUpdate } = useExperimentUpdates(experimentId);

  if (!stats) {
    return <div className="animate-pulse">Loading...</div>;
  }

  const analysis = calculateBayesianResults(stats, stats.map(s => s.variant));

  return (
    <div className="bg-white rounded-lg shadow p-4">
      <div className="flex justify-between items-center mb-4">
        <h3 className="font-medium">Live Results</h3>
        {lastUpdate && (
          <span className="text-xs text-gray-500">
            Updated {lastUpdate.toLocaleTimeString()}
          </span>
        )}
      </div>

      <div className="space-y-4">
        {stats.map((s) => (
          <div key={s.variant} className="flex items-center gap-4">
            <span className="w-8 font-mono">{s.variant}</span>
            <div className="flex-1">
              <div className="h-4 bg-gray-200 rounded overflow-hidden">
                <div
                  className="h-full bg-blue-500 transition-all duration-500"
                  style={{
                    width: `${s.conversion_rate * 100}%`,
                  }}
                />
              </div>
            </div>
            <span className="w-16 text-right font-medium">
              {(s.conversion_rate * 100).toFixed(2)}%
            </span>
            <span className="w-20 text-right text-sm text-gray-500">
              {s.conversions}/{s.exposures}
            </span>
          </div>
        ))}
      </div>

      {/* Win probability */}
      <div className="mt-4 pt-4 border-t">
        <div className="text-sm text-gray-500 mb-2">Probability of winning</div>
        {Object.entries(analysis.winProbabilities).map(([variant, prob]) => (
          <div key={variant} className="flex items-center gap-2">
            <span className="w-8 font-mono">{variant}</span>
            <div className="flex-1 h-2 bg-gray-200 rounded overflow-hidden">
              <div
                className={`h-full transition-all duration-500 ${
                  prob > 0.95 ? 'bg-green-500' : prob > 0.5 ? 'bg-blue-500' : 'bg-gray-400'
                }`}
                style={{ width: `${prob * 100}%` }}
              />
            </div>
            <span className="w-12 text-right text-sm">
              {(prob * 100).toFixed(1)}%
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
```

---

## Key Takeaways

1. **Protect admin routes**: Use middleware to verify authentication and admin role
2. **Use Edge Config for fast reads**: Middleware needs sub-10ms config access
3. **Sync on status change**: Only push to Edge Config when experiment goes live
4. **Real-time updates**: Supabase Realtime enables live dashboards
5. **Visual statistics**: Show posteriors and probabilities, not just raw numbers
6. **Winner declaration workflow**: Require explicit confirmation before 100% rollout
