#!/usr/bin/env node
// generate-coverage-matrix.mjs — Walk references/patterns/ and emit a coverage-matrix skeleton.
//
// Usage: node scripts/generate-coverage-matrix.mjs > .billing_workspace/phase2_coverage_matrix.md
//
// One row per pattern; status fields blank for the agent to fill from Phase 1 findings.

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PATTERNS_DIR = join(__dirname, '..', 'references', 'patterns');

const bundleFiles = readdirSync(PATTERNS_DIR)
  .filter((f) => f.endsWith('.md'))
  .sort();

console.log('# Phase 2 — Coverage Matrix');
console.log('');
console.log('One row per pattern. Status: `present` | `partial` | `missing` | `n/a`. Cite file:line in Evidence for present/partial. n/a requires a justification in Notes.');
console.log('');
console.log('See `references/methodology/COVERAGE-MATRIX.md` for the full schema.');
console.log('');

for (const file of bundleFiles) {
  const path = join(PATTERNS_DIR, file);
  const content = readFileSync(path, 'utf-8');

  // Bundle title: first ## or # heading
  const titleMatch = content.match(/^#\s+(.+)$/m);
  const bundleTitle = titleMatch ? titleMatch[1].trim() : basename(file, '.md');

  // Pattern sections: every ## heading inside the bundle, minus meta sections
  const sectionRegex = /^##\s+(.+)$/gm;
  const sections = [];
  let m;
  while ((m = sectionRegex.exec(content)) !== null) {
    const title = m[1].trim();
    // Skip meta / wrapper sections that aren't themselves patterns to score
    if (
      /Polish Bar checks/i.test(title) ||
      /Common.*mistakes/i.test(title) ||
      /Where this comes from/i.test(title) ||
      /How to use/i.test(title) ||
      /Reference Index/i.test(title) ||
      /Reading list/i.test(title) ||
      /^Per-/i.test(title) ||
      /-specific gotchas/i.test(title) ||
      /^The (step-ordered|12-day|9 most common|architecture diagram|3 axes|three axes|state model)/i.test(title) ||
      /^Common /i.test(title) ||
      /^Battle-tested checklist/i.test(title) ||
      /^Bead dictionary/i.test(title) ||
      /^File map/i.test(title) ||
      /^Failure-mode catalog/i.test(title) ||
      /^Patterns tried and rejected/i.test(title) ||
      /^Operational runbooks$/i.test(title) ||
      /^Compromise procedure/i.test(title) ||
      /^Rotation procedure/i.test(title)
    ) continue;
    sections.push(title);
  }

  if (sections.length === 0) continue;

  console.log(`\n## ${bundleTitle}`);
  console.log('');
  console.log('| Pattern (file §section) | Status | Evidence (file:line) | Operator | Notes |');
  console.log('|--------------------------|--------|----------------------|----------|-------|');
  for (const sec of sections) {
    console.log(`| \`${file} §${sec}\` |  |  |  |  |`);
  }
  console.log('');
}

console.log('\n---\n');
console.log('## Summary (filled in by Phase 2 reviewers)');
console.log('');
console.log('Counts:');
console.log('- present: ');
console.log('- partial: ');
console.log('- missing: ');
console.log('- n/a:     ');
console.log('');
console.log('Top-level themes:');
console.log('- ');
