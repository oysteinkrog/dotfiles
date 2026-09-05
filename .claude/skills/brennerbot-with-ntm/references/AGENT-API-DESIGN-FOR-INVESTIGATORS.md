# AGENT-API-DESIGN-FOR-INVESTIGATORS.md — Script + MO Ergonomics for Pane Consumers

<!-- TOC: Why this matters | The pane is the consumer | The 7 ergonomic principles | Script output discipline | Error message specificity | --robot mode for scripts | MO template ergonomics | Stdout vs stderr discipline | Exit-code semantics | Help text discipline | Logging vs stdout | Fail-fast vs degrade gracefully | Versioning | Composition with /agent-ergonomics-cli -->

Per `/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools`. The brennerbot scripts (`scripts/*.sh`) and marching orders (`assets/marching-orders/MO-*.md`) are CONSUMED BY agents (panes), not by humans. Their ergonomics determine whether panes can apply them reliably under tick-time pressure.

This file is the rubric for keeping that interface clean as the skill evolves.

---

## Why this matters

When a script's output is ambiguous, the consuming pane (which is a Claude/Codex/Gemini instance running through the dispatched MO) makes a guess. Sometimes the guess is right. Often it isn't, and the pane reports "I tried and got X" without knowing X is malformed.

Compounded across a session:

- Phase 4 has 3 rounds × 5 panes × 5 script invocations per pane = 75 script calls
- Each ambiguous output → ~10% chance of misinterpretation
- 75 × 0.10 = ~7.5 misinterpretations per session

That's ~7.5 unnecessary recovery cycles. The fix is upstream: make the script outputs unambiguous.

---

## The pane is the consumer

When designing or modifying a script in `scripts/` or an MO in `assets/marching-orders/`, ask:

> "If a fresh Claude Code instance ran this once, would they understand what just happened from the output alone?"

