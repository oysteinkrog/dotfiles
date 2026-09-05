#!/usr/bin/env node
// replay-from-dlq.mjs — Replay webhook DLQ entries against the live webhook handler.
//
// Usage: node scripts/replay-from-dlq.mjs [--dry-run] [--limit N] [--provider stripe|paypal]
//
// Per B140 § Pattern 3. Used after an incident is resolved to drain the DLQ.
//
// Requires: DATABASE_URL, APP_URL, REPLAY_TOKEN env vars.
// REPLAY_TOKEN is a separate secret from production webhook secrets.

import { execFileSync } from 'node:child_process';

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const limitIdx = args.indexOf('--limit');
const limit = limitIdx >= 0 ? parseInt(args[limitIdx + 1], 10) : 100;
const providerIdx = args.indexOf('--provider');
const provider = providerIdx >= 0 ? args[providerIdx + 1] : null;

if (!Number.isInteger(limit) || limit < 1 || limit > 1000) {
  console.error('--limit must be an integer between 1 and 1000');
  process.exit(2);
}
if (provider && !['stripe', 'paypal'].includes(provider)) {
  console.error('--provider must be stripe or paypal');
  process.exit(2);
}
if (!process.env.DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }
if (!process.env.APP_URL) { console.error('APP_URL required'); process.exit(2); }
if (!process.env.REPLAY_TOKEN) { console.error('REPLAY_TOKEN required'); process.exit(2); }

const PROVIDER_FILTER = provider ? `AND provider = '${provider}'` : '';
const sqlLiteral = (value) => `'${String(value).replaceAll("'", "''")}'`;

// Fetch unreplayed DLQ rows
const query = `
  SELECT COALESCE(json_agg(row_to_json(dlq_rows)), '[]'::json)
  FROM (
    SELECT id::text, provider, body, headers, recorded_at::text AS "recordedAt"
    FROM webhook_dlq
    WHERE replayed_at IS NULL ${PROVIDER_FILTER}
    ORDER BY recorded_at ASC
    LIMIT ${limit}
  ) dlq_rows
`;

const result = execFileSync('psql', [process.env.DATABASE_URL, '-tAc', query], { encoding: 'utf-8' });
const rows = JSON.parse(result.trim() || '[]');

console.log(`Found ${rows.length} unreplayed DLQ rows.`);
if (rows.length === 0) process.exit(0);
if (dryRun) {
  console.log('--dry-run: not replaying.');
  rows.forEach(r => console.log(`  ${r.id} (${r.provider}, ${r.recordedAt})`));
  process.exit(0);
}

let replayed = 0;
let failed = 0;
for (const row of rows) {
  const sigHeader = row.provider === 'stripe' ? 'stripe-signature' : 'paypal-transmission-id';
  const headers = row.headers && typeof row.headers === 'object' ? row.headers : {};

  try {
    const response = await fetch(`${process.env.APP_URL}/api/${row.provider}/webhook?replay=true`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        [sigHeader]: headers[sigHeader] ?? '',
        'X-Replay-Token': process.env.REPLAY_TOKEN,
      },
      body: row.body,
    });
    if (response.ok) {
      execFileSync('psql', [process.env.DATABASE_URL, '-c',
        `UPDATE webhook_dlq SET replayed_at = now() WHERE id = ${sqlLiteral(row.id)}`]);
      replayed++;
      console.log(`  ✓ ${row.id} (${row.provider})`);
    } else {
      failed++;
      console.log(`  ✗ ${row.id} (${row.provider}): HTTP ${response.status}`);
    }
  } catch (err) {
    failed++;
    console.log(`  ✗ ${row.id} (${row.provider}): ${err.message}`);
  }
}

console.log(`\nReplay complete: ${replayed} succeeded, ${failed} failed.`);
process.exit(failed > 0 ? 1 : 0);
