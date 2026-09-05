# Pattern 12 — SPEC-CONFLICT-DETECTION

**Family:** Kernel — Phase 2 BLOCKER gate for greenfield projects with more than one spec source. Pairs with the `◊ PARADOX-HUNT` operator in [`../methodology/OPERATORS.md`](../methodology/OPERATORS.md) and with [pattern:11-SPEC-TAG-EXTRACTION](11-SPEC-TAG-EXTRACTION.md) (which is the upstream that produces the tag set this pattern conflict-checks).

**When to apply:** Phase 2, immediately after tag extraction, whenever `spec_version_contract.toml` lists more than one `[[spec_sources]]`. The most common shape: a project ships both `AGENTS.md § Hard Requirements` and `docs/spec/v1/specification.md`, and the two drift over time. Also applies to port-mode projects with multiple upstream reference documents (e.g., SQL standard + SQLite implementation guide).

## What

A pairwise contradiction detector that walks every `[[spec_sources]]` document's extracted tag set and finds: (1) tag-collision-with-different-body (same `[SPEC-NNN]` tag, different canonical assertion); (2) cross-source contradictions on the same topic (different tags, semantically opposing statements); (3) cross-source unverified-overlap (different tags, identical canonical body — these should have been deduped, missing dedup is a bug). Output is `<workspace>/phase2_spec_conflict.md` — a structured report listing every conflict pair with source-A vs source-B verbatim text and a *resolution-needed-from-user* note. **Phase 3 is BLOCKED until this file is empty.**

The detector is a hard gate, not a warning: silently picking one source-of-truth and proceeding is the failure mode that kills greenfield certification claims six months later when the user notices their `AGENTS.md` says one thing and the test suite verifies another.

## Why

> "Conflicts between spec sources are a Phase 2 BLOCKER; scope-decider must canonicalize one source-of-truth before proceeding to Phase 3." — [`SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) §2 (verbatim from `spec_version_contract.toml` schema).

> "When two spec sources contradict each other, Phase 2 is BLOCKED. The scope-decider writes `<workspace>/phase2_spec_conflict.md` listing every conflict pair." — [`SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) §4.

Failure mode prevented: *silent canonicalization*. The cheap thing is to pick whichever spec source the extractor parsed first (or whichever has the higher-priority listed in `[[spec_sources]]`) and proceed. This buries the conflict in the extractor's silent choice — six months later the user reads `AGENTS.md` and is shocked to learn the harness has been verifying the *other* statement. The user's bug report rightly reads "I told you this was a hard requirement, why isn't it tested?"

The second failure mode prevented: *deferral-as-resolution*. An agent who detects a conflict and writes "TODO: resolve conflict between AGENTS.md and docs/spec/v1 — tracking in bd-N" is hiding the conflict in a bead that, statistically, will not be picked up. The blocker discipline forces resolution before any Phase 3 verifier is written — because every verifier written under conflict is a verifier built on sand.

The third failure mode prevented: *cross-source overlap left undeduped*. Two assertions in two different sources say the same thing in slightly different words; the canonicalizer in [pattern:11-SPEC-TAG-EXTRACTION](11-SPEC-TAG-EXTRACTION.md) should have collapsed them. When it didn't, you end up with two tags, two verifiers, double counting in the parity score. The detector's "unverified overlap" check (high-similarity-body across-source pairs that did NOT dedup) is the audit that catches this.

## The pattern

### The three detector functions

