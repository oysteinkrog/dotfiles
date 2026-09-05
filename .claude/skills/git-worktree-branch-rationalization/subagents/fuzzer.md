---
name: fuzzer
description: Phase 3 / Phase 11 — defense-in-depth fuzzing of the recovery bundle's surface. Generates transformed copies of the bundle (tar/untar, fs-copy, simulated bit-flips); runs `verify-bundle.sh` against each; identifies "cliff edges" where the recovery breaks. Writes findings to `bundle_fuzz_report.md`. Per AGENTS.md, never `rm -rf` the fuzz copies — `mv` them to `.archived` for user-managed lifecycle.
---

# Fuzzer

Defense-in-depth check on the recovery bundle's robustness. Where `verify-bundle.sh` enforces byte-equality (Axiom 4) and `audit-conductor` enforces cross-layer coherence, the fuzzer asks: *what happens when the bundle is degraded the way real-world filesystems degrade it?* Tar archives get partially extracted; cloud syncs flip bits; a `git bundle` packed on one git version gets read by another; a permissions issue truncates a file mid-write.

If the recovery bundle is the safety net for hundreds of branches and dozens of worktrees, that net needs to be robust under degradation, not just under perfect conditions. The fuzzer is invoked at Phase 3 (right after build, before authorizing destructive logic) and again at Phase 11 (post-cleanup, to certify the bundle the user is left with) — both are paranoid checkpoints, not the happy-path verifier.

## When invoked

- **Phase 3 invocation** — after `bundle-builder` and `verify-bundle.sh` succeed; before `audit-conductor` runs the post-phase-3 checkpoint. The fuzzer is opt-in here for Standard mode (under-budget) and on by default for Comprehensive / Council modes.
- **Phase 11 invocation** — after Phase 10 cleanup completes; certifies the bundle the user is left with against degradation scenarios.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path (read-only; fuzzer never mutates the original)
- `{INVOCATION}` — `phase-3` or `phase-11`
- `{MODE}` — Quick / Standard / Comprehensive / Council
- `{FUZZ_DIR}` — `<workspace>/fuzz/`

## Outputs

- `<workspace>/bundle_fuzz_report.md` — per-transform table (verify-bundle exit, recovery-test exit, classification ∈ `robust` / `expected-failure` / `false-alarm` / `cliff-edge`), cliff-edge findings narrative, recommendations, fuzz-copy locations.
- `<workspace>/fuzz/baseline/` — verified mirror of `{BUNDLE}` (never mutated).
- `<workspace>/fuzz/<transform-name>/{verify_stdout.log,verify_stderr.log,verify_status,recover_stdout.log,recover_status}` — one set per transform.
- `<workspace>/fuzz/.archived/<name>-<timestamp>/` — archived fuzz copies (NEVER `rm -rf`-d; user manages lifecycle).
- **Side effects:** disk-space check before mirroring (refuses if free space < 2× bundle size); operates entirely on copies under `{FUZZ_DIR}`; original `{BUNDLE}` remains byte-identical pre/post (verified via sha256sum manifest).
- **Decision contract:** Phase 3 invocation — any cliff-edge finding HALTS the run via `incident-responder`; no cliff-edge → Phase 4 proceeds. Phase 11 invocation — findings are non-blocking, surfaced into `handoff_report.md`'s "Bundle robustness" section.

## Workflow

### 1. Mirror the bundle into a fuzz workspace

`cp -r {BUNDLE} {FUZZ_DIR}/baseline/` — never operate on the original. Verify the copy via `verify-bundle.sh {FUZZ_DIR}/baseline/` exits 0 before any transform.

### 2. Generate transformed copies

For each transformation, mirror baseline → `{FUZZ_DIR}/<transform-name>/` then apply the transform. Transforms (per `references/MEASUREMENT.md` § Bundle Robustness):

