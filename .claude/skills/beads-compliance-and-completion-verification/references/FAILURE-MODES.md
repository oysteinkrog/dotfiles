# FAILURE-MODES.md — Real-World False-Closed Patterns

The patterns this skill is designed to catch. Mined from `cass` searches, `mock-code-finder` sessions, and the `multi-pass-bug-hunting` skill's accumulated war stories. Each pattern has a **trigger** (what to grep / look for), a **rubric impact** (which dimension it dings), and a **remediation hint**.

---

## Pattern 1 — `unimplemented!()` / `todo!()` in primary deliverable

**Trigger.** `rg -n "unimplemented!|todo!|panic!\(\"not implemented" <evidence-files>` over the files cited in `evidence.json#code_artifacts`.

**What it looks like.**
```rust
pub fn process(input: &Input) -> Result<Output, Err> {
    todo!("wire this up after the schema migration lands")
}
```

**Rubric impact.** `theater.json: BLOCKING`, invalidates Phase 4 PASS, zeros dimension 1.

**Remediation hint.** Either reopen the original bead OR create a completion-debt bead with the verbatim missing-items list. The original closer was almost certainly mid-flight when something distracted them.

---

## Pattern 2 — Hardcoded happy-path returns

**Trigger.** Functions that always return the same value regardless of input. Look for short function bodies (`ast-grep run -l <lang> -p 'fn $NAME($$$) -> $RET { $SINGLE_STMT }'`) where the single statement is a literal.

**What it looks like.**
```typescript
export function calculateRiskScore(transaction: Transaction): number {
  return 3;  // TODO: actually compute
}
```

```rust
pub fn verify_signature(_sig: &[u8], _msg: &[u8]) -> bool { true }
```

**Rubric impact.** `theater.json: BLOCKING` if the function is in the bead's primary deliverable; `MAJOR` if it's a side helper. The mock-code-finder skill calls these "behavioral simulations."

**Remediation hint.** Trace callers — if any caller depends on real output (e.g., risk_score is used to gate a transaction), this is BLOCKING. If nobody uses the output meaningfully, the function may be dead code; flag in synthesis.

---

## Pattern 3 — `assert true` / `expect(true).toBe(true)` test theater

**Trigger.** `rg -n "assert\s*\(?\s*true\s*\)?$|expect\(true\)\.toBe\(true\)|self\.assertTrue\(True\)" <test-files>`.

**What it looks like.**
```typescript
it('handles edge case', () => {
  expect(true).toBe(true);
});
```

```rust
#[test]
fn test_parser() {
    assert!(true);
}
```

**Rubric impact.** `theater.json: BLOCKING`, zeros the test in Phase 4 retroactively, dings dimension 2.

**Remediation hint.** This is the most insidious pattern — the test "passes" forever and lulls everyone into thinking the feature works. The completion-debt bead must require a *meaningful* assertion (one that would fail if the implementation regressed).

---

## Pattern 4 — `it.skip` / `#[ignore]` on required tests

**Trigger.** `rg -n "it\.skip|test\.skip|describe\.skip|#\[ignore\]" <evidence-files>` cross-referenced against `spec.json#tests`.

**What it looks like.**
```typescript
it.skip('should reject expired tokens', () => {
  // implementation pending
});
```

**Rubric impact.** If the spec required this test, `theater.json: BLOCKING`. Otherwise NOTE.

**Remediation hint.** A skipped test is *worse* than a missing test — it claims to exist (boosting test counts) without actually verifying anything. Phase 4 should treat SKIPPED as a hard FAIL when the test name matches a spec item.

---

## Pattern 5 — `#[cfg(not(test))]` guards that skip the real work in test mode

**Trigger.** `rg -n "if cfg!\(test\)|#\[cfg\(test\)\]|#\[cfg\(not\(test\)\)\]|process\.env\.NODE_ENV.*test" <evidence-files>` looking for branches that bypass the actual logic when running tests.

**What it looks like.**
```rust
pub fn charge_card(amount: u64) -> Result<(), Err> {
    if cfg!(test) {
        return Ok(());  // skip the real Stripe call in tests
    }
    stripe::Charge::create(...)
}
```

