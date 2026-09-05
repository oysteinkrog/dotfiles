#!/usr/bin/env node
// generate-inventory.mjs — normalize per-crate enumeration into a single sorted JSONL
// Usage: node generate-inventory.mjs <audit-dir>

import fs from 'node:fs';
import path from 'node:path';

const AUDIT_DIR = process.argv[2];
if (!AUDIT_DIR) {
  console.error('usage: generate-inventory.mjs <audit-dir>');
  console.error('');
  console.error('  This script takes exactly ONE argument: the audit directory');
  console.error('  (typically <project>/.unsafe-audit). The project root is');
  console.error('  inferred from <audit-dir>/phase1/project-root.txt (written by');
  console.error('  enumerate-unsafe.sh) or by walking upward for a Cargo.toml.');
  console.error('');
  console.error('  Note: enumerate-unsafe.sh takes TWO arguments (<project> <audit-dir>),');
  console.error("  but this script takes ONE. Don't copy the enumerate-unsafe.sh args.");
  process.exit(1);
}
if (process.argv[3]) {
  console.error('error: generate-inventory.mjs takes exactly one argument (<audit-dir>)');
  console.error(`       you passed: ${JSON.stringify(process.argv.slice(2))}`);
  console.error('       did you mean to pass the audit dir only? (the project root is');
  console.error('       inferred from <audit-dir>/phase1/project-root.txt)');
  process.exit(1);
}

const auditDirAbs = realpath(AUDIT_DIR);
const phase1 = path.join(auditDirAbs, 'phase1');
const out = path.join(auditDirAbs, 'unsafe-inventory.jsonl');
const projectRoot = inferProjectRoot(auditDirAbs);
assertAuditDirInsideProject(auditDirAbs, projectRoot);

let rows = [];

const files = fs.readdirSync(phase1).filter(f => f.endsWith('.json'));

for (const file of files) {
  // We want files like <crate>__ast_<kind>.json + <crate>__expand_unsafe.json
  const match = file.match(/^(.+)__(ast_(.+)|expand_unsafe|geiger)\.json$/);
  if (!match) continue;

  const [, crate, fullKind, kindRaw] = match;
  if (!kindRaw && fullKind !== 'expand_unsafe' && fullKind !== 'geiger') continue;

  const isExpand = fullKind === 'expand_unsafe';
  const isGeiger = fullKind === 'geiger';

  if (isGeiger) continue; // geiger is per-crate aggregate, not per-site

  let content;
  try {
    content = JSON.parse(fs.readFileSync(path.join(phase1, file), 'utf8'));
  } catch {
    continue;
  }

  // ast-grep --json output is an array of match objects with file + range info
  if (!Array.isArray(content)) continue;

  for (const m of content) {
    if (!m.range) continue;
    const rawText = m.text || '';
    const kindFromFile = kindRaw || 'block'; // best-effort
    const kind = classifyKind(kindFromFile, rawText);
    const lineStart = oneBasedLine(m.range.start?.line);
    const lineEnd = oneBasedLine(m.range.end?.line);
    const expandPath = `phase1/${crate}__expand.rs`;
    rows.push({
      crate,
      file: isExpand ? expandPath : normalizeSourcePath(m.file),
      line_start: lineStart,
      line_end: lineEnd,
      kind,
      enclosing_fn: null,           // filled by site-analyzer
      enclosing_type: null,
      public_api_exposed: null,     // requires rustdoc cross-ref; left for site-analyzer
      macro_origin: isExpand,
      macro_origin_path: isExpand ? `${expandPath}:${lineStart}` : null,
      ffi: kind === 'extern_block' || /libc::|extern\s+"/.test(rawText),
      intrinsic: kind === 'intrinsic_call' || /(?:core|std)::(?:intrinsics|hint)::(?:unreachable_unchecked|assert_unchecked|assume|atomic_load_unsynchronized|atomic_store_unsynchronized|likely|unlikely)/.test(rawText),
      source_excerpt: rawText.slice(0, 300),
      rustdoc_anchor: null,         // filled by site-analyzer
      geiger_count: geigerCountForKind(kind),
      ubs_findings: [],
      _dedupe_text: normalizeText(rawText),
    });
  }
}

