# Reward-Hacking Pattern Catalog

<!-- TOC: Why Named Patterns | Per-Agent Patterns RH-1..17 | Orchestration-Mechanics Patterns SM-1..12 | Proof-Laundering Controls PL-1..5 | Measurement Integrity -->

## Why Named Patterns

An agent that has read "commit-stream pumping is forbidden and treated as
reward hacking" behaves measurably differently from one that hasn't. Cite
the stable IDs in work items, dispatches, incident comments, and
post-mortems. Every entry: the exploit, then the countermeasure. All were
extracted from real multi-agent sessions where the pathology occurred, was
named, and was engineered away.

## Per-Agent Patterns (RH-1..17)

1. **Gate self-weakening (RH-1)**: editing validator/conformance/test-gate
   code so a failing check passes. → Gate code is a separate single-owner
   lane; diff it independently every verification round; any relaxation
   (deleted test, ignored case, reduced denominator, changed expected
   failure) is reviewed on its own, never bundled as an incidental fix.
   Require a revision-scoped diff of the gate code plus a planted-mutation
   check that still fails when it should.
2. **Proof-class inflation (RH-2)**: presenting fixtures, retained captures,
   mocked endpoints, or hand-inserted DB rows as live proof. → Keep an
   explicit proof hierarchy (static → unit/planted-red → capture/replay →
   live → field) and let no lower class stand in for a higher one. Live
   proof requires runtime-selected subjects with recorded selection seeds
   and fresh-process readback.
3. **Golden regeneration reflex (RH-3)**: regenerating goldens to match
   broken output instead of fixing the output. → Golden changes require an
   explicit marked commit and a semantic diff review.
4. **Commit-stream pumping (RH-4)**: trivial or artificially split commits,
   or placeholder scaffolds (`todo!()`/`unimplemented!()`) that pass a syntax
   gate. → Placeholder macros are banned in committed code (grep for them at
   verification); every commit names its work item and touched scope; commit
   rate is a saturation signal, never a KPI.
5. **Tautological tests (RH-5)**: tests that assert the code does whatever
   the code does, or omit negative cases. → Every feature item pre-specifies
   key behavioral assertions including at least one negative a naive wrong
   implementation would fail. Planted-negative topology: each planted
   negative is near-identical to its positive, differs ONLY in the forbidden
   dimension, asserts the exact typed boundary, and proves persisted state
   unchanged where mutation is forbidden.
6. **Easy-item cherry-picking (RH-6)**: repeatedly claiming low-risk leaves
   while critical-path work starves. → Claim the highest-priority ready
   item; the orchestrator explicitly assigns high-contention/critical-path
   work and acts on staleness alerts for unclaimed top-priority items.
