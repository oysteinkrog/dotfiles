# Cookbook: Spec-Tag Orphan Cleanup

## Trigger

Either of these states is detected at round-close synthesis or during Phase 3 oracle preflight:

- A `[SPEC-NNN]` tag exists in `<workspace>/docs/spec/SPEC-TAGS.md` but no matching `verify_spec_<lowercase_tag>` function exists in `spec_oracle.rs` (orphan tag).
- A `verify_spec_<lowercase_tag>` function exists but no matching `[SPEC-NNN]` tag exists in SPEC-TAGS.md (orphan verifier).

Either form is a release-blocker per [`methodology/SPEC-PINNING-FOR-GREENFIELD.md § 3`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md): the catalog count is a release-readiness gate.

## Operator Pipeline

```
🪞 ENGINE-IDENTITY-GUARD → ⊕ ISOMORPHIC-REWRITE (orphan → matched pair) → ✦ ENUMERATE-SURFACE (re-extract) → 🧪 EXPERIMENT-DESIGN (orphan verifier without spec)
```

## Scripts

### Step 1 — enumerate orphans

```bash
WORKSPACE="$1"
TARGET="$2"

# All tags from SPEC-TAGS.md
grep -oE '\[SPEC-[A-Z0-9_-]+\]' "$WORKSPACE/docs/spec/SPEC-TAGS.md" | sort -u > /tmp/tags.txt

# All verifier function names from spec_oracle.rs
ORACLE_PATH="$TARGET/src/harness/spec_oracle.rs"
[ -f "$ORACLE_PATH" ] || ORACLE_PATH="$TARGET/crates/$(basename $TARGET)-harness/src/spec_oracle.rs"
grep -oE 'verify_spec_[a-z0-9_]+' "$ORACLE_PATH" | sort -u > /tmp/verifiers.txt

# Convert tags to expected verifier names
sed -E 's/\[SPEC-([A-Z0-9_-]+)\]/verify_spec_\L\1/' /tmp/tags.txt | tr '-' '_' > /tmp/expected_verifiers.txt

# Orphan tags = expected_verifiers - actual_verifiers
comm -23 /tmp/expected_verifiers.txt /tmp/verifiers.txt > /tmp/orphan_tags.txt
# Orphan verifiers = actual_verifiers - expected_verifiers
comm -13 /tmp/expected_verifiers.txt /tmp/verifiers.txt > /tmp/orphan_verifiers.txt

echo "Orphan tags (in SPEC-TAGS.md, no verifier):"
cat /tmp/orphan_tags.txt
echo
echo "Orphan verifiers (in spec_oracle.rs, no tag):"
cat /tmp/orphan_verifiers.txt
```

### Step 2 — decide retire-or-implement per orphan tag

For each orphan in `/tmp/orphan_tags.txt`:

- **Implement** if the spec assertion is still normative + has a falsification test surface: dispatch `subagents/greenfield-oracle-wirer.md` to author the verifier. Cross-link the bead to the spec-tag.
- **Retire** if the assertion was downgraded to Charter-only (e.g., user decided it's aspirational, not testable): remove the tag from SPEC-TAGS.md and move the original spec sentence to `<workspace>/docs/CHARTER.md`. Bump `spec_version_contract.toml#/meta.revision`.
- **Refine** if the assertion is genuinely ambiguous (can't classify): flag in `<workspace>/phase2_unverifiable_assertions.md` for user disambiguation.

### Step 3 — decide kill-or-rename per orphan verifier

For each orphan in `/tmp/orphan_verifiers.txt`:

- **Kill** if the verifier corresponds to a removed spec assertion (the assertion was retired but the verifier wasn't): delete the verifier function + the corresponding test in `tests/spec_*_oracle_e2e.rs`. Per AGENTS.md Rule #1, this requires explicit user permission.
- **Rename** if the verifier was authored ahead of the spec tag (the assertion exists in the spec but wasn't yet tagged): add the corresponding `[SPEC-NNN]` to SPEC-TAGS.md; rename the verifier if the casing/naming drifted.
- **Promote-to-spec** if the verifier checks an invariant that SHOULD be in the spec but isn't: dispatch `subagents/spec-tag-extractor.md` after the user adds the assertion to the spec source.

### Step 4 — re-run spec-tag-extractor

```bash
# After all decisions applied, re-extract:
./scripts/dispatch-subagent.sh spec-tag-extractor \
  --param workspace="$WORKSPACE" \
  --param target="$TARGET"

# Verify the new SPEC-TAGS-STATS.json shows zero orphans
jq '.orphan_tags == 0 and .orphan_verifiers == 0' "$WORKSPACE/docs/spec/SPEC-TAGS-STATS.json"
# Must echo: true
```

## Beads

For each orphan-tag implementation:
- One implementation bead: `bd-XXX: implement verifier for [SPEC-XXX-NNN]` with test-bead + bench-bead (if perf-sensitive) + doc-bead dependencies per [`methodology/DEFINITION-OF-DONE.md § Per-bead`](../methodology/DEFINITION-OF-DONE.md).
- One verification bead: `bd-XXX.t: verify <verifier> passes on baseline + regression fixture`.

For each orphan-verifier retire:
- One retire bead: `bd-XXX: retire orphan verifier <name>` with the user's signoff message verbatim attached.

## Exit Criteria

- `/tmp/orphan_tags.txt` is empty.
- `/tmp/orphan_verifiers.txt` is empty.
- `SPEC-TAGS-STATS.json` reports `orphan_tags == 0 && orphan_verifiers == 0`.
- `spec_version_contract.toml#/meta.revision` bumped (if any retire/refine landed).
- Re-invoked `spec-tag-extractor` returns green precondition verdict.

## Anti-patterns

- **Silently delete orphans without classification** — orphans are signal; they often reveal a spec edit that drifted from the harness. Always classify before action.
- **Mass-implement without user input** — a spec source may have grown stale; the orphan tag might be ready to retire, not implement. ASK the user for each orphan above a threshold (e.g., 5+ orphans = require user triage).
- **Skip the spec-tag-extractor re-run** — without re-extraction, the catalog stays inconsistent and the next round repeats the orphan-cleanup work.
- **Bump `spec_version_contract.toml#/meta.revision` without re-pinning source SHA-256s** — the contract becomes a lie (revision incremented but SHA-256s point to pre-edit content).
- **Treat orphan verifiers as harmless dead code** — they pass `cargo build` but their absence-from-spec means the operator can't audit "what does this verifier guarantee". Either tie to a spec tag or retire.

## Cross-references

- [`methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) — the spec-tag catalog discipline.
- [`pattern:11-SPEC-TAG-EXTRACTION`](../patterns/11-SPEC-TAG-EXTRACTION.md) — extraction pattern.
- [`subagents/spec-tag-extractor.md`](../../subagents/spec-tag-extractor.md) — the subagent that maintains the catalog.
- [`subagents/spec-conflict-resolver.md`](../../subagents/spec-conflict-resolver.md) — sibling subagent for spec conflicts.
- [`subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md) — Phase 3 (greenfield) oracle author.
- [`methodology/DEFINITION-OF-DONE.md`](../methodology/DEFINITION-OF-DONE.md) — per-phase + per-bead exit criteria.
- [`cookbook/spec-conflict-detected.md`](spec-conflict-detected.md) — sibling cookbook for conflict resolution.
- [`cookbook/INDEX.md`](INDEX.md) — recipe index.
