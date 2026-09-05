# CONTRIBUTING-PATTERNS.md — How To Add A New Failure-Mode Pattern

<!-- TOC: When to add | The 7-step contribution flow | Pattern card template | Regex / AST / non-grep | Severity calibration | Updating the rubric version | Testing the pattern | Don't-add checklist -->

> When you discover a new theater pattern in the wild, the audit can be taught to catch it next pass. This file is the contribution flow. Inspired by `/codebase-pattern-extraction` — patterns recur across projects, and the catalog should grow with experience.

---

## When to add a new pattern

Add a pattern when:

1. You found theater that the existing 30 patterns missed.
2. The pattern is **reproducible** — you can describe a regex / AST shape / non-grep signal that catches it.
3. The pattern is **calibratable** — you have at least one verbatim quote (cass mining or session log) showing the closer's intent.
4. The pattern is **likely to recur** — not a one-off in a specific project (project-specific patterns go in `rubric.md#project_specific_patterns`, not `FAILURE-MODES.md`).

Don't add when:

- The pattern is just a variant of an existing one (extend the existing pattern's regex instead).
- The pattern is project-specific (use the per-project rubric.md instead).
- The pattern is a one-off (note in the audit's pass-specific synthesis but don't promote to the catalog).

---

## The 7-step contribution flow

### Step 1: Document the pattern

Write a pattern card (template below) capturing:
- Trigger (regex / AST / non-grep signal)
- What it looks like (concrete example)
- Rubric impact (severity, dimension penalty)
- Remediation hint

### Step 2: Find a quote

From cass mining OR your own session log, capture a verbatim agent quote that anchors the pattern. Add to `QUOTE-BANK.md`. Anonymize bead IDs and project paths if sensitive.

### Step 3: Implement the detection

| Detection type | Where to add |
|----------------|--------------|
| Grep / ripgrep regex | `scripts/theater-scan.sh` `scan_pattern` calls |
| AST shape | `scripts/theater-scan.sh` ast-grep blocks (where applicable) |
| Non-grep (git history, close reason, time delta) | `scripts/anomaly-scan.sh` |
| Subagent-only (LLM judgment required) | `subagents/theater-detector.md` discipline section |

### Step 4: Test the pattern

Create a synthetic bead that should trigger the pattern. Run the audit on it. Verify:
- Phase 5 / anomaly-scan flags the new pattern.
- Severity matches the card.
- Phase 8 docks the right dimension by the right amount.

```bash
# Smoke test
TEST_PROJ=/tmp/pattern-test-$(date +%s)
mkdir -p "$TEST_PROJ" && cd "$TEST_PROJ"
git init -q && br init >/dev/null
# Create the synthetic stub matching the new pattern
echo '<the pattern content>' > test_file.rs
git add . && git commit -q -m "synthetic"
# Create + close a bead that should trip the pattern
ID=$(br create --title "Test pattern N" --type feature --priority 1 \
  --description='spec' --json | jq -r .id)
br close "$ID" --reason "done" >/dev/null
~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh "$TEST_PROJ" --threshold 700 --policy report-only
# Verify the new pattern surfaced
grep "<pattern category>" "${TEST_PROJ}/beads_compliance_audit/passes/"*/beads/*/theater.json
```

### Step 5: Update FAILURE-MODES.md

Add a new section "Pattern N — <name>" with the card content. Keep the numbering monotonic.

### Step 6: Bump the rubric version

In `assets/rubric-template.md` frontmatter:
```yaml
rubric_version: 1.0.1   # was 1.0.0
```

Add an entry to the rubric.md "Rubric change history" table:
```markdown
| 2026-05-06 | 1.0.0 → 1.0.1 | Added pattern N (<short name>) | <reason> |
```

This bump signals to `convergence-check.py` that score changes pass-over-pass include the new pattern's effects, so they're not "drift" but expected calibration.

### Step 7: Document the test fixture

In a new `assets/test-fixtures/pattern-N/` directory, save:
- The synthetic bead body
- The synthetic file content that triggers the pattern
- The expected `theater.json` output

This becomes a regression test for the pattern detector itself.

---

## Pattern card template

Copy this into `FAILURE-MODES.md`:

```markdown
## Pattern N — <name>

**Trigger.** <regex / AST shape / non-grep signal>. Specifically: `<pattern>`.

**What it looks like.**
\`\`\`<language>
<concrete example showing the pattern>
\`\`\`

(Quote anchor: see `QUOTE-BANK.md` Pattern N.)

**Rubric impact.** `theater.json: <SEVERITY>`. <How it folds into Phase 8 scoring.>

**Remediation hint.** <What completion-debt should require.>

**False-positive caveats.** <When this pattern matches but it's actually fine — e.g., legitimate `pass` in Python protocol method.>
```

---

## Regex vs AST vs non-grep

| Pattern type | Use | Example |
|-------------|-----|---------|
| **Regex** | Surface-level keyword / phrase | `unimplemented!\(`, `assert\s+true` |
| **AST shape** | Structural code patterns | "function with single statement that's a literal" |
| **Non-grep** | Metadata signals | Time-to-close < 5 min, batch close, empty git diff |
| **LLM-only** | Semantic intent | "the test asserts on input not behavior" — needs reasoning |

**Prefer regex** when possible (fastest, deterministic). Fall back to AST when regex would have too many false positives. Use non-grep for metadata. Reserve LLM-only patterns for the subagent layer (theater-detector.md), not for `scripts/`.

---

## Severity calibration

When choosing severity for a new pattern, calibrate against existing ones in `RUBRIC.md` §3:

| Severity | Penalty | Anchor patterns |
|----------|--------:|-----------------|
| BLOCKING | -50 | unimplemented!, assert true, mock-where-forbidden, sleep-as-fake-work, schema-without-migration |
| MAJOR | -15 | hardcoded trivial return (non-primary), cfg(test) guard, 501 stub, batch-close, time-to-close anomaly |
| MINOR | -3 | TODO comment, dead branch with no test |
| NOTE | 0 | Style nit, harmless `pass` in protocol method |

**Rule of thumb:** BLOCKING means "this invalidates the bead's primary claim." MAJOR means "significant gap, but not invalidating." MINOR is "small concern." NOTE is "flagged for awareness only."

If your new pattern doesn't fit cleanly into one severity, it might need to be MULTIPLE patterns at different severities (e.g., "explicit no-op" = BLOCKING; "TODO comment" = MINOR).

---

## Updating the rubric version

`rubric.md` is SHA-pinned in every audit's `manifest.json#rubric_sha256`. When the rubric changes, the SHA changes, and `convergence-check.py` records it as `rubric_changed_since_prior_pass`. Without a version bump, score deltas appear as "drift" instead of "expected calibration."

**Rule:** any change to `rubric.md` (including adding pattern detection to `FAILURE-MODES.md` if it changes Phase 5/8 behavior) MUST bump the version.

```
1.0.0 → 1.0.1   patch: added new pattern, no scoring changes for existing patterns
1.0.0 → 1.1.0   minor: changed weights, rebalanced dimensions, new bead-type rubric
1.0.0 → 2.0.0   major: scoring scale changed (e.g., 0-1000 → 0-100), incompatible
```

---

## Testing the new pattern

The new pattern should pass two tests:

### Test 1: Catches the synthetic case

```bash
# The synthetic project from Step 4 should produce a theater.json finding
# matching pattern N.
jq '.findings[] | select(.category == "<pattern_category>")' \
  "$AUDIT_DIR/passes/"*/beads/*/theater.json
```

### Test 2: Doesn't catch a known-good case

Create a *negative test*: a bead where the pattern *almost* matches but legitimately doesn't:

```bash
# E.g., for "unimplemented_macro": ensure that a doc-comment containing the
# word "unimplemented" doesn't trigger the pattern.
echo '/// This handles input that is unimplemented in the spec.' > test_file.rs
echo 'fn handle(input: Input) -> Result<(), Error> { Ok(()) }' >> test_file.rs
# Run the audit
~/.../run-pass.sh "$TEST_PROJ"
# Verify pattern did NOT fire
jq '.findings[] | select(.category == "unimplemented_macro")' \
  "$AUDIT_DIR/passes/"*/beads/*/theater.json
# Should be empty
```

If your pattern fires on the negative test, the regex is too broad. Tighten it.

---

## Don't-add checklist

Before merging your pattern, verify:

- [ ] Regex / detection is **specific** (negative tests pass).
- [ ] At least one verbatim quote anchors the pattern (`QUOTE-BANK.md`).
- [ ] Severity is calibrated against existing patterns.
- [ ] False-positive caveats are documented.
- [ ] The remediation hint is **concrete** (file:line, not "fix the code").
- [ ] `assets/test-fixtures/pattern-N/` includes both positive and negative test cases.
- [ ] `rubric_version` bumped in `assets/rubric-template.md`.
- [ ] Detection added to `scripts/theater-scan.sh` OR `scripts/anomaly-scan.sh`.
- [ ] `FAILURE-MODES.md` numbered monotonically.

---

## Project-specific patterns vs catalog patterns

- **Catalog patterns** (`FAILURE-MODES.md`) apply to every project the skill audits.
- **Project-specific patterns** live in the project's own `rubric.md#project_specific_patterns`. Discovered via CASS mining (see `CASS-MINING.md`).

The decision is "does this pattern recur across projects?" If you've seen it on 2+ projects, promote to the catalog. If only one, keep it project-specific.

Project-specific patterns can be promoted later when their cross-project recurrence is established.

---

## Removing a pattern

Patterns are rarely removed (the audit dir's history references them). If a pattern is consistently producing false positives:

1. **First, tighten** the regex / AST / signal. The fix is usually narrowing, not removal.
2. **If still bad,** mark the pattern DEPRECATED in `FAILURE-MODES.md`. Don't delete the section — old audit dirs reference it.
3. **In `theater-scan.sh`**, comment out the `scan_pattern` call (don't delete) so historical patterns can be re-enabled if needed.
4. **Bump rubric version** as a major (e.g., 1.x.x → 2.0.0) since scoring becomes non-comparable across the boundary.

This is rare; the catalog grows much more than it shrinks.