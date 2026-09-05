# AUDIT-FIXTURE-LIBRARY.md — Synthetic Test Projects For The Audit Itself

<!-- TOC: Why fixtures | The 6 fixtures | Generating fresh fixtures | Using fixtures for regression | Adding new fixtures -->

> The audit is itself code. Code needs tests. The fixture library is a set of synthetic projects (good, bad, yo-yo, edge-case) used to regression-test the audit infrastructure itself.

> **Why this matters.** When you change the rubric, add a new theater pattern, or upgrade a subagent prompt, you need to verify the audit still produces the right verdicts on known cases. The fixtures provide those known cases.

> ✅ **Implementation status: shipped.** `scripts/regression-test.sh`, `scripts/compare-to-expected.py`, `scripts/regenerate-fixture.sh`, and `assets/fixtures/{known-good,theater-only}/` are real and runnable. Run `scripts/regression-test.sh` to invoke the suite. Adding the remaining 4 of the 6 documented fixtures (yo-yo, edge-case, bug-bead, perf-bead) is incremental: copy `assets/fixtures/known-good/` as a template, edit `seed.sh`, generate `EXPECTED.md` via `scripts/regenerate-fixture.sh`.

---

## The 6 fixtures

Located in `assets/fixtures/`:

### Fixture 1: `known-good`

A 3-bead project where every bead is genuinely complete:
- `bd-feat-clean` — feature with proper impl, happy + error + edge tests, 92% coverage.
- `bd-bug-clean` — bug with regression test that BISECTs cleanly.
- `bd-docs-clean` — docs bead with README updated and runnable code samples.

**Expected audit verdict:** all 3 score ≥ 950, 0 false-closed.

### Fixture 2: `known-bad`

A 3-bead project where every bead is theater:
- `bd-feat-stub` — `unimplemented!()` in primary deliverable, `assert true` test.
- `bd-bug-no-regression` — fix exists but no regression test.
- `bd-docs-todo` — README has "TODO: write this section".

**Expected audit verdict:** all 3 score < 250, 3 false-closed.

### Fixture 3: `mixed-realistic`

A 10-bead project with realistic distribution:
- 4 clean (score 850-985).
- 3 partial (score 600-750).
- 2 false-closed (score 300-500).
- 1 epic that legitimately ties them together.

**Expected audit verdict:** 2 false-closed; epic dimension 6 reflects child quality.

### Fixture 4: `yo-yo-trajectory`

Same project as fixture 3, but with **two passes** baked in:
- Pass 1: bd-foo at 900.
- Pass 2: bd-foo at 600 (project regression).
- Pass 3: bd-foo back at 900.

**Expected:** trends.md shows yo-yo trajectory; convergence detects instability.

### Fixture 5: `cross-bead-drift`

A 5-bead project with deliberate cross-bead contract drift:
- `bd-emit` claims to emit `{user_id, score: float}`.
- `bd-consume` claims to consume events, parses `{userId, rating: int}`.
- Both individually score 850+; Phase 7 should catch the drift.

**Expected audit verdict:** synthesis.md flags integration gap; both beads' dimension 6 docked.

### Fixture 6: `edge-cases`

A 5-bead project exercising the audit's edge cases:
- Bead with empty body (auditor should record `coverage_gaps: ["bead body too thin"]`).
- Bead in `tombstone` status (auditor should skip).
- Bead with custom issue_type (auditor should fall back to task defaults).
- Bead with `closed_by_session` matching a sloppy-session pattern.
- Bead with WIP close reason (anomaly-scan should fire).

**Expected:** spec extractor handles each; anomaly-scan flags the WIP and sloppy session.

---

## Layout

```
assets/fixtures/
├── README.md                # how to use the fixtures
├── known-good/
│   ├── .beads/
│   │   ├── beads.db
│   │   └── issues.jsonl
│   ├── src/
│   ├── tests/
│   ├── README.md
│   └── EXPECTED.md          # what the audit should produce
├── known-bad/
│   └── ... (same structure)
├── mixed-realistic/
├── yo-yo-trajectory/
├── cross-bead-drift/
└── edge-cases/
```

Each fixture's `EXPECTED.md` documents:
- Bead count and statuses.
- Per-bead expected score (with tolerance).
- Per-bead expected verdict band.
- Cross-bead expected findings.
- Convergence expected behavior across N passes.

---

## Using fixtures for regression

```bash
# scripts/regression-test.sh
SKILL=~/.claude/skills/beads-compliance-and-completion-verification
FIXTURES=("$SKILL/assets/fixtures"/*/)

PASSED=0
FAILED=0

for fixture in "${FIXTURES[@]}"; do
  name=$(basename "$fixture")
  echo "=== Fixture: $name ==="

  # Copy to /tmp so the audit doesn't pollute the fixture
  TMPDIR=$(mktemp -d)
  cp -r "$fixture" "$TMPDIR/"
  cp -r "$fixture/.beads" "$TMPDIR/$name/"

  # Run audit
  "$SKILL/scripts/run-pass.sh" "$TMPDIR/$name" --threshold 700 --policy report-only \
    >"$TMPDIR/$name.audit.log" 2>&1

  # Compare to EXPECTED.md
  python3 "$SKILL/scripts/compare-to-expected.py" \
    "$TMPDIR/$name" \
    "$fixture/EXPECTED.md" \
    && PASSED=$((PASSED+1)) \
    || { FAILED=$((FAILED+1)); cat "$TMPDIR/$name.audit.log"; }
done

echo
echo "Regression: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
```

