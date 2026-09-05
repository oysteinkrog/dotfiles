# PRE-EXISTING-UB-PROTOCOL.md — Triage for UB Outside Refactor Scope

The audit sometimes surfaces UB in code that was NOT in scope for refactor. This is good — finding latent bugs is valuable. But folding pre-existing UB into the refactor plan conflates "we made it worse" with "we found something old." Don't.

This file is the formal protocol.

---

## What counts as pre-existing UB

A finding is **PRE-EXISTING** iff:

1. The site exists in `git log origin/main HEAD~` before the current refactor started, AND
2. The finding's symptom can be reproduced WITHOUT any of the current refactor's changes applied.

A finding is **IN-SCOPE** iff:

1. The site was created OR modified by the current refactor, AND
2. The finding's symptom did NOT appear before the refactor's changes.

The two are mutually exclusive. Pre-existing UB stays out of the current refactor.

---

## Triage procedure (per finding)

When `verify.sh` or any per-tool script surfaces a finding:

1. **Extract the location.** `<file>:<line>`.
2. **Cross-reference with `<audit-dir>/audit/plans/*.md`.** If any plan touches the same file (and a span overlapping the finding's line range), the finding is IN-SCOPE.
3. **Otherwise, attempt isolated reproduction.**
   - Create a baseline archive snapshot: `BASELINE_DIR="<audit-dir>/baseline-repro/origin-main"; mkdir -p "$BASELINE_DIR"; git -C <project> archive origin/main | tar -x -C "$BASELINE_DIR"`.
   - Run the same tool (miri / fuzz / loom) from `"$BASELINE_DIR"`.
   - If the same finding reproduces → PRE-EXISTING.
   - If it doesn't → IN-SCOPE (something the refactor introduced).

The script `scripts/detect-pre-existing-ub.sh` automates step 2 (the heuristic check). Step 3 is manual when step 2 is ambiguous.

---

## Filing a pre-existing-ub bead

Per Phase 8 bead conversion:

```bash
br create --title "pre-existing-ub-<N>: <short summary> [NOT IN REFACTOR SCOPE]" \
          --type bug --priority 0 \
          --description "$(cat <<'EOF'
**Found in.** Phase 7 verification harness during audit on <date>.

**Verified pre-existing.** Reproduces on origin/main at commit <hash>.

**Symptom.** <Verbatim miri / fuzz / loom output, with file:line and stack trace>

**Hypothesis.** <First-principles guess at cause — but NOT the fix>

**Scope tag.** [NOT IN REFACTOR SCOPE] — explicitly out of the unsafe-exorcist refactor wave.

**Recommended next step.**
- (a) address as separate `harden-incident` mode run, OR
- (b) include in next `audit-only` pass, OR
- (c) leave for the project's normal bug-triage cycle.
EOF
)"
```

The `[NOT IN REFACTOR SCOPE]` tag is required. It signals to reviewers + future agents that this bead is outside the current refactor wave.

---

## Triage scorecard — severity × exploitability × fix-cost

When filing a pre-existing-ub bead, compute a triage score from three axes. The score maps to a bead priority and a recommended response timeline.

### Severity (S) — what UB is, on a 0–3 scale

| S | Meaning | Examples |
|---|---------|----------|
| 0 | Undefined behavior in dead code or test-only paths | UB inside `#[cfg(test)]` modules; in a binary that's never shipped |
| 1 | UB in private-API code paths only | Internal helper reachable only from other internal helpers; no `pub` reaches it |
| 2 | UB reachable from `pub` API only with unusual inputs | Provenance violation triggered only by misaligned 1-in-2^32 input |
| 3 | UB reachable from `pub` API with realistic inputs | miri reports UB on the example in the README; fuzz finds it in seconds |

### Exploitability (E) — what an attacker could do, on a 0–3 scale

| E | Meaning | Examples |
|---|---------|----------|
| 0 | Not exploitable in any realistic threat model | Process abort only; no info leak; no memory corruption |
| 1 | Exploitable for DoS only (panic / abort the process) | Wrong panic path; bounded resource leak |
| 2 | Exploitable for info-leak | Uninit memory read returned to caller; provenance leak through error message |
| 3 | Exploitable for memory corruption / RCE | Heap overflow with attacker-controlled bytes; use-after-free with attacker-controlled type |

### Fix cost (F) — what closing it takes, on a 0–3 scale (NOTE: this axis is INVERTED — lower is more expensive)

| F | Meaning | Examples |
|---|---------|----------|
| 0 | Architectural change required | Pin self-ref needs to be split across types; ABI break needed |
| 1 | Substantial refactor | Touches several modules; tests need to be rebuilt |
| 2 | Targeted patch | One file, one function, one property test |
| 3 | One-line fix | Replace `unwrap()` with bounds-check; add a missing fence |

### Score → priority + timeline

```
PRIORITY = (S × E) + (3 - F)
```

Higher = address sooner.

| Score range | Bead priority | Timeline recommendation |
|-------------|---------------|--------------------------|
| ≥ 9 | P0 | This week. Probably needs harden-incident mode. |
| 6–8 | P1 | This sprint. Address before next release. |
| 3–5 | P2 | Next audit-only pass. Schedule explicitly. |
| 0–2 | P3 | Defer to project's normal bug-triage cycle. |

### Example scoring

| Finding | S | E | F | Priority |
|---------|---|---|---|----------|
| miri reports provenance violation in `pub fn parse_packet`; one-line fix to add `.with_addr()` | 3 | 2 | 3 | P0 (9: critical + cheap) |
| loom finds rare race in private inbox shard; needs architectural split | 1 | 1 | 0 | P2 (4: low + expensive) |
| fuzz finds UB in dead binary main | 0 | 0 | 2 | P3 (1) |
| asan finds heap overflow in `pub` accessor; fuzz repros in 5s; fix is a one-liner | 3 | 3 | 3 | P0 (12: maximum critical) |

The triage scorecard goes inside the bead's body (the `Recommended next step` section) so the maintainer can see the reasoning behind the priority.

### Why this axis-decomposition

A simple "high / medium / low" obscures the trade-off the maintainer is actually making. The three-axis decomposition makes the trade-off explicit:

- A P0 high-severity-cheap-fix is obvious — close it now.
- A P2 low-severity-expensive-fix is also reasonable — defer.
- The hard case is P1: severity-high-but-expensive. The scorecard surfaces that case, which lets the maintainer make an informed call (do the architecture work now vs accept the risk until a planned refactor).

---

## What goes in `<audit-dir>/audit/synthesis/pre-existing-ub.md`

A summary index of every pre-existing-ub bead, with the audit's recommendation per finding:

```markdown
# Pre-existing UB summary

Generated during audit on <date>.

| Bead | Severity | Reproduction | Recommendation |
|------|----------|--------------|----------------|
| pre-existing-ub-1 | high (soundness-surface; provenance violation in pub fn) | `cargo +nightly miri test --test repro_ub_1` | Address ASAP via separate harden-incident run. |
| pre-existing-ub-2 | medium (off-surface; rare interleaving caught by loom) | `RUSTFLAGS="--cfg loom" cargo test loom_repro_2` | Address in next audit-only pass. |
| pre-existing-ub-3 | low (deprecated module to be removed in v2.0) | Manual repro per bead. | Leave for v2.0 removal cycle. |
```

The user reads this in Phase 10 (maintainer-empathy review) and decides each recommendation.

---

## Why the separation matters

### Reason 1 — bisection clarity

If pre-existing UB is folded silently into a refactor PR, future bisection (e.g., "when did this UB start? was it introduced by the refactor?") fails because the refactor's commit is ambiguous: did it fix the UB, introduce it, or just touch the same area?

Keeping pre-existing-ub in a separate bead/PR means `git bisect` can answer cleanly.

### Reason 2 — scope creep prevention

Once an agent starts "while we're here, let me also fix this related issue," scope balloons. The refactor's review takes 5× longer. The user loses confidence in what they're approving.

The bead system + `[NOT IN REFACTOR SCOPE]` tag is the friction that prevents creep.

### Reason 3 — auditability

A reviewer reading the refactor PR can trust that every change in the PR is what the plan said. Pre-existing UB in a separate bead doesn't pollute the PR's diff.

### Reason 4 — credit clarity

If pre-existing UB is folded into the refactor, the refactor's "wins" are inflated. The honest claim — "this refactor closed N (C) sites AND found M pre-existing-UB findings filed separately" — is more useful for the user's decision making.

---

## Anti-patterns

- **Silently fixing pre-existing UB in the refactor.** Don't. File the bead; fix in a separate PR.
- **Folding pre-existing UB into the audit's geiger-delta.** If the delta says "decreased by 17," and 8 of those decreases were pre-existing-UB fixes, that's misleading. Report two numbers: refactor-delta + pre-existing-ub-delta.
- **Refusing to file pre-existing-UB because "it's not our problem right now."** Yes it is — the audit found it; the audit owes the project a bead. File it; recommend deferral if appropriate.
- **Filing pre-existing-UB without reproduction steps.** A bead that says "miri flagged something somewhere" is worthless. Include the verbatim output + the exact command to reproduce.

---

## Recovery: a pre-existing-UB bead was missed

If during Phase 10 maintainer-empathy review the user spots a finding that should have been filed but wasn't:

1. File it now via `br create`.
2. Update `audit/synthesis/pre-existing-ub.md`.
3. Don't backdate; the bead's `created_at` is whenever it actually got filed.
4. Note in `REVIEWER_RESPONSES.md § Q3` that the audit missed it.

The audit improves by recording its own gaps.

---

## Acceptance signal

The protocol is followed when:

1. `scripts/detect-pre-existing-ub.sh` has been run; its output triaged.
2. Every OUT-OF-SCOPE finding has a `pre-existing-ub-N` bead.
3. `audit/synthesis/pre-existing-ub.md` exists with the summary table.
4. `audit/phase7/in-scope-findings.md` exists with the in-scope findings list.
5. No finding silently appears in a cluster's refactor PR.
6. The `AUDIT_SUMMARY.md` reports refactor-delta AND pre-existing-ub-count separately.
