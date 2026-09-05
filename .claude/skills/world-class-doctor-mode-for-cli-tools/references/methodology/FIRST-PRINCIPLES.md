# First Principles — Why Each Axiom Exists

The 24 axioms in [KERNEL.md](KERNEL.md) didn't appear by decree. Each was painfully extracted from a real failure or a near-miss. This file documents the *reasoning chain* behind each axiom: the failure that motivated it, the alternative we considered and rejected, the evidence in the corpus.

Read this when:
- A reviewer pushes back on an axiom and you need to explain why it's there.
- You're tempted to relax an axiom for a "special case" — first read here why the axiom isn't actually about that special case.
- You're proposing a new axiom and want to check if the existing 24 already cover it.

---

## Axiom 0 — A doctor is a contract with a future agent who has no context

**The failure that motivated it:** an agent invokes `<tool>`, sees a 5-line "doctor reports issues" message, and has no idea what to do next. Agent escalates. User, mid-conversation, has to context-switch.

**Why this isn't "obvious":** because tools are usually designed for humans (who have memory and patience), not agents (who have one shot and no recall). A "good" UI for humans is a bad contract for agents. The axiom forces explicit thinking about the agent reader.

**Alternative considered:** "design for agents AND humans." Rejected: a mediocre design for both is a bad design for the harder one (agents). Design for agents and the human-readable Markdown narrative comes for free as a side-output.

**Corpus citation:** Q-005 (cass discipline: stdout=data, stderr=diagnostics).

---

## Axiom 1 — Detect-then-fix; mutations flow through one chokepoint

**The failure:** a fixer in pass-N writes directly via `std::fs::write`. Pass-N+1's reviewer adds a backup invariant. The direct-write fixer doesn't get a backup. State corruption isn't recoverable.

**Why this isn't "trivial":** because in any real codebase, "small" direct writes accumulate. A single bypass invalidates every guarantee built atop the chokepoint. The validator (`scripts/validate-doctor.sh`) is what makes this enforceable.

**Alternative considered:** "make backups optional for cheap fixers." Rejected: there are no genuinely cheap fixers when the user data is the cost.

