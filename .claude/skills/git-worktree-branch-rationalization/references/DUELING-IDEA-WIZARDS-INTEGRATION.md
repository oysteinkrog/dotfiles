# Dueling Idea Wizards — Adversarial Harmonization-Plan Generation

When ≥2 branches collide on a high-stakes file, the harmonization plan is the load-bearing artifact: it determines which defensive checks survive, which refactors win, which intents get composed. A single planner subagent producing a single plan is fine for routine collisions. For high-stakes files (security-sensitive, performance-critical, architecturally-dominant), a single plan is *epistemically thin* — the planner's reasoning may be defensible but isn't *contested*.

This file documents how the skill integrates with the [`/dueling-idea-wizards`](../../dueling-idea-wizards/SKILL.md) skill to generate competing harmonization plans, then adjudicate between them. The output is a plan with adversarial review built in — far harder for a single subtle error to slip through.

> **Why a separate reference?** [HARMONIZATION.md](HARMONIZATION.md) is the methodology — the variant matrix, intent taxonomy, synthesis principles. [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md) is about getting independent agreement from different *models* (Claude vs Codex vs Gemini). This file is about *adversarial divergence inside one model* — two wizards with different optimization criteria, plus an adjudicator. The three are complementary; a Council run uses all three.

---

## 1. The Premise

Two harmonization-planner subagents are spawned with different system-prompt biases:

- **Wizard A — "Preserve every defensive intent"**: prefers conservative composition; never drops a defensive check; willing to land more code if it preserves user intent. Optimization: minimize regression risk. Bias: "if a branch added a guard, the guard belongs in the synthesis."
- **Wizard B — "Minimize total surface area"**: prefers aggressive consolidation; willing to drop redundant guards or merge them into helpers; willing to refactor for clarity. Optimization: minimize maintenance cost. Bias: "if two guards prevent the same input class, one helper covers both."

Both read the *same* variant matrix from Phase 7. Both produce a *full* harmonization plan (synthesis description + line-level proposed changes + variant attributions). The third agent — the adjudicator — reads both plans, the variant matrix, and either picks one, picks-best-of-each, or rejects both and asks for a third round.

The artifact `harmonization_plan_duel.md` records both plans + the adjudication. The synthesis that lands at Phase 8 reflects the adjudicated decision.

---

## 2. When to Duel

Different modes activate the duel at different thresholds.

| Mode | Trigger |
|---|---|
| **Quick** | Never. Quick mode skips harmonization unless ≥2 branches collide; even then, single planner. The duel is overkill at Quick scale. |
| **Standard** | Opt-in via `--duel-harmonization`. Useful when a single contested file is known to be high-stakes (security-sensitive helper, hot-path performance code). |
| **Comprehensive** | When ≥3 branches collide on the same file. Three-way collisions have enough variant-matrix complexity that adversarial planning produces meaningfully different outputs. |
| **Council** | Always for every contested file with ≥2 variants. Council mode is for production-critical / security-sensitive content; the cost of a missed defensive check is too high to skip the duel. |

The trigger is recorded in `project_profile.json:harmonization_duel_threshold` at Phase 1.

> **Why these thresholds?** The duel doubles the harmonization-planner subagent cost AND adds an adjudicator. On a 7-collision Comprehensive run, that's 7 × 3 = 21 subagent invocations vs. 7 single-planner invocations. The cost is justified at Comprehensive+Council scale because the planner's decision is load-bearing for code that ships; it's wasted at Quick scale where the user is going to manually review every synthesis anyway.

---

## 3. Multi-NTM-Pane Setup (Optional Orchestration)

Wizard A and Wizard B run in separate NTM panes when NTM is available. This gives them genuinely independent reasoning contexts (different conversation history, different memory).

