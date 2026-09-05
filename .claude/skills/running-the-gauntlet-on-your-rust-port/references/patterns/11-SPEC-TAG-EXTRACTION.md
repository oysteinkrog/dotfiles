# Pattern 11 — SPEC-TAG-EXTRACTION

**Family:** Kernel — Phase 2 (REFERENCE PINNING / SPEC PINNING) mechanism. Pairs with the `≡ INVARIANT-EXTRACT` operator in [`../methodology/OPERATORS.md`](../methodology/OPERATORS.md). Companion to [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) and [pattern:12-SPEC-CONFLICT-DETECTION](12-SPEC-CONFLICT-DETECTION.md).

**When to apply:** Greenfield mode, Phase 2. The spec source(s) listed in `docs/contracts/spec_version_contract.toml#[[spec_sources]]` exist and have been SHA-pinned, but the harness needs to turn prose assertions into a machine-actionable, per-tag enumeration. Also applies to port mode where the upstream reference ships a normative spec (SQL standard, RESP3 doc, RFC 9110) alongside the implementation.

## What

A regex-set walker that scans every `[[spec_sources]]` document for normative assertions, assigns each a stable `[SPEC-<area>-NNN]` tag, deduplicates across sources, and emits a *tagged statement table* (`docs/spec/SPEC-TAGS.md`) that becomes the contract between Phase 2 (pinning) and Phase 3 (oracle wiring). Every tag in the table MUST have a matching verifier function in `crates/<port>-harness/src/spec_oracle.rs`; every verifier MUST have at least one passing E2E test in `tests/spec_*_oracle_e2e.rs`. The tag is the join key.

Per-area numbering means tags are stable across spec revisions: adding an assertion at the end of "Hard Requirements" gets the next free `SPEC-EE-NNN` in that area's sequence; renumbering of unrelated areas does not cascade. This is what makes [pattern:31-SCHEMA-VERSION-MIGRATION-DUAL-READER](31-SCHEMA-VERSION-MIGRATION-DUAL-READER.md) actually work for spec-version bumps.

## Why

> "Each becomes a `Feature { id: F-{CAT}-{SEQ}, ... }` row with weight summing to 1.0 per category. The InvariantCatalog is even more critical: with no external reference, the catalog IS the contract." — [`GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) §2.

Failure mode prevented: *prose-conformance theater*. Without extracted tags, the spec is a wall of "the system should ..." sentences that nobody can grep against the test suite. Six months in, the team genuinely doesn't know whether they've tested assertion #47 in section §4.2. Tag extraction makes coverage countable: there are N tagged statements; M have verifiers; M/N is the surface-coverage number that goes in the certification bundle ([pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md)).

The second failure mode prevented: *tag-collision-induced false agreement*. Two spec sources both define `[SPEC-EE-005]` for different statements (one in `AGENTS.md`, one in `docs/spec/v1/`). The harness picks the first one it loads; the second's assertion goes silently unverified. Without dedup, you can't tell. The extractor's collision detector makes this loud.

## The pattern

### The regex set + extraction CLI

```rust
//! crates/<port>-harness/src/spec_tag_extractor.rs

use once_cell::sync::Lazy;
use regex::Regex;
use std::collections::BTreeMap;
use std::path::Path;

/// Regex set for normative-language extraction. Order matters: more specific
/// patterns first (already-tagged assertions are matched before plain MUST/SHALL
/// so the existing tag is preserved verbatim, not re-numbered).
pub static SPEC_PATTERNS: Lazy<Vec<(&'static str, Regex)>> = Lazy::new(|| {
    vec![
        // Already-tagged by the spec author — preserve verbatim.
        ("AlreadyTagged",
         Regex::new(r"(?m)^\s*\[SPEC-(?P<area>[A-Z]+)-(?P<num>\d{3,4})\]\s+(?P<body>.+?)\s*$")
             .expect("static regex")),

        // RFC-2119 normative + project-style — anchored to start of line or list item.
        ("MustVerb",
         Regex::new(r"(?m)^[\s\-\*]*\bMUST\b\s+(?P<body>(?:NOT\s+)?[a-z][^.]+\.)")
             .expect("static regex")),
        ("ShallVerb",
         Regex::new(r"(?m)^[\s\-\*]*\bSHALL\b\s+(?P<body>(?:NOT\s+)?[a-z][^.]+\.)")
             .expect("static regex")),

        // Project-conventional labels.
        ("InvariantLabel",
         Regex::new(r"(?m)^[\s\-\*]*INVARIANT:\s*(?P<body>[^\n]+)")
             .expect("static regex")),
        ("PropertyLabel",
         Regex::new(r"(?m)^[\s\-\*]*PROPERTY:\s*(?P<body>[^\n]+)")
             .expect("static regex")),
        ("HardRequirementLabel",
         Regex::new(r"(?m)^[\s\-\*]*HARD REQUIREMENT:\s*(?P<body>[^\n]+)")
             .expect("static regex")),
    ]
});