Not the operator (who has session context). The pane (who has the MO + the script's output + the artifacts directory; nothing else).

---

## The 7 ergonomic principles

1. **Stdout = data; stderr = diagnostics.** Scripts that mix them force consumers to grep.
2. **Exit codes carry meaning.** 0 = success; nonzero = consumer must read stderr.
3. **`--robot` mode = JSON output.** Predictable schema, parseable.
4. **Errors include the specific failing condition.** Not "command failed" but "X must be ≥ Y but is Z".
5. **Help text shows realistic invocations.** Copy-paste-able by panes.
6. **Validate inputs early; fail fast.** Don't half-execute and leave inconsistent state.
7. **Idempotent where possible.** A re-run shouldn't break things further.

The remainder of this file is each principle expanded with brennerbot-specific examples.

---

## Principle 1: Script output discipline

✗ **Bad:** `bootstrap-session.sh` mixes status messages and the workspace path on stdout:

```bash
$ ./scripts/bootstrap-session.sh ~/foo "what is X?"
[INFO] checking skills...
[INFO] mkdir -p workspace
[INFO] writing intake/question_of_record.md
/home/ubuntu/foo
[INFO] done
```

A pane consuming this might extract `/home/ubuntu/foo` as the answer to a question the script wasn't asked.

✓ **Good:** if a script is meant to be machine-consumed, status goes to stderr and the requested value is the only semantic stdout:

```bash
$ machine-helper --workspace ~/foo --print-workspace
WORKSPACE: /home/ubuntu/foo

# stderr (separate stream):
# [INFO] resolving workspace
# [INFO] done
```

`bootstrap-session.sh` itself is operator-facing; panes should read the generated `.brenner_workspace/phase0_scope_decision.md` and `phase0_skill_inventory.json` instead of scraping its summary text.

---

## Principle 2: Error message specificity

✗ **Bad:**

```
$ ./scripts/check-six-layer-validation.sh ./bad-workspace
[FATAL] Cannot cd to workspace: ./bad-workspace
```

A pane reading this thinks "OK, workspace doesn't exist." But it might exist and just be unreadable, or be a symlink-cycle, or have permission issues.

✓ **Good:**

```
[FATAL] Cannot cd to workspace: /abs/path/from/here/./bad-workspace
        Reason: ENOENT (no such file or directory)
        Hint: did you mean ./bad-workspace-2026? Listing ./:
          bad-workspace-2026/
          bad-workspace-prior/
```

Specific failure + the absolute path + a hint pointing toward the likely correct path.

In `--robot` mode:

```json
{
  "fatal": true,
  "code": "ENOENT",
  "message": "Cannot cd to workspace",
  "argument": "./bad-workspace",
  "resolved_to": "/abs/path/from/here/./bad-workspace",
  "siblings": ["bad-workspace-2026", "bad-workspace-prior"]
}
```

---

## Principle 3: --robot mode for scripts

Every script that's consumed by a pane (not just human-readable) should support `--robot` for JSON output:

```bash
# Human-readable (default):
$ ./scripts/convergence-check.sh --phase=4
Phase 4: kill_rate=2 (1 H refuted, 1 H deferred), add_rate=4
Status: NOT CONVERGED. 2 more rounds expected.

# Robot mode:
$ ./scripts/convergence-check.sh --robot --phase=4
{
  "phase": 4,
  "kill_rate": 2,
  "add_rate": 4,
  "status": "not_converged",
  "expected_more_rounds": 2,
  "h_refuted_this_round": ["H-002"],
  "h_deferred_this_round": ["H-005"]
}
```

The pane can `jq` the JSON to make decisions. Schema stability matters: change keys carefully (versioned breaking changes only).

---

## Principle 4: Errors include the specific failing condition

✗ **Bad:** "validation failed"
✓ **Good:** "Phase 3 invariant: ≥3 active hypotheses required; found 2 (H-001, H-003). H-002 closed at 16:23 by p2(cc) without third-alternative pairing. Per F-301, dispatch MO-03c."

The good error message:
- States the invariant
- Reports current state with specifics
- Names the failure code (F-301)
- Suggests the recovery (MO-03c)

For panes (and operators) reading this in real-time, this is actionable.

---

## Principle 5: Help text shows realistic invocations

`--help` should show:

1. The synopsis (one-line)
2. Required + optional args
3. ≥2 realistic invocations
4. Exit-code semantics

Example:

```
Usage: ./scripts/score-ev.sh <EV_ID> | --all | --check <EV_ID>

Compute composite W for EV beads from W_source/W_verification/W_independence/
W_recency/W_domain_fit per EVIDENCE-WEIGHTING-TAXONOMY.md.

Required:
  Specify exactly one of:
    <EV_ID>           Update single EV (re-score and write to bead)
    --all             Re-score every EV bead in current workspace
    --check <EV_ID>   Compute and report W without modifying

Optional:
  --workspace <path>  Override workspace path (default: current dir)
  --help|-h           Show this help

Examples:
  ./scripts/score-ev.sh EV-014                    # update EV-014
  ./scripts/score-ev.sh --all                     # re-score everything
  ./scripts/score-ev.sh --check EV-014            # report only

Exit codes:
  0  Success
  1  br update failed (see WARN on stderr)
  2  Argument error (e.g., --check without EV ID)
  3  br/jq not found (install dependencies)
```

A pane invoking this script for the first time reads the help and gets enough to use it correctly.

---

## Principle 6: Validate inputs early; fail fast

✗ **Bad:** script does `cd "$WORKSPACE"`, then `mkdir -p output`, then 3 commands later realizes the WORKSPACE was wrong path. Now there's an output dir created in the wrong place.

✓ **Good:** validate ALL inputs at script entry; only proceed when all checks pass:

```bash
# At entry:
[ -d "$WORKSPACE" ] || { echo "[FATAL] $WORKSPACE not a directory" >&2; exit 1; }
[ -w "$WORKSPACE" ] || { echo "[FATAL] $WORKSPACE not writable" >&2; exit 1; }
[ -f "$WORKSPACE/.brenner_workspace/phase0_scope_decision.md" ] \
    || { echo "[FATAL] $WORKSPACE not a brennerbot workspace" >&2; exit 1; }

# Only AFTER validation:
cd "$WORKSPACE"
mkdir -p output
# ...
```

A failed validation should leave the filesystem unchanged.

---

## Principle 7: Idempotent where possible

`bootstrap-session.sh` is the canonical example: run it 10 times, get the same workspace. Doesn't matter if it's already bootstrapped.

For scripts that aren't naturally idempotent (e.g., `br create`):

- Document explicitly: "this script is NOT idempotent"
- Consider adding a `--idempotent` flag that detects existing state
- Or wrap in a check-then-create pattern

Idempotence matters because panes sometimes retry on failure. A non-idempotent script can corrupt state on retry.

---

## MO template ergonomics

Marching orders are dispatched to panes. They're not scripts but they have similar ergonomic requirements:

### MO-1: One-line summary at top

✗ **Bad:** MO-04a-investigate.md starts with a multi-paragraph context-setting prologue.

✓ **Good:** MO starts with:
```markdown
# MO-04a-investigate.md — Per-H Phase 4 Investigation

**Phase:** 4
**Operator activated:** ✂ Exclusion-Test, 𝓛 Recode
**Parameters:** `<H_ID>`, `<SESSION_ID>`, `<INVESTIGATOR_PANE>`
```

A pane reads the first 6 lines and knows what's expected.

### MO-2: Steps numbered

Each step starts with `**Step N — <verb>.**`. Panes can find step N quickly.

### MO-3: Concrete commands, not pseudo-code

✗ **Bad:** "Use beads to file the evidence."
✓ **Good:**
```bash
ev_ref="EV-NNN"  # public ref; replace NNN before running
ev_id="$(br create "$ev_ref: <one-line claim>" \
    --type=task --labels=evidence --priority=2 \
    --slug="$ev_ref" --external-ref="$ev_ref" --silent \
    --description="$(cat <<'EOF'
<full bead schema>
EOF
)")"
printf 'Created %s as br id %s\n' "$ev_ref" "$ev_id"
```

The pane can copy-paste with placeholder substitution while preserving the
generated `br` ID for later updates.

### MO-4: Anti-patterns explicit

Each MO ends with `**Anti-patterns:**` listing 3-7 things NOT to do. Per CRITIQUE-CRAFT.md, specific examples beat abstract guidance.

### MO-5: Ship-or-Surface SLA

Each MO declares: "Ship-or-Surface SLA: within X min, [outcome] or [escalation]." This sets the pane's mental clock.

---

## Stdout vs stderr discipline (specific)

For brennerbot scripts:

```
stdout = the answer the script was asked
stderr = how the script got there (status, warnings, info)
```

Examples:

| Script | Stdout | Stderr |
|--------|--------|--------|
| `bootstrap-session.sh` | human bootstrap summary | progress messages |
| `convergence-check.sh` | verdict + numbers | reasoning |
| `score-ev.sh` (single) | `EV-NNN src=X ver=Y ind=Z rec=W dom=V → W=N (strength)` | warnings |
| `score-ev.sh --all` | per-EV scoring lines | summary line + warnings |
| `audit-bead-invariants.sh` | violation list (one per line) | progress + summary |

Pane scripting (in MOs) can rely on this:

```bash
result=$(./scripts/convergence-check.sh --robot --phase=4 2>/dev/null)
if [ "$(echo "$result" | jq -r .status)" = "converged" ]; then
    # advance to Phase 5
fi
```

---

## Exit-code semantics

Brennerbot's exit-code convention:

| Code | Meaning |
|------|---------|
| 0 | Success; consumer can proceed |
| 1 | Operation failed (logical / runtime); consumer must investigate via stderr |
| 2 | Argument error; consumer should fix invocation |
| 3 | Missing dependency (br, jq, ntm not found) |
| 5 | Validation failed (e.g., invariant violation reported on stdout) |
| Other | Reserved for script-specific errors; document in --help |

Panes can branch on exit code:

```bash
./scripts/audit-bead-invariants.sh --check=phase4_round
case $? in
    0) echo "Phase 4 invariants clean";;
    5) echo "Phase 4 has violations; see stdout";;
    *) echo "Audit script failed";;
esac
```

---

## Help text discipline

Run `script.sh --help`. Output should:

- Fit on a typical terminal (≤30 lines)
- Show synopsis line
- List all flags with one-line description
- Show 2-3 realistic examples (copy-paste-able)
- List exit codes if non-trivial

Bad: tersely "use --help for help" or no --help support.
Good: scripts/score-ev.sh's `--help` (per Principle 5 example above).

For MOs, the analogous interface is the top-of-file metadata block + the **Step 1** line. A pane reads those to orient.

---

## Logging vs stdout

Some scripts produce per-call log entries (e.g., `tick.sh` appends to `tick_history.jsonl`). Logs are FILES, not stdout/stderr.

Convention:

- Log files use `.jsonl` for append-only structured data
- Log file location is documented in --help
- Log entries are timestamped (ISO-8601 UTC)
- Log rotation isn't automatic; operator controls retention

---

## Fail-fast vs degrade gracefully

Two modes:

**Fail-fast** (most scripts): stop at first failure, exit non-zero.
- Use for: validators, audits, anything where partial success is misleading.

**Degrade gracefully** (some scripts): continue past failures, summarize at end.
- Use for: bulk operations (score-ev.sh --all), reporting tools.
- Mark in --help.

Don't mix: a script either fails fast or degrades. Mid-script behavior changes confuse panes.

---

## Versioning

When a script's output schema changes (e.g., add a new key in --robot JSON):

- Backwards-compat addition: OK to ship without version bump
- Breaking change: bump the script's version comment + announce in changelog (per `references/METHODOLOGY-EVOLUTION-LOG.md`)

Avoid breaking changes in stable scripts (bootstrap-session.sh, convergence-check.sh, etc.). For new scripts, version field in --robot output:

```json
{"version": "1.0", "phase": 4, ...}
```

---

## Audit your own scripts

Every quarter (per Phase 10 lessons), audit:

```bash
for script in scripts/*.sh; do
    echo "=== $script ==="
    "$script" --help 2>&1 | head -3
done
```

Flag scripts that:
- Don't support --help
- Have ambiguous output
- Fail with vague errors

Refactor for the 7 principles.

---

## Composition with /agent-ergonomics-cli

`/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools` covers the broader principles. This file is the brennerbot-specific application.

Specifically, /agent-ergonomics-cli's "WORKED-EXAMPLES.md" patterns apply directly:

- Command-naming consistency
- Flag-naming conventions
- Stable JSON schemas
- Error-class taxonomy

Read /agent-ergonomics-cli when designing new brennerbot scripts; back-port lessons via Phase 10.

---

## Cross-references

- [/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools](../../agent-ergonomics-and-intuitiveness-maximization-for-cli-tools/SKILL.md) — concept source
- [scripts/](../scripts/) — the scripts this rubric audits
- [assets/marching-orders/](../assets/marching-orders/) — MO-* templates this rubric audits
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — version-tracking
- [SKILL-AS-METHODOLOGY-PATTERN.md](SKILL-AS-METHODOLOGY-PATTERN.md) — meta-design context
