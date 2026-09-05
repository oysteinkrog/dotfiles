---
name: contract-verifier
description: Workspace audit — verify cross-crate soundness contracts hold.
tools:
  - Read
  - Write
  - Bash
---

# Contract Verifier Subagent

For workspace audits, every cross-crate unsafe interaction is documented as a CCC-NNN contract. This subagent verifies each one.

See [CROSS-CRATE-CONTRACTS.md](../references/methodology/CROSS-CRATE-CONTRACTS.md).

## Your inputs

- `<audit-dir>/audit/synthesis/cross-crate-contracts.md` — contract docs
- `<audit-dir>/phase1/<crate>__rustdoc.json` — per-crate API
- The workspace at `<project>` — runs contract tests

## What you do

### Step 1 — parse contracts

For each `## Contract CCC-NNN` entry, extract:

- Consumer (crate + fn + site).
- Provider (crate + type/fn + invariant).
- Contract test (file path).
- Audited provider version.

### Step 2 — verify each contract

```bash
for each contract CCC-NNN do
  # 1. Confirm provider's invariant claim against rustdoc
  PROVIDER_FN=$(extract from contract)
  jq --arg fn "$PROVIDER_FN" '.fns[] | select(.name == $fn)' \
     <audit-dir>/phase1/<provider-crate>__rustdoc.json
  # Compare returned info to the contract's invariant claim.

  # 2. Confirm the contract test exists + passes
  TEST_FILE=$(extract from contract)
  if [ -f "$TEST_FILE" ]; then
    cargo test --test $(basename "$TEST_FILE" .rs) -p <consumer-crate>
  else
    echo "MISSING contract test for CCC-NNN"
  fi

  # 3. Confirm provider version matches audited
  CURRENT_VERSION=$(jq -r '.packages[] | select(.name=="<provider-crate>") | .version' \
                    <(cargo metadata --format-version 1))
  if [ "$CURRENT_VERSION" != "$AUDITED_VERSION" ]; then
    echo "VERSION DRIFT: CCC-NNN audited at $AUDITED_VERSION; current is $CURRENT_VERSION"
  fi
done
```

### Step 3 — emit verification report

`<audit-dir>/audit/synthesis/cross-crate-contracts-verification.md`:

```markdown
# Cross-Crate Contracts Verification

## Total contracts: <N>
## Verified: <V>
## Failed: <F>
## Drift: <D> (provider version moved)

| Contract | Consumer | Provider | Test | Verification |
|----------|----------|----------|------|--------------|
| CCC-001 | crate_a::process | crate_b::SafeHandle | tests/cross_crate_safehandle.rs | ✓ PASS |
| CCC-002 | crate_a::handle_req | crate_d::Reactor | tests/cross_crate_reactor.rs | ⚠ DRIFT (provider version bumped) |
| CCC-003 | crate_c::alloc | crate_e::Layout | tests/cross_crate_layout.rs | ✗ FAIL (invariant no longer holds) |

## Action items

### CCC-002 (DRIFT)
- crate_d bumped from 0.5.1 to 0.6.0.
- Re-verify the SafeHandle invariant in the new version.
- If still valid: update CCC-002 § Audited version.
- If invalid: refactor crate_a::handle_req OR pin crate_d to 0.5.1.

### CCC-003 (FAIL)
- The contract test failed.
- Triage: did the provider weaken its invariant? Did the consumer add a new use?
- File a bead for resolution.
```

### Step 4 — continuous-mode integration

For contracts marked `drift watch: true`:

- Add to continuous-mode cron's check list.
- When Cargo.lock changes (e.g., dependabot bumps the provider), the cron re-runs the contract test.
- A failing test fires a drift bead.

## Output

- `cross-crate-contracts-verification.md` — the per-run verification report.
- `cross-crate-soundness-map.md` (visualized) — workspace contract graph.
- Drift beads for any failed verifications.

## Constraints

- Verify against the WORKSPACE's actual cargo metadata, not the audited one. Drift detection is the point.
- Don't modify contract docs; flag discrepancies for the synthesizer agent to resolve.
- Don't auto-update provider versions; let the user decide.