```rust
//! crates/<port>-harness/src/spec_conflict_detector.rs

use crate::spec_tag_extractor::{ExtractedAssertion, Verifiability};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone)]
pub enum SpecConflict {
    /// Same `[SPEC-NNN]` tag appears in two sources with different bodies.
    /// This is the highest-priority kind of conflict; it means the join key
    /// is broken.
    TagCollision {
        tag: String,
        source_a: SourceLocation,
        body_a: String,
        source_b: SourceLocation,
        body_b: String,
    },
    /// Two different tags assert opposite things on the same topic, detected by
    /// the negation/affirmation pair heuristic.
    Contradiction {
        topic: String,                   // derived from shared noun phrases
        tag_a: String,
        body_a: String,
        source_a: SourceLocation,
        tag_b: String,
        body_b: String,
        source_b: SourceLocation,
        contradiction_signal: ContradictionSignal,
    },
    /// Two assertions with very similar (but not identical) canonical bodies
    /// that did NOT dedup. Likely intentional restatement, but flag for review.
    UnverifiedOverlap {
        similarity_score: f64,           // [0.0..1.0]; >0.85 triggers
        tag_a: String,
        body_a: String,
        source_a: SourceLocation,
        tag_b: String,
        body_b: String,
        source_b: SourceLocation,
    },
}

#[derive(Debug, Clone)]
pub struct SourceLocation {
    pub source_name: String,             // matches `[[spec_sources]].name`
    pub source_path: String,
    pub section: String,
    pub line: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContradictionSignal {
    NegationPair { negator: &'static str },       // "must" vs "must not"
    QuantifierMismatch { a: &'static str, b: &'static str }, // "every" vs "some"
    NumericThresholdMismatch { a: f64, b: f64 },  // "< 1e-15" vs "< 1e-12"
    BehaviorDirective { a: &'static str, b: &'static str }, // "reject" vs "coerce"
}
```

### The pairwise scan

```rust
pub fn detect_conflicts(
    per_source: &BTreeMap<String, Vec<ExtractedAssertion>>,
) -> Vec<SpecConflict> {
    let mut conflicts = Vec::new();

    // (1) Tag-collision: same tag, different body.
    let mut by_tag: BTreeMap<String, Vec<&ExtractedAssertion>> = BTreeMap::new();
    for assertions in per_source.values() {
        for a in assertions {
            by_tag.entry(a.tag.clone()).or_default().push(a);
        }
    }
    for (tag, occurrences) in &by_tag {
        if occurrences.len() < 2 { continue; }
        // All occurrences with the same tag must share the same canonical body.
        let canonical_set: BTreeSet<&str> = occurrences.iter()
            .map(|o| o.body.as_str())
            .collect();
        if canonical_set.len() > 1 {
            // collect each pair
            for i in 0..occurrences.len() {
                for j in (i + 1)..occurrences.len() {
                    if occurrences[i].body != occurrences[j].body {
                        conflicts.push(SpecConflict::TagCollision {
                            tag: tag.clone(),
                            source_a: occurrences[i].location(),
                            body_a: occurrences[i].body.clone(),
                            source_b: occurrences[j].location(),
                            body_b: occurrences[j].body.clone(),
                        });
                    }
                }
            }
        }
    }

    // (2) Contradiction: scan all (a, b) pairs from different sources, find
    //     topic-aligned negation/quantifier/threshold/directive opposition.
    let sources: Vec<&String> = per_source.keys().collect();
    for i in 0..sources.len() {
        for j in (i + 1)..sources.len() {
            for a in &per_source[sources[i]] {
                for b in &per_source[sources[j]] {
                    if a.tag == b.tag { continue; } // same-tag handled above
                    if let Some(signal) = detect_contradiction(&a.body, &b.body) {
                        conflicts.push(SpecConflict::Contradiction {
                            topic: extract_shared_topic(&a.body, &b.body),
                            tag_a: a.tag.clone(),
                            body_a: a.body.clone(),
                            source_a: a.location(),
                            tag_b: b.tag.clone(),
                            body_b: b.body.clone(),
                            source_b: b.location(),
                            contradiction_signal: signal,
                        });
                    }
                }
            }
        }
    }

    // (3) Unverified overlap: high body-similarity across sources that did NOT dedup.
    for i in 0..sources.len() {
        for j in (i + 1)..sources.len() {
            for a in &per_source[sources[i]] {
                for b in &per_source[sources[j]] {
                    if a.tag == b.tag { continue; }
                    let sim = jaccard_word_similarity(&a.body, &b.body);
                    if sim > 0.85 {
                        conflicts.push(SpecConflict::UnverifiedOverlap {
                            similarity_score: sim,
                            tag_a: a.tag.clone(),
                            body_a: a.body.clone(),
                            source_a: a.location(),
                            tag_b: b.tag.clone(),
                            body_b: b.body.clone(),
                            source_b: b.location(),
                        });
                    }
                }
            }
        }
    }

    conflicts
}
```