Run after every change to scorer / theater-scan / synthesize / rubric. If any fixture fails, the change broke an expected behavior.

---

## Compare-to-expected script

`scripts/compare-to-expected.py` (sketch):

```python
import argparse, json, re, sys
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("audit_dir")
p.add_argument("expected_md")
args = p.parse_args()

# Parse EXPECTED.md
expected = {}
text = Path(args.expected_md).read_text()
for m in re.finditer(r'`(bd-[a-z0-9-]+)`.*?score:\s*(\d+)\s*[±+/-]\s*(\d+)', text):
    expected[m.group(1)] = (int(m.group(2)), int(m.group(3)))

# Read actual scores
audit_dir = Path(args.audit_dir) / "beads_compliance_audit"
latest = sorted((audit_dir / "passes").iterdir())[-1]
mismatches = []
for sc in (latest / "beads").glob("*/scorecard.md"):
    bead_id = sc.parent.name
    score_m = re.search(r'\*\*Score:\s+(\d+)', sc.read_text())
    if not score_m or bead_id not in expected:
        continue
    actual = int(score_m.group(1))
    target, tol = expected[bead_id]
    if abs(actual - target) > tol:
        mismatches.append(f"{bead_id}: expected {target}±{tol}, got {actual}")

if mismatches:
    print("MISMATCHES:", file=sys.stderr)
    for m in mismatches:
        print(f"  {m}", file=sys.stderr)
    sys.exit(1)
print(f"OK ({len(expected)} beads matched)")
```

---

## Generating fresh fixtures

The fixtures are check-in-able but slowly drift if br schema changes. Regenerate via:

```bash
# scripts/regenerate-fixture.sh known-good
# 1. Wipe fixture .beads/
rm -rf "$FIXTURE_DIR/.beads"
# 2. Re-init with current br
cd "$FIXTURE_DIR" && br init >/dev/null
# 3. Apply the fixture's bead-creation script
bash "$FIXTURE_DIR/seed.sh"
# 4. Sync
br sync --flush-only
# 5. Commit
cd "$SKILL_REPO" && git add -A && git commit -m "fixtures: regenerate $name"
```

Each fixture has a `seed.sh` that creates the beads via `br create` / `br update` / `br close` so the bead state is reproducible.

---

## Adding new fixtures

When you discover a real-world pattern that the existing fixtures don't cover:

1. **Create a new fixture directory** under `assets/fixtures/<descriptive-name>/`.
2. **Write `seed.sh`** that creates the beads via br commands.
3. **Run `seed.sh`** to populate `.beads/`.
4. **Run the audit once** and capture the output as `EXPECTED.md`.
5. **Hand-verify** the EXPECTED.md is what the audit *should* produce.
6. **Add to `regression-test.sh`** (if not auto-discovering all fixtures).
7. **Commit** the fixture.

Fixtures should be small (< 10 beads) — they're sanity tests, not load tests.

---

## What fixtures don't cover

The fixture library tests the audit's *correctness*, not:

- **Performance.** Use a realistic-size project for cost / time benchmarking.
- **Multi-pass behavior.** Some fixtures (yo-yo) span passes, but full convergence over 5 passes isn't fixture-tested — it's manually validated.
- **Subagent invocation.** Fixtures run via the wrapper script which stubs Phase 4. Real subagent runs require a different test harness.
- **CI / Tripwire.** Fixtures don't exercise the GitHub Actions / cron paths.

For those, use real projects.

---

## Fixture lifecycle

| Event | Action |
|-------|--------|
| New theater pattern added | Add a fixture that triggers it |
| Rubric weight changed | Re-run all fixtures; verify EXPECTED.md still matches (or update with reason) |
| br schema changes | Regenerate `.beads/` via `seed.sh` for every fixture |
| Subagent prompt changed | Re-run fixtures; differences indicate prompt drift |
| Major skill version bump | Snapshot fixtures' EXPECTED.md alongside the version tag |

---

## CI integration

```yaml
# .github/workflows/skill-regression.yml
on: [push, pull_request]
jobs:
  regression:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install br
        run: curl -fsSL .../install.sh | bash
      - name: Run fixture regression
        run: |
          ~/.claude/skills/beads-compliance-and-completion-verification/scripts/regression-test.sh
```

Every push to the skill repo runs all fixture audits. If any fail, the change isn't merged. This is the same discipline the skill teaches projects: verify the verifier.

---

## Anti-patterns

- Editing `EXPECTED.md` to make a regression "pass" without understanding why.
- Skipping fixtures because "the change is small."
- Adding fixtures that depend on external state (network, time of day, env vars).
- Storing real customer data in fixtures.
- Using fixtures as performance benchmarks (they're correctness tests).