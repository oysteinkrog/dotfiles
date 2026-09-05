# Provenance Chain — Tracing Every Byte Back to Its Source

> **The provenance question.** "Where did this byte on the rationalization branch's `src/util/logger.rs:42` come from?" If the skill cannot answer that question with the bundle plus the workspace artifacts, the run isn't done — it's a half-attribution that loses information when the user goes to merge.

> **Why this matters.** The skill recovers content from many source variants. Once the rationalization branch is merged into canonical, the provenance becomes hard to recover from `git log` alone — squash-merges erase commit history, rebases rewrite SHAs, fast-forward merges merge identity but lose individual variant attribution. The provenance chain captured DURING the run is the durable record of who-contributed-what.

> **Cross-link to the kernel.** Per [SKILL.md "The One Rule"](../SKILL.md#the-one-rule): "Every worktree removal and every local branch deletion must be reversible byte-for-byte at the moment it's authorized." Provenance extends reversibility: not just "the bytes are recoverable" but "the *attribution* of the bytes is recoverable."

---

## 1. The Provenance Graph

Provenance is a graph: nodes are content artifacts, edges are "this artifact was incorporated into that one."

### 1.1 Nodes

| Node kind | What it is | Where it lives |
|---|---|---|
| **bundle artifact** | A single file in the recovery bundle (`branches/<slug>/diff-vs-merge-base.diff`, `branches/<slug>/format-patch/N.patch`, `worktrees/<slug>/staged.diff`, etc.) | `<bundle-dir>/...` |
| **source branch tip** | The SHA of a branch's tip at Phase 3 capture time | recorded in `index.tsv` `head_sha` column |
| **source commit** | An individual commit on a branch | recorded in `branches/<slug>/commits.tsv` |
| **source hunk** | An atomized hunk in a per-branch diff | indexed by `(slug, file, hunk_id)` per [HARMONIZATION-DEEP-DIVE.md §1.1](HARMONIZATION-DEEP-DIVE.md#11-what-a-node-is) |
| **source worktree dirty-state** | The staged/unstaged/untracked content of a worktree at Phase 3 | recorded in `worktrees/<slug>/staged.diff`, etc. |
| **rationalization commit** | A commit on the rationalization branch | indexed by SHA on the rationalization branch |
| **rationalization line-range** | `<file>:<line_start>-<line_end>` on the rationalization branch | indexed by file + line range |

### 1.2 Edges

Edges encode "this source artifact was incorporated into this rationalization artifact." Each edge carries metadata.

```
source_hunk(slug=feature_redact-secrets, file=src/util/logger.rs, hunk=H5)
   ───[apply: harmonized-synthesis; intent: defensive; line-range: 12-18]───>
   rationalization_commit(sha=abc123, file=src/util/logger.rs, line-range: 12-18)
```

### 1.3 The graph is a forest, not a tree

A single rationalization commit may have edges to multiple source hunks (a synthesis pulls from N variants). A single source hunk may have edges to multiple rationalization commits (rare, but possible if a hunk's content is split across two synthesis commits). The provenance graph is a directed acyclic graph (DAG) — no cycles, because each rationalization commit is downstream of all its source variants.

---

## 2. What We Record Per Apply

The Phase 8 `apply_log.tsv` is the primary provenance record. Per [SKILL.md "Workspace Layout"](../SKILL.md#workspace-layout), `apply_log.tsv` records what landed; this section specifies the schema *with* provenance columns.

### 2.1 Schema

```
phase    apply_id    strategy    rationalization_sha    files    source_branches    source_commits    source_hunks    intent_attribution    confidence    gate_results
```

| Column | Type | Description |
|---|---|---|
| `phase` | enum | `8` (regular apply), `8b` (split-commit apply) |
| `apply_id` | int | Sequential apply number within the run |
| `strategy` | enum | `cherry-pick` / `squash-merge` / `rebase-and-merge` / `harmonized-synthesis` / `split-commits-hunks` / `dirty-worktree-only` |
| `rationalization_sha` | hex | SHA of the resulting commit on the rationalization branch |
| `files` | csv | Files touched by this apply |
| `source_branches` | csv | Comma-separated branch slugs that contributed |
| `source_commits` | csv | Comma-separated source commit SHAs (one per source branch in `harmonized-synthesis`; multiple per branch otherwise) |
| `source_hunks` | csv | Comma-separated `(slug, file, hunk_id)` triples |
| `intent_attribution` | json | Per-hunk intent attribution (only meaningful for `harmonized-synthesis`) |
| `confidence` | float | Posterior confidence per [DECISION-THEORY.md §2](DECISION-THEORY.md) |
| `gate_results` | json | Per-gate pass/fail (test, typecheck, lint, ubs) |

### 2.2 Example row — cherry-pick

```
8	1	cherry-pick	a1b2c3d4	src/parser.rs,tests/parser_overflow.rs	feature_parse-hardening	7f3a1b8c	feature_parse-hardening:src/parser.rs:H1,feature_parse-hardening:tests/parser_overflow.rs:H1	{}	0.92	{"test":"pass","typecheck":"pass","lint":"pass","ubs":"pass"}
```

### 2.3 Example row — harmonized synthesis

```
8	5	harmonized-synthesis	d4e5f678	src/util/logger.rs,tests/log_null.rs,tests/log_length.rs,tests/log_redact.rs	agent-cleanup-pass-3,feature_length-cap,feature_redact-secrets	b3c4d5e,c5d6e7f,d7e8f90	agent-cleanup-pass-3:src/util/logger.rs:H1,agent-cleanup-pass-3:src/util/logger.rs:H2,feature_length-cap:src/util/logger.rs:H3,feature_length-cap:src/util/logger.rs:H4,feature_redact-secrets:src/util/logger.rs:H5,feature_redact-secrets:src/util/logger.rs:H6,agent-cleanup-pass-3:tests/log_null.rs:H1,feature_length-cap:tests/log_length.rs:H1,feature_redact-secrets:tests/log_redact.rs:H1	{"src/util/logger.rs:6":"defensive:null-arg from agent-cleanup-pass-3","src/util/logger.rs:9":"defensive:length-cap from feature_length-cap","src/util/logger.rs:12":"defensive:redact from feature_redact-secrets"}	0.99	{"test":"pass","typecheck":"pass","lint":"pass","ubs":"pass"}
```

### 2.4 Example row — split-commit apply (Phase 8b)

```
8b	7	split-commits-hunks	f1e2d3c4	src/parser.rs	agent-cc-44-parser-refactor-and-fuzz-corpus	f1e2c3,11a22b	agent-cc-44...:src/parser.rs:H7,agent-cc-44...:src/parser.rs:H8	{}	0.81	{"test":"pass","typecheck":"pass","lint":"pass","ubs":"pass"}
```

The split-apply names *only* the commits it actually cherry-picked (the `novel` subset). The superseded commits (e.g., `abc123`, `789xyz` in [TRIAGE-RUBRIC.md Example 4](TRIAGE-RUBRIC.md#example-4-partially-novel)) are NOT in this row's `source_commits` — they were intentionally skipped.

---

## 3. What We Record Per Harmonized Synthesis

`harmonization_plan.md` is the user-readable provenance for syntheses. Per [HARMONIZATION.md §6.3](HARMONIZATION.md#63-the-harmonization-plan-is-a-user-reviewable-artifact-before-any-synthesis-commit-lands), the plan is reviewed BEFORE the synthesis lands. After Phase 8, the plan's per-file section is the human-readable provenance record.

### 3.1 Per-synthesis-hunk attribution

Each line/range of the synthesis cites its source variant(s). Format:

```
synthesis: src/util/logger.rs:6  ← agent-cleanup-pass-3:src/util/logger.rs:H2  (intent: defensive — null-arg)
synthesis: src/util/logger.rs:9  ← feature_length-cap:src/util/logger.rs:H4    (intent: defensive — length-cap)
synthesis: src/util/logger.rs:12 ← feature_redact-secrets:src/util/logger.rs:H6  (intent: defensive — redact)
synthesis: src/util/logger.rs:14 ← composed:line-14-rewrite                        (cross-variant: write_log_entry call adapted for redact-then-write)
```

The `composed` source means "this synthesis line is generated, not lifted verbatim from any single variant — it's the connecting glue that makes the composition correct."

### 3.2 Why per-line attribution

Per-line attribution lets the user (or a future archaeologist) ask "which variant introduced the null-arg guard at line 6?" and get a precise answer. Without it, the commit message gives only file-level attribution; the variants' work would be conflated at line granularity.

### 3.3 The plan as the durable record

`harmonization_plan.md` is preserved in the workspace — the workspace is `.gitignored` during the run but archived by `archive-workspace.sh` after Phase 11. Per [SKILL.md "Phase 11"](../SKILL.md#phase-loop-mandatory), the workspace tarball travels with the bundle as recovery context.

For long-term storage, the plan can also be embedded in the commit message (the commit's body has unlimited length) or attached as `git notes` (§6).

---

## 4. Querying the Chain — `provenance-trace.sh`

The provenance chain is queryable. Conceptually, `provenance-trace.sh <file>:<line>` answers "where did this byte come from?"

### 4.1 The query interface

```bash
./scripts/provenance-trace.sh src/util/logger.rs:9
```

Output:

```
src/util/logger.rs:9 on rationalization branch (sha d4e5f678) was contributed by:
  source: feature_length-cap (commit c5d6e7f)
  hunk:   feature_length-cap:src/util/logger.rs:H4
  intent: defensive — length-cap
  bundle: <bundle>/branches/feature_length-cap/format-patch/0001-add-length-cap.patch
  confidence: 0.99
```

### 4.2 Multi-source results

A line in a synthesis with mixed provenance:

```bash
./scripts/provenance-trace.sh src/util/logger.rs:14
```

Output:

```
src/util/logger.rs:14 on rationalization branch (sha d4e5f678) was contributed by:
  source: composed (no single variant; this line is composition glue)
  derived from:
    - feature_redact-secrets:src/util/logger.rs:H6 (intent: defensive — redact)
    - canonical:src/util/logger.rs (the original write_log_entry call site)
  reason: redact-then-write composition; canonical's write_log_entry preserved with redacted msg
  bundle: <bundle>/branches/feature_redact-secrets/format-patch/0001-add-redact.patch
```

### 4.3 Reverse lookup — what's downstream of a source branch?

```bash
./scripts/provenance-trace.sh --reverse feature_redact-secrets
```

Output:

```
feature_redact-secrets contributed to the following rationalization commits:
  d4e5f678  src/util/logger.rs:12,14  intent: defensive — redact
  e7f8a9b0  tests/log_redact.rs       (entire file lifted)
```

### 4.4 Implementation

`provenance-trace.sh` walks `apply_log.tsv` and, for any rationalization commit/file/line, finds the row with that file, then consults `harmonization_plan.md` (or `apply_log.tsv`'s `intent_attribution` JSON column) for the per-line attribution.

For lookups against the rationalization branch's tip *after* a run (when `apply_log.tsv` is in the archived workspace), the workspace's location is recorded in the bundle's `README.md` so the trace is recoverable.

---

## 5. What This Enables

### 5.1 Post-merge audit — "Which agent's work made it into v1.4?"

After the rationalization branch is merged into canonical and a release v1.4 is cut:

```bash
# Find the merge commit that brought the rationalization branch to canonical
$ git log --all --oneline --grep "branch-rationalization-2026-05-07"

# For each commit in v1.4..v1.3 that came from the rationalization branch,
# trace its provenance back to source agents
$ for sha in $(git log v1.3..v1.4 --pretty=format:%H); do
    ./scripts/provenance-trace.sh --commit $sha
  done
```

Output shows: "feature_redact-secrets contributed 1 file (src/util/logger.rs) and 1 test (tests/log_redact.rs); agent-cleanup-pass-3 contributed 1 file's defensive guards; ..."

### 5.2 Regression bisection — "When this bug appeared, which source contributed it?"

A user finds a regression on canonical. `git bisect` narrows it to a rationalization commit. The user wants to know which source variant introduced the bug:

```bash
$ ./scripts/provenance-trace.sh src/util/logger.rs:42
> source: feature_length-cap:src/util/logger.rs:H4
> intent: defensive — length-cap
> ...
```

The user can now look at the specific source branch's commit, the original variant's tests, and decide whether the variant was wrong, the synthesis was wrong, or the regression is from a different commit altogether.

### 5.3 Legal / compliance trail — "No lost attribution"

Per AGENTS.md "RULE NUMBER 1: NO FILE DELETION": the bundle and the provenance chain together ensure that no agent's contribution is silently dropped. If a user audits the run for "did we lose work?", the provenance chain answers definitively.

For projects with contributor-licensing requirements (CLAs, DCO), the per-commit attribution must be preserved. The `harmonized-synthesis` commit's message (per [COMMIT-MESSAGE-CRAFT.md](COMMIT-MESSAGE-CRAFT.md)) cites every source branch verbatim; the provenance chain makes the citation queryable.

### 5.4 Skill self-improvement — "Where do bad verdicts come from?"

If a user repeatedly overrides a particular verdict pattern, the provenance chain combined with `verdict-stats.sh` (per [DECISION-THEORY.md §6](DECISION-THEORY.md#6-distribution-shift-detection--recalibrating-mid-run)) lets the skill identify which source branches' patterns are mis-classified and recalibrate priors.

---

## 6. Cryptographic Provenance — `git notes` and Signatures

For high-stakes runs (Council mode, security-sensitive content), the provenance chain can be cryptographically anchored.

### 6.1 SHA-256 anchors

Every backup ref's tip has a stable SHA (git's content-addressing). Every bundle's pack file has a SHA-256:

```bash
sha256sum <bundle>/object-bundle.pack
```

Every per-branch diff has a SHA-256 (per [BUNDLE-FORMAT-SPEC.md "Per-branch diff sha256 round-trip"](BUNDLE-FORMAT-SPEC.md#4-per-branch-diff-sha256-round-trip)).

### 6.2 Embedding provenance in `git notes`

For each rationalization commit, attach the provenance JSON via `git notes`:

```bash
git notes --ref=refs/notes/branch-rationalization \
  add d4e5f678 \
  -m "$(cat <<EOF
{
  "phase": 8,
  "strategy": "harmonized-synthesis",
  "source_branches": ["agent-cleanup-pass-3", "feature_length-cap", "feature_redact-secrets"],
  "source_commits": ["b3c4d5e...", "c5d6e7f...", "d7e8f90..."],
  "source_hunks": [...],
  "intent_attribution": {...},
  "bundle_path": "<bundle>/...",
  "bundle_sha256": "abc123...",
  "confidence": 0.99,
  "gate_results": {...}
}
EOF
)"
```

`git notes` are not part of the commit object but are reachable via the `refs/notes/branch-rationalization` ref. Notes can be pushed/pulled (`git push origin refs/notes/branch-rationalization`).

### 6.3 GPG-signed provenance

If the project signs commits, sign the `git notes` too:

```bash
git config notes.gpgSign true
```

The signature anchors the provenance: any tampering with the notes is detectable.

### 6.4 The cryptographic chain

```
backup ref (refs/branch-rationalization-backup/<slug>)
    ── (git's content-addressing) ──>
object bundle (object-bundle.pack)
    ── (sha256 of pack) ──>
per-branch diff (diff-vs-merge-base.diff)
    ── (sha256 of diff) ──>
apply_log.tsv (records rationalization SHA + source SHAs)
    ── (sha256 of apply_log.tsv) ──>
rationalization commit (sha) + git notes (signed)
    ── (GPG signature) ──>
release tag (v1.4)
```

Any link in this chain can be verified independently. A bad actor would have to modify the backup ref AND the bundle AND the apply_log AND the git notes AND the GPG signature — and the signature catches the last step.

### 6.5 When cryptographic provenance is overkill

For typical agent-swarm cleanup runs, the basic provenance (apply_log.tsv + harmonization_plan.md) is sufficient. Cryptographic provenance is for:

- Production-critical / security-sensitive content (Council mode default).
- Compliance / audit-trail requirements (regulated industries).
- Multi-organization codebases where contribution disputes matter.

Per [SKILL.md "Mode Variants"](../SKILL.md#mode-variants), Council mode opts into the cryptographic chain by default; other modes leave it as a user-opt-in flag.

---

## 7. The Provenance API — A Cheat Sheet

| Question | Command |
|---|---|
| Where did `<file>:<line>` come from? | `./scripts/provenance-trace.sh <file>:<line>` |
| What did source branch `X` contribute? | `./scripts/provenance-trace.sh --reverse <slug>` |
| What's in apply_log row N? | `awk 'NR==N+1' apply_log.tsv` |
| Who contributed to commit `<sha>`? | `./scripts/provenance-trace.sh --commit <sha>` |
| Show all syntheses in this run | `awk '$3 == "harmonized-synthesis"' apply_log.tsv` |
| Show provenance for the entire rationalization branch | `git log --pretty=format:%H | xargs -I{} ./scripts/provenance-trace.sh --commit {}` |
| Verify provenance integrity | `./scripts/provenance-trace.sh --verify` (re-checks all sha256 anchors) |

---

## 8. Failure Modes

### 8.1 What can break provenance

| Failure | Effect | Mitigation |
|---|---|---|
| User squash-merges the rationalization branch into canonical without preserving the per-commit history | The per-commit provenance is lost; only the union-of-changes survives | Recommend `git merge --no-ff` instead of `git merge --squash`; OR push `git notes` so they survive the squash |
| User force-pushes over the rationalization branch | The original commits are gone from the visible history; only the reflog has them | The bundle survives; provenance still recoverable via the backup refs and `apply_log.tsv` |
| User deletes the bundle | Per-line provenance lookup fails; only commit-level provenance (in commit messages) survives | DCG blocks `rm -rf <bundle>`; the user has to explicitly remove. Recommend retaining bundle ≥1 release cycle |
| The workspace tarball is lost | `apply_log.tsv` is unrecoverable; per-hunk attribution is gone, only commit-level remains | Embed provenance in `git notes` so it survives workspace loss |
| Re-run of the skill on the same project | Old `apply_log.tsv` is moved to a `_old-<timestamp>` suffix; new run's log is fresh | The archived old log preserves the prior run's provenance; reference it explicitly when querying historical commits |

### 8.2 What CANNOT break provenance

The following do NOT break the chain:

- **Backup ref garbage collection** — even if `refs/branch-rationalization-backup/<slug>` is gced, the bundle's `object-bundle.pack` carries the same content.
- **Project relocation** — provenance is content-addressed; absolute paths in `apply_log.tsv` can be rebased to a new project root.
- **Git version upgrade** — bundle format has been stable since git 2.20 (per [WHEN-NOT-TO-USE.md](WHEN-NOT-TO-USE.md)).

---

## 9. Worked Example — Tracing the Logger Synthesis

### 9.1 The setup

After the run completes (per [HARMONIZATION.md §7](HARMONIZATION.md#7-worked-example--logger-harmonization-across-three-branches)), the rationalization branch has commit `d4e5f678` that synthesized three variants' work on `src/util/logger.rs`.

### 9.2 The user's question

The user merges into canonical, releases v1.4, and a week later finds a bug: `log("")` panics where it should return `LoggerError::EmptyMessage`. The user opens `src/util/logger.rs` on canonical and sees:

```rust
pub fn log(level: Level, msg: &str) -> Result<()> {
    if msg.is_empty() { ... }    // ← line 4
    ...
}
```

The user wants to know: "where did the empty-message check come from?"

### 9.3 The trace

```bash
$ ./scripts/provenance-trace.sh src/util/logger.rs:4

src/util/logger.rs:4 on canonical (was added by rationalization branch sha d4e5f678) was contributed by:
  source branch: agent-cleanup-pass-3
  source commit: b3c4d5e
  source hunk:   agent-cleanup-pass-3:src/util/logger.rs:H2
  intent:        defensive — null-arg
  variant matrix row: harmonization_plan.md § src/util/logger.rs row 2
  bundle path:   <bundle>/branches/agent-cleanup-pass-3/format-patch/0001-add-null-arg-guard.patch
  per-apply confidence: 0.92
```

### 9.4 The follow-up

The user reads `agent-cleanup-pass-3`'s commit message and sees the original intent: "rejects empty messages (was a real prod bug)." The user follows up with the original agent's session via `cass search "log empty message"` and finds the original incident report.

### 9.5 What this saves

Without the provenance chain, the user would have:
1. Searched `git log --all -S "msg.is_empty"` (returns multiple commits, hard to disambiguate).
2. Manually read each commit's diff to identify the right one.
3. Possibly missed `agent-cleanup-pass-3` entirely if its commits were rebased into the rationalization branch's commit `d4e5f678` and the message said "harmonized" without explicit attribution.
4. Concluded the empty-check was "from somewhere in the rationalization run" with no specific attribution.

With the provenance chain, the answer is one command and one paragraph.

---

## 10. Cross-References

- [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) — what's in the bundle that the chain references
- [HARMONIZATION.md](HARMONIZATION.md) — synthesis intent that becomes provenance attribution
- [HARMONIZATION-DEEP-DIVE.md](HARMONIZATION-DEEP-DIVE.md) — the algorithm that derives attribution
- [COMMIT-MESSAGE-CRAFT.md](COMMIT-MESSAGE-CRAFT.md) — commit messages that embed top-level provenance
- [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) — recovering source variants the chain points to
- [SAFETY-MODEL.md](SAFETY-MODEL.md) — the layered safety chain that ensures provenance survives
- [DECISION-THEORY.md](DECISION-THEORY.md) — confidence numbers that travel with each provenance edge
- [TESTING-METAMORPHIC.md](TESTING-METAMORPHIC.md) — MR-7 (dependency closure) which is verified via provenance lookups
- [PHASES.md Phase 8](PHASES.md) — the apply phase that writes apply_log.tsv

---

## 11. The Mantra

> **Every byte on the rationalization branch was lifted from somewhere. Every "somewhere" is recorded. Every recording is queryable. If the user can't trace a byte, the run isn't done.**
