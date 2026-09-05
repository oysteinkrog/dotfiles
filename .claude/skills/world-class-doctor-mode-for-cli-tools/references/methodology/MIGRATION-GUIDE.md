# Migration Guide — Existing Doctor → This Methodology

If your project already has a `doctor` / `health` / `verify` / `check` / `repair` subcommand, you don't need to start from scratch. This guide pins the steps to migrate an existing implementation to the methodology in this skill while preserving its behavior.

The skill's `upgrade` mode handles most of this automatically. This file is the manual / per-step companion for cases where you need to migrate piecewise.

---

## Migration patterns by starting state

### Pattern A — "We have `<tool> doctor` but it only diagnoses"

**Common case.** Your existing doctor reads state and reports issues; no `--fix`. Add `--fix` per the methodology.

**Steps:**
1. Run `<tool> doctor --json` against a healthy fixture; capture the schema. This becomes your `baseline/json_output_healthy.json`.
2. Compare against [CLI-SURFACE.md](CLI-SURFACE.md). Note schema differences.
3. Choose: extend the existing schema (preserve current consumers) OR break to the canonical schema (bump major contract version).
4. For each existing detector: classify by [FAILURE-ONTOLOGY.md](FAILURE-ONTOLOGY.md) kind. Identify which kinds are auto-fixable.
5. Build the `mutate()` chokepoint per [MUTATE-CHOKEPOINT.md](MUTATE-CHOKEPOINT.md).
6. Add a fixer for each auto-fixable detector. Route every write through `mutate()`.
7. Add the canonical surface (`undo`, `capabilities`, `health`, `robot-docs`).

**Effort:** ~1 week at Pair tier.

---

### Pattern B — "We have `<tool> repair` that does ad-hoc fixes"

**Common case.** Your existing tool has subcommands like `<tool> repair-db` or `<tool> recover`. Each fix is bespoke; no chokepoint, no audit log.

**Steps:**
1. Phase 0 baseline: capture each `<tool> repair-X` invocation against a corrupted fixture. What does it write? What does it leave?
2. Migrate each repair to a `mutate()`-routed fixer.
3. Combine into a unified `<tool> doctor --fix --only fm-XXX` surface. Keep `<tool> repair-X` as deprecated aliases (per [VERSIONING.md](VERSIONING.md), short-term wrappers; remove in next major).
4. Add backups + undo retroactively.

**Effort:** ~2 weeks at Pair tier (more if many repair commands).

---

### Pattern C — "We have NO doctor; we have AGENTS.md / README full of manual steps"

**This is `add` mode + `absorb-playbook`.**

**Steps:**
1. Apply skill in `add` mode.
2. Phase 1's archaeologist mines AGENTS.md / README for manual recovery steps.
3. Each step becomes a candidate FM.
4. Phase 2's repair-spec-author proposes a fixer per step.
5. Continue normally.

The output is a NEW `<tool> doctor` whose behavior matches the documented manual playbook.

---

### Pattern D — "We have a `doctor` that auto-mutates without `--fix`" (BUG)

**Critical.** Per Axiom 7 (read-only by default), this is a bug. The baseline-snapshotter detects it via hash drift.

**Steps:**
1. The first action of your migration is to STOP the auto-mutation.
2. Add `--fix` flag. Default false.
3. All current behavior moves behind the flag.
4. Existing automation (CI, hooks) needs to add `--fix` explicitly OR the mutations stop.
5. Coordinate the change: announce in CHANGELOG; bump major contract version.

This is exactly the scenario [WORKED-EXAMPLE.md](WORKED-EXAMPLE.md) starts from.

---

### Pattern E — "We have a `doctor` written in a different language than the rest of the project"

E.g., a Bash `<tool>-doctor.sh` shipped alongside a Rust `<tool>` binary.

**Decision:** rewrite OR keep separate?

- **Rewrite into the main binary** if the doctor needs to share types/state with the binary (typical for state_files subsystem). The native-language recipe applies.
- **Keep separate** if the doctor is purely external (process inspection, file mode checks). The wrapper Pattern 8 applies; recipes/other-languages.md § Bash works.

Either way, the chokepoint and contract are the same.

---

## Per-axiom migration

For each of the 24 axioms, the migration question is: does the existing doctor honor it? If not, what's the cheapest path to compliance?