**Rubric impact.** `theater.json: BLOCKING` for the test in Phase 4 — the test never exercised the production path. This is "the test is a lie" pattern.

**Remediation hint.** Per `/testing-real-service-e2e-no-mocks`, replace the cfg-guard with real-service hits to the test mode endpoint (Stripe test mode counts as real). Or refactor so the test injects a real test double, not a code-path skip.

---

## Pattern 6 — Mock where the bead said no mocks

**Trigger.** When `spec.constraints.no_mocks: true`: `rg -n "Mock|jest\.mock|sinon|nock|httpmock|mockall|MagicMock" <evidence-files>`.

**What it looks like.**
```typescript
// Bead said: "verify the real Stripe webhook signature"
const stripe = jest.mock('stripe');
stripe.webhooks.constructEvent.mockReturnValue(fakeEvent);
```

**Rubric impact.** `theater.json: BLOCKING` per dimension 3.

**Remediation hint.** Use `/testing-real-service-e2e-no-mocks` to refactor to a real signature with a known test secret. Stripe test mode produces real signed webhooks.

---

## Pattern 7 — `sleep()` simulating real I/O

**Trigger.** `rg -n "sleep\(|thread::sleep|time\.sleep|setTimeout" <production-files>` (not test files; sleeps in tests are usually legitimate).

**What it looks like.**
```rust
pub async fn run_preflight() -> Result<(), Err> {
    // TODO: actually run SSH preflight
    tokio::time::sleep(Duration::from_secs(2)).await;
    Ok(())
}
```

**Rubric impact.** `theater.json: BLOCKING` per dimension 3 — production code shouldn't sleep to simulate work.

**Remediation hint.** From rch sessions: `run_preflight()` used `sleep()` to fake SSH operations. The completion-debt bead must require real SSH commands with captured output.

---

## Pattern 8 — API route returns `501 Not Implemented`

**Trigger.** `rg -n "501|Not Implemented|not.yet.implemented" <api-route-files>`.

**What it looks like.**
```typescript
export async function POST(req: Request) {
  return new Response('Not Implemented', { status: 501 });
}
```

**Rubric impact.** `theater.json: BLOCKING` if the route is in the bead's deliverable. From midas-edge sessions: `promo/validate/route.ts` returned 501 with no callers.

**Remediation hint.** Check callers (`rg <route-path>` over the codebase). If there are real callers, this is a high-priority remediation. If no callers, flag in synthesis as "dead route — was this needed?"

---

## Pattern 9 — Divergent code paths (same concept, different impl in two files)

**Trigger.** Cross-reference: search for the same constant or business rule in multiple files; if the values differ, the paths diverged.

**What it looks like.** From midas-edge: `batch-enrichment.ts` returned `redFlagsDetected: 0` (hardcoded), but the API route that consumed it actually counted red flags using a separate, real implementation. The two paths diverged silently.

**Rubric impact.** Phase 7 synthesis finding (cross-bead). The bead that produced one path may pass; the bead that produced the other may pass; but the *integration* is broken.

**Remediation hint.** Synthesis recommends consolidating to a single implementation; the completion-debt bead is "merge divergent <X> implementations and add a property test that they agree."

---

## Pattern 10 — Stub test files (test exists; assertions are sparse)

**Trigger.** `rg -c "(assert|expect|self\.assert)" <test-file>` should produce ≥ 5 for non-trivial test files. Below 5 = candidate stub.

**What it looks like.**
```python
# test_unicode.py
def test_unicode_handles_emoji():
    pass

def test_unicode_handles_combining_chars():
    pass
```

**Rubric impact.** `theater.json: MAJOR` per Phase 5; dings dimension 6 (test depth) hard.

**Remediation hint.** From mcp-agent-mail E2E audit: `null_fields` and `unicode` test files were themselves stubs (5–7 real assertions for what should have been ~30). Completion-debt: write the missing assertions per the bead's original AC.

---

