# AGENTS.md Mandate Paragraph — Drop-in Template

> Paste this paragraph (with the `<TOKEN>` substitutions filled in for your project class) into the target project's `AGENTS.md` near the top, under a `## Negative-Evidence Discipline` heading. It mandates the ledger-grep + cass-mining workflow that prevents agents from re-discovering already-rejected optimization candidates. The text below is mined verbatim from the FrankenSQLite bibles (CC.md lines 479–482 + CODEX.md §10.2 lines 1464–1472).

---

## Negative-Evidence Discipline

This project maintains three durable negative-evidence ledgers in
`docs/progress/`:

- `perf-negative-results.md` — performance ideas that were measured and rejected.
- `conformance-negative-results.md` — conformance hypotheses that were tested and refuted.
- `surface-deferrals.md` — surface features explicitly Excluded with rationale and retry-condition predicate.

> **Verbatim from the gauntlet methodology (CC.md lines 479–482):** "This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass, and add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction."

Before any agent starts a perf-affecting change, a conformance-affecting change, or a surface-affecting change, the agent MUST:

1. **Grep the relevant ledger** for the proposed hotspot, behavior, or feature. If the ledger already names this candidate, READ the rejection rationale + the load-bearing **retry-condition predicate** before proceeding. If the current evidence does not satisfy the predicate, do not proceed.

2. **Mine 60 days of `cass` session history** for the failure terms:
   - **Universal terms:** `rejected`, `reverted`, `abandoned`, `slower`, `regressed`, `didn't help`, `within noise`, `no improvement`, `failed to improve`, `rolled back`, `backed out`, `not a keep`, `keep gate`.
   - **Project-class-specific terms:** `<TOKEN_FAILURE_TERMS>` (see your project class row in [running-the-gauntlet-on-your-rust-port/references/taxonomy/PROJECT-CLASSES.md](path/to/skill/references/taxonomy/PROJECT-CLASSES.md)).

   ```bash
   for term in rejected reverted abandoned slower regressed "within noise" "keep gate"; do
     timeout 30s cass search "$term" --robot --days 60 --limit 50 --mode lexical --timeout 30000 \
       | jq '.matches[]? // .hits[]? // .results[]? | {file, line, snippet}'
   done
   ```

3. **Check recent commits** (`git log --since='60 days ago' --grep -iE 'perf|optimiz|hot.path|bench|ratchet'`) for prior closure on this candidate.

4. **If `cass` is unavailable or the ledger is reserved** (per MCP Agent Mail reservations), the agent MUST record a *blocker* entry in the ledger ("Cannot proceed — cass unavailable; recheck before next attempt") rather than silently skipping the step.

> **Verbatim from CODEX.md §10.2 lines 1464–1472:** "For major perf campaigns, agents must also mine: last 60 days of CASS session history, recent commits, perf artifacts, failed/rejected/slower/regressed terms. If CASS or the ledger is unavailable or reserved, the agent must record a blocker or patch-ready entry rather than silently skipping the step."

When closing or rejecting a candidate, the ledger entry MUST include the load-bearing **retry-condition predicate** — never "later", never "if it seems important", never "we should revisit", never "tracked elsewhere". The predicate is a concrete, falsifiable condition under which the candidate becomes worth reconsidering. The 8 acceptable predicate forms are documented in the [running-the-gauntlet-on-your-rust-port/references/methodology/RETRY-CONDITION-VOCABULARY.md](path/to/skill/references/methodology/RETRY-CONDITION-VOCABULARY.md) reference.

Examples of load-bearing predicates:
- "Retry only if a profiler attributes a clearly-above-noise share to `<specific counter>` on `<wider workload shape>`."
- "Reconsider only inside the broader `<X>` redesign (track as `<beads_id>`)."
- "Worth reconsidering when `<specific gate>` crosses `<threshold>`."
- "Not worth retrying as a standalone patch."
- "Do not retry from a cold read; use comprehensive-bench attribution instead."

A ledger entry without one of these load-bearing predicates fails the bead-graph-validator and blocks the parent bead from closing.

---

## Substitution Tokens

Before pasting, replace:

| Token | Value (per project class) |
|---|---|
| `<TOKEN_FAILURE_TERMS>` | SQL-class: `within noise, micro-lever trap, focused vs broad, MT8 attribution, ratio frontier, fused-design, DML mutation operator`<br>RESP-class: `event-loop changes, parser fast paths, allocator swaps, write coalescing, AOF batching, RDB codec changes`<br>Numerical-Python-class: `SIMD/vectorization changing dtype, view/copy shortcuts, RNG acceleration breaking bit-exact seeds`<br>ML-System-class: `kernel fusion changes, memory format changes, allocator pooling, graph capture, autograd tape shortcuts, AD shortcuts breaking higher-order gradients`<br>HTTP-Protocol-class: `extractor fast paths, parser zero-copy changes, validation schema caching, DI lifetime changes` |
| `path/to/skill` | The relative path from your repo root to wherever `running-the-gauntlet-on-your-rust-port/` lives (typically `~/.claude/skills/`). |