| Axiom | Migration check | If non-compliant... |
|-------|-----------------|---------------------|
| 0 — Contract with future agent | Does --json output exist with stable schema? | Add --json + schema_version. |
| 1 — Detect-then-fix; chokepoint | Are detectors pure? Do all writes go through one function? | Refactor; introduce mutate(). |
| 2 — Backups before mutation | Does --fix back up before changing? | Add backup step at mutate() entry. |
| 3 — Reversible; quarantine not delete | Is there an undo? Are deletes implemented as moves? | Add undo command; replace unlink with rename-to-quarantine. |
| 4 — Idempotent | Does running --fix twice change nothing the second time? | Make detectors pure; short-circuit in fixer. |
| 5 — Crash-recoverable | Are writes atomic (temp+rename)? | Replace direct writes with atomic rename. |
| 6 — Concurrency-safe | Is there a lock? | Acquire lock at mutate() entry. |
| 7 — Read-only by default | Does bare invocation NOT mutate? | Move all writes behind --fix flag. |
| 8 — Stdout=data, stderr=progress | Does --json | jq parse without grep filtering? | Audit logger; route progress to stderr. |
| 9 — Exit-code dictionary | Are exit codes documented? | Document in capabilities --json. |
| 10 — Errors teach | Does each error name the fix? | Add remediation field to findings. |
| 11 — Reflective discovery | Does capabilities --json exist? | Generate from runtime registry. |
| 12 — Offline by default | Does it run without network? | Mark online detectors; gate on --online. |
| 13 — Append-only run artifacts | Do runs produce a .doctor/runs/<id>/ directory? | Add per-run artifact emission. |
| 14 — Bounded blast radius | Does --dry-run print the write set? | Add --dry-run support; print plan. |
| 15 — Fixtures + round-trip | Are there fixtures per FM? | Build tests/doctor_fixtures/ tree. |
| 16 — Pass after pass | Is there a methodology for evolving the doctor? | Adopt this skill. |
| 17–23 (stretch) | (See KERNEL.md) | Optional at first; required at Stage 7+. |

---

## Preserving behavior during migration

Worry: "we have users; we don't want to break their automation."

**Strategy:**

1. **Snapshot existing behavior** (Phase 0 baseline-snapshotter).
2. **Add new surface** alongside the old.
3. **Deprecate old surface** with a warning that says "use new surface; old will be removed in vN.0".
4. **Per AGENTS.md no-shims-long-term:** at vN.0 (next major), remove the old surface. No permanent shims.

Schedule:
- v0.X: existing surface only.
- v0.X+1: both surfaces; old emits deprecation warning.
- v0.Y (= next major): only new surface. Migration deadline.

Document in [CHANGELOG.md](../../CHANGELOG.md) at every step.

---

## Migrating the test suite

Existing tests for the old doctor:
- **Keep them** during the transition (per AGENTS.md no-delete).
- **Mark deprecated** with a comment.
- **Add new tests** in `tests/doctor_fixtures/<fm-id>/` per the skill's discipline.
- **At vN.0:** existing tests remain in the source tree but moved to `tests/deprecated/` (still NOT deleted). They serve as historical reference.

---

## Migrating CI

Existing CI step:
```yaml
- run: <tool> doctor --legacy
```

Migration step:
```yaml
- run: <tool> doctor --legacy   # During transition
- run: <tool> doctor health     # New shape; runs in parallel
```

After migration. The CI structure has two gates: (1) `<tool> doctor health` — the hard gate (exit 0 = healthy, exit 1+ = CI fails); (2) the scorecard regression check — runs only if the hard gate passes, with defensive `0|1` exit-code handling on its own `doctor --json` invocation in case state shifted between steps:
```yaml
- run: <tool> doctor health
- run: |
    # Use the doctor's own scorecard.json + jq for hermetic CI — `./scripts/scorecard.py`
    # lives in this skill's repo, not the target's CI workdir. See
    # subagents/integration-wirer.md § Step 2 for the canonical jq-based check.
    rc=0
    <tool> doctor --json > /tmp/run.json || rc=$?
    case "$rc" in 0|1) ;; *) exit "$rc";; esac
    run_dir=$(jq -er .run_dir /tmp/run.json)
    curr=$(jq -er '.aggregate.score // .aggregate_score // 0' "$run_dir/scorecard.json")
    prev=$(jq -er '.aggregate.score // .aggregate_score // 0' .doctor/baseline-scorecard.json)
    [ "$((prev - curr))" -le 50 ] || { echo "FAIL: regression > 50 pts"; exit 1; }
```

---

## Migrating call sites

If other tools / scripts invoke `<tool> doctor` programmatically:

1. **Audit call sites.** `git grep '<tool> doctor'` across the org.
2. **For each:** classify by what it expects.
3. **For exit-code-only consumers:** map old exit codes to new.
4. **For JSON-parsing consumers:** if schema changed, provide a translation script.
5. **Communicate the migration timeline** to those consumers' owners.