#[derive(Debug, Clone)]
pub struct ExtractedAssertion {
    pub tag: String,                 // e.g., "SPEC-EE-001"
    pub area: String,                // e.g., "EE"
    pub body: String,                // canonicalized assertion text
    pub source_path: String,         // e.g., "AGENTS.md"
    pub source_section: String,      // e.g., "Hard Requirements - Non Negotiable"
    pub source_line: usize,
    pub pattern_name: &'static str,  // which regex matched
    pub classification: Verifiability,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Verifiability {
    Verifiable,
    CharterOnly,
    Ambiguous,
}

pub struct SpecTagExtractor {
    area_counters: BTreeMap<String, u32>,
    seen_bodies: BTreeMap<String, String>,  // canonical body -> existing tag (dedup)
    next_num_per_area: BTreeMap<String, u32>,
}
```

### The per-source walker

```rust
impl SpecTagExtractor {
    pub fn extract_from_source(&mut self, path: &Path, source_name: &str)
        -> Result<Vec<ExtractedAssertion>, SpecExtractError>
    {
        let text = std::fs::read_to_string(path)?;
        let area = derive_area_from_source_name(source_name);
        let mut out = Vec::new();
        let mut seen_in_this_source: BTreeMap<usize, ()> = BTreeMap::new();

        for (pattern_name, rx) in SPEC_PATTERNS.iter() {
            for cap in rx.captures_iter(&text) {
                let m = cap.get(0).unwrap();
                let line = line_of_offset(&text, m.start());

                // Skip if a more-specific pattern already claimed this line.
                if seen_in_this_source.contains_key(&line) {
                    continue;
                }
                seen_in_this_source.insert(line, ());

                let body_raw = cap.name("body")
                    .map(|m| m.as_str())
                    .unwrap_or(m.as_str());
                let body = canonicalize_assertion_body(body_raw);

                // Dedup across sources by canonical body.
                let tag = if let Some(existing) = self.seen_bodies.get(&body) {
                    existing.clone()
                } else if *pattern_name == "AlreadyTagged" {
                    let tag = format!("SPEC-{}-{:03}",
                                      &cap["area"],
                                      cap["num"].parse::<u32>().unwrap());
                    self.register_explicit_tag(&tag, &body)?;
                    tag
                } else {
                    self.next_tag(&area)
                };

                let classification = classify(&body);

                out.push(ExtractedAssertion {
                    tag: tag.clone(),
                    area: area.clone(),
                    body: body.clone(),
                    source_path: path.display().to_string(),
                    source_section: section_for_line(&text, line),
                    source_line: line,
                    pattern_name,
                    classification,
                });

                self.seen_bodies.insert(body, tag);
            }
        }
        Ok(out)
    }

    fn next_tag(&mut self, area: &str) -> String {
        let n = self.next_num_per_area.entry(area.to_string()).or_insert(1);
        let tag = format!("SPEC-{}-{:03}", area, *n);
        *n += 1;
        tag
    }