## Pattern 11 — Bead body says "WIP" / "draft" but status is closed

**Trigger.** `rg -i "WIP|draft|in progress|TODO" <bead-body>` while `status == closed`.

**What it looks like.**
```
description: "WIP: implementing the parser. TODO: add fuzzer once basic flow works."
status: closed
```

**Rubric impact.** Auto-flag as false-closed regardless of score; status-body mismatch is a Phase 1 finding.

**Remediation hint.** Reopen with high priority. The closer almost certainly fat-fingered the close.

---

## Pattern 12 — Closed bead has zero git commits referencing its ID

**Trigger.** `git log --all --grep=<bead-id>` returns nothing for a closed bead.

**Rubric impact.** Strong evidence of theater. The closer didn't even bother to mention the bead in any commit. Phase 8 dimension 1 → near-zero.

**Remediation hint.** Either the work was done but the agent forgot to reference the bead (low priority — search for likely commits and confirm), or the bead was closed without any work (high priority — reopen).

---

## Pattern 13 — Tests pass because the implementation short-circuits

**Trigger.** Phase 4 says PASS; Phase 5 finds a hardcoded return / cfg-guard / `unimplemented!()` in the implementation that the test exercises. The test's "pass" is meaningless.

**What it looks like.**
```rust
fn validate_input(_: &Input) -> bool { true }   // implementation: always true

#[test]
fn test_validation_accepts_valid() {
    assert!(validate_input(&valid_input()));    // passes trivially
}
```

**Rubric impact.** Phase 5 BLOCKING; Phase 8 docks dimensions 1 AND 2; the scorer marks "passing test invalidated by theater."

**Remediation hint.** This is the hardest pattern to catch automatically — the cross-reference between Phase 4 (test passed) and Phase 5 (impl is theater) is what surfaces it. Once surfaced, completion-debt: "implement real validation + add a test that *fails* against the trivial impl."

---

## Pattern 14 — Closed bead's dependents are all open (and downstream is broken)

**Trigger.** Phase 7 synthesis: bead X is closed; every bead that depends on X is open and blocked.