// `cargo expand` repeats source-authored unsafe as well as macro-generated
// unsafe. Consume one expanded copy for each exact source-text occurrence, but
// keep surplus expanded copies with the same text: those can still be genuine
// macro-origin sites emitted by derives or macro_rules expansions.
const sourceTextCounts = new Map();
const sourceRowsSeen = new Set();
for (const row of rows) {
  if (row.macro_origin) continue;
  const rowKey = rowDedupKey(row);
  if (sourceRowsSeen.has(rowKey)) continue;
  sourceRowsSeen.add(rowKey);
  const key = sourceTextKey(row);
  sourceTextCounts.set(key, (sourceTextCounts.get(key) || 0) + 1);
}
rows = rows.filter(row => {
  if (!row.macro_origin) return true;
  const key = sourceTextKey(row);
  const remaining = sourceTextCounts.get(key) || 0;
  if (remaining === 0) return true;
  sourceTextCounts.set(key, remaining - 1);
  return false;
});

// Variant-specific search patterns can intentionally converge on the same
// canonical kind, especially in rg/grep fallback mode. Collapse exact duplicate
// rows before assigning stable IDs.
const deduped = [];
const seen = new Set();
for (const row of rows) {
  const key = rowDedupKey(row);
  if (seen.has(key)) continue;
  seen.add(key);
  deduped.push(row);
}

// Sort by (crate, file, line_start)
deduped.sort((a, b) => {
  if (a.crate !== b.crate) return a.crate.localeCompare(b.crate);
  if (a.file !== b.file) return a.file.localeCompare(b.file);
  return a.line_start - b.line_start;
});

// Assign stable IDs
deduped.forEach((r, i) => {
  r.id = `site-${String(i + 1).padStart(4, '0')}`;
});

const stream = fs.createWriteStream(out);
for (const r of deduped) {
  const { _dedupe_text, ...publicRow } = r;
  stream.write(JSON.stringify(publicRow) + '\n');
}
stream.end();

console.log(`Wrote ${deduped.length} rows to ${out}`);

function classifyKind(rawKind, text) {
  // rawKind comes from the filename slug (e.g., `ast_unsafe_cell_decl` → `unsafe_cell_decl`).
  // Normalize by stripping the `ast_` prefix and lowercasing.
  const k = String(rawKind || '').toLowerCase().replace(/^ast_/, '');
  if (k === 'unsafe_fn' || k === 'unsafe_fn_vis' || k === 'unsafe_fn_async' || k === 'unsafe_fn_async_vis') return 'unsafe_fn';
  if (k === 'unsafe_impl') return 'unsafe_impl';
  if (k === 'unsafe_trait' || k === 'unsafe_trait_vis') return 'unsafe_trait';
  if (k === 'extern_block') return 'extern_block';
  if (k === 'asm') return 'asm';
  if (k === 'unsafe_cell_decl' || k === 'unsafe_cell_turbofish') return 'unsafe_cell_decl';
  if (k === 'intrinsic_call' || k === 'intrinsic_call_core' || k === 'intrinsic_call_std') return 'intrinsic_call';
  if (k === 'intrinsic_hint_unreach' || k === 'intrinsic_hint_unreach_core' || k === 'intrinsic_hint_unreach_std') return 'intrinsic_call';
  if (k === 'intrinsic_hint_assert' || k === 'intrinsic_hint_assert_core' || k === 'intrinsic_hint_assert_std') return 'intrinsic_call';
  if (k === 'intrinsic_ptr' || k === 'intrinsic_ptr_core' || k === 'intrinsic_ptr_std') return 'intrinsic_ptr';
  if (k === 'raw_ptr_decl_const' || k === 'raw_ptr_decl_mut') return 'raw_ptr_decl';
  if (k === 'raw_ptr_as_cast' || k === 'raw_ptr_as_cast_const' || k === 'raw_ptr_as_cast_mut') return 'raw_ptr_cast';
  if (k === 'unsafe_block' || k === 'block') return 'block';
  // Legacy/loose match for older slugs
  if (/^unsafefn/i.test(rawKind)) return 'unsafe_fn';
  if (/^unsafeimpl/i.test(rawKind)) return 'unsafe_impl';
  if (/^unsafetrait/i.test(rawKind)) return 'unsafe_trait';
  if (/^extern/i.test(rawKind)) return 'extern_block';
  if (/^(core|std)archasm/i.test(rawKind)) return 'asm';
  if (/^unsafe/i.test(rawKind)) return 'block';
  return 'block';
}

function oneBasedLine(line) {
  const n = Number(line);
  return Number.isFinite(n) ? Math.max(1, Math.trunc(n) + 1) : 1;
}

