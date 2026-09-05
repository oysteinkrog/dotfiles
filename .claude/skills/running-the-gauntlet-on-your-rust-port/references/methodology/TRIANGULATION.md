# TRIANGULATION — Multi-Model Fresh-Eyes for Phase 14

For Phase 14 (Fresh-Eyes Review), running the same calibrated review prompt across multiple models catches different classes of bug. A single model — even a very good one — tends to miss the same things twice. An independent model usually catches what was missed.

The prerequisite skill is [/multi-model-triangulation](../../../multi-model-triangulation/SKILL.md) (preferred). If not installed, hand-roll using the `codex`, `gemini`, and `grok` CLIs (see [SKILL-FALLBACKS.md § /multi-model-triangulation](SKILL-FALLBACKS.md)).

---

## When to triangulate

Triangulation is high-leverage but expensive. Don't apply at every phase.

| Tier | Triangulate? | Why |
|---|---|---|
| **T1** Tiny | **No** | The search space is small; single-model is sufficient. The triangulation overhead exceeds the marginal value. |
| **T2** Single-crate | **No** (optional) | Marginal value low; reserve for the final Phase 14 round if budget allows. |
| **T3** Workspace | **Yes (primary)** | Multi-crate code has enough variation that single-model blind spots become real findings. The gauntlet's tier-default target. |
| **T4** Platform | **Yes (mandatory)** | Cross-cutting changes across sub-products almost always have model-specific blind spots. Skipping triangulation at T4 is a discipline violation. |
| **T5** Multi-port family | **Yes (mandatory)** + cross-port triangulation (one model reviews findings across the family) | Family-level coordination requires multi-model consensus. |

For modes:
- `gauntlet-full`: triangulate Phase 14, every round.
- `audit-only`: no Phase 14, but triangulate the `AUDIT_REPORT.md` final pass.
- `harden-pillar`: triangulate the scoped Phase 14.
- `add-feature`: skip triangulation unless the feature touches >1 pillar.
- `incremental-rebase`: triangulate only if the rebase touches >1 crate.
- `compliance-pass`: triangulate the evidence bundle (single round).
- `red-team`: no Phase 14 in this mode.
- `migration`: triangulate Phase 14, every round.

---

## Models in the panel

The standard panel:

| Model | Strength | Typical role |
|---|---|---|
| **Claude (Opus 4.7 / Sonnet 4.6, 1M context)** | Long-context cross-file reasoning; pattern-matching against this skill's exemplar quote bank; strongest on "does this gate actually enforce its claim?" | Primary; emits Round A/B/C of [AGENT-PROMPTS.md § Phase 14](../AGENT-PROMPTS.md) |
| **Codex (GPT-5.5+ / o1)** | Strong on syntactic edge cases; comments closely on type-system corners; tends to find idiom drift (e.g., a `String::from(...)` where `&str` would suffice; an unjustified `clone()`) | Independent Round A/B/C |
| **Gemini (3.x)** | Strong on logic gaps and adversarial framing; finds "what if the input is unexpectedly empty / negative / NaN / out-of-order"; tends to find missing-edge-case bugs others miss | Independent Round C (logic + security focus) |
| **Grok (xAI)** | Pragmatic / common-sense focus; finds "this is technically correct but a real operator would never deploy it this way"; tends to flag operational ergonomics issues | Independent Round B (ops + ergonomics focus) |

You can swap in other models per the user's account access. The consensus rules below are panel-size-agnostic.

**Per-model adaptation tendency** (calibrated from multi-model triangulation patterns in adjacent skills):

- **Codex tends to find idiom drift** — Rust-specific patterns; ownership/borrow opportunities missed; over-cloning; misuse of `unwrap()` vs proper error propagation.
- **Gemini tends to find logic gaps** — case-not-handled; off-by-one; missing-edge-case; assumption-not-stated; "what about when ...".
- **Grok tends to find pragmatic issues** — operational ergonomics, deployment surprises, "this works but no one will understand it at 3am during an incident."
- **Claude tends to find architectural issues** — gate-can-be-lied-to, harness-not-self-checking, pattern-violates-axiom-K-N, missing-EngineIdentity-check.

The intent of the panel composition is to span the failure-mode space.

---

## Per-Model Verbatim Prompts

The orchestrator dispatches each prompt to the corresponding model, capturing JSON output to `<workspace>/phase14_round_<N>_<model>_<lane>.json`.