**Rubric impact.** Often legitimate (X was closed, downstream just hasn't started yet). But sometimes a sign that X's actual deliverable doesn't satisfy what its dependents expected — the closed bead is technically done but useless to consumers.

**Remediation hint.** Look at one or two dependent beads' specs and check whether X's evidence satisfies them. If not, contract drift — flag in synthesis.

---

## Pattern 15 — Tombstoned dependency

**Trigger.** Phase 7 synthesis: closed bead's `dep add` lists a bead that was later tombstoned.

**Rubric impact.** The bead's "implementation" assumed a primitive that no longer exists. Likely subtle bugs. Dimension 6 docked.

**Remediation hint.** Re-verify the bead's evidence on current main; if anything broke, completion-debt.

---

## Pattern 16 — Conformance harness present but not wired to CI

**Trigger.** `evidence.json` cites a conformance harness file; `.github/workflows/` has no job that runs it.

**Rubric impact.** Per `/testing-conformance-harnesses`: the harness exists but never runs → drift creeps in unnoticed. Phase 6 FAIL on `ci_wired`.

**Remediation hint.** Completion-debt: add CI job; gate PRs on harness pass.

---

## Pattern 17 — Goldens stale or missing

**Trigger.** Per `/testing-golden-artifacts`: golden files in tree but `regenerate && git diff --exit-code` shows huge unintentional diff; OR the goldens directory is empty.

**Rubric impact.** Phase 6 FAIL on `golden_freshness`.

**Remediation hint.** Regenerate, review the diff carefully (some changes are intentional — record in synthesis), commit fresh goldens. Completion-debt: add a CI gate that catches stale goldens.

---

## Pattern 18 — Fuzzer exists; corpus is empty; never seeded

**Trigger.** `evidence.json` cites a fuzz target; `fuzz/corpus/<target>/` is empty.

**Rubric impact.** Phase 6 FAIL on `corpus_size`. The fuzzer can theoretically run, but starts from scratch every time and never accumulates interesting inputs.

**Remediation hint.** Per `/testing-fuzzing`: seed the corpus with a representative sample (10+ inputs covering all parser branches). Add a `cargo fuzz cmin` to CI to prune.

---

## Pattern 19 — Empty PR diff (closing commit touches no production code)

**Trigger.** `git -C <project> show --stat <closing-sha> | tail -1` shows zero file changes OR the diff is entirely whitespace / formatter-only.

**What it looks like.** Bead's closing commit is a "no-op" — perhaps the closer cherry-picked a placeholder commit, or rebased away the actual change. The bead is now closed but no code shipped under its name.

**Rubric impact.** Phase 8 dimension 1 → 0. This is essentially **Pattern 12 (no commits)** with one extra step: there IS a commit, but it's empty.

**Remediation hint.** Investigate `git reflog` and the agent's session for the missing change. Often the agent intended to commit a real fix but rebased/squashed it away.

---

## Pattern 20 — Batch-close anomaly (N>5 beads closed in <5 min by same session)

**Trigger.** Group `inventory.jsonl` by `closed_by_session`; if any session has > 5 beads closed within a 5-minute window, flag.

**What it looks like.** End of session, the agent rapid-fires `br close bd-A bd-B bd-C bd-D bd-E bd-F bd-G --reason "done"` to clean up the active list. None had any actual verification.

**Rubric impact.** Project-specific pattern (added via CASS_MINING.md). Each bead in the batch starts with a -50 penalty until evidence proves otherwise.

**Remediation hint.** Audit the batch carefully. The agent's intent was hygiene, not verification. Most batch-closed beads will have weak / missing evidence.

---

## Pattern 21 — Time-to-close < 5 min after creation

**Trigger.** `closed_at - created_at < 5 minutes` AND there were no prior interactions with the bead.

**What it looks like.** Bead was created and immediately closed by the same session. Either it was a placeholder for tracking, OR genuinely instant work, OR a status-flip without intent.

**Rubric impact.** Per-bead context: trivial chores (e.g., "remove unused import") are legitimately fast. But for `feature` / `bug` beads, < 5 min implies no real work. Phase 8 dimension 1 → expect MISSING evidence.

**Remediation hint.** Cross-reference with the closing diff. If diff is non-trivial → legitimate fast work. If diff is trivial → false-close.

---

## Pattern 22 — Apologetic close reason

**Trigger.** `close_reason` matches `/(for now|will follow up|first pass|coming next|partial|temp|placeholder|good enough|ship it)/i`.

**What it looks like.** *"Closing for now to unblock CI; real fix coming in bd-XXX."* Self-disclosure that the bead isn't really done.

**Rubric impact.** Phase 1 auto-flag. Score capped at 600 regardless of evidence (the closer themselves admitted incompleteness).

**Remediation hint.** Always create a follow-up bead. The closer's "real fix coming in bd-XXX" should literally exist.

---

## Pattern 23 — Tests added to ignore list

**Trigger.** `git -C <project> log --grep=<bead-id> -p -- .ubsignore .eslintignore .gitignore` shows additions of test paths during the bead's commits.

**What it looks like.** The fix "works" because it's now exempt from being checked. Linter / scanner ignores added in the same diff as the bead's "fix".

**Rubric impact.** `theater.json: BLOCKING` per dimension 3. Adding to ignore lists IS the theater.

**Remediation hint.** Remove the ignore entries; address the underlying lint/scan issue. The completion-debt bead must include "remove `.ubsignore` entry added by bd-XXX".

---

## Pattern 24 — Force-merged PR (review bypassed)

**Trigger.** `gh pr view <num> --json reviews,mergedBy,mergeable` shows the merger == author AND zero approving reviews.

**What it looks like.** Bead's PR was self-merged without review. Common in solo-agent flows but worth flagging on team projects.

**Rubric impact.** None automatic — flag for human attention. (Solo flows legitimately self-merge.)

**Remediation hint.** Project-specific. If the project's policy requires review, this is a process violation; record in the audit but don't block.

---

## Pattern 25 — Bead's "implementation" is in a different module than the spec said

**Trigger.** Spec's `expected_path_hints` doesn't intersect with any cited evidence path; the actual implementation lives somewhere else.

**What it looks like.** Bead said "implement at src/auth/oauth.ts"; the actual implementation went to `src/lib/auth.ts` (or vice versa). The bead's plan-space name doesn't match the code-space name.

**Rubric impact.** Phase 3 marks `AMBIGUOUS`; Phase 8 dimension 1 → -25%. The implementation may be correct, but the bead's location-claim was wrong.

**Remediation hint.** Either move the code to match the bead OR update the bead's path-hints to match the actual code. The completion-debt bead documents the divergence so future audits don't re-flag.

---

## Pattern 26 — Dead code added by the bead

**Trigger.** The bead's commit added a function/module; `git -C <project> log --since=<closed_at> -- <added-file>` shows zero callers; OR `rg <symbol-name> --files-with-matches` returns only the file itself (no callers anywhere).

**What it looks like.** Bead "implemented" a helper that nothing calls. Could be: planned for future use (legitimate), prematurely-extracted, or the actual production code was never wired up to consume it.

**Rubric impact.** Phase 5 NOTE if no callers; Phase 5 MAJOR if `evidence.json` cited the unused function as the bead's primary deliverable.

**Remediation hint.** Either wire the consumer (often the missing piece), or accept the bead is incomplete (closer punted the integration). Completion-debt: "wire <function> into <consumer>".

---

## Pattern 27 — Agent left a "I'm not sure" comment in code

**Trigger.** Within the bead's diff, search for: `// not sure`, `// might`, `// TODO: verify`, `// ?`, `// maybe`, `// I think`.

**What it looks like.** Agent committed code with explicit uncertainty markers. The agent themselves didn't understand the change.

**Rubric impact.** Phase 5 MAJOR. Code with self-disclosed uncertainty isn't done.

**Remediation hint.** Resolve the uncertainty (test it, ask the human, consult docs). Completion-debt should require removing the uncertainty marker.

---

## Pattern 28 — Schema changes without migration

**Trigger.** Bead's diff modifies a schema file (e.g., `schema.sql`, `schema.ts`, Prisma schema, Drizzle schema) but adds NO migration file.

**What it looks like.** Schema diverges between dev (which used `db.push`) and prod (which never got the migration). Production deploy will fail or silently corrupt.

**Rubric impact.** Phase 5 BLOCKING. Schema changes without migrations are a deployment landmine.

**Remediation hint.** Generate the missing migration; verify forward + reverse per `BEAD-TYPE-PLAYBOOKS.md` migration recipe.

---

## Pattern 29 — Migration without rollback

**Trigger.** Bead's diff adds a migration file with non-empty `up()` but empty / missing `down()`.

**What it looks like.** Forward migration works; rollback is impossible. If something goes wrong in prod, the team is stuck.

**Rubric impact.** Phase 5 MAJOR. Migration beads must have rollback unless explicitly documented as one-way.

**Remediation hint.** Implement reverse migration OR document as one-way with explicit `// IRREVERSIBLE: <reason>` comment.

---

## Pattern 30 — `closed_by_session` matches a known sloppy session

**Trigger.** Project's `rubric.md#sloppy_sessions` lists session IDs that have been observed batch-closing or status-flipping. Cross-reference each closed bead's `closed_by_session`.

**What it looks like.** A specific agent / session has been identified (via past audits or CASS mining) as a low-quality closer. Its closes are higher-risk by default.

**Rubric impact.** Project-specific pattern. Each bead closed by a sloppy session starts with a -25 penalty until evidence proves otherwise.

**Remediation hint.** Beyond the audit: have a human conversation with the agent about close-quality standards.

---

## How the scanner catches these

`scripts/theater-scan.sh` runs the rg/ast-grep patterns above over the files in `evidence.json` and emits `theater.json`. It does not scan the whole project — only the cited evidence — to keep noise low and keep findings tied to specific beads.

Patterns 19–30 also leverage **non-evidence-file** signals (git history, PR metadata, session metadata). Those are checked by `scripts/anomaly-scan.sh` (see scripts directory) which runs after theater-scan and merges its findings into `theater.json` under the same severity classification.

For new patterns: add the regex to `scripts/theater-scan.sh` (or anomaly-scan.sh for non-grep patterns), document it here with a real example, add a quote to `QUOTE-BANK.md` if you have one, and rev `rubric.md`'s version.

---

## Pattern 31 — Coverage-via-import (no assertions)

**Trigger.** Test file imports every module in the bead's surface. Coverage hits 92%+. But assertion density is < 1 assertion per 30 LoC of test code.

**What it looks like.**
```python
# tests/test_billing.py
from billing import *  # import everything; coverage will count the load
def test_smoke():
    assert True       # one trivial assertion; coverage looks great
```

**Rubric impact.** Phase 6 should require an assertion-density floor (≥ 1 non-trivial assertion per 30 LoC of test code). Falls under the "test depth" dimension.

**Remediation hint.** Add this to `scripts/theater-scan.sh` and to `audit-policy.yaml#project_theater_patterns`. Re-score affected beads.

---

## Pattern 32 — Branch coverage of dead branches

**Trigger.** Test exercises a branch guarded by an env var nobody sets in production (`if os.getenv("EXPERIMENTAL"): return early`). Coverage thinks the branch is exercised; it's actually dead code.

**Remediation hint.** Cross-reference coverage with reachability analysis. Static analyzers (e.g. `vulture`, `cargo-udeps`) help. For now, theater-scan flags `if os.getenv\(.*\)` near returns in evidence-cited files.

---

## Pattern 33 — `panic!()` substituted for `unimplemented!()`

**Trigger.** Closer learned the audit catches `unimplemented!()` and `todo!()` and substituted `panic!("not done")` (free-form string).

**What it looks like.**
```rust
pub fn compute_charge(input: &Input) -> Result<Charge> {
    panic!("billing isn't wired yet — temp")
}
```

**Rubric impact.** BLOCKING. Same severity as `unimplemented!()`.

**Remediation hint.** Theater-scan pattern: `panic!\(.*not\s*(implemented|done|wired|finished|complete)`. Also flag `panic!()` in production paths from beads tagged `feature` or `api`.

---

## Pattern 34 — Side-channel via env var ("real impl in production")

**Trigger.** Implementation has a stub return AND a real branch behind `if os.getenv("REAL_IMPL")`. Tests don't set it; only prod allegedly will (which never gets tested).

**Rubric impact.** BLOCKING. The whole point of Phase 4 is exercising the path that runs in production.

**Remediation hint.** Theater-scan: branching on env vars in non-config paths (e.g. inside business-logic functions, not in `config.py`).

---

## Pattern 35 — Future-dated `closed_at`

**Trigger.** A bead's `closed_at` is in the future (e.g. `2099-01-01`). Closer is dodging the time-to-close < 5min anomaly check by making the close *appear* to have taken a long time.

**Rubric impact.** MAJOR. Anomaly scan flags any `closed_at > now()`.

**Remediation hint.** Add to `scripts/anomaly-scan.sh`: parse `closed_at`, compare to current UTC, flag future dates.

---

## Pattern 36 — Citation salting (padding evidence with unrelated files)

**Trigger.** `evidence.json` cites 15 files. 12 are unrelated to the spec (random docs, README, license file) but inflate the citation-count metric.

**What it looks like.** Spec is "implement Stripe webhook signature verification"; evidence cites `LICENSE`, `README.md`, `CONTRIBUTING.md`, `docs/changelog.md`, etc.

**Rubric impact.** MAJOR. Each cited file:line range must contain at least one identifier from the spec's checklist (function/struct/feature names).

**Remediation hint.** `validate-evidence.py` cross-checks: each citation's file:line content must match ≥ 1 spec checklist keyword. Padded citations → flag.

---

## Pattern 37 — Stale-commit citation

**Trigger.** Cited file:line existed at the cited commit, but the line was deleted before the audit pass. Closer cited an old SHA where the implementation existed but later was reverted.

**Remediation hint.** `git log --follow <cited-file>` between cited-commit and audit-pass head; if the cited line range is no longer present at HEAD, flag.

---

## Pattern 38 — Reverse-migration spoof

**Trigger.** Migration bead has a reverse migration that's syntactically valid but logically a no-op (e.g. `-- TODO: reverse this; for now this comment serves`).

**Rubric impact.** BLOCKING. `migration-safety-reviewer.md` must EXECUTE the reverse against a clone and assert state diff matches expectations.

---

## Pattern 39 — Backfill with implicit `LIMIT`

**Trigger.** Spec says "backfill all rows where X is null". Implementation backfills 100 rows then exits (LIMIT 100, no looping). Post-migration query shows 95% of rows still null.

**Rubric impact.** BLOCKING for the migration bead. Phase 6 must verify post-migration row count matches spec expectation.

---

## Pattern 40 — Bench in `--release` only (feature-flag mismatch)

**Trigger.** `cargo bench` builds with `--release` but the production binary builds with `--release --features=production-tracing`. Benchmarks measure a different binary than ships.

**Rubric impact.** MAJOR. Bench harness must use the same feature-flag set as production. `performance-auditor.md` reads the bench config and compares to the project's release build.

---

## Pattern 41 — Single-sample benchmark

**Trigger.** "Achieves p95 < 100ms" with one (1) measurement.

**Rubric impact.** BLOCKING for perf claims. `performance-auditor.md` enforces n_samples ≥ 30 for percentile metrics.

---

## Pattern 42 — Sloppy session by AI agent (mined via `cass`)

**Trigger.** A single CLI session closed ≥ 5 beads within 10 minutes, all with terse close reasons. Cross-check `closed_by_session` field.

**Rubric impact.** Each bead in the session starts with -25 prior penalty (per `audit-policy.yaml#attribution.prior_penalty_amount`).

**Remediation hint.** `subagents/cass-pattern-miner.md` extracts the session IDs; prior penalty is automatic.

---

## Pattern 43 — Test in directory not run by CI

**Trigger.** Test file exists, would pass if run, but the project's CI invocation (`cargo test`, `pytest`, `npm test`) doesn't reach the file's directory.

**Rubric impact.** BLOCKING. Phase 4 must compute the union of tests CI runs vs tests the bead claims; mismatch → flag.

**Remediation hint.** `compliance-verifier.md` walks the project's CI config + test runner config to determine which tests CI actually executes; cross-references against citations in `evidence.json#items[].test_path`.

---

## Pattern 44 — Re-introduced `#[ignore]` after the bead closed

**Trigger.** At bead close, the test was un-ignored and passing. A subsequent commit re-added `#[ignore]` claiming flakiness; the test no longer runs.

**Rubric impact.** Cross-pass diff: any added `#[ignore]` / `it.skip` / `@pytest.mark.skip` against an already-audited bead's tests → flag, retroactively dock the bead's score, mark for re-audit.

**Remediation hint.** `scripts/diff-passes.sh` already shows pass-over-pass deltas; extend `synthesize.py` to track per-bead test-skip churn.

---

## Pattern 45 — Apologetic close with no file:line citations

**Trigger.** Long, sincere close reason ("I struggled with this; please review carefully…") that mentions tests + commits but doesn't link any file:line ranges.

**Rubric impact.** MAJOR. The anomaly-scan already flags apologies; tighten by requiring `[a-z_]+\.[a-z]+:\d+` in long close reasons (≥ 200 chars).

---

## Pattern 46 — Status-code lie (200 OK with error body)

**Trigger.** API endpoint returns HTTP 200 with `{"error": "operation failed: ..."}` in the body. Status-based scanners think it succeeded; only body-reading reveals the failure.

**Rubric impact.** MAJOR for API beads. `api-contract-checker.md` must scan response bodies for error-shaped JSON when status is 2xx.

**Remediation hint.** Theater-scan adds: response handlers that return 2xx with bodies matching `error|fail|exception|wrong` keys.
