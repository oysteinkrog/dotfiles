#!/usr/bin/env node
// audit-exclusions-coverage.mjs — Detect crons / publishers / readers that don't import the canonical exclusions module.
//
// Usage: node scripts/audit-exclusions-coverage.mjs <project-path>
//
// Output: JSON to stdout listing missing imports.
// Exits 1 if any violations found, 0 if clean.

import { readFileSync, statSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

const PROJECT = resolve(process.argv[2] || process.cwd());

// Use ripgrep with execFileSync (no shell) so regex metacharacters in patterns
// don't get mangled by shell interpretation.
function rg(pattern) {
  const args = [
    '--no-heading',
    '--files-with-matches',
    '--no-config',
    '--type-add', 'src:*.{ts,tsx,js,jsx,py,rb,ex,exs}',
    '-tsrc',
    '-e', pattern,
    PROJECT,
  ];
  try {
    return execFileSync('rg', args, { encoding: 'utf-8', maxBuffer: 64 * 1024 * 1024 })
      .split('\n')
      .filter(Boolean);
  } catch (e) {
    if (e.status === 1) return [];
    throw e;
  }
}

// Find every cron route + admin event publisher + analytics read
const cronFiles = [...rg('/api/cron/'), ...rg('vercel\\.json')];
const publisherFiles = rg('publishAdminEvent|admin-event-publishers');
const analyticsFiles = rg('getCurrentMrrSnapshot|computeChurn|customerHealth');

const allFiles = [...new Set([...cronFiles, ...publisherFiles, ...analyticsFiles])];

const violations = [];
for (const file of allFiles) {
  if (!existsSync(file)) continue;
  if (!statSync(file).isFile()) continue;
  const content = readFileSync(file, 'utf-8');
  // Look for an import from analytics/exclusions (or the project's equivalent)
  const importsExclusions =
    /from\s+['"][^'"]*analytics\/exclusions['"]/.test(content) ||
    /from\s+['"][^'"]*\/exclusions['"]/.test(content) ||
    /import.*exclusions/i.test(content) ||
    /analyticsExclusions/.test(content) ||
    // Explicit opt-out: file documents that exclusions don't apply
    /\/\/\s*analytics-exclusions:\s*not-required/.test(content);

  // Allow the canonical exclusions file itself
  const isExclusionsFile = /\/exclusions(\.|\/)/.test(file);

  if (!importsExclusions && !isExclusionsFile) {
    violations.push({
      file: file.replace(PROJECT + '/', ''),
      reason: 'No import of analytics/exclusions or analyticsExclusions reference detected',
      suggested_fix: 'Import from src/lib/analytics/exclusions and apply the SQL fragment / predicate. If exclusions truly do not apply, add `// analytics-exclusions: not-required` with reasoning.',
      operator: '⛓ ANALYTICS-EXCLUSION',
    });
  }
}

console.log(JSON.stringify({
  project: PROJECT,
  files_scanned: allFiles.length,
  violations: violations.length,
  items: violations,
}, null, 2));

if (violations.length > 0) process.exit(1);