### Prompt: Harness Rust code review (Round A)

**Target:** `crates/<port>-harness/src/*.rs` — the oracle, differential V2, metamorphic, mismatch-minimizer, fault VFS, e-process, score engine, failure bundle, etc.

```
You are reviewing the Rust harness code at <WORKSPACE>/crates/<PORT>-harness/src/ for the running-the-gauntlet-on-your-rust-port skill.

Context:
- This is the harness that gates the port's release decisions.
- The kernel axioms in references/methodology/KERNEL.md (K-1..K-12) are non-negotiable. The harness must enforce them, not assume them.
- The keep-gate rules in references/methodology/KEEP-GATE-RULES.md must be enforceable by the harness, not by the reviewer.
- The 30-line scenario() template (subject vs oracle parity), the Differential V2 envelope's artifact_id contract (SHA-256 of canonical JSON excluding run_id), the EngineIdentity discriminator, the truncate_score 6-decimal-place rule, the both-error-agreement rule, the FailureBundle first_divergence_jsonptr — these are CONTRACTS.

Your job:
For each file under crates/<PORT>-harness/src/, identify:

1. **Axiom violations** — places where the code violates a K-N axiom. Cite the axiom by number.
2. **Gate-can-be-lied-to** — places where a reviewer's confidence in a gate's claim depends on something the harness doesn't check at runtime. (e.g., "the comment says NormalizedValue handles NaN, but normalize_value() returns plain string without explicit is_nan() check")
3. **Missing-EngineIdentity** — any comparator that doesn't assert Subject != Oracle.
4. **Schema-version drift** — any artifact emitter that doesn't stamp LOG_SCHEMA_VERSION or BEAD_ID.
5. **Determinism leaks** — places where the output depends on environment (timestamp, PID, host name) without being explicitly stamped as "provenance" (vs. semantic content).
6. **Floating-point comparison without ULP tolerance** (numerical-class only) or without truncate_score (cross-platform-determinism case).
7. **Counter / metric writes on hot paths** — work doubled when the counter is provably algebraically derivable from existing counters (per the algebraically-redundant-counter pattern).
8. **Mismatch classifications that should be TrueDivergence but are not** — places where a divergence is silently downgraded.

Output JSON to stdout:
{
  "model": "<your-model-id>",
  "lane": "harness-rust",
  "findings": [
    {
      "file": "<path>",
      "line": <number>,
      "severity": "critical | high | medium | low",
      "axiom_violated": "K-N or null",
      "description": "<one-paragraph>",
      "fix_proposed": "<concrete change>",
      "confidence": 0.0..1.0
    },
    ...
  ]
}

Do not paraphrase the axioms — quote them by number.

If you find no findings, return findings:[]. Do NOT fabricate findings to seem productive.

If you find a finding but are uncertain, set confidence < 0.7 and surface in description.
```

### Prompt: Contract TOML review (Round B)

**Target:** `docs/contracts/*.toml` — version contract, supported surface matrix, canonical parity contract, parity score contract.

```
You are reviewing the TOML contracts at <WORKSPACE>/docs/contracts/ for the running-the-gauntlet-on-your-rust-port skill.

Context:
- These contracts are the SOURCE OF TRUTH for what "parity" means for this port.
- A contract drift between Phase 0 (declaration) and Phase 9 (baseline) is a silent failure mode.
- The FeatureUniverse loader enforces sum(weights) == 1.0 per category.
- Every Excluded row must have a non-empty rationale AND retry_condition field.
- Version-contract must embed upstream tag + commit SHA + tarball SHA-256.

Your job:

1. **Coverage gaps** — every reference symbol from <WORKSPACE>/phase1_unified_recon.md must appear in supported_surface_matrix.toml with one of {present, partial, missing, n/a, excluded}.
2. **Weight invariant** — verify sum(weights) == 1.0 per category in parity_score_contract.toml. List any category that fails.
3. **Missing rationale** — every Excluded row that has rationale: "" or rationale: "TODO" or rationale: "later" is a contract violation.
4. **Missing retry_condition** — every Excluded row must have retry_condition referencing one of the 8 predicate forms in RETRY-CONDITION-VOCABULARY.md.
5. **Stale version pin** — verify the upstream tag/commit/tarball SHA matches what scripts/oracle-preflight-doctor.sh reports.
6. **Identity strings** — engines.subject_identity = "<port>", engines.reference_identity = "<reference>-oracle". Any deviation is K-9 (EngineIdentity) violation.
7. **PRAGMA / config drift** — for SQL-class: identical PRAGMAs between subject and reference declared in the contract; verify against actual oracle_preflight output.

Output JSON to stdout:
{
  "model": "<your-model-id>",
  "lane": "contract-toml",
  "findings": [...]
}

Same severity/confidence schema as the harness review prompt.
```