    fn register_explicit_tag(&mut self, tag: &str, body: &str)
        -> Result<(), SpecExtractError>
    {
        // Author-supplied tag — must not collide with auto-numbered space.
        let (area, num) = parse_tag(tag)?;
        let cursor = self.next_num_per_area.entry(area.to_string()).or_insert(1);
        if num >= *cursor {
            *cursor = num + 1;
        }
        // Check collision: two different bodies with same tag = ERROR.
        for (existing_body, existing_tag) in &self.seen_bodies {
            if existing_tag == tag && existing_body != body {
                return Err(SpecExtractError::TagCollision {
                    tag: tag.to_string(),
                    body_a: existing_body.clone(),
                    body_b: body.to_string(),
                });
            }
        }
        Ok(())
    }
}
```

### Body canonicalization (the dedup join key)

```rust
fn canonicalize_assertion_body(raw: &str) -> String {
    raw.trim()
       .trim_end_matches('.')
       .split_whitespace()
       .collect::<Vec<_>>()
       .join(" ")
       .to_lowercase()  // lower-case for matching, original case kept in `body_raw`
}
```

Two assertions with the same canonical body get the same tag, even across spec sources. This is the *intentional* dedup: if AGENTS.md and docs/spec/v1/specification.md both say "every recall returns the same context-pack for the same query+state hash", they're the same requirement, not two.

### The tagged statement table emission

The extractor emits `docs/spec/SPEC-TAGS.md`:

```markdown
# SPEC Tags Catalog

Auto-extracted at Phase 2 by `spec-tag-extractor` (run `scripts/extract-spec-tags.sh`).

Generated: <ISO-utc>
Source contract sha: <sha-of-spec_version_contract.toml>
Total: <N> verifiable, <M> charter-only, <K> ambiguous.

## Verifiable Assertions

| Tag | Statement | Source | Section | Line | Pattern | Verifier |
|---|---|---|---|---|---|---|
| `[SPEC-EE-001]` | Every `remember` produces a content-addressable identifier with collision-rate < 1e-15. | `AGENTS.md` | Hard Requirements | 84 | `HardRequirementLabel` | `verify_spec_ee_001` |
| `[SPEC-EE-002]` | Every `recall` returns the same context-pack for the same `(query, state_hash)`. | `AGENTS.md` | Hard Requirements | 92 | `HardRequirementLabel` | `verify_spec_ee_002` |
| `[SPEC-PACK-001]` | The `pack` MUST respect the configured token budget within ±1%. | `docs/spec/v1/specification.md` | Token Budget | 145 | `MustVerb` | `verify_spec_pack_001` |
...

## Charter-Only Lines (NOT testable, NOT tagged)

Moved to `docs/CHARTER.md` per [`SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) §5.

| Original line | Reason |
|---|---|
| "ee should be useful" | Aspirational; no falsifier surface |
| "ee is hermetic" | True but not measurable as a single assertion (compose smaller invariants) |

## Ambiguous (needs user resolution — Phase 2 yellow)

| Line | Source | Reason |
|---|---|---|
| "the system handles errors gracefully" | AGENTS.md:121 | "gracefully" undefined; refine into concrete assertions |
```

### The driver script (idempotent, per [`COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md))

```bash
#!/usr/bin/env bash
# scripts/extract-spec-tags.sh
set -euo pipefail
workspace="${1:?usage: $0 <workspace>}"

# Idempotent: re-running produces bytewise-identical output if sources unchanged.
contract="$workspace/docs/contracts/spec_version_contract.toml"
test -f "$contract" || { echo "spec_version_contract.toml missing"; exit 2; }

# Verify pinned SHAs match current source files (refuse to extract from drifted source).
cargo run --quiet -p "<port>-harness" --bin spec-tag-extractor -- \
  --contract "$contract" \
  --out "$workspace/docs/spec/SPEC-TAGS.md" \
  --out-json "$workspace/docs/spec/SPEC-TAGS.json" \
  --fail-on-collision \
  --fail-on-drift
```

## Variants per project class

| Class | Primary spec sources | Typical `[SPEC-<area>-NNN]` areas |
|---|---|---|
| **SQL-class** | SQL standard subset; `sqlite3.h` doc-comments; SQLite TCL test names | `SPEC-DML-NNN`, `SPEC-DDL-NNN`, `SPEC-TXN-NNN`, `SPEC-VDBE-NNN` |
| **RESP-class** | RESP3 specification; Redis command docs; persistence semantics doc | `SPEC-RESP-NNN`, `SPEC-CMD-NNN`, `SPEC-AOF-NNN`, `SPEC-PUBSUB-NNN` |
| **Numerical-Python** | NumPy NEP-50 (dtype promotion); per-ufunc docstrings; PCG64DXSM RFC | `SPEC-NUMPY-NNN`, `SPEC-UFUNC-NNN`, `SPEC-DTYPE-NNN`, `SPEC-RNG-NNN` |
| **ML-System** | PyTorch op docs; autograd whitepapers; CUDA determinism docs | `SPEC-TORCH-NNN`, `SPEC-AUTOGRAD-NNN`, `SPEC-DTYPE-NNN`, `SPEC-DETERM-NNN` |
| **HTTP-Protocol** | RFC 9110/9111/9112; OpenAPI 3.1 spec; project's own route contract | `SPEC-HTTP-NNN`, `SPEC-ROUTE-NNN`, `SPEC-MW-NNN`, `SPEC-OPENAPI-NNN` |
| **Greenfield-Rust** | Project's own `docs/spec/v1/*.md`, `AGENTS.md § Hard Requirements`, design plan | Project-defined: e.g., `SPEC-EE-NNN`, `SPEC-PACK-NNN`, `SPEC-RECALL-NNN` |

### Per-class area-naming convention

- Area is `[A-Z]{2,8}`; uppercase; no separators. Choose from a small fixed vocabulary listed in the project's `docs/spec/AREA-VOCABULARY.md` (and pinned in the contract).
- Numeric portion is 3-digit zero-padded; promotes to 4-digit at 1000.
- Tags are *append-only*: once a tag is assigned to an assertion, it stays. If the assertion is removed from the spec, the tag is *retired* (kept in the table with status `RETIRED`, verifier deleted, retirement reason logged). Never re-used for a different assertion.

## Failure modes

| Failure | Symptom | Detection | Fix |
|---|---|---|---|
| **Regex too greedy** | A two-sentence paragraph matches `MustVerb`; the captured `body` includes the second sentence ("MUST do X. The implementation also Y."). | Tag table review; assertion text reads weirdly long; `len(body) > 240` heuristic alarm. | Anchor `body` capture with `[^.]+\.` (single-sentence stop at first period); add unit tests for multi-sentence inputs. |
| **Unverifiable assertion slips in as verifier** | An aspirational line like "ee MUST be reliable" gets tagged `SPEC-EE-099` and a "verifier" written that returns Ok unconditionally. | `verify_spec_*` body grep for trivial returns; coverage of the verifier in any property test is 0; classification reviewer flags. | Mandatory `Verifiability::Verifiable | CharterOnly | Ambiguous` classification step; CharterOnly assertions MUST NOT be tagged. Charter-only goes to `docs/CHARTER.md`. |
| **Tag collision across sources** | `AGENTS.md` author wrote `[SPEC-EE-005]` for assertion A; `docs/spec/v1` author wrote `[SPEC-EE-005]` for unrelated assertion B. Extractor picks whichever it loaded first; the other silently overwrites or is dropped. | `SpecExtractError::TagCollision` raised by `register_explicit_tag`. Phase 2 blocks. | Author-supplied tags must use disjoint per-area sub-ranges (e.g., `AGENTS.md` uses `SPEC-EE-001..099`, `docs/spec` uses `SPEC-EE-100..199`); convention pinned in `AREA-VOCABULARY.md`. |
| **Body-canonicalization too loose** | Two distinct assertions normalize to the same canonical body (e.g., both end up as "the system rejects malformed input"); extractor dedups them; one is silently dropped. | Per-tag source-line backreference enables manual audit; `--fail-on-suspect-dedup` flag warns when two raw bodies of different lengths normalize identically. | Tune canonicalization: keep punctuation that differs; warn loud on near-dups; require user confirmation for high-similarity collapses. |
| **Author renumbers an existing tag** | Spec author edits `[SPEC-EE-005]` → `[SPEC-EE-006]` because they think gaps are ugly. Every downstream verifier reference now broken. | `extract-spec-tags.sh` diffs against `SPEC-TAGS.json` from previous revision; alarms on any tag's `(area, num)` change. | Tags are append-only; refuse to extract if any tag's body changed (use migration via [pattern:31-SCHEMA-VERSION-MIGRATION-DUAL-READER](31-SCHEMA-VERSION-MIGRATION-DUAL-READER.md) instead). |
| **Per-area counter resets across runs** | Different RNG / iteration order in `BTreeMap` produces different next-num assignments; CI assigns SPEC-EE-007, local assigns SPEC-EE-006. | Compare extracted JSON byte-by-byte across machines. | Counter state persisted in `<workspace>/spec_tag_state.json` and checked in. Extractor reads it on start, writes incremented state on commit. |
| **Spec source path drift** | Source file moved; SHA still pins the *old* path; extractor errors. | Phase 2 doctor green-yellow-red. | Contract revision bumped (per [`SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) §6); `bless-spec.sh` updates path + SHA atomically. |
| **Pattern matches inside a code-block** | A markdown ` ```rust if x.MUST { ... } ``` ` block triggers `MustVerb`; nonsense tag emitted. | Preprocess: strip fenced code blocks before regex pass. Verify by extraction-test corpus. | Multi-line-aware preprocessing; skip ranges between ` ``` ` fences and ` <!-- nospec --> `..` <!-- /nospec --> ` comment markers. |
| **Extractor runs at Phase 6 instead of Phase 2** | Verifiers authored against an un-pinned tag set; tags shift; verifiers break under spec churn. | Phase 2 commit gate: refuses to advance to Phase 3 unless `SPEC-TAGS.md` exists and matches `SPEC-TAGS.json` byte-for-byte. | Spec-tag extraction is a Phase 2 *blocker step*, not a Phase 6 convenience. Run it on every contract revision. |

## Cross-references

- [pattern:06-5-MODE-ORACLE-DISPATCH](06-5-MODE-ORACLE-DISPATCH.md) — `OracleMode::Spec.tags` is populated from the extracted catalog.
- [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) — port-mode analog; tags come from the upstream spec.
- [pattern:12-SPEC-CONFLICT-DETECTION](12-SPEC-CONFLICT-DETECTION.md) — runs *after* extraction; finds same-tag-different-body collisions and cross-source contradictions.
- [pattern:13-SINGLE-CRATE-VS-WORKSPACE-DECISION](13-SINGLE-CRATE-VS-WORKSPACE-DECISION.md) — affects where `spec_tag_extractor.rs` lives.
- [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) — green/yellow/red on extractor health.
- [pattern:31-SCHEMA-VERSION-MIGRATION-DUAL-READER](31-SCHEMA-VERSION-MIGRATION-DUAL-READER.md) — when extractor output schema bumps `v1 → v2`.
- [pattern:105-FEATURE-UNIVERSE](105-FEATURE-UNIVERSE.md) — every `[SPEC-NNN]` is a Feature with weight.
- [pattern:110-INVARIANT-CATALOG](110-INVARIANT-CATALOG.md) — invariant-class tags (`InvariantLabel` matches) flow into the catalog.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — `fail-missing-evidence` if any tag lacks a verifier.
- [`../methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) §3 — the source convention this pattern implements.
- [`../methodology/COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md) — the `spec_tag_state.json` durable-state contract.
- [`../../subagents/scope-decider.md`](../../subagents/scope-decider.md) — Phase 2 owner.
- [`../../subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md) — Phase 3 consumer of the catalog.
