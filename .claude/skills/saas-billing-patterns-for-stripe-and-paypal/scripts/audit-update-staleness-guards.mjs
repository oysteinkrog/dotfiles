#!/usr/bin/env node
// audit-update-staleness-guards.mjs — Walk every UPDATE on subscriptions/organizations;
// report ones missing the `last_event_at` clause.
//
// Usage: node scripts/audit-update-staleness-guards.mjs <project-path>
//
// Output: JSON to stdout listing each violation with file:line + suggested fix.
// Exits 1 if any violations found, 0 if clean.

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

const PROJECT = resolve(process.argv[2] || process.cwd());

// Use ripgrep to find every line that looks like an UPDATE on subscriptions/organizations.
// Use execFileSync (not execSync) so we never invoke a shell — the regex pattern
// contains `|`, `\`, `(?:...)` characters that a shell would mangle.
function rg(pattern) {
  const args = [
    '--no-heading',
    '--line-number',
    '--no-config',
    '--type-add', 'src:*.{ts,tsx,js,jsx,py,rb,ex,exs,go,rs}',
    '-tsrc',
    '-e', pattern,
    PROJECT,
  ];
  try {
    return execFileSync('rg', args, { encoding: 'utf-8', maxBuffer: 64 * 1024 * 1024 });
  } catch (e) {
    if (e.status === 1) return '';   // rg returns 1 when no matches
    throw e;
  }
}

// Patterns matching ORM-level UPDATEs on relevant tables
const updatePatterns = [
  /db\.update\((subscriptions|organizations|orgs)\)/,            // Drizzle
  /prisma\.(subscription|organization)\.update/,                 // Prisma
  /Subscription\.update|Organization\.update/,                   // Sequelize / generic
  /UPDATE\s+(?:subscriptions|organizations)/i,                   // raw SQL
];

// Single regex for the rg call (alternation via | inside one pattern)
const SEARCH_REGEX = String.raw`db\.update|prisma\.(subscription|organization)\.update|UPDATE\s+(?:subscriptions|organizations)`;

const lines = rg(SEARCH_REGEX).split('\n').filter(Boolean);

const violations = [];

for (const line of lines) {
  // ripgrep output: PATH:LINE:TEXT
  const m = line.match(/^([^:]+(?::[^:]+)*?):(\d+):(.*)$/);
  if (!m) continue;
  const [, file, lineNo, text] = m;

  // Match against any of the update patterns (filters out incidental hits like comments)
  if (!updatePatterns.some((p) => p.test(text))) continue;

  // Read ~30 lines following to scan for the WHERE clause
  let content;
  try {
    content = readFileSync(file, 'utf-8');
  } catch {
    continue;
  }
  const fileLines = content.split('\n');
  const startIdx = parseInt(lineNo, 10) - 1;
  const window = fileLines.slice(startIdx, startIdx + 30).join('\n');

  // Quick check: does the window contain a staleness-guard token?
  const hasGuard = /last_event_at|lastEventAt|paypalLastEventAt|paypal_last_event_at/.test(window);

  // Heuristic exception: INSERTs disguised as updates and "create-on-conflict" upserts
  // don't always need the guard since they create the row. We DO want to flag every
  // genuine UPDATE; if a project legitimately upserts via .update() they should add a comment.
  const looksLikeUpsert = /onConflict|upsert|onDuplicateKeyUpdate/.test(window);

  if (!hasGuard && !looksLikeUpsert) {
    violations.push({
      file: file.replace(PROJECT + '/', ''),
      line: parseInt(lineNo, 10),
      snippet: text.trim(),
      suggested_fix: 'Add `WHERE last_event_at < new_event_at` (or paypalLastEventAt for orgs) to the UPDATE.',
      operator: '⏱ STALE-EVENT-GATE',
    });
  }
}

console.log(JSON.stringify({
  project: PROJECT,
  total_updates_scanned: lines.length,
  violations: violations.length,
  items: violations,
}, null, 2));

if (violations.length > 0) process.exit(1);