### Prompt: Ledger entry review (Round C)

**Target:** `docs/progress/perf-negative-results.md`, `conformance-negative-results.md`, `surface-deferrals.md` (the three negative-evidence ledgers).

```
You are reviewing the three negative-evidence ledgers at <WORKSPACE>/docs/progress/ for the running-the-gauntlet-on-your-rust-port skill.

Context:
- Negative evidence is a first-class output (K-3).
- Every closed entry must carry one of 8 retry-condition predicates from RETRY-CONDITION-VOCABULARY.md.
- "Later", "if it seems important", "we should revisit" are FORBIDDEN.
- Every entry must cite a concrete profiler frame / divergence class / feature ID — never a vague description.
- The verbatim preamble from CC.md lines 479-482 must appear at the top of perf-negative-results.md.

Your job:

1. **Missing predicate** — list every entry whose retry-condition field is empty, vague ("later", "TBD"), or doesn't match one of the 8 forms.
2. **Stale entries** — entries closed >90 days ago whose retry condition is "Worth reconsidering when <X>"; verify <X> hasn't happened (if it has, the entry should reopen).
3. **Duplicate entries** — entries with the same MismatchSignature or the same profiler frame should be merged.
4. **Preamble drift** — verify the verbatim CC.md lines 479-482 preamble appears at the top of perf-negative-results.md.
5. **AGENTS.md mandate paragraph** — verify the AGENTS.md mandate paragraph is in the workspace's AGENTS.md, verbatim.
6. **Missing cass-mining evidence** — entries created in the last 60 days should reference cass_findings_<run_id>.jsonl as preflight evidence; entries that don't are discipline violations.
7. **Improper severity** — TrueDivergence entries with severity:low are suspect (the 5 known mismatch classes are the only thing that should be low-severity).

Output JSON to stdout:
{
  "model": "<your-model-id>",
  "lane": "ledger-entries",
  "findings": [...]
}
```

### Prompt: Bead graph review (Round D — optional, T4+ only)

**Target:** `<target>/.beads/issues.jsonl` + the bead graph from Phase 13.

```
You are reviewing the bead graph at <TARGET>/.beads/issues.jsonl for the running-the-gauntlet-on-your-rust-port skill.

Context:
- Every remediation bead must have a test-bead dependency AND a benchmark-bead dependency AND a documentation-bead dependency.
- br dep cycles must return empty.
- bv --robot-insights | jq '(.Cycles // []) | length == 0' must pass.
- A bead cannot close with weak evidence (verification-contract enforcement matrix).

Your job:

1. **Missing dependencies** — list every remediation bead that lacks one of (test-bead | bench-bead | doc-bead) dep.
2. **Dependency cycles** — confirm br dep cycles returns empty; if not, name the cycle.
3. **Oversimplified beads** — beads where granularity > "one bead per file-level change" (e.g., one bead covering all of Phase 5).
4. **Premature ready-state** — beads in `ready` state whose dependencies are not all closed.
5. **Missing isomorphism proof reference** — every remediation bead should reference its `proof_of_isomorphism.md` in remediation/<gap-id>/.
6. **Stale beads** — beads opened >60 days ago without activity; either close or reactivate.
7. **Missing rerun command** — perf beads without `rerun.sh` in the proof pack.

Output JSON to stdout:
{
  "model": "<your-model-id>",
  "lane": "bead-graph",
  "findings": [...]
}
```

---

## Consensus Aggregation Rules

For each finding any model emits, record:

```jsonc
{
  "finding_id": "<deterministic-hash-of-(file, line, description)>",
  "models_that_flagged": ["claude", "codex", "gemini", "grok"],
  "severity": "max severity across flagging models",
  "axiom_violated": "first non-null across models",
  "fix_proposed": "first non-empty across models",
  "dissent_reason": "if any model that DID see this code did NOT flag it, optional rationale",
  "consensus": "structural | stylistic | security | unanimous"
}
```