function normalizeSourcePath(file) {
  if (typeof file !== 'string') return file;
  if (!path.isAbsolute(file)) return file.split(path.sep).join('/');
  if (!projectRoot) return file;

  const relative = path.relative(projectRoot, file);
  if (!relative.startsWith('..') && !path.isAbsolute(relative)) {
    return relative.split(path.sep).join('/');
  }
  return file;
}

function inferProjectRoot(auditDir) {
  const metadataPath = path.join(auditDir, 'phase1', 'project-root.txt');
  try {
    const recordedRoot = fs.readFileSync(metadataPath, 'utf8').trim();
    if (recordedRoot) return path.resolve(recordedRoot);
  } catch {
    // Older audit dirs predate project-root.txt. Fall back to the common layout
    // where the audit dir sits somewhere under a Rust project root.
  }

  let projectCandidate = path.dirname(auditDir);
  while (true) {
    if (fs.existsSync(path.join(projectCandidate, 'Cargo.toml'))) {
      return projectCandidate;
    }
    const parent = path.dirname(projectCandidate);
    if (parent === projectCandidate) break;
    projectCandidate = parent;
  }

  let cur = auditDir;
  while (true) {
    if (/^\.unsafe-audit(?:$|[-_.])/.test(path.basename(cur))) {
      return path.dirname(cur);
    }
    const parent = path.dirname(cur);
    if (parent === cur) return null;
    cur = parent;
  }
}

function realpath(filePath) {
  return fs.realpathSync(path.resolve(filePath));
}

function assertAuditDirInsideProject(auditDir, projectRoot) {
  if (!projectRoot) {
    console.error(`error: cannot infer audited project root from audit dir: ${auditDir}`);
    process.exit(2);
  }
  const auditReal = realpath(auditDir);
  const projectReal = realpath(projectRoot);
  if (auditReal === projectReal) {
    console.error('error: audit dir must be a child directory inside the project, not the project root');
    process.exit(2);
  }
  const relative = path.relative(projectReal, auditReal);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    console.error('error: audit dir must live inside the project being audited');
    console.error(`       project:   ${projectReal}`);
    console.error(`       audit dir: ${auditReal}`);
    process.exit(2);
  }
}

function geigerCountForKind(kind) {
  // These rows are audit signals, not unsafe operations by themselves.
  if (kind === 'unsafe_cell_decl' || kind === 'raw_ptr_decl' || kind === 'raw_ptr_cast') {
    return 0;
  }
  return 1;
}

function sourceTextKey(row) {
  return `${row.crate}\0${row._dedupe_text}`;
}

function rowDedupKey(row) {
  return [
    row.crate,
    row.file,
    row.line_start,
    row.line_end,
    row.kind,
    row.macro_origin,
    row._dedupe_text,
  ].join('\0');
}

function normalizeText(text) {
  // Strip comments so dedup matches across cargo-expand (which strips comments)
  // and the original source (which retains them). Do this with a small lexer
  // rather than regexes so URL-like string literals keep their `//`.
  return collapseWhitespaceOutsideRustStrings(stripRustComments(String(text)));
}

function collapseWhitespaceOutsideRustStrings(text) {
  let out = '';
  let pendingSpace = false;
  let i = 0;

  while (i < text.length) {
    const raw = rawStringAt(text, i);
    if (raw) {
      out = appendNormalized(out, text.slice(i, raw.end), pendingSpace);
      pendingSpace = false;
      i = raw.end;
      continue;
    }

    const byteChar = byteCharLiteralAt(text, i);
    if (byteChar) {
      out = appendNormalized(out, text.slice(i, byteChar.end), pendingSpace);
      pendingSpace = false;
      i = byteChar.end;
      continue;
    }

    const charEnd = charLiteralEnd(text, i);
    if (charEnd) {
      out = appendNormalized(out, text.slice(i, charEnd), pendingSpace);
      pendingSpace = false;
      i = charEnd;
      continue;
    }

    if ((text[i] === 'b' || text[i] === 'c') && text[i + 1] === '"') {
      const end = quotedStringEnd(text, i + 1);
      out = appendNormalized(out, text.slice(i, end), pendingSpace);
      pendingSpace = false;
      i = end;
      continue;
    }

    if (text[i] === '"') {
      const end = quotedStringEnd(text, i);
      out = appendNormalized(out, text.slice(i, end), pendingSpace);
      pendingSpace = false;
      i = end;
      continue;
    }

    if (/\s/.test(text[i])) {
      pendingSpace = true;
      i += 1;
      continue;
    }

    out = appendNormalized(out, text[i], pendingSpace);
    pendingSpace = false;
    i += 1;
  }

  return out.trim();
}