| Transform | Method | Why |
|-----------|--------|-----|
| `tar-roundtrip` | `tar -czf - <copy> \| tar -xzf -` (in-memory pipe), then re-checksum | Many users will tar the bundle for sharing; verify the tar layer doesn't lose information |
| `fs-copy` | `cp -r <copy> <new>` followed by `rsync --checksum` to surface attribute drift | Filesystem copies (ext4 → tmpfs → smb) drop xattrs / hardlinks; verify recovery path doesn't depend on them |
| `permission-strip` | `chmod -R u+rw,go-rwx <copy>` (preserve readability for owner) | Verify recovery doesn't depend on group/other access |
| `single-file-truncate` | `dd if=/dev/null of=<one-of-the-format-patch-files> bs=1 count=0 conv=notrunc seek=<half-its-size>` on a randomly-selected non-critical file | Verify graceful failure when ONE artifact is corrupted, not silent data return |
| `bit-flip-pack` | Flip 1 byte at a random offset in a *copy* of `object-bundle.pack`; do NOT touch the original | Verify `git bundle verify` catches it (it should — pack files are checksummed) |
| `bit-flip-diff` | Flip 1 byte in a copy of one `branches/<slug>/diff-vs-merge-base.diff` | Verify `git apply --check` catches the corrupted patch |
| `delete-format-patch-file` | Move (NOT delete) one `.patch` file out of `branches/<slug>/format-patch/` into `<copy>/.archived/` | Verify the recovery has redundancy: the bundle pack OR the diff still resolves |
| `gz-truncate-untracked` | Truncate `worktrees/<sanitized-path>/untracked.tar.gz` mid-stream | Verify the worktree-recovery path surfaces a clear error rather than silent data loss |
| `git-version-mismatch` | Run `verify-bundle.sh` with `GIT_TEST_DEFAULT_PACK_VERSION=2` and `=3` if available | Verify cross-version compat |

For each transform, `mv` the result into `{FUZZ_DIR}/<transform-name>/`. **Never `rm -rf` a fuzz copy** — per AGENTS.md RULE NUMBER 1, all cleanup is `mv` to `{FUZZ_DIR}/.archived/<transform>-<timestamp>/`.

### 3. Run verification on each transform

For each `{FUZZ_DIR}/<transform-name>/`:

```bash
./scripts/verify-bundle.sh {FUZZ_DIR}/<transform-name>/ \
  > {FUZZ_DIR}/<transform-name>/verify_stdout.log \
  2> {FUZZ_DIR}/<transform-name>/verify_stderr.log
echo "exit=$?" >> {FUZZ_DIR}/<transform-name>/verify_status
```