**Corpus citation:** Q-011 (br doctor's RecoveryAuditRecord pattern: every action is audit-trailed).

---

## Axiom 2 — Backup is verbatim, immediate, and witnessed before mutation

**The failure:** a fixer reformats JSON it touches "while we're here". Backup captures the pre-reformat state. Undo restores byte-for-byte to pre-fix. But the agent's downstream tools were checksumming the JSON; they see the checksum mismatch and report data corruption that doesn't exist.

**Why this isn't "obvious":** byte-identicality is more strict than logical-equivalence. A doctor can be "logically correct" yet break agents that depend on byte-stability.

**Alternative considered:** "back up canonicalized JSON." Rejected: canonicalization itself is a mutation; the user's content might have semantic information in formatting (comments, key order, whitespace).

**Corpus citation:** Q-021 (data_safety §750 anchor).

---

## Axiom 3 — Every fix has a recorded inverse; gc is the only deletion surface

**The failure:** AGENTS.md RULE 1. The user has lost too much expensive work to deletion. Every "delete" is a removable risk; every move-to-quarantine preserves the option to recover.

**Why this isn't "trivial":** because deletion sometimes seems necessary (e.g., "the lockfile must go"). For diagnose/fix/undo, the axiom says: NO. Move it. The quarantine has zero ongoing cost; the deletion has ongoing risk.

**Alternative considered:** "delete files older than N days" as an automatic fixer behavior. Rejected: defining N is intent territory; what looks like "old" might be deliberately preserved for compliance. The separate `doctor gc --before <date> --yes` command exists only when the user explicitly supplies that intent.

**Corpus citation:** Q-001 (AGENTS.md RULE 1).

---

## Axiom 4 — Run twice = run once

**The failure:** an agent retries a flaky operation. The detector caches a side-effect to disk. The retry sees the cache and skips work. State stays half-broken. User notices weeks later.

**Why this isn't "obvious":** detector purity is subtle. Every memoization is a hidden side-effect. Every "while we're here, write a log line" is a hidden side-effect. The axiom forces detector authors to be unforgiving about purity.

**Alternative considered:** "make detectors idempotent (allow side-effects but ensure they're commutative)." Rejected: weaker than purity; harder to reason about; hides bugs.

**Corpus citation:** [REGRESSION-TEST-PATTERNS.md § idempotence](../rubric/REGRESSION-TEST-PATTERNS.md).

---

## Axiom 5 — Crash mid-fix never produces torn writes

**The failure:** Mac kernel panic mid-`<tool> sync`. After reboot, `<tool>` panics on startup because state file is half-written. User googles, finds forum post, deletes state, loses work.

**Why this isn't "obvious":** because most code uses `write()` or `fs.writeFileSync()` directly. These are not atomic. Atomic writes require deliberate plumbing (temp + rename, same-FS).

**Alternative considered:** "rely on filesystem journaling." Rejected: filesystem journaling protects metadata, not data. The application is responsible for atomicity at the data layer.

**Corpus citation:** [Case 2 § "lockfile that survived a kernel panic"](CASE-STUDIES.md).

---

## Axiom 6 — Concurrent doctors serialize via the project's lock primitive

**The failure:** two agents run `<tool> doctor --fix` simultaneously (Q-009: "multiple times PER MINUTE"). Both write the same file. Result: torn write or interleaved bytes.

**Why this isn't "obvious":** in single-agent contexts, locks seem like premature optimization. In the user's multi-agent reality, they're table stakes.

**Alternative considered:** "trust agents to coordinate via Agent Mail reservations only." Rejected: belt-and-suspenders. Reservations are advisory; the doctor's lock is mandatory.

**Corpus citation:** Q-009 (concurrent-edit reality).

---

## Axiom 7 — Read-only by default

**The failure:** a user runs `<tool> doctor` (no flags) expecting just to see findings. The pre-existing doctor auto-mutates `.gitignore`. The user's `git diff` now has unexpected changes; commits them by mistake; ships a broken `.gitignore` to production.

**Why this isn't "obvious":** because some doctors do auto-fix "trivial" things "to save the user a step." The axiom rejects this entire class of design — every mutation must be opt-in.

**Alternative considered:** "auto-fix only changes that are unambiguously safe." Rejected: "unambiguously safe" is in the eye of the beholder; the user's intent is unknowable.

**Corpus citation:** Phase-0 baseline-snapshotter detected this exact violation in our worked example ([WORKED-EXAMPLE.md](WORKED-EXAMPLE.md)).

---

## Axiom 8 — Stdout = data, stderr = progress

**The failure:** an agent pipes `<tool> doctor --json | jq`. jq fails because stdout has progress lines mixed in. Agent escalates because it can't parse.

**Why this isn't "obvious":** because in human-CLI design, progress on stdout is conventional ("Loading... [============>     ] 50%"). The axiom forces a separation that humans hate but agents need.

**Alternative considered:** "use a debug flag to switch modes." Rejected: agents shouldn't have to know which flag combination produces parseable output. Default is parseable; humans use a `--pretty` flag.

**Corpus citation:** Q-005 (cass discipline).

---

## Axiom 9 — Exit codes are a documented dictionary

**The failure:** an agent's wrapper script does `if [ $? -ne 0 ]; then ABORT`. The doctor returns exit 1 for "findings present" — not an error, just informational. Wrapper aborts unnecessarily.

**Why this isn't "obvious":** because exit code 1 is conventionally "an error." We're refining: 1 = findings (informational), 4 = unsafe-refused (decision needed), 5 = lock-lost (retry-later), 64 = usage error.

**Alternative considered:** "0 = ok, anything-non-zero = problem." Rejected: agents need to distinguish problem-types without parsing JSON.

**Corpus citation:** Q-014 (caam robot exit-code dictionary).

---

## Axiom 10 — Errors teach

**The failure:** an agent sees `Error: invalid state`. Agent has no recourse; can't grep `--help` for a remediation; escalates.

**Why this isn't "obvious":** because terse errors are conventional in CLI design. The axiom rejects terseness in favor of self-explaining errors that name the next move.

**Alternative considered:** "let users RTFM." Rejected: agents don't RTFM; they read JSON. The remediation is a JSON field.

**Corpus citation:** Q-016 (dcg block-with-redirect pattern).

---

## Axiom 11 — Reflective self-description

**The failure:** an agent doesn't know which detectors exist. It runs `<tool> doctor --json` and gets findings, but doesn't know what *wasn't* checked. False sense of completeness.

**Why this isn't "obvious":** because reflection requires extra design work. The axiom forces it.

**Alternative considered:** "publish docs separately and trust agents to read them." Rejected: docs drift; reflective contract doesn't.

**Corpus citation:** Q-005 (cass capabilities --json + robot-docs).

---

## Axiom 12 — Offline by default

**The failure:** doctor runs in CI with no network. The license-check detector tries to call home. Times out. CI takes 30 seconds longer than it should. Five years of accumulated CI time wasted on doctors phoning home.

**Why this isn't "obvious":** because vendor checks feel like "free" features. They're not free; they're a tax on every offline invocation.

**Alternative considered:** "auto-detect network availability." Rejected: TCP timeouts ARE the cost. By the time you've detected "no network", the agent has waited.

**Corpus citation:** [Case 4 § "wrangler dev port collision"](CASE-STUDIES.md).

---

## Axiom 13 — Run artifacts are append-only and content-addressable

**The failure:** an agent reads `.doctor/runs/<id>/report.json`. Another agent updates it concurrently. First agent reads inconsistent JSON.

**Why this isn't "obvious":** because mutable artifacts are conventional. The axiom forces append-only + content-addressing for crash-safety AND concurrency.

**Alternative considered:** "use file locks for reads too." Rejected: append-only is simpler; locks add coordination overhead for no benefit.

---

## Axiom 14 — Bounded blast radius, disclosed in dry-run

**The failure:** an agent runs `<tool> doctor --fix`. The doctor mutates 200 files (a fixer with unbounded scope). The agent didn't expect that. Cleanup takes hours.

**Why this isn't "obvious":** because some FMs naturally span many files. The axiom forces declaration: if the doctor will touch many files, say so up front.

**Alternative considered:** "hard cap at 10 files per fixer." Rejected: too rigid. The axiom is "disclose AND bound by declared cardinality"; high-cardinality is allowed if explicit.

---

## Axiom 15 — Every fixer has a fixture; every fixture round-trips

**The failure:** pass-N+1's regression of pass-N's fixer. There's no fixture proving the original fix worked. Investigation takes a day.

**Why this isn't "obvious":** because writing fixtures is tedious. The axiom forces it. The CI gate (`tests/doctor_fixtures/run_all.sh`) is what makes this real.

**Alternative considered:** "trust manual QA per release." Rejected: doesn't scale; agents can't verify without programmatic tests.

---

## Axiom 16 — Plans atrophy on contact with reality; pass after pass

**The failure:** a doctor at version 1.0 doesn't get updated. Two years pass. The project's failure modes have evolved; the doctor catches the wrong things.

**Why this isn't "obvious":** because doctors feel "done" once shipped. The axiom forces ongoing maintenance.

**Alternative considered:** "ship once, test forever." Rejected: tests catch regressions of caught FMs; they don't surface new FMs.

---

## Stretch axioms (17–23)

These have shorter rationales — they're refinements, not foundational reversals.

### Axiom 17 — Provenance tagging

**The failure:** an agent reads a cached `last_run` field, treats it as fresh; acts. The cache was 2 weeks old. State has changed. Action is wrong.

**Why:** users of cached/derived values need to know freshness. The `live | fallback | unavailable` triple is the minimum signal.

**Corpus:** Q-007 (bv two-phase status pattern).

### Axiom 18 — Bidirectional coverage

**The failure:** a fixer is written but no fixture. Pass-N+1's regression goes unnoticed until production.

**Why:** the inverse — a fixture without a fixer — is dead code. Both directions matter; the bidirectional invariant keeps them in sync.

### Axiom 19 — Cardinality disclosed

**The failure:** a fixer's cardinality drifts from 10 paths to 200 paths without changing the contract. Agents budget assuming 10.

**Why:** disclosing is the cheapest defense. Declaring `cardinality: "high"` lets agents react.

### Axiom 20 — Closed contract

**The failure:** the doctor adds a JSON field undocumented in capabilities. An agent's parser breaks; another's silently ignores it. Inconsistent agent behavior.

**Why:** the contract IS the API. If it's not in capabilities, it doesn't exist (from the agent's view).

### Axiom 21 — Decay-aware

**The failure:** a doctor accumulates 200 detectors over 5 years. Many are dead (never fire). Health-mode budget blown.

**Why:** retire dead code. Decay-awareness is the policy that makes retirement systematic instead of ad-hoc.

### Axiom 22 — Refusal as a feature

**The failure:** users complain that "the doctor refused to fix." Yes — that's the point. Refusal is correct when state is unsafe.

**Why:** doctors that "best-effort" through unsafe states corrupt occasionally. Doctors that refuse precisely earn trust.

### Axiom 23 — Action-trail auditable

**The failure:** an agent investigates a doctor run from 6 months ago. Can't reconstruct what happened from artifacts alone — has to read source code.

**Why:** trustability requires reconstructability. The action trail IS the doctor's argument.

---

## How to propose a new axiom

If you find yourself wanting to add one:

1. Articulate the SPECIFIC failure that motivates it (date, project, citation).
2. Articulate the ALTERNATIVE you considered (and why you rejected).
3. Confirm none of the existing 24 already cover it (citing chapter and verse).
4. If 1-3 hold, propose at the next pass with an Axiom Number 24+.

The kernel grows slowly. The current set covers 99%+ of failure modes the user has experienced; the 1% margin is where new axioms come from.

---

## What axioms NOT to add

- **"Doctor must be fast."** Performance is operational ([PERFORMANCE.md](PERFORMANCE.md)), not foundational. Slow doctors are imperfect, not broken.
- **"Doctor must be in `language X`."** Language is contingent; recipes handle it.
- **"Doctor must respect `--config`."** Configuration is contingent; capabilities document it.
- **"Doctor must support multiple users."** Multi-user is a project decision; not a kernel concern.

The kernel is for invariants that hold across every project, every language, every team. Anything contingent goes in the recipes / cookbook / methodology.