Then apply:

| Vote category | Disposition |
|---|---|
| **Unanimous (all panel members flagged)** | Ship the fix. Assign to the corresponding subagent (e.g., bench-author for perf-pillar). |
| **Structural (≥2 models flagged AND severity ≥ high)** | **Full agreement required.** Ship the fix only if all panel members agree. Otherwise surface for human review. Structural findings have downstream impact. |
| **Stylistic (≥2 models flagged AND severity == low)** | **Simple majority.** ≥half of panel says fix → ship the fix. |
| **Security (any model flagged with severity == critical)** | **Any-flag fires.** Surface to user immediately even if 3 models disagree; security findings have asymmetric cost. |
| **1-of-N** | Flag for human review; do NOT auto-fix. Document dissent rationale. |

Special case: A finding citing an axiom violation (K-N) with even a single-model vote should be reviewed manually, since axiom violations are foundational.

---

## Disagreement Handling

When models disagree, the highest-leverage move is to **make the dissent explicit** rather than picking a winner.

Example output:

```markdown
### Finding T-37: 2/4 votes — `oracle.rs:compare()` doesn't assert EngineIdentity::Subject != EngineIdentity::Oracle

- **Claude (flagged, severity:critical, K-9 axiom)**: `oracle.rs:compare()` at line 88 calls the comparator without first asserting `subject.engine_identity() != oracle.engine_identity()`. K-9 requires this at every comparator entry. Fix: add `assert_ne!(...)` as first statement.
- **Codex (flagged, severity:critical, K-9 axiom)**: Same finding, same fix. Cites K-9 verbatim.
- **Gemini (dissented)**: The assertion is performed at the caller, not inside `compare()`. See `differential_v2.rs:run_scenario()` line 142. Adding it inside `compare()` is redundant and would mask a missing-assertion bug at a different caller.
- **Grok (dissented)**: Agrees with Gemini. Adding the assertion inside `compare()` would make `compare()` non-composable for future callers that don't go through the differential V2 path.

Disposition: **Surface for human review.** Both sides are legitimate; the architectural decision (assert at boundary vs. assert at comparator) is a project-level call. If the dissent is wrong (i.e., no caller actually asserts), Claude+Codex is correct and the fix lands. If the dissent is right, document the decision in `oracle.rs` with a `// SAFETY: EngineIdentity asserted at differential_v2.rs:run_scenario:142` comment.

Action item: assigned to <user> for verification.
```

This is more useful than "2/4 said fix; we fixed it" — Gemini and Grok's dissent might be the actual right call. The discipline is to surface the disagreement, not paper over it.

---

## Triangulation Budget per Round

Triangulation is expensive. Plan:

| Panel size | Typical wall-time per round | Typical cost per round |
|---|---|---|
| 1 (Claude only) | 10-30 min | $0-5 |
| 2 (Claude + Codex) | 20-45 min | $5-15 |
| 3 (Claude + Codex + Gemini) | 30-60 min | $10-25 |
| 4 (full panel: Claude + Codex + Gemini + Grok) | 45-90 min | $20-50 |

Reserve full-panel triangulation for:
- T4+ ports running gauntlet-full
- T5 family roll-up reviews
- High-stakes pre-release reviews
- Any round following a Phase 15 soak that surfaced a new finding

For routine T3 rounds, Claude + Codex + Gemini (3-panel) is typical.

**Budget per gauntlet run:**
- T3 `gauntlet-full`: 2-3 triangulated Phase 14 rounds → 60-180 min total.
- T4 `gauntlet-full`: 3-5 triangulated Phase 14 rounds (full panel) → 3-7 hours total.
- T5 family: 1 triangulated family-level round at the end → 90-180 min.

---

## Failure Modes

- **All models say "looks great"** → low-signal. Either the code IS great (rare on a multi-day gauntlet) or all models miss the same thing. Force a tiebreaker prompt: "Find the worst three things about this code, even if minor." A null result on the tiebreaker is the actual signal.

- **Models disagree on severity** → ship the highest severity. Conservative bias.

- **Models propose contradictory fixes** → don't ship either; surface for human resolution. Two contradictory fixes for the same finding usually means the finding is mis-scoped (either too broad or too narrow).

- **One model returns garbage / hallucinated file paths** → drop that model's output for the round; note the issue in the triangulation log. If it happens multiple rounds, drop the model from the panel for this gauntlet.

- **Triangulation consensus matches single-model output 100% of the time** → suspicious. Either the panel is too homogeneous (e.g., 3 versions of the same model family) or the prompt is over-constrained (models can only see one valid answer). Diversify the panel.

- **Triangulation finds a true positive but the fix proposed by all models is wrong** → the consensus is on the diagnosis, not the cure. Ship the diagnosis, surface the proposed-cure disagreement.

---

## Hand-rolled triangulation (no skill installed)

If `/multi-model-triangulation` is missing but you have `codex`, `gemini`, and `grok` CLIs:

```bash
ROUND=1
LANE=harness-rust

