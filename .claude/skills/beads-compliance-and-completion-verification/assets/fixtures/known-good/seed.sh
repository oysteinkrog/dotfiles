#!/usr/bin/env bash
# known-good/seed.sh — Seed a fixture project with a properly-implemented closed bead.
#
# Run from the tmp dir that should become the fixture project (cwd at invoke time).
#
# Creates:
#   - git repo at cwd
#   - .beads/ with one closed bead `bd-add` whose implementation, tests, and
#     close reason all match the spec
#   - src/add.rs with a real implementation
#   - tests/add.rs with assertive tests
set -euo pipefail

git init -q
git config user.email "fixture@example.com"
git config user.name "Fixture Bot"

# Initialize br
br init >/dev/null

# Real implementation
mkdir -p src tests
cat > src/add.rs <<'EOF'
//! Two-integer addition with overflow checking.
pub fn add(a: i64, b: i64) -> Result<i64, &'static str> {
    a.checked_add(b).ok_or("overflow")
}
EOF

cat > tests/add.rs <<'EOF'
use crate::add::add;
#[test] fn handles_normal()        { assert_eq!(add(2, 3).unwrap(), 5); }
#[test] fn handles_negative()      { assert_eq!(add(-2, 3).unwrap(), 1); }
#[test] fn detects_overflow()      { assert!(add(i64::MAX, 1).is_err()); }
#[test] fn detects_underflow()     { assert!(add(i64::MIN, -1).is_err()); }
EOF

cat > Cargo.toml <<'EOF'
[package]
name = "known_good_fixture"
version = "0.1.0"
edition = "2021"
EOF

git add -A && git commit -m "initial: real add() with overflow tests" -q

# Create + close the bead with a substantive close reason. Backtick-quoting
# `src/add.rs` and `tests/add.rs` is REQUIRED for the deterministic spec
# extractor (`extract-spec.py::PATH_HINT_RE`) to register them as
# `code_artifacts.expected_path_hints`. Without backticks the chain
# spec → evidence → theater produces a false-positive
# `missing_evidence_citations` BLOCKING finding (the fixture would look
# theater-laden when it's actually the canonical happy-path example).
ID=$(br create \
  --title "Implement checked addition with overflow handling" \
  --type feature --priority 2 \
  --description="Add a checked_add helper at \`src/add.rs\` that returns Result<i64, &str>. Must handle: positive, negative, MAX+1 (overflow), MIN-1 (underflow). Unit tests at \`tests/add.rs\` required for each path." \
  --json | jq -r .id)

br update "$ID" --acceptance-criteria="$(printf '%s\n' \
  '- add(a, b) returns Result<i64, &str>' \
  '- handles positive operands' \
  '- handles negative operands' \
  '- detects overflow (returns Err)' \
  '- detects underflow (returns Err)' \
  '- unit tests cover all 4 paths')"

br close "$ID" --reason "Implemented in src/add.rs:1-4 with 4 unit tests in tests/add.rs covering normal, negative, overflow, underflow. All tests pass." >/dev/null

br sync --flush-only >/dev/null 2>&1 || true
git add .beads/ 2>/dev/null && git commit -m "close $ID" -q 2>/dev/null || true

echo "$ID"  # for the test harness