### Contradiction-signal heuristics

```rust
fn detect_contradiction(body_a: &str, body_b: &str) -> Option<ContradictionSignal> {
    // Negation pair: "must X" vs "must not X" (same X stem).
    if let Some(neg) = detect_negation_pair(body_a, body_b) {
        return Some(ContradictionSignal::NegationPair { negator: neg });
    }
    // Quantifier mismatch: "every" vs "some" on the same noun phrase.
    if let Some((a, b)) = detect_quantifier_mismatch(body_a, body_b) {
        return Some(ContradictionSignal::QuantifierMismatch { a, b });
    }
    // Numeric threshold: "< X" vs "< Y" on same metric.
    if let Some((a, b)) = detect_numeric_threshold_mismatch(body_a, body_b) {
        return Some(ContradictionSignal::NumericThresholdMismatch { a, b });
    }
    // Behavior directive: "reject" vs "coerce", "error" vs "silently truncate".
    if let Some((a, b)) = detect_behavior_directive_mismatch(body_a, body_b) {
        return Some(ContradictionSignal::BehaviorDirective { a, b });
    }
    None
}
```

### The blocker report writer

```rust
pub fn write_blocker_report(
    conflicts: &[SpecConflict],
    workspace_path: &Path,
) -> Result<bool, std::io::Error> {
    let report_path = workspace_path.join("phase2_spec_conflict.md");
    if conflicts.is_empty() {
        // Empty file = no conflicts = Phase 3 can proceed.
        std::fs::write(&report_path, "# Phase 2 Spec Conflict Report\n\n_No conflicts detected._\n")?;
        return Ok(false);  // not blocked
    }

    let mut out = String::new();
    out.push_str("# Phase 2 Spec Conflict Report — BLOCKER\n\n");
    out.push_str("Phase 3 is **blocked** until every conflict below is resolved.\n");
    out.push_str("Each conflict requires:\n\n");
    out.push_str("1. The user canonicalizes ONE source-of-truth, OR\n");
    out.push_str("2. The user amends both sources to agree on a new shared assertion, OR\n");
    out.push_str("3. The user explicitly marks one source as `delegates_to: <other_source>` \
                  in `spec_version_contract.toml`.\n\n");
    out.push_str("After resolution, re-run `scripts/extract-spec-tags.sh && scripts/detect-spec-conflicts.sh`.\n\n");
    out.push_str("---\n\n");

    let by_kind = group_by_kind(conflicts);

    if let Some(collisions) = by_kind.get("TagCollision") {
        out.push_str("## (1) Tag Collisions — same `[SPEC-NNN]`, different body\n\n");
        for c in collisions {
            render_tag_collision(&mut out, c);
        }
    }
    if let Some(contradictions) = by_kind.get("Contradiction") {
        out.push_str("## (2) Contradictions — different tags, opposing statements\n\n");
        for c in contradictions {
            render_contradiction(&mut out, c);
        }
    }
    if let Some(overlaps) = by_kind.get("UnverifiedOverlap") {
        out.push_str("## (3) Unverified Overlap — high similarity, separate tags\n\n");
        out.push_str("These may be intentional restatement (downgrade to a yellow), \
                      or a missed dedup (upgrade body-canonicalizer in `spec_tag_extractor.rs`).\n\n");
        for c in overlaps {
            render_overlap(&mut out, c);
        }
    }

    std::fs::write(&report_path, out)?;
    Ok(true)  // blocked
}
```

### Sample blocker entry (rendered)

```markdown
### TagCollision — `[SPEC-EE-005]`

- **Source A:** `AGENTS.md § Hard Requirements`, line 92
  > "every recall MUST return the same context-pack for the same query+state_hash"
- **Source B:** `docs/spec/v1/recall.md § Determinism`, line 14
  > "every recall returns the same pack for the same (query, state) within ±5% token variance"

**Resolution required:** the two sources disagree on whether determinism is strict
(byte-identical) or approximate (±5% token variance). One of:
  (a) Amend `AGENTS.md` to state ±5% variance explicitly.
  (b) Amend `docs/spec/v1/recall.md` to strict equality.
  (c) Split into two tags `[SPEC-EE-005a]` (strict) and `[SPEC-EE-005b]` (loose) covering
      different code paths.
```