```bash
# Phase 7 — duel orchestration
RUN_ID="branch-rationalization-2026-05-07"
COLLIDED_FILE="src/checkout/tokenize.rs"

# Wizard A pane
ntm send "$BASENAME" --pane wizard-a --message "$(cat <<'EOF'
You are Wizard A, harmonization planner with bias: PRESERVE EVERY DEFENSIVE INTENT.

Read .worktree_branch_rationalization_workspace/harmonization/<slug>_variant_matrix.md
for src/checkout/tokenize.rs. Produce a synthesis plan that:
  1. Preserves every defensive check from every variant
  2. Layers them in entry order (cheapest first, most-restrictive last)
  3. Cites every hunk's source variant and intent
  4. Lifts every novel test from every variant

Output: .worktree_branch_rationalization_workspace/harmonization/<slug>_wizard_a.md
EOF
)"

# Wizard B pane
ntm send "$BASENAME" --pane wizard-b --message "$(cat <<'EOF'
You are Wizard B, harmonization planner with bias: MINIMIZE TOTAL SURFACE AREA.

Read .worktree_branch_rationalization_workspace/harmonization/<slug>_variant_matrix.md
for src/checkout/tokenize.rs. Produce a synthesis plan that:
  1. Identifies redundant defensive checks (multiple guards rejecting the same input class)
  2. Collapses them into helpers where it reduces line count without losing coverage
  3. Picks the strongest single refactor as the spine
  4. Notes which intents from variants are dropped and WHY they're redundant

Output: .worktree_branch_rationalization_workspace/harmonization/<slug>_wizard_b.md
EOF
)"
```

Both panes work in parallel; the orchestrator polls both outputs.

When NTM is not available, the duel runs sequentially in the main agent's session via Task subagents — slower (no parallelism) but functionally equivalent.

```python
# In-session fallback when NTM is unavailable
plan_a = task_subagent(
    prompt=WIZARD_A_PROMPT,
    inputs=variant_matrix_path,
    expected_output=f"<slug>_wizard_a.md"
)
plan_b = task_subagent(
    prompt=WIZARD_B_PROMPT,
    inputs=variant_matrix_path,
    expected_output=f"<slug>_wizard_b.md"
)
```

Both mechanisms produce identical artifacts; the only difference is wall time.

---

## 4. Adjudication

A third subagent (or the user) reads both plans + the variant matrix and produces one of four outcomes:

| Outcome | What it means | Next step |
|---|---|---|
| **Pick-A** | Wizard A's plan is correct; Wizard B's drops something important | Use Wizard A's plan as the final synthesis |
| **Pick-B** | Wizard B's plan is correct; Wizard A's preserves redundancy | Use Wizard B's plan as the final synthesis |
| **Pick-best-of-each** | Different parts of each plan are correct; merge into a third synthesis | The adjudicator emits the merged plan |
| **Reject-both** | Both plans miss something material; surface to user | Re-spawn wizards with adjusted bias OR escalate to user |

The adjudicator is a separate subagent with NO bias — its system prompt explicitly says "you are not Wizard A and not Wizard B; you are reviewing both plans for correctness against the variant matrix and the project's stated goals."

```bash
# Adjudicator pane (Council mode) or in-session subagent
prompt=$(cat <<'EOF'
You are the harmonization adjudicator. Read:
  - The variant matrix at <slug>_variant_matrix.md
  - Plan A from Wizard A at <slug>_wizard_a.md (bias: preserve defensive intent)
  - Plan B from Wizard B at <slug>_wizard_b.md (bias: minimize surface area)

Produce <slug>_adjudication.md with:
  1. A side-by-side comparison of the two plans for each contested hunk
  2. A verdict for each hunk: A / B / merged / surface-to-user
  3. The final synthesized plan, citing which wizard each piece came from
  4. A confidence score 0.0–1.0 for the overall synthesis
  5. Surface-to-user notes for any hunk where you can't confidently choose

The user reviews <slug>_adjudication.md before Phase 8 mutates anything.
EOF
)
```