---

## When migration is unsafe

Sometimes the existing doctor is load-bearing in ways that can't be migrated cleanly:

- **Auto-mutates without --fix** AND callers depend on it. Migrating to `--fix`-required would break callers.
- **Uses a custom transport** (e.g., DBus, JSON-RPC over socket) that the methodology doesn't model.
- **Has security-critical behavior** that's been audited; any refactor invalidates the audit.

In these cases:

- Keep the existing doctor as `<tool> doctor-legacy`.
- Build the new doctor as `<tool> doctor` (fresh).
- Document both in capabilities; flag legacy as `deprecated: true`.
- Don't try to merge their state.

---

## Migrating workspaces (if you have a prior doctor's run artifacts)

Run artifacts from a prior doctor implementation may not match this methodology's schema. They're still valuable forensically.

**Strategy:**

1. Move existing artifacts to `<workspace>/legacy_runs/`. They become read-only history.
2. Start fresh `.doctor/runs/` with the new schema.
3. Optionally write a translator script (`scripts/translate-legacy-artifacts.py`) that converts old → new for trend analysis.

Per AGENTS.md no-delete, never delete the legacy artifacts.

---

## Verifying migration completeness

Run the meta-doctor on the migrated project:

```bash
{{skill}}/scripts/validate-skill.sh {{your-doctor-skill-or-spec}}
```

Or directly verify against the canonical conformance checklist in [RFC.md § Appendix A](RFC.md):

```
[ ] All required subcommands exist
[ ] All universal flags supported
[ ] Exit-code dictionary matches Section 4
[ ] diagnose --json schema matches Section 5.1
[ ] capabilities --json schema matches Section 5.2
[ ] --robot envelope matches Section 5.3
[ ] Per-run artifacts created per Section 6
[ ] mutate() chokepoint per Section 7
[ ] Reflective discovery per Section 8
[ ] --online behavior per Section 9
[ ] Versioning per Section 10
[ ] Negative-space spec per Section 11
[ ] Conformance test suite per Section 12 passes
```

When all 13 boxes are checked, your doctor is RFC-conformant.

---

## Common migration mistakes

1. **Migrating in one big bang.** Better to migrate per-axiom (or per-subsystem). Each step is independently shippable.

2. **Removing old behavior before the new is proven.** Run both in parallel for at least one release cycle.

3. **Skipping baseline snapshot.** You'll regress something subtle; the baseline catches it.

4. **Trying to merge old run artifacts with new.** Don't. Old artifacts → `legacy_runs/`. New artifacts → `.doctor/runs/`. Different schemas.

5. **Migrating without filing beads for known incomplete migrations.** Future-you forgets; bead tracker remembers.

---

## Migration plan template

```markdown
# Migration plan: <tool> doctor → world-class methodology

## Current state
- Existing surface: <one or more of: doctor / health / verify / repair / check / diagnose / fix — the 7 verbs `discover-cli.sh --probe-doctor` looks for>
- Existing schema: <link to baseline snapshot>
- Existing fixers: <count + list>

## Target state
- RFC-conformant per [RFC.md]
- All 24 axioms honored
- Aggregate score ≥ 700

## Migration phases
- [ ] Phase A: Add chokepoint + backups (axioms 1, 2)
- [ ] Phase B: Add undo (axiom 3)
- [ ] Phase C: Make idempotent + crash-safe (axioms 4, 5)
- [ ] Phase D: Add concurrency safety (axiom 6)
- [ ] Phase E: Read-only by default (axiom 7)
- [ ] Phase F: stdout/stderr discipline (axiom 8)
- [ ] Phase G: Exit codes + error pedagogy (axioms 9, 10)
- [ ] Phase H: capabilities + robot-docs (axiom 11)
- [ ] Phase I: Offline + run-artifacts (axioms 12, 13)
- [ ] Phase J: Bounded blast + fixtures (axioms 14, 15)

## Effort estimate
- ~N weeks at <tier>

## Migration deadlines
- Phase A-D: by <date> (load-bearing)
- Phase E-J: by <date> (agent-ergonomic)
- Stretch axioms: as time allows
```

---

## After migration

1. Update CHANGELOG with migration entry.
2. Document the new surface in user-facing README.
3. Communicate timeline to call-site owners.
4. Schedule the deprecation deadline for the next major.
5. Run the meta-doctor.

The methodology is the persistence (Axiom 16). After migration, the project is in the same boat as a fresh `add`-mode pass — quarterly cadence, ongoing scoring, evolving FM coverage.