### Idempotent driver script

```bash
#!/usr/bin/env bash
# scripts/detect-spec-conflicts.sh
set -euo pipefail
workspace="${1:?usage: $0 <workspace>}"
cargo run --quiet -p "<port>-harness" --bin spec-conflict-detector -- \
  --tags-json "$workspace/docs/spec/SPEC-TAGS.json" \
  --out "$workspace/phase2_spec_conflict.md"
# Exit non-zero if blocked.
if [[ "$(head -1 "$workspace/phase2_spec_conflict.md")" =~ BLOCKER ]]; then
  echo "Phase 2 is BLOCKED — see $workspace/phase2_spec_conflict.md"
  exit 64
fi
```

## Variants per project class

| Class | Common conflict shapes | Resolution convention |
|---|---|---|
| **SQL-class** | SQL standard says "REAL is double-precision IEEE 754"; SQLite docs say "REAL is approximate, implementation-defined precision" | Default: SQLite docs win (project is a SQLite port); pin in contract under `delegates_to = "sqlite-impl-guide"` |
| **RESP-class** | RESP2 doc and RESP3 doc disagree on inline-command framing | Per-version-tagged spec sources; `[SPEC-RESP2-NNN]` vs `[SPEC-RESP3-NNN]`; project asserts which version it ports |
| **Numerical-Python** | NumPy 1.x and 2.x dtype-promotion rules differ (NEP-50) | Pin to one NumPy version via `[reference]` block in port; greenfield: pick one and commit |
| **ML-System** | PyTorch op docs vs upstream PR comments often disagree on edge cases | PyTorch op docs win; cite the doc URL in the contract |
| **HTTP-Protocol** | RFC 9110 + project's OpenAPI spec disagree on header case-handling | OpenAPI spec wins for project-specific routes; RFC wins for general framing |
| **Greenfield-Rust** | `AGENTS.md` vs `docs/spec/v1` vs `COMPREHENSIVE_PLAN_TO_MAKE_*.md` drift over months of development | User must canonicalize; convention: `docs/spec/v1/*.md` is highest priority, `AGENTS.md § Hard Requirements` second, plan documents lowest |

### Per-class delegation syntax

When sources have a stable hierarchy, the contract can declare it:

```toml
[[spec_sources]]
name = "primary-spec"
path = "docs/spec/v1/specification.md"
sha256 = "..."

[[spec_sources]]
name = "hard-requirements"
path = "AGENTS.md#hard-requirements-non-negotiable"
sha256 = "..."
delegates_to = "primary-spec"
# When this source is silent or conflicts with primary-spec, primary-spec wins.
# Detector downgrades TagCollision to Yellow (not Blocker) when delegates_to is set
# AND the source-A and source-B differ in *additional detail* not *opposition*.
```

## Failure modes