The adjudicator's output is the final harmonization plan for that file. The skill writes `harmonization_plan_duel.md` as the *combined* artifact (variant matrix + Plan A + Plan B + adjudication + final synthesis), one section per contested file.

---

## 5. Output Artifact: `harmonization_plan_duel.md`

The duel produces one section per contested file. Layout:

```markdown
# Harmonization Plan — Duel Edition

## File: src/checkout/tokenize.rs

### Variant matrix
[full table from Phase 7's <slug>_variant_matrix.md]

### Wizard A's plan (bias: preserve defensive intent)
[full synthesis description + proposed changes]
Conf: 0.86

### Wizard B's plan (bias: minimize surface area)
[full synthesis description + proposed changes]
Conf: 0.82

### Adjudication
For hunk 1 (defensive null-check at fn entry):
  Wizard A: keep all 3 variants' guards (one per network)
  Wizard B: collapse into validate_card_network() helper
  Verdict: A — the per-network guards have different error codes; collapsing loses
           the per-network observability the production debugging team relies on.

For hunk 2 (length cap):
  Wizard A: 4096-byte cap (from feature/length-cap)
  Wizard B: 1024-byte cap (from feature/length-cap-tighter)
  Verdict: B — feature/length-cap-tighter is newer and the tighter bound is justified
           by the upstream tokenizer's actual maximum (1024); 4096 was speculative.

For hunk 3 (refactor: route() → match):
  Both wizards agree on the match-arm structure.
  Verdict: consensus — adopt without contention.

### Final synthesis
[the picked-of-each plan, in the same format as Phase 7's standard harmonization_plan.md
 entries, with explicit attribution per hunk]

Overall confidence: 0.84
Surface-to-user items: none

## File: src/db/connection.rs
[next section, same structure]

## File: src/util/log.rs
[next section]
```

The user reviews `harmonization_plan_duel.md` before Phase 8 just like they would the standard `harmonization_plan.md`. The "verbatim authorization" gate applies.

---

## 6. When the Duel Converges

Sometimes Wizard A and Wizard B independently produce **highly similar** plans. This is not a failure — it's a high-confidence signal.

**Convergence criteria.**

- Same set of variants adopted vs. dropped.
- Same composition order for defensive checks.
- Same refactor spine.
- Same novel-test set lifted.
- Differences only in commit-message phrasing or trivial code-style.

When the diff between Plan A and Plan B is < 5 lines (across the entire synthesis), the adjudicator emits:

```
Convergence detected (diff < 5 lines).
Verdict: high-confidence; either plan is acceptable. Defaulting to Plan A.
Conf: 0.95
```

**Why convergence is informative.** Two independently-biased planners reaching the same conclusion is strong evidence that the variant matrix is *unambiguous* — there's a clear correct synthesis. Pick-A becomes the default; the user can override.

---

## 7. When the Duel Diverges Substantially

The opposite case: Plan A and Plan B differ in fundamental ways.

**Divergence criteria.**

- Different variants adopted (Plan A keeps `feature/redact-secrets`; Plan B drops it as redundant).
- Different refactor spine (Plan A picks the older refactor; Plan B picks the newer one).
- Different intent classification on the same hunk (Plan A: `defensive`; Plan B: `refactor`).

When the diff is large, the adjudicator emits:

```
Divergence detected: plans differ on N hunks (out of M contested hunks).
This is an indicator that the variant matrix has fundamental ambiguity:
  - The branches' intents may not be cleanly separable.
  - There may be a divergent-refactor that needs user resolution.

Recommendation: surface to user as `divergent-refactor` and ask for guidance
on the contested hunks. Do not auto-adjudicate.
```

The user gets a focused question: "Plan A wants X; Plan B wants Y; here's why each is plausible; pick one or describe a third synthesis."

> **Why divergence is informative.** Two independently-biased planners disagreeing fundamentally is evidence that the variant matrix is *genuinely ambiguous*. The right move is to surface, not to silently adjudicate. Per [HARMONIZATION.md § 6](HARMONIZATION.md): "When in doubt, surface to user."

