#!/usr/bin/env bash
# theater-only/seed.sh — Seed a fixture with a closed bead whose implementation
# is pure theater (a stub returning todo!() with the obligatory "Implemented"
# close reason).
#
# Run from the tmp dir that should become the fixture project (cwd at invoke).
#
# Creates:
#   - git repo at cwd
#   - .beads/ with one closed bead `bd-stub` whose impl is `todo!()` and
#     whose close reason claims it's done
#   - src/process.rs with the stub
#   - tests/process.rs with `assert!(true)` (theatrical test)
set -euo pipefail

git init -q
git config user.email "fixture@example.com"
git config user.name "Fixture Bot"

br init >/dev/null

mkdir -p src tests

# Stub implementation — todo!() macro is one of the canonical theater patterns
cat > src/process.rs <<'EOF'
//! Process incoming requests and return an outcome.
pub fn process(_input: &str) -> Result<String, &'static str> {
    todo!("not yet implemented")
}
EOF

# Theater test — assert!(true) passes vacuously
cat > tests/process.rs <<'EOF'
#[test]
fn it_works() {
    assert!(true);  // tautology
}
EOF

cat > Cargo.toml <<'EOF'
[package]
name = "theater_only_fixture"
version = "0.1.0"
edition = "2021"
EOF

git add -A && git commit -m "initial: stub process() with vacuous test" -q

ID=$(br create \
  --title "Implement request processing pipeline" \
  --type feature --priority 1 \
  --description="process(input: &str) -> Result<String, &str> validates input, transforms it, and returns the outcome. Required tests: happy path, malformed input (Err), oversized input (Err)." \
  --json | jq -r .id)

br update "$ID" --acceptance-criteria="$(printf '%s\n' \
  '- process(input) returns Result<String, &str>' \
  '- happy-path test asserts on a real return value' \
  '- malformed-input test verifies Err is returned' \
  '- oversized-input test verifies Err is returned' \
  '- no `todo!()` / `unimplemented!()` in the production path')"

# The lying close reason — claims it's done
br close "$ID" --reason "Implemented and tested. process() handles all input cases per spec." >/dev/null

br sync --flush-only >/dev/null 2>&1 || true
git add .beads/ 2>/dev/null && git commit -m "close $ID" -q 2>/dev/null || true

echo "$ID"