| Failure | Symptom | Detection | Fix |
|---|---|---|---|
| **Silently picking one** | Two spec sources conflict; extractor picks first-loaded; harness verifies that one; user finds out months later that the other source's requirement is unverified. | Phase 2 blocker absent; agents proceed to Phase 3 with conflicts unresolved; `phase2_spec_conflict.md` either missing or marked OK by hand. | The script exits 64 on blocker; CI fails Phase 2; orchestrator refuses to advance phase. Never "manually mark resolved without amending sources." |
| **Hiding the conflict in a deferred bead** | Agent detects conflict, writes "TODO: resolve in bd-N" in `phase2_spec_conflict.md`, marks as resolved. | Audit `phase2_spec_conflict.md` for the phrase "TODO" or "tracking in bd-"; per-conflict resolution must include a SHA change to one or both spec sources. | The blocker report has a structured `resolved_by: { source: X, commit_sha: Y }` field; harness verifies the commit SHA touched the source's path. |
| **Negation-pair false-positive** | "MUST accept" and "MUST not accept" detected as contradiction; but the second is in an error-handling subsection and refers to malformed input. Both correct. | Manual review of `SpecConflict::Contradiction` entries before resolution; user marks false-positives via `false_positive: true` flag in resolution. | Contradiction detection augmented with topic-extraction (`extract_shared_topic`) to scope the conflict; if topics diverge by >0.3 Jaccard, downgrade to yellow. |
| **Numeric threshold tolerated as same** | Source A: "< 1e-15"; Source B: "< 1e-12"; both interpreted as "small enough" by the harness author, picked one. | Numeric extractor parses every threshold; flags any mismatch ≥ 2 orders of magnitude as blocker. | Resolve explicitly: pick one threshold, amend the other source. Or split into two tags scoped to different operating regimes. |
| **Contradiction detector over-flags small wording differences** | Source A: "the system must reject malformed input"; Source B: "the system rejects malformed input"; flagged as quantifier mismatch. | Manual review queue grows huge; agents start ignoring it. | Tune signal sensitivity; bake well-known equivalent-rewording pairs into a normalized form pre-comparison. |
| **Unverified-overlap below 0.85 sim missed** | Two sources say the same thing at sim=0.82; one is unverified; user sees both in catalog but no overlap flag. | Periodic audit; raise the threshold gradually as detector matures. | Tunable `--overlap-threshold` flag; default 0.85; lower in projects with verbose spec style. |
| **Detector run before extractor** | `spec-conflict-detector` reads stale `SPEC-TAGS.json`; reports phantom conflicts from old extraction. | Detector cross-checks `SPEC-TAGS.json` modification time against source SHAs in contract; refuses to run if stale. | Idempotent two-step driver: extractor always runs first; detector reads its output. |
| **Resolution by deleting the harder source** | Conflict between `AGENTS.md` and `docs/spec/v1`; "resolved" by deleting `AGENTS.md` Hard Requirements section. | Contract revision delta review: any spec source whose SHA goes to zero-bytes or whose extraction count drops by >50% is a yellow on its own. | User must justify deletion in `spec_version_contract.toml#meta.revision_log`; orchestrator pings for confirmation. |
| **`delegates_to` chain that loops** | `AGENTS.md delegates_to docs/spec/v1`; `docs/spec/v1 delegates_to AGENTS.md`. | Detector topologically sorts the delegation graph; emits hard error on cycle. | Phase 2 refuses to extract until graph is acyclic. |

## Cross-references

- [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) — port-mode analog; conflicts there are between upstream patch versions.
- [pattern:11-SPEC-TAG-EXTRACTION](11-SPEC-TAG-EXTRACTION.md) — upstream producer; this pattern is the immediate downstream consumer.
- [pattern:13-SINGLE-CRATE-VS-WORKSPACE-DECISION](13-SINGLE-CRATE-VS-WORKSPACE-DECISION.md) — affects where the detector binary lives.
- [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) — preflight Red if `phase2_spec_conflict.md` is non-empty BLOCKER.
- [pattern:31-SCHEMA-VERSION-MIGRATION-DUAL-READER](31-SCHEMA-VERSION-MIGRATION-DUAL-READER.md) — when `SpecConflict` enum gains a new variant.
- [pattern:110-INVARIANT-CATALOG](110-INVARIANT-CATALOG.md) — invariants that resolve via "delegates_to" still flow into the catalog with the resolved body.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — `fail-invalid-references` if a verifier claims it tests a tag that was resolved via deletion.
- [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) — resolutions that "we chose A over B because B was wrong" should be banked as conformance-negative-results entries.
- [pattern:275-THEORY-KILL-IMMEDIATE-CLOSE](275-THEORY-KILL-IMMEDIATE-CLOSE.md) — resolving a Contradiction by amending one source is literally a theory-kill: one of the two beliefs is refuted, close it.
- [`../methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) §4 — the BLOCKER convention this pattern implements.
- [`../methodology/DEEP-HYPOTHESIS-REVIEW.md`](../methodology/DEEP-HYPOTHESIS-REVIEW.md) §2 — the `◊ PARADOX-HUNT` operator drives the detection step.
- [`../../subagents/scope-decider.md`](../../subagents/scope-decider.md) — Phase 2 owner; runs the detector.
