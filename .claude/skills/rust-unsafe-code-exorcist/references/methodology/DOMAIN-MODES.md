# DOMAIN-MODES.md — Domain-Specific Audit Overlays

The 7 base modes ([OPERATING-MODES.md](OPERATING-MODES.md)) cover the audit's lifecycle. Domain-specific modes are OVERLAYS that adjust priorities, operators, and acceptance criteria for specific kinds of projects.

The overlay does NOT replace a base mode. It runs ALONGSIDE:

```
base_mode = audit-only
overlay   = cryptography-audit

→ The base mode dictates phases / convergence / harness.
→ The overlay adjusts which patterns are emphasized, which operators run first,
  and what counts as acceptable in each polish-bar dimension.
```

---

## Shipped overlays

| Overlay | When | Adjusts | Status |
|---------|------|---------|--------|
| `cryptography-audit` | Crypto crates (RNG, cipher, hash, signature) | Constant-time, secret-zeroing, side-channel | shipped → [100-CRYPTOGRAPHY-AUDIT.md](../patterns/100-CRYPTOGRAPHY-AUDIT.md) |
| `tagged-pointer-migration` | Codebases with tagged-pointer-via-usize patterns | Strict-provenance migration patterns | shipped → [130-TAGGED-POINTER-MIGRATION.md](../patterns/130-TAGGED-POINTER-MIGRATION.md) |
| `kernel-driver-audit` | Kernel modules / drivers / VFIO | Interrupt safety, IOCTL surfaces, lifecycle | proposed (see IDEA-015 in [IDEAS.md](IDEAS.md)) |
| `database-engine-audit` | Database engines / storage primitives | Durability, ACID, storage-format soundness | proposed |
| `cryptocurrency-audit` | Wallet / signing libraries | Same as crypto + key-zeroing + canonical encoding | proposed |
| `embedded-rtos-audit` | RTOS / hard real-time | Determinism, no-allocator, interrupt-safety | proposed (overlaps with [55-EMBEDDED-PATTERNS.md]) |
| `wasm-sandbox-audit` | wasm runtime / sandbox | Module isolation, memory bounds, ABI safety | proposed |

---

## How an overlay works

Each overlay declares:

### 1. Emphasis bundles

Which `references/patterns/` bundles get higher attention in this domain.

```markdown
## Emphasis bundles (crypto)

- 100-CRYPTOGRAPHY-AUDIT.md (the primary; domain-specific)
- 00-CANONICAL-UNAVOIDABLE.md (constant-time intrinsics are A)
- 50-SEND-SYNC-IMPLS.md (key material's Send/Sync is critical)
- 70-UNINIT-AND-TRANSMUTE.md (secret-bearing types need Zeroize)
```

### 2. Operator order overrides

Some operators move up in priority for this domain.

```markdown
## Operator priorities (crypto)

Phase 4 classifier walks operators in this order:
1. (NEW) ⊠ Constant-time-witness — primary concern
2. (NEW) ⌗ Secret-zeroing-check
3. ⊙ Invariant-Locator (standard)
4. ⊕ Reachability-From-Safe
5. (rest of standard order)
```

### 3. Polish-bar dimension adjustments

The dimensions in [POLISH-BAR.md](POLISH-BAR.md) are tightened or relaxed for the domain.

```markdown
## Polish-bar adjustments (crypto)

- Dimension 7 (Send/Sync audit) — TIGHTENED: every secret-bearing type
  must have explicit `Zeroize` impl + `Send` constraint analysis.

- (NEW) Dimension 13: Constant-time discipline — every unsafe site touching
  secret data MUST be constant-time (no early returns; no data-dependent branches).

- (NEW) Dimension 14: Secret-zeroing — every secret-bearing type MUST have
  `Drop` that zeroes the secret. Verified via dtolnay's `zeroize` crate.
```

### 4. Additional verification tools

Beyond the standard harness:

```markdown
## Additional verification (crypto)

- `cargo-careful` with constant-time check (custom; not in upstream).
- `dudect` or similar for constant-time empirical verification.
- `clippy::eq` lints on secret comparison (always use `subtle::ConstantTimeEq`).
```

### 5. Specific (A) / (B) / (C) defaults

The overlay's pattern bundle has its own (A)/(B)/(C) examples + rules.

---

## How to invoke an overlay

```bash
/rust-unsafe-code-exorcist <project> --mode audit-only --overlay cryptography-audit
```

The orchestrator:
1. Reads the overlay's methodology file.
2. Composes its emphasis bundles + operator order + polish-bar dimensions into the audit.
3. Runs the standard phase loop with the adjusted priorities.
4. The final AUDIT_SUMMARY documents the overlay applied.

---

## Composing overlays

Multiple overlays can apply to the same project (e.g., a crypto wallet is `cryptography-audit` + `cryptocurrency-audit`).

```bash
/rust-unsafe-code-exorcist <project> --overlay cryptography-audit,cryptocurrency-audit
```

Conflict resolution:
- Emphasis bundles: union (both bundles emphasized).
- Operator order: the LATER overlay's priority wins (per-overlay declared order).
- Polish-bar dimensions: the STRICTER overlay wins (if one tightens, the other can't relax).

Document the composition in `audit/synthesis/overlay-composition.md`.

---

## Authoring a new overlay

To add a new domain overlay:

1. Write `references/patterns/<NNN>-<DOMAIN>-AUDIT.md` with:
   - Domain-specific failure modes.
   - Domain-specific operators.
   - Domain-specific (A) / (B) / (C) examples.
   - Acceptance criteria adjustments.

2. Add an entry to this file (DOMAIN-MODES.md) under "Shipped overlays".

3. Add to the SKILL.md scope governor's overlay list.

4. Add to KICKOFF-PROMPTS.md if a per-overlay kickoff makes sense.

5. Update IDEAS.md's IDEA-015 with the new overlay.

6. Test against a representative project from the domain.

---

## When to NOT use an overlay

Overlays add discipline but also overhead. Don't apply if:

- The project doesn't actually fit the domain (e.g., applying `cryptography-audit` to a parser library that happens to compute checksums).
- The base mode + standard polish-bar suffices.
- You're doing a quick `audit-only` for triage; full overlay discipline is for the deep audit.

The overlay's value is the DOMAIN-SPECIFIC bar. Outside the domain, it adds friction without proportional benefit.

---

## Acceptance signal

An overlay-applied audit passes when:

1. The overlay's emphasis bundles are explicitly read + cited in plans.
2. The overlay's operator order is followed in Phase 4 / 6.
3. The overlay's polish-bar dimensions are checked in addition to standard.
4. The overlay's additional verification tools have run (or been documented as skipped with reason).
5. `audit/synthesis/overlay-composition.md` documents the overlay(s) applied.

Domain-specific bar, when the project is in the domain.