---

## 8. Worked Example — Council Mode on a Payment-Tokenizer File

Project: `/srv/payments/checkout-core` (scenario D in [WORKED-EXAMPLES-EXTENDED.md](WORKED-EXAMPLES-EXTENDED.md#d-production-critical--council-mode--80-branches-payment-codebase)). The file `src/checkout/tokenize.rs` is touched by 7 branches; Council mode triggers the duel.

### 8.1 Variant matrix (excerpt)

```
file: src/checkout/tokenize.rs (Council)

variant                              | hunks                                               | intent           | conf
-------------------------------------|-----------------------------------------------------|------------------|-----
canonical                            | (baseline; tokenize() at line 142)                  | base             | —
feat/visa-bin-redaction              | + Visa BIN-range stripping                          | defensive        | 0.91
feat/mastercard-bin-redaction        | + MC BIN-range stripping                            | defensive        | 0.91
feat/amex-bin-redaction              | + Amex BIN-range stripping                          | defensive        | 0.92
feat/length-cap-4096                 | + cap to 4096 bytes                                 | defensive        | 0.85
feat/length-cap-1024-tighter         | + cap to 1024 bytes (newer; tighter)                | defensive        | 0.93
feat/luhn-prevalidation              | + Luhn check before tokenizer call                  | defensive        | 0.94
feat/match-arm-refactor              | refactor: switch route() → match                    | refactor         | 0.88
```

### 8.2 Wizard A's plan (preserve every defensive intent)

```
Synthesis approach: layer all defensive checks at fn entry; preserve per-network observability.

fn tokenize(input: &[u8]) -> Result<Token, TokenizeError> {
    // Defensive layer (composed from 7 branches)
    if input.is_empty() { return Err(TokenizeError::Empty); }
    if input.len() > 4096 { return Err(TokenizeError::TooLong); }   // from feat/length-cap-4096

    // Per-network BIN-range stripping (preserves per-network error codes)
    if is_visa_bin(input) { return Err(TokenizeError::VisaBinRefused); }     // from feat/visa-bin-redaction
    if is_mc_bin(input) { return Err(TokenizeError::McBinRefused); }         // from feat/mastercard-bin-redaction
    if is_amex_bin(input) { return Err(TokenizeError::AmexBinRefused); }     // from feat/amex-bin-redaction

    // Luhn prevalidation
    if !luhn_check(input) { return Err(TokenizeError::InvalidLuhn); }        // from feat/luhn-prevalidation

    // Refactored body
    match route_card(input) {                                                // from feat/match-arm-refactor
        CardRoute::Visa(buf) => tokenize_visa(buf),
        CardRoute::Mastercard(buf) => tokenize_mc(buf),
        ...
    }
}

Tests lifted: 7 (one new test per defensive variant + 1 from refactor variant)
Conf: 0.86
```

Note Wizard A picked `length-cap-4096`, not the tighter `length-cap-1024`. Its bias is to preserve all defensive intent; it picks the looser cap because it's a "less restrictive default" guard that doesn't reject legitimate inputs.

### 8.3 Wizard B's plan (minimize surface area)

```
Synthesis approach: collapse the 3 BIN-range guards into one helper; pick tighter length-cap.

fn tokenize(input: &[u8]) -> Result<Token, TokenizeError> {
    if input.is_empty() { return Err(TokenizeError::Empty); }
    if input.len() > 1024 { return Err(TokenizeError::TooLong); }   // from feat/length-cap-1024-tighter (newer)

    // Collapsed BIN-range check
    if let Some(network) = detect_unrefused_network_bin(input) {
        return Err(TokenizeError::BinRefused(network));
    }

    if !luhn_check(input) { return Err(TokenizeError::InvalidLuhn); }

    match route_card(input) {
        CardRoute::Visa(buf) => tokenize_visa(buf),
        CardRoute::Mastercard(buf) => tokenize_mc(buf),
        ...
    }
}

Helpers introduced:
  - detect_unrefused_network_bin(input: &[u8]) -> Option<Network>
    (consolidates is_visa_bin + is_mc_bin + is_amex_bin)

Tests lifted: 5 (the 3 per-network BIN tests collapsed into 1 parameterized test;
              the 2 length-cap variants merged; the Luhn + refactor tests preserved)
Conf: 0.82
```

### 8.4 Adjudication

```
For hunk 1 (length cap):
  Wizard A: 4096
  Wizard B: 1024
  Verdict: B — feat/length-cap-1024-tighter is newer (cherry SHA timestamp 2026-04-22 vs.
           4096's 2026-03-10); the tighter bound is justified by the upstream tokenizer's
           actual maximum (1024 per spec); the looser bound was speculative.

For hunk 2 (BIN-range guards):
  Wizard A: keep all 3 (per-network error codes preserved for observability)
  Wizard B: collapse into one helper returning Network enum
  Verdict: MERGED — collapse the implementation into the helper (B), but preserve the
           per-network error variants in the Result (A's observability concern). The
           helper returns Option<Network>; the call site emits the per-network error.

For hunk 3 (Luhn): consensus — adopt as A and B both proposed.

For hunk 4 (refactor spine): consensus — match-arm refactor.

For hunk 5 (test consolidation):
  Wizard A: 7 tests preserved verbatim
  Wizard B: 5 tests after consolidation
  Verdict: A — the 3 per-network tests have different fixture sets (Visa BINs vs. MC vs.
           Amex); a parameterized test would obscure the per-network fixture coverage.
           Better to preserve all 7.

Final synthesis:
  fn tokenize(input: &[u8]) -> Result<Token, TokenizeError> {
      if input.is_empty() { return Err(TokenizeError::Empty); }
      if input.len() > 1024 { return Err(TokenizeError::TooLong); }    // B's tighter cap

      if let Some(network) = detect_card_bin(input) {                  // B's helper structure
          return Err(match network {                                   // A's per-network errors
              Network::Visa => TokenizeError::VisaBinRefused,
              Network::Mastercard => TokenizeError::McBinRefused,
              Network::Amex => TokenizeError::AmexBinRefused,
          });
      }

      if !luhn_check(input) { return Err(TokenizeError::InvalidLuhn); }

      match route_card(input) {
          CardRoute::Visa(buf) => tokenize_visa(buf),
          ...
      }
  }

Tests lifted: 7 (per A — preserve per-network fixtures)
Helper introduced: detect_card_bin (per B — single-helper structure)
Confidence: 0.91 (high — adjudication clearly favored specific picks per hunk)
Surface-to-user items: none
```

The user reviews; agrees; approves. Phase 8 lands the harmonized synthesis with this exact structure.

---

## 9. Cost-Benefit

| Aspect | Single-planner | Duel |
|---|---|---|
| Subagent invocations per contested file | 1 | 3 (A + B + adjudicator) |
| Wall time (sequential) | ~5–10 min | ~15–30 min |
| Wall time (parallel via NTM) | ~5–10 min | ~10–15 min (A and B parallel; adjudicator after) |
| Confidence on contested hunks | medium-high | high |
| Probability of missed defensive check | non-zero | very low (A's bias makes this their job) |
| Probability of preserving redundancy | non-zero | very low (B's bias makes this their job) |
| Audit-trail richness | one plan, one author | three plans, three authors, one adjudication |

The duel is justified at Council scale (production-critical content) and at Comprehensive scale on files with ≥3 colliders. Outside those, single-planner is sufficient.

---

## 10. Failure Modes Specific to the Duel

| Failure | Detection | Recovery |
|---|---|---|
| Wizard A and Wizard B produce identical plans (no divergence) | Adjudicator notices; flags convergence | High-confidence outcome; proceed with either |
| Wizard A produces an empty plan (system-prompt confusion) | Plan A is missing or 0 bytes | Re-spawn Wizard A with corrected prompt; if still empty, fall back to single-planner |
| Adjudicator returns "reject-both" twice in a row | The variant matrix is genuinely unsolvable by automated planning | Surface to user with the matrix; ask for direct guidance |
| Wizard B's helper introduces a new symbol that collides with canonical | Phase 8 apply-check fails | Surface to user; the duel's adjudication picked B's helper but it doesn't fit; pick A's plan instead |
| The adjudicator picks "merged" but the merge produces invalid syntax | Phase 8 apply-check fails | Surface to user; ask for direct manual synthesis |

For most failures, the recovery is "fall back to single-planner" or "surface to user" — both safe defaults; the duel never leaves the variant matrix in a state where the apply can't be retried.

---

## 11. Integration with Multi-Model Triangulation

When both `/dueling-idea-wizards` and `/multi-model-triangulation` are available (Council mode), they layer:

```
┌──────────────────────────────────────────────────────────────┐
│  Variant matrix (per contested file)                         │
└─────────────────────────┬────────────────────────────────────┘
                          ▼
        ┌────────────────────────────────┐
        │ Multi-model triangulation pass │   Claude + Codex + Gemini
        │ (reaches consensus on the      │   each propose a single plan;
        │  variant matrix's row labels)  │   merge labels via majority
        └─────────────┬──────────────────┘
                      ▼
        ┌────────────────────────────────┐
        │ Dueling-idea-wizards pass       │   Wizard A vs Wizard B
        │ (on the consensus matrix)       │   on the agreed-on rows
        └─────────────┬──────────────────┘
                      ▼
        ┌────────────────────────────────┐
        │ Adjudicator                     │
        │ (picks A / B / merged / reject) │
        └─────────────┬──────────────────┘
                      ▼
                Final synthesis
                → harmonization_plan_duel.md
                → user review
                → Phase 8 apply
```

Triangulation reaches consensus *on the matrix labels* (which intent each hunk has, which variants are redundant); the duel runs *on top of that consensus* to produce competing syntheses. The adjudicator picks between syntheses, not between matrix labels (those are already decided).

This separation keeps the duel focused on the hard part (composition strategy) and the triangulation focused on its hard part (intent classification).

---

## 12. When NOT to Duel

| Situation | Reason |
|---|---|
| Quick mode | The user is going to review every synthesis manually; the duel adds cost without value |
| File has only 1 non-protected variant | Nothing to harmonize; the duel has no input |
| File has 2 variants that are both clearly the same intent (e.g., 2 defensive null-checks) | A single planner trivially composes them; the duel's adversarial bias is wasted |
| The user explicitly says "don't duel; trust the planner" | User authority overrides the threshold |
| Phase 8 has already applied a partial synthesis and we're resuming | The partial state may be incompatible with a re-dueled plan; finish the existing plan first |

---

## 13. Cross-References

- The `/dueling-idea-wizards` skill: [../../dueling-idea-wizards/SKILL.md](../../dueling-idea-wizards/SKILL.md)
- Harmonization methodology: [HARMONIZATION.md](HARMONIZATION.md)
- Multi-model triangulation: [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md)
- Modes of reasoning (which stance applies to which phase): [MODES-OF-REASONING.md](MODES-OF-REASONING.md)
- Council-mode worked example: [WORKED-EXAMPLES-EXTENDED.md scenario D](WORKED-EXAMPLES-EXTENDED.md#d-production-critical--council-mode--80-branches-payment-codebase)
- Mode tier overview: [SKILL.md "Mode Variants"](../SKILL.md#mode-variants)
- Orchestration tiers (Solo / Pair / Squad / Swarm / Council): [ORCHESTRATION.md](ORCHESTRATION.md)