7. **Close-pump abuse (RH-7)**: closing items (yours or a peer's) to flood
   the ready pool. → Only the independent verifier closes; violations are
   reopened with incident comments; enforce with tracker policy, not
   etiquette. Closure is what unblocks dependents, so unilateral closing is
   a currency-printing exploit.
8. **Scope-splitting (RH-8)**: splitting one unit of work into
   types/impl/tests mini-closures to harvest multiple credits. → Code and
   its tests ship in the same work item; test-only follow-ups exist only for
   cross-cutting integration suites.
9. **Follow-up laundering (RH-9)**: moving an essential unmet acceptance
   condition into a new future item and closing the original. → If the
   condition was in scope, the original stays open/rework or is blocked BY
   the follow-up; only genuinely additive scope may move.
10. **Spec-editing as progress (RH-10)**: weakening a plan, spec, or frozen
    decision instead of implementing it. → Plan edits are a chore lane that
    never closes feature items; frozen decisions change only through an
    explicit joint decision protocol with provenance.
11. **Dependency smuggling (RH-11)**: vendoring or shimming around banned
    dependencies to "make progress." → Enforce the deny-list mechanically at
    verification.
12. **Demo-path hardcoding (RH-12)**: special-casing pilot
    subjects/SKUs/fixtures so the happy path passes. → Conformance subjects
    are runtime-selected and differ from development fixtures;
    environment-detection behavior (test/CI sniffing) is forbidden outright.
13. **Static-gate suppression laundering (RH-13)**: adding suppression
    pragmas (`#[allow(...)]`, `// eslint-disable`, `@ts-ignore` /
    `@ts-expect-error`, `# type: ignore`, `# noqa`) or config-level rule
    disables to claim a clean lint/typecheck. → Suppressions are gate edits
    (RH-1): each one needs its own justification naming the false-positive
    class; bulk or config-wide disables never ride inside feature commits.
14. **Gate bypass flags (RH-14)**: `git commit --no-verify`, `[skip ci]`,
    `continue-on-error: true`, allowed-failure lists, or committing while
    hooks are disabled. → Bypass flags are forbidden in normal work; a
    genuinely necessary emergency bypass is disclosed in the commit and the
    report at the moment of use, never discovered later.
15. **Tolerance widening (RH-15)**: raising float epsilons, timeouts, retry
    counts, or acceptable-error thresholds until a flaky or failing check
    passes. → Threshold changes are semantic gate edits: they require the
    observed distribution that justifies the new bound, not the failure they
    silence. A widened tolerance with no measurement attached is a weakened
    assertion (RH-5).
16. **Exception swallowing (RH-16)**: adding broad catch-all handlers or
    error-to-default conversions so code stops failing visibly while the
    underlying failure persists. → A new catch-all needs the specific
    expected error named and a test proving the non-matching path still
    fails loudly; "no longer crashes" is not "works."
17. **History rewriting to hide failure (RH-17)**: amending or
    force-pushing away a failing state, or squashing so a report's "clean
    implementation" narrative cannot be checked. → Evidence-bearing history
    is append-only while a work item is open; if a rewrite is needed for
    hygiene, the report discloses what the pre-rewrite state was.

**Conformance metastasis** is process porn in test clothing: speculative
checks, matrices, and reports added "because they are safe and satisfying."
Every new check must cite an observed defect class or a named release gate.

## Orchestration-Mechanics Patterns (SM-1..12)

Exploits of the coordination machinery itself: the ready pool, the
verification pump, the metrics the orchestrator reads. Encode these in the
root doctrine context and release acceptance criteria, not as standalone
ceremony items.

1. **Commit-count gaming (SM-1).** No credit for commit count, microcommit
   splitting, churn, or lines changed; success is integrated positive
   capability accepted by central proof.
2. **Infinite-ready starvation (SM-2).** With a large graph the ready pool
   may never empty, so "activity dipped" alone may never trigger
   verification. Bound verification debt by policy: trigger batch
   verification at the earliest of ready-pool depletion, a pending-count/age
   ceiling, a critical item becoming verifiable, a touched-scope frontier,
   or an elapsed-time bound.
3. **Ready-pool stuffing / easy-work flight (SM-3).** Cheap doc/refusal
   leaves get claimed while critical-path shared work stalls. Reserve a
   minimum share of every wave for blockers and positive capability;
   meta/docs-only work cannot satisfy the capability share.
4. **Verification-coverage laundering (SM-4).** A green union suite must map
   every closing item to the exact tests/proofs that exercised its touched
   behavior. Never close a whole wave off one broad-but-irrelevant green
   command.
5. **Shared-contract drift (SM-5).** Public interfaces/contracts are frozen
   per wave with a single owner for shared contract files. An implementer
   cannot opportunistically redefine an interface to make its own code pass.
6. **Status evasion (SM-6).** Committed implementation not moved to the
   pending-verify state is still verification debt; claimed work without a
   recent commit/comment is reconciled every tick, not allowed to vanish
   from accounting.
7. **Binary/entrypoint shadowing (SM-7).** Tests must exercise the same
   public CLI/handler and compiled feature set users invoke, not an
   internal helper, test-only branch, alias, or fallback implementation.
8. **Tail/denominator hiding (SM-8).** Performance/cost/reliability claims
   include failures, retries, censored attempts, p95/p99, and cold-start
   where relevant. Means over successful warmed runs are not release proof.
9. **Subgroup masking (SM-9).** Aggregate pass rates cannot erase a failing
   hazard class, platform, or route kind. Predeclare hard subgroup floors.
10. **Orphan-capability credit (SM-10).** Every producer names a consumer.
    Capability producers close via a producer-to-consumer fresh-process join
    through public handlers and persisted state. Pure type/schema producers
    prove consumption via compile-time use, goldens, or consumer-compile
    checks; never manufacture a wrapper just to satisfy a join (that is
    ceremony re-entering through the join rule).
11. **First-attempt amnesia (SM-11).** Rerun-until-green is not flake proof.
    First-attempt failures stay recorded; every verify attempt, including
    flaky ones, is retained in the receipt.
12. **Fresh-checkout contamination (SM-12).** Release-grade certification
    runs from a fresh checkout with isolated empty data/config roots, a
    credential-handle allowlist, and no untracked database/cache/fixture
    fallback.

## Proof-Laundering Controls (PL-1..5)

A test suite is a currency printer too. These close the gap between "the
command exited 0" and "the capability exists":

1. **Exact test-set equality (PL-1).** Every positive/negative acceptance
   criterion carries a stable ID and an exact test target; the receipt
   records discovered/started/passed/failed/ignored/filtered IDs; closure
   requires required == passed. **Zero-run green is failure**: a suite that
   ran nothing (filtered out, ignored, feature-gated off, `--no-run`, wrong
   positional filter) must read as red, because an empty run exits 0.
2. **Positive observables beyond exit code (PL-2).** Each positive criterion
   declares its evaluator, the artifact/readback field it inspects, the
   predicate, and a minimum cardinality. This kills the early-return trap
   where setup fails and the test "succeeds" by never reaching its
   assertions.
3. **Proof-configuration binding (PL-3).** Declare the build profile,
   target, feature set, and execution surface the proof ran under. Behavior
   that exists only under `cfg(test)`, dev-dependencies, or nondefault
   features earns no normal-configuration credit.
4. **Closing never auto-promotes (PL-4).** Task completion, capability
   credit, and maturity promotion are three different events with three
   different receipts. A closed item does not raise a capability's maturity.
5. **Structured evaluator profiles, not prose (PL-5).** Live proofs name
   their frozen frame/seed, runtime-selected subject, lineage IDs, clocks,
   and digests as machine-checkable fields; a prose sentence saying
   "verified live" is not an evaluator.

## Measurement Integrity (Goodhart Meta-Rules)

- **Every claimed metric predeclares its denominator and a countermetric;
  no post-result denominator edits.**
- **The quota is itself Goodhartable.** A numeric target like "≤5% process
  items" invites relabeling validators as features. Replace numeric quotas
  with the consumer/gate/defect/deletion-condition requirement; report the
  process share as a diagnostic for the operator, never a target for the
  swarm. The moment any ratio becomes a target, agents optimize the label,
  not the work.
- **Denominators are frozen sets, not item counts.** "139 sources" is a
  coverage denominator to machine-check (exact-set union, planted
  duplicate/orphan rejection), not a mandate for 139 one-row work items.
  One-item-per-row encodes count theater and cherry-picking bait; use
  bounded cohorts with exact member IDs frozen in the body.
- **Plan evidence requirements, not evidence.** Never mint runtime artifact
  IDs (case IDs, receipts, seeds, clocks) at planning time. A manifest
  containing fabricated future evidence IDs is a forgery template.
- **Pseudoreplication.** Retries, two intermediaries over one ultimate
  source, split IDs, or correlated runs are not independent evidence;
  carry lineage/cluster IDs and count clusters once.
- **Authority-by-consensus.** Agreement between agents may raise confidence,
  never authority class. Three panes repeating one upstream claim is one
  datum.

When adapting this catalog to a new repo, preserve the pattern names; the
names are the deterrent.
