# UB Bead Ladder — The 5-Step Execution Pattern

When a UB remediation is converted to beads (Phase 9), the recurring structure in the user's corpus is a **5-step ladder**: audit → core fix → ancillary fix → tests → e2e + close. Each step depends on the previous via `br dep add`.

Anchor: cass Q-802 — bd-1ddv series after the bd-gsjqf series was deleted by another agent. *"Wired dependencies: .1→.2→.3→.4→.5 (with .3 also depending on .1)."* Final pass runs `bv` to confirm no cycles.

---

## The ladder

```
[remediation epic R-NNN]
  br-201 [audit]      Document the UB shape; sweep all affected sites (≣ SHAPE-SWEEP)
    │
  br-202 [core]       Implement the chosen rewrite at the originally-found site (operator ⊕ REWRITE)
    │            depends on br-201
  br-203 [ancillary]  Apply the rewrite to the other sweep-discovered sites
    │            depends on br-201 AND br-202
  br-204 [test]       Add regression tests: per-site asserts + matrix test (UB-TEST-MATRIX)
    │            depends on br-202 AND br-203
  br-205 [e2e]        End-to-end test exercising the full code path; close the epic
                 depends on br-204
```

Why this shape:
- **br-201 [audit]** is the *plan*. It documents the shape, the sweep results, the chosen remediation candidate + runners-up. Other beads depend on it because they implement what it specifies.
- **br-202 [core]** is the *originally-found-site fix*. Single-site; minimal diff.
- **br-203 [ancillary]** is the *sweep fixes*. Multi-site; same shape; parallel-implementable.
- **br-204 [test]** depends on both [core] and [ancillary] because the test must cover all fixed sites.
- **br-205 [e2e]** depends on [test] because e2e tests assume unit tests pass.

---

## Variant: matrix-test remediation

When the UB shape has known variants (UAF / dangling / wild / double-free), [test] expands into a matrix:

```
  br-204 [test]
    br-204a [unit-test-per-site] One test per site
    br-204b [matrix-test]        Adversarial matrix at zero-false-negative (see UB-TEST-MATRIX.md)
    br-204c [property-test]      Proptest covering the shape's input space
```

---

## Variant: documentation accompaniment

Phase 9 requires every remediation bead to have a docs-bead dep (per kernel invariant I5). Add:

```
  br-201 [audit]
  br-202 [core]
  br-203 [ancillary]
  br-204 [test]
  br-205 [e2e]
  br-206 [docs]   Update // SAFETY: comments at each fixed site; update # Safety doc sections
              depends on br-202 AND br-203
```

The docs bead is parallel-implementable with [test].

---

## Variant: forward-only release ladder

After Phase 9 produces the ladder, Phase 13 (run) implements; Phase 14 (land) releases. Per cass Q-501, the user's release pattern is **forward-only re-publish** (no backporting). Add release beads:

```
  br-205 [e2e]
  br-206 [docs]
  br-207 [release-prep]   Bump workspace version (per /rust-crates-publishing skill)
                      depends on br-205 AND br-206
  br-208 [release-publish] Topological re-publish: every crate in dep order, 35s sleep between
                      depends on br-207
  br-209 [release-tag]    git tag v$VERSION; push tag
                      depends on br-208
```

See [RELEASE-FORWARD-ONLY.md](RELEASE-FORWARD-ONLY.md) for the topological-publish details.

---

## The validation gates

After ladder construction, before declaring Phase 9 done:

```bash
br dep cycles                                            # exit 0, empty
bv --robot-insights | jq -e '.Cycles | length == 0'
bv --robot-insights | jq -e '[.beads[] | select(.id | test("br-2[0-9]+"))] | length >= 5'
# Optionally enforce the 5-step shape exists:
br dep tree R-NNN | grep -E 'audit|core|ancillary|test|e2e'
```

`bv` should show zero alerts. If alerts fire, polish until they don't.

---

## Naming conventions

The user uses both `bd-XXX` and `br-XXX` IDs (project-dependent). The ladder structure doesn't care about the prefix. The five tags `[audit]`, `[core]`, `[ancillary]`, `[test]`, `[e2e]` (and `[docs]`, `[release-*]`) go in the bead title for searchability:

```
br create "[audit] fix UB shape: float-mod-instead-of-int in numeric paths" \
  -t task -p 1 \
  --body "Documentation of the shape, sweep results, chosen remediation. See R-007 in phase8_remediation_plan.md."

br create "[core] apply integer modulo at VDBE sql_rem" \
  -t task -p 1 \
  --body "Implement R-007 at the originally-found site (crates/fsqlite-vdbe/src/sql_rem.rs:412). See br-201."

br dep add br-202 br-201
```

---

## When the ladder shrinks or expands

Not every UB remediation needs all 5 steps:

- **Trivial fix at one site, no sweep**: ladder shrinks to `[audit] → [core] → [test] → [e2e]` (4 beads)
- **Architectural rewrite affecting many sites**: ladder expands with sub-ladders per affected module
- **Pure documentation update (a SAFETY comment was wrong)**: ladder shrinks to `[audit] → [docs] → [test]` (3 beads)

The 5-step is the *default* shape. Document deviations in `phase9_beads_log.md`.

---

## Multi-agent execution

Once the ladder lands, agents can fan out:

```
br-201 → orchestrator's planning agent
br-202 → swarm worker A
br-203 → swarm worker B (parallel with A; same plan)
br-204 → swarm worker C (depends on A+B; sequenced)
br-205 → swarm worker D
br-206 → swarm worker E (parallel with C+D)
```

Use NTM tmux orchestration (see `/vibing-with-ntm`) or Agent Mail file reservations to coordinate. The dep graph means each worker knows what's safe to start.

---

## CVE arena artifact integration

If the remediation is CVE-grade, [test] should produce a CVE-arena artifact (see [CVE-ARENA-LAYOUT.md](CVE-ARENA-LAYOUT.md)):

```
  br-204 [test]
    br-204a [unit-test-per-site]
    br-204b [cve-arena-artifact]
        Produce tests/cve_arena/results/br-204b/<scenario>.v1.json
        Persist trace.jsonl and artifact_index.json
```

This is mandatory for the disclosure timeline (see [DISCLOSURE.md](DISCLOSURE.md)).

---

## Cross-references

- cass Q-101 (matrix-test gate), Q-802 (5-step ladder) — verbatim sources
- [PHASES.md §Phase 9](PHASES.md#phase-9-beads-handoff-parallel-write-phase) — phase spec
- [UB-TEST-MATRIX.md](UB-TEST-MATRIX.md) — matrix test variant
- [RELEASE-FORWARD-ONLY.md](RELEASE-FORWARD-ONLY.md) — release variant
- [SHAPE-SWEEP.md](SHAPE-SWEEP.md) — the audit step