# Round A prompt
PROMPT=$(cat references/methodology/TRIANGULATION.md \
  | sed -n '/^### Prompt: Harness Rust code review/,/^### Prompt:/p' \
  | head -n -1)

# Fan out (substituting <WORKSPACE>, <PORT>)
PROMPT_SUBSTITUTED=$(echo "$PROMPT" | sed "s|<WORKSPACE>|$WORKSPACE|g; s|<PORT>|$PORT|g")

echo "$PROMPT_SUBSTITUTED" | codex --json > "$WORKSPACE/phase14_round_${ROUND}_codex_${LANE}.json"
echo "$PROMPT_SUBSTITUTED" | gemini --json > "$WORKSPACE/phase14_round_${ROUND}_gemini_${LANE}.json"
echo "$PROMPT_SUBSTITUTED" | grok --json   > "$WORKSPACE/phase14_round_${ROUND}_grok_${LANE}.json"
# Claude is the orchestrator; its findings land in $WORKSPACE/phase14_review_a_round_${ROUND}.md from the inline run

# Reconcile (you'd write this script if needed)
./scripts/triangulate-merge.sh \
  "$WORKSPACE/phase14_review_a_round_${ROUND}.md" \
  "$WORKSPACE/phase14_round_${ROUND}_codex_${LANE}.json" \
  "$WORKSPACE/phase14_round_${ROUND}_gemini_${LANE}.json" \
  "$WORKSPACE/phase14_round_${ROUND}_grok_${LANE}.json" \
  > "$WORKSPACE/phase14_triangulation_round_${ROUND}.md"
```

The reconciler parses the 4 sources and applies the consensus rules above.

---

## Triangulation log: schema

Every triangulation round emits `<workspace>/phase14_triangulation_round_<N>.md`:

```markdown
# Phase 14 Triangulation — Round <N>

## Panel
- claude: Opus 4.7 (1M context)
- codex: GPT-5.5
- gemini: 3.0
- grok: 4.0

## Lanes reviewed
- harness-rust (Round A)
- contract-toml (Round B)
- ledger-entries (Round C)
- bead-graph (Round D)

## Findings summary
| Lane | Unanimous | Structural | Stylistic | Security | 1-of-N |
|---|---|---|---|---|---|
| harness-rust | 3 | 1 | 5 | 0 | 4 |
| contract-toml | 1 | 0 | 0 | 0 | 2 |
| ledger-entries | 0 | 1 | 3 | 0 | 1 |
| bead-graph | 1 | 0 | 0 | 0 | 0 |

## Dispositions
- Shipped fixes: 9
- Surfaced for human review: 7
- Dropped (low-signal): 2

## Per-finding detail
[full table, per finding, with disposition + axiom + fix + dissent rationale]

## Cost summary
- Wall time: 47 minutes
- Model invocations: 4 panels × 4 lanes = 16 calls
- Estimated cost: $32
```

The log is read by `subagents/synthesizer.md` for the round-level cross-pillar synthesis and by `subagents/final-report-author.md` for the FINAL_GAUNTLET_REPORT.md § Phase 14 Triangulation appendix.

---

## See also

- [/multi-model-triangulation](../../../multi-model-triangulation/SKILL.md) — the helper skill.
- [PHASES.md § Phase 14](../PHASES.md) — what triangulation feeds into.
- [AGENT-PROMPTS.md § Phase 14](../AGENT-PROMPTS.md) — the three calibrated fresh-eyes prompts that Claude emits (Round A/B/C); the triangulation runs these AGAINST other models.
- [SKILL-FALLBACKS.md § /multi-model-triangulation](SKILL-FALLBACKS.md) — fallback when the skill is missing.
