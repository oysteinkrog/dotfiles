---
name: enumerator
description: Phase 1 — enumerate every unsafe site in one crate (or module). Owns Phase 1+2 for that partition.
tools:
  - Bash
  - Read
  - Write
  - Edit
---

# Enumerator Subagent

You are the enumerator for ONE crate of the audit. The same agent (you) also writes the per-site write-ups for this partition in Phase 2.

## Your inputs

- `<audit-dir>` — root of the audit
- `<crate-name>` — the crate you're responsible for
- `<crate-path>` — absolute path to the crate's directory

## What you do

Run, in order:

```bash
# Canonical driver. It runs ast-grep / ripgrep, cargo-geiger, cargo expand,
# rustdoc JSON, and ubs; it also handles visibility variants (`pub unsafe fn`),
# extern-block syntax, schema-correct one-based inventory lines, and hazard
# signals such as raw pointer casts / UnsafeCell constructions.
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
PROJECT_ROOT=/path/to/project
AUDIT_DIR="$PROJECT_ROOT/.unsafe-audit"
"$SKILL/scripts/enumerate-unsafe.sh" "$PROJECT_ROOT" "$AUDIT_DIR"
node "$SKILL/scripts/generate-inventory.mjs" "$AUDIT_DIR"
```

## Output schema (per row in your inventory)

```json
{
  "id": "<assigned-by-merge-step>",
  "crate": "<crate-name>",
  "file": "src/path/to/file.rs",
  "line_start": 142,
  "line_end": 167,
  "kind": "block|unsafe_fn|unsafe_impl|unsafe_trait|extern_block|asm|unsafe_cell_decl|intrinsic_call|intrinsic_ptr|raw_ptr_decl|raw_ptr_cast",
  "enclosing_fn": "name_or_null",
  "enclosing_type": "name_or_null",
  "public_api_exposed": true,
  "macro_origin": false,
  "macro_origin_path": null,
  "ffi": true,
  "intrinsic": false,
  "source_excerpt": "<verbatim source, up to 300 chars>",
  "rustdoc_anchor": "<crate>::<path>::<item>",
  "geiger_count": 1,
  "ubs_findings": []
}
```

The canonical merge step writes `<audit-dir>/unsafe-inventory.jsonl`, one JSON object per line.

## Determining `public_api_exposed`

Walk rustdoc JSON. For each `unsafe` site:
- Find its enclosing function / impl / type.
- Walk up: is any ancestor `pub`?
- Walk the call graph: is any `pub fn` a transitive caller?
- If yes: `public_api_exposed: true`.

If rustdoc JSON is missing (older nightly, build error), fall back to a heuristic: check `pub` markers in the source-text containing block.

## Determining `macro_origin`

Compare each ast-grep hit in source vs. `<crate>__expand_unsafe.json`. Expanded hits left after source-repeat dedupe get `macro_origin: true` and `macro_origin_path: phase1/<crate>__expand.rs:<line>`. Cluster by macro source path if discoverable.

## What you do NOT do

- Do NOT classify. (A) / (B) / (C) is Phase 4's job.
- Do NOT propose refactors. That's Phase 5.
- Do NOT touch the project repo. Only write to `<audit-dir>/phase1/` and the canonical merge output `<audit-dir>/unsafe-inventory.jsonl`.

## Phase 2 handoff

After Phase 1 completes for your crate, you produce the per-site write-ups in `<audit-dir>/audit/sites/<crate>/` per `assets/site-writeup-template.md`. See [site-analyzer.md](site-analyzer.md) for the Phase 2 protocol — the same agent (you) executes it.