function appendNormalized(out, chunk, pendingSpace) {
  if (pendingSpace && out.length > 0 && chunk.length > 0 && shouldKeepOutsideStringSpace(out[out.length - 1], chunk[0])) {
    return out + ' ' + chunk;
  }
  return out + chunk;
}

function shouldKeepOutsideStringSpace(left, right) {
  return isWordChar(left) && isWordChar(right);
}

function isWordChar(ch) {
  return /^[A-Za-z0-9_]$/.test(ch);
}

function stripRustComments(text) {
  let out = '';
  let i = 0;

  while (i < text.length) {
    const raw = rawStringAt(text, i);
    if (raw) {
      out += text.slice(i, raw.end);
      i = raw.end;
      continue;
    }

    const byteChar = byteCharLiteralAt(text, i);
    if (byteChar) {
      out += text.slice(i, byteChar.end);
      i = byteChar.end;
      continue;
    }

    const charEnd = charLiteralEnd(text, i);
    if (charEnd) {
      out += text.slice(i, charEnd);
      i = charEnd;
      continue;
    }

    if ((text[i] === 'b' || text[i] === 'c') && text[i + 1] === '"') {
      const end = quotedStringEnd(text, i + 1);
      out += text.slice(i, end);
      i = end;
      continue;
    }

    if (text[i] === '"') {
      const end = quotedStringEnd(text, i);
      out += text.slice(i, end);
      i = end;
      continue;
    }

    if (text[i] === '/' && text[i + 1] === '/') {
      out += ' ';
      i += 2;
      while (i < text.length && text[i] !== '\n') i += 1;
      continue;
    }

    if (text[i] === '/' && text[i + 1] === '*') {
      out += ' ';
      i = blockCommentEnd(text, i + 2);
      continue;
    }

    out += text[i];
    i += 1;
  }

  return out;
}

function rawStringAt(text, start) {
  let r = start;
  if ((text[start] === 'b' || text[start] === 'c') && text[start + 1] === 'r') {
    r = start + 1;
  }
  if (text[r] !== 'r') return null;

  let quote = r + 1;
  while (text[quote] === '#') quote += 1;
  if (text[quote] !== '"') return null;

  const hashes = quote - r - 1;
  const close = '"' + '#'.repeat(hashes);
  const closeAt = text.indexOf(close, quote + 1);
  return { end: closeAt === -1 ? text.length : closeAt + close.length };
}

function byteCharLiteralAt(text, start) {
  if (text[start] !== 'b' || text[start + 1] !== "'") return null;
  const end = charLiteralEnd(text, start + 1);
  return end ? { end } : null;
}

function charLiteralEnd(text, quoteAt) {
  if (text[quoteAt] !== "'") return null;
  let i = quoteAt + 1;
  if (i >= text.length || text[i] === '\n') return null;

  if (text[i] === '\\') {
    i += 1;
    if (text[i] === 'u' && text[i + 1] === '{') {
      const closeBrace = text.indexOf('}', i + 2);
      if (closeBrace === -1) return null;
      i = closeBrace + 1;
    } else if (text[i] === 'x') {
      i += 3;
    } else {
      i += 1;
    }
  } else {
    const codePoint = text.codePointAt(i);
    if (codePoint === undefined || codePoint === 10 || codePoint === 13) return null;
    i += codePoint > 0xffff ? 2 : 1;
  }

  return text[i] === "'" ? i + 1 : null;
}

function quotedStringEnd(text, quoteAt) {
  let i = quoteAt + 1;
  while (i < text.length) {
    if (text[i] === '\\') {
      i += 2;
      continue;
    }
    if (text[i] === '"') return i + 1;
    i += 1;
  }
  return text.length;
}

function blockCommentEnd(text, start) {
  let depth = 1;
  let i = start;
  while (i < text.length && depth > 0) {
    if (text[i] === '/' && text[i + 1] === '*') {
      depth += 1;
      i += 2;
      continue;
    }
    if (text[i] === '*' && text[i + 1] === '/') {
      depth -= 1;
      i += 2;
      continue;
    }
    i += 1;
  }
  return i;
}