Then run `./scripts/recovery-test.sh {FUZZ_DIR}/<transform-name>/` (which clones the project to `/tmp/`, exercises branch-restore + worktree-dirty-state-restore, verifies the recovered SHAs match the bundle's recorded SHAs):

```bash
./scripts/recovery-test.sh {FUZZ_DIR}/<transform-name>/ \
  > {FUZZ_DIR}/<transform-name>/recover_stdout.log \
  2>&1
echo "exit=$?" >> {FUZZ_DIR}/<transform-name>/recover_status
```

### 4. Classify outcomes

For each transform, classify:

- `cliff-edge` — verify-bundle exits 0 (bundle says it's healthy) but recovery-test fails (recovery actually broken). This is the worst failure mode: silent corruption.
- `expected-failure` — verify-bundle exits non-zero AND recovery-test exits non-zero. Acceptable: the gate caught the degradation.
- `false-alarm` — verify-bundle fails but recovery still works via fallback path. Acceptable but worth investigating: the verify gate may be over-strict.
- `robust` — both succeed despite the transform. Best outcome (e.g., the bundle survived a tar-roundtrip).

### 5. Emit `bundle_fuzz_report.md`

```markdown
# Bundle Fuzz Report

Invocation: {INVOCATION}
Bundle under test: {BUNDLE}
Transforms run: <count>
Generated: <UTC>

## Outcomes

| transform | verify-bundle exit | recovery-test exit | classification |
|---|---|---|---|
| tar-roundtrip | 0 | 0 | robust |
| fs-copy | 0 | 0 | robust |
| permission-strip | 0 | 0 | robust |
| single-file-truncate | 1 | 1 | expected-failure |
| bit-flip-pack | 1 | 1 | expected-failure |
| bit-flip-diff | 0 | 0 | cliff-edge ⚠ |
| ... |

## Cliff-edge findings (HIGH SEVERITY)

(per finding: which transform, what verify-bundle missed, what recovery-test failed on, recommended hardening)

## Recommendations

(e.g., "verify-bundle.sh should checksum each branches/<slug>/diff-vs-merge-base.diff; currently it byte-equality-checks against the live ref but doesn't validate the diff is internally consistent")

## Fuzz copy locations

All fuzz copies are at `{FUZZ_DIR}/<transform-name>/`. Originals are at `{FUZZ_DIR}/.archived/` after each run.
The user manages lifecycle; the fuzzer never deletes.
```

### 6. Halt on cliff-edge findings (Phase 3 invocation only)

If any cliff-edge finding surfaces in the Phase 3 invocation, halt the run via `incident-responder`. The bundle is unsafe — verify-bundle says it's healthy, but recovery is actually broken. The user remediates (re-run `bundle-builder`, address the verify-bundle blind spot) before destructive phases proceed.

In the Phase 11 invocation, cliff-edge findings are recorded in `handoff_report.md` under "Bundle robustness" and surfaced to the user as a follow-up; they don't halt because the destructive phase already ran.

## Critical rules

- **Never operate on the original bundle.** Always `cp -r` first; transforms apply to copies only. `verify-bundle.sh` is run against the copy.
- **Never `rm -rf` fuzz copies.** Per AGENTS.md RULE NUMBER 1: cleanup is `mv` to `{FUZZ_DIR}/.archived/<name>-<timestamp>/`. The user manages lifecycle.
- **Never run mass-delete primitives.**
- **Don't fight DCG.** If DCG blocks an `rm -rf` attempt, that's the system working correctly — `mv` instead.
- **Bound disk usage.** Before mirroring, check `df` for `<workspace>`'s mount; refuse if free space < 2× bundle size. Surface a recommendation to use `--fuzz-on-tmpfs` or skip fuzzing if disk-constrained.
- **The fuzz transforms are deterministic given a seed.** Default seed = run-id; record the seed in the report so re-runs reproduce the same transforms.
- **Cliff-edge findings halt Phase 3.** Phase 11 findings surface but don't halt (cleanup already ran).
- **Per AGENTS.md "No Script-Based Changes":** never run sed/awk on source files. The fuzzer transforms bundle artifacts (already not source files), not source files.
- **Per AGENTS.md "Note for Codex/GPT-5.5":** never disturb concurrent agents' working-tree state in any worktree. The fuzzer operates entirely on copies under `{FUZZ_DIR}`.
- **Never bypass pre-commit hooks** (no commits here).
- **Never push.** Fuzz copies are local-only; never pushed.
- **Never run `git push --delete` or force-push.**

## Coordination

- File reservation: `paths=["<workspace>/fuzz/**", "<workspace>/bundle_fuzz_report.md"]`, `exclusive=true`, `reason="branch-rationalization-fuzz-<invocation>"`, `ttl_seconds=7200`.
- Thread id: `branch-rationalization-<run-id>`.
- Reads `{BUNDLE}` (the original) read-only; never holds an exclusive reservation on the original.

## Quality gates

- [ ] `bundle_fuzz_report.md` exists with one row per transform
- [ ] Original bundle is byte-identical pre- and post-fuzz (`sha256sum -c` on a manifest snapshot)
- [ ] No `rm -rf` was issued (verify via dcg log if available)
- [ ] Every cliff-edge finding has a recommended-hardening narrative
- [ ] `{FUZZ_DIR}/.archived/` is non-empty after run; the user can inspect any fuzz copy
- [ ] Disk-space check ran before any mirroring

## Exit criteria

Phase 3 invocation: `bundle_fuzz_report.md` written; on cliff-edge findings, `incident-responder` invoked and run halted; on no findings, Phase 4 proceeds. Phase 11 invocation: report written; findings surfaced to handoff-reporter for inclusion in the final handoff.
