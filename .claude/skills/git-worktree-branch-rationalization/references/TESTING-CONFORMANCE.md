# Conformance Testing — Verifying the Bundle Format Contract

> **The bundle format is a contract.** Tools other than this skill consume the bundle: `git apply`, `git am`, `git fetch`, `git bundle list-heads`, future "branch-archaeology" indexers, possibly third-party recovery tools. Every consumer assumes [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) is the truth. The conformance harness verifies that any bundle satisfies the spec — that is, the contract is honored.

> **Conformance vs unit testing.** Unit tests check internal invariants ("the slugify function produces N hex chars"). Conformance tests check the external contract ("the slug column in `index.tsv` matches `<safe-name>-<sha1-12>` per spec section 'Slug naming convention'"). Both are required. A run that passes unit tests but fails conformance is a regression in the contract — even if the skill itself works, downstream tools break.

> **Companion skill.** Read [/testing-conformance-harnesses SKILL.md](../../testing-conformance-harnesses/SKILL.md) for the underlying methodology (MUST/SHOULD/MAY clause enumeration, compliance matrix, divergence tracking).

---

## 1. The Conformance Test Suite

For each section of [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md), there is a check function. The full table:

| Spec section | Check function | What it verifies |
|---|---|---|
| Top-level layout | `check_toplevel_layout` | `README.md`, `object-bundle.pack`, `index.tsv`, `branches/`, `worktrees/` all present at the bundle root |
| Slug naming convention | `check_slug_naming` | Every slug in `index.tsv` matches `<safe-name>-<sha1-12>` regex |
| `index.tsv` schema | `check_index_tsv_schema` | Header has 10 expected columns; every data row has 10 columns |
| `index.tsv` row consistency | `check_index_tsv_consistency` | Every `bundle_paths` entry resolves to an existing file |
| Per-branch directory presence | `check_branch_dirs_exist` | For every `kind=branch` row, `branches/<slug>/` exists |
| Per-branch meta.txt schema | `check_branch_meta_schema` | All required keys present (ref, slug, head_sha, merge_base, ...) |
| Per-branch commits.tsv schema | `check_branch_commits_schema` | Header has 8 expected columns |
| Per-branch diff sha256 | `check_branch_diff_sha` | Per [BUNDLE-FORMAT-SPEC.md "Per-branch diff sha256 round-trip"](BUNDLE-FORMAT-SPEC.md#4-per-branch-diff-sha256-round-trip) |
| Per-branch format-patch series | `check_branch_format_patch` | File count matches `commit_count` from meta.txt |
| Per-worktree directory presence | `check_worktree_dirs_exist` | For every `kind=worktree` row, `worktrees/<slug>/` exists |
| Per-worktree meta.txt schema | `check_worktree_meta_schema` | All required keys present |
| Per-worktree status.txt format | `check_worktree_status_porcelain_v2` | Output is `--porcelain=v2` format |
| Per-worktree dirty diffs | `check_worktree_dirty_diffs` | `staged.diff` / `unstaged.diff` exist iff `dirty_staged` / `dirty_unstaged` flags say so |
| Per-worktree untracked artifacts | `check_worktree_untracked_artifacts` | `.untracked.list` and `untracked.tar.gz` both present iff `dirty_untracked=true` |
| README.md required sections | `check_readme_required_sections` | All 6 required sections present |
| Backup ref byte-equality | `check_backup_ref_byte_equality` | Per [BUNDLE-FORMAT-SPEC.md "Backup refs"](BUNDLE-FORMAT-SPEC.md#backup-refs) |
| object-bundle.pack list-heads round-trip | `check_object_bundle_list_heads` | `git bundle list-heads` returns expected refs |

Together, these check functions form `scripts/conformance-check.sh`.

---

## 2. The Compliance Matrix

For every conformance run, generate a matrix: spec section × bundle artifact × pass/fail.

### 2.1 The matrix format

```
              | branch_1 | branch_2 | worktree_1 | OVERALL
--------------|----------|----------|------------|--------
toplevel      |    ✓     |    ✓     |     ✓      |    ✓
slug-naming   |    ✓     |    ✓     |    n/a     |    ✓
index-schema  |    ✓     |    ✓     |     ✓      |    ✓
index-consist |    ✓     |    ✓     |     ✓      |    ✓
branch-dir    |    ✓     |    ✓     |    n/a     |    ✓
branch-meta   |    ✓     |    ✓     |    n/a     |    ✓
branch-commits|    ✓     |    ✓     |    n/a     |    ✓
branch-diff   |    ✓     |    ✓     |    n/a     |    ✓
branch-fmt-pat|    ✓     |    ✓     |    n/a     |    ✓
worktree-dir  |   n/a    |   n/a    |     ✓      |    ✓
worktree-meta |   n/a    |   n/a    |     ✓      |    ✓
worktree-stat |   n/a    |   n/a    |     ✓      |    ✓
worktree-dirty|   n/a    |   n/a    |     ✓      |    ✓
worktree-untrk|   n/a    |   n/a    |     ✓      |    ✓
readme-sects  |    -     |    -     |     -      |    ✓
backup-ref-eq |    ✓     |    ✓     |    n/a     |    ✓
list-heads-rt |    ✓     |    ✓     |    n/a     |    ✓
--------------|----------|----------|------------|--------
OVERALL       |    ✓     |    ✓     |     ✓      |    ✓
```

A `✗` anywhere in the matrix is a non-conformance.

### 2.2 Generating the matrix

```bash
./scripts/conformance-check.sh "$BUNDLE_DIR" \
  --output matrix \
  --format markdown > compliance_matrix.md
```

The matrix is part of the bundle's metadata for any external tool to read.

### 2.3 Spec section severity

Per [/testing-conformance-harnesses](../../testing-conformance-harnesses/SKILL.md), each spec clause has a severity:

| Severity | Examples | Pass-rate threshold |
|---|---|---|
| MUST | Top-level layout; index.tsv schema; backup ref byte-equality | 100% — any failure halts the bundle |
| SHOULD | README.md sections present; per-branch commits.tsv format | ≥95% — failures are warnings |
| MAY | Optional sidecar artifacts (forensic notes, future extensions) | informational only |

The compliance matrix tags each row with its severity. A run with all MUSTs ✓ but a SHOULD ✗ is *conformant with warnings*.

### 2.4 Reading the compliance matrix

The user reading the matrix gets:

- **OVERALL ✓** → the bundle is fully conformant. Downstream tools should work without surprises.
- **OVERALL ✓ with SHOULD warnings** → the bundle is conformant but has minor deviations. The deviations are documented in the matrix and may surface as soft warnings in tooling.
- **OVERALL ✗** → at least one MUST clause failed. The bundle is non-conformant. The skill's `verify-bundle.sh` should have caught this; if it didn't, the skill has a bug.

---

## 3. Each Check Function

The check functions are typically 20–50 line shell scripts that take a bundle path and return exit 0 (pass) or non-zero (fail).

### 3.1 `check_toplevel_layout`

```bash
check_toplevel_layout() {
  local bundle="$1"
  local errors=0
  for required in README.md object-bundle.pack index.tsv branches worktrees; do
    if [[ ! -e "$bundle/$required" ]]; then
      echo "MISSING: $bundle/$required"
      errors=$((errors + 1))
    fi
  done
  return $errors
}
```

### 3.2 `check_slug_naming`

```bash
check_slug_naming() {
  local bundle="$1"
  local errors=0
  awk -F'\t' 'NR>1 && $1=="branch" { print $2 }' "$bundle/index.tsv" | while read branch_name; do
    # Compute expected slug
    safe_name=$(echo -n "$branch_name" | sed 's|/|_|g; s/[^A-Za-z0-9._-]/_/g')
    sha=$(echo -n "$branch_name" | sha1sum | cut -c1-12)
    expected="$safe_name-$sha"

    # Compare to actual slug in branches/ dir
    if [[ ! -d "$bundle/branches/$expected" ]]; then
      echo "SLUG MISMATCH for branch $branch_name (expected $expected)"
      errors=$((errors + 1))
    fi
  done
  return $errors
}
```

### 3.3 `check_index_tsv_schema`

```bash
check_index_tsv_schema() {
  local bundle="$1"
  local expected_header="kind	name_or_path	head_sha	merge_base	ahead	behind	smell	intake_protected	verdict	bundle_paths"
  local actual_header=$(head -1 "$bundle/index.tsv")
  if [[ "$actual_header" != "$expected_header" ]]; then
    echo "SCHEMA MISMATCH: index.tsv header"
    return 1
  fi
  # Verify every data row has 10 columns
  local bad_rows=$(awk -F'\t' 'NR>1 && NF!=10' "$bundle/index.tsv" | wc -l)
  if [[ $bad_rows -gt 0 ]]; then
    echo "SCHEMA MISMATCH: $bad_rows rows have != 10 columns"
    return 1
  fi
  return 0
}
```

### 3.4 `check_branch_diff_sha`

```bash
check_branch_diff_sha() {
  local bundle="$1"
  local repo="$2"
  local errors=0
  awk -F'\t' 'NR>1 && $1=="branch" {print $2"\t"$3"\t"$4}' "$bundle/index.tsv" | \
  while IFS=$'\t' read branch_name head merge_base; do
    safe_name=$(echo -n "$branch_name" | sed 's|/|_|g; s/[^A-Za-z0-9._-]/_/g')
    sha=$(echo -n "$branch_name" | sha1sum | cut -c1-12)
    slug="$safe_name-$sha"

    diff_path="$bundle/branches/$slug/diff-vs-merge-base.diff"
    [[ -f "$diff_path" ]] || { echo "MISSING: $diff_path"; errors=$((errors+1)); continue; }

    expected_sha=$(cd "$repo" && git diff --binary "$merge_base...$head" | sha256sum | awk '{print $1}')
    actual_sha=$(sha256sum "$diff_path" | awk '{print $1}')

    if [[ "$expected_sha" != "$actual_sha" ]]; then
      echo "DIFF MISMATCH for $slug (expected $expected_sha, got $actual_sha)"
      errors=$((errors+1))
    fi
  done
  return $errors
}
```

### 3.5 `check_object_bundle_list_heads`

```bash
check_object_bundle_list_heads() {
  local bundle="$1"
  local repo="$2"

  bundle_refs=$(git -C "$repo" bundle list-heads "$bundle/object-bundle.pack" | sort)

  expected_refs=$(awk -F'\t' '
    NR>1 && $1=="branch" {
      branch_name=$2
      head_sha=$3
      gsub("/", "_", branch_name)
      # ...slug computation...
      printf "%s\trefs/branch-rationalization-backup/%s\n", head_sha, slug
    }' "$bundle/index.tsv" | sort)

  if ! diff -q <(echo "$bundle_refs") <(echo "$expected_refs"); then
    echo "LIST-HEADS MISMATCH"
    diff <(echo "$bundle_refs") <(echo "$expected_refs")
    return 1
  fi
  return 0
}
```

The other check functions follow the same pattern: read the spec section, encode it as one or more shell-level assertions, return non-zero on any violation.

---

## 4. Cross-Implementation Testing

The bundle format is meant to be stable. A bundle written by skill v1.0 must be readable by skill v1.1; a bundle written by skill v1.1 must be readable by skill v1.0 (for the v1.0-defined subset).

### 4.1 The compatibility matrix

```
              | reader v1.0 | reader v1.1
--------------|-------------|------------
writer v1.0   |    ✓        |    ✓
writer v1.1   |    ✓        |    ✓
```

Per [BUNDLE-FORMAT-SPEC.md "Versioning"](BUNDLE-FORMAT-SPEC.md#versioning):

> Version 1.0 will remain a strict subset of any future version. Tools written for v1.0 will work on later versions (they ignore unknown artifacts).

The compatibility matrix verifies this property. Specifically:

- Reader v1.0 against writer v1.1: reader must accept (ignoring unknown columns / unknown artifacts) — that's the forward-compat requirement.
- Reader v1.1 against writer v1.0: reader must accept everything (a v1.0 bundle is a strict subset of v1.1).

### 4.2 The harness

```bash
#!/usr/bin/env bash
# scripts/conformance/cross_version.sh

# Build a v1.0 bundle (use a pinned skill version)
git -C ~/.claude/skills/git-worktree-branch-rationalization checkout v1.0
./scripts/build-bundle.sh /tmp/test-repo
mv /tmp/test-repo-bundle /tmp/v1.0_bundle

# Build a v1.1 bundle (current skill version)
git -C ~/.claude/skills/git-worktree-branch-rationalization checkout v1.1
./scripts/build-bundle.sh /tmp/test-repo
mv /tmp/test-repo-bundle /tmp/v1.1_bundle

# Cross-test
for writer_version in v1.0 v1.1; do
  for reader_version in v1.0 v1.1; do
    git -C ~/.claude/skills/git-worktree-branch-rationalization checkout $reader_version
    if ./scripts/verify-bundle.sh /tmp/${writer_version}_bundle; then
      echo "writer=$writer_version reader=$reader_version: ✓"
    else
      echo "writer=$writer_version reader=$reader_version: ✗"
    fi
  done
done
```

### 4.3 What happens when conformance fails across versions

If a v1.0 reader rejects a v1.1 bundle, the v1.1 bundle has used a feature that's incompatible with v1.0. Per [BUNDLE-FORMAT-SPEC.md "Versioning"](BUNDLE-FORMAT-SPEC.md#versioning), this is a violation of the strict-subset contract. Either:

- The v1.1 spec needs to label the new feature as optional (so v1.0 can ignore it), OR
- The bundle format needs a real version bump to v2.0 (with a `format_version=2.0` key in `index.tsv` or a top-level `VERSION.txt`).

The conformance test catches the violation and the skill's maintainer must decide.

---

## 5. Conformance vs Unit Testing — When Each Is Right

| Property | Unit test | Conformance test |
|---|---|---|
| `slugify_branch("feature/foo")` returns `feature_foo-<hash>` | ✓ | (covered) |
| Every slug in `index.tsv` matches the regex | (impossible — depends on bundle content) | ✓ |
| `verify-bundle.sh` halts on byte-equality mismatch | ✓ | (covered indirectly) |
| `index.tsv` header has exactly 10 columns | (could be unit) | ✓ |
| `git apply` succeeds on the diff (covered by recovery-test.sh) | (integration) | ✓ |
| Reader v1.0 accepts a v1.1 bundle | (impossible — depends on real bundles) | ✓ |
| AGENTS.md "No Script-Based Changes" was followed | (CR review) | (CR review) |

Unit tests are fast and cover the inside of the skill. Conformance tests are slower but cover the external contract. A change to the skill that introduces a non-conforming bundle is detected only by the conformance suite — unit tests can pass while the bundle drifts.

### 5.1 Where to put what

| Question | Where |
|---|---|
| "Does `slugify_branch` produce the right shape?" | unit test in `scripts/integration-test.sh` |
| "Does the bundle written by `build-bundle.sh` satisfy the spec?" | conformance test in `scripts/conformance-check.sh` |
| "Does `verify-bundle.sh` agree with `conformance-check.sh`?" | both — meta-conformance |

The skill has both. `integration-test.sh` runs unit-style tests on a synthetic repo (40 cases). `conformance-check.sh` runs against any real or synthetic bundle.

---

## 6. The 40/40 Integration Test as a Conformance Anchor

The `scripts/integration-test.sh` produces a known-good bundle on a synthetic repo. Running `conformance-check.sh` against this bundle must yield 100% conformance.

### 6.1 The harness

```bash
#!/usr/bin/env bash
# scripts/conformance/anchor_test.sh
set -euo pipefail

# Step 1: run the integration test to produce a synthetic-repo bundle
./scripts/integration-test.sh

# Step 2: locate the bundle
BUNDLE_DIR=$(cat /tmp/integration-test-bundle-path)

# Step 3: run conformance check
./scripts/conformance-check.sh "$BUNDLE_DIR" --strict

# Step 4: verify 100% conformance
if [[ "$?" -ne 0 ]]; then
  echo "ANCHOR FAIL: integration-test bundle is non-conformant"
  exit 1
fi

# Step 5: report
echo "ANCHOR PASS: 40/40 integration test + 100% conformance"
```

### 6.2 The expected output

```
ANCHOR PASS: 40/40 integration test + 100% conformance

Compliance matrix:
              | feature_redact-secrets | agent-broken-attempt | worktree-1 | OVERALL
--------------|------------------------|----------------------|------------|--------
all 17 checks |          ✓             |          ✓           |     ✓      |    ✓

40 conformance checks PASSED. Bundle is contract-conformant.
```

### 6.3 What this anchors

When CI runs the conformance test against the integration bundle and the result is "40/40 + 100%", we have:

- The skill produces conformant bundles (writer side).
- The skill's reader (verify-bundle.sh) accepts the conformant bundle (reader side).
- The bundle round-trips through the recovery recipes (recovery-test.sh).

If any of these regress in a future skill change, the conformance anchor catches it before the change ships.

### 6.4 The anchor as a quality gate

`scripts/conformance/anchor_test.sh` is a recommended Phase 11 (post-handoff) check that the user can run to verify a real run produced a conformant bundle:

```bash
# At end of any production run:
./scripts/conformance/anchor_test.sh \
  --bundle "$BUNDLE_DIR" \
  --report-to "$WORKSPACE/conformance_report.md"
```

The report is included in `handoff_report.md`. A non-conformant bundle is a hard error — the skill's maintainer must investigate.

---

## 7. Conformance Failures and Recovery

If conformance reveals a failure, the bundle is non-conformant. The user needs a path forward.

### 7.1 The failure ladder

| Failure | Severity | Path forward |
|---|---|---|
| Missing `README.md` | Should-warning | Re-run `build-bundle.sh --emit-readme` to regenerate |
| Missing per-branch directory | Must-error | Bundle is broken; re-run Phase 3 |
| Slug mismatch | Must-error | Bundle is broken; the slugify function changed; reconcile |
| Diff sha256 mismatch | Must-error | Diff was not captured correctly; re-run `build-bundle.sh` |
| List-heads mismatch | Must-error | Object bundle was built incorrectly; re-run `git bundle create` |
| Worktree dirty-state mismatch | Should-warning | The worktree drifted between Phase 3 and conformance check; re-snapshot |
| Per-worktree untracked.tar.gz missing despite `dirty_untracked=true` | Must-error | tarball was not generated; re-run worktree capture |

### 7.2 The non-conformant bundle is preserved

Per [SKILL.md Axiom 18](../SKILL.md#the-rationalization-kernel-universal-axioms): "Drop the bundle only at the user's pace." A non-conformant bundle is NOT deleted — the user moves it aside (`mv <bundle> <bundle>.non-conformant`) and re-runs Phase 3 to regenerate.

Per AGENTS.md "RULE NUMBER 1: NO FILE DELETION" — the skill never deletes the non-conformant bundle. The user decides when (if ever) to remove it.

---

## 8. Worked Example — Conformance Check on the Synthetic Bundle

### 8.1 Setup

```bash
$ ./scripts/integration-test.sh
[40/40 PASS]
$ BUNDLE=$(cat /tmp/integration-test-bundle-path)
$ ls "$BUNDLE"
README.md  branches/  index.tsv  object-bundle.pack  worktrees/
```

### 8.2 Run conformance

```bash
$ ./scripts/conformance-check.sh "$BUNDLE"

Conformance check:
  check_toplevel_layout                ✓
  check_slug_naming                    ✓ (3/3 slugs valid)
  check_index_tsv_schema               ✓
  check_index_tsv_consistency          ✓ (8/8 bundle paths resolve)
  check_branch_dirs_exist              ✓ (2/2 branches)
  check_branch_meta_schema             ✓ (2/2 meta files valid)
  check_branch_commits_schema          ✓ (2/2 commits.tsv valid)
  check_branch_diff_sha                ✓ (2/2 sha256 match)
  check_branch_format_patch            ✓ (3 patches across 2 branches; counts match)
  check_worktree_dirs_exist            ✓ (1/1 worktree)
  check_worktree_meta_schema           ✓
  check_worktree_status_porcelain_v2   ✓
  check_worktree_dirty_diffs           ✓
  check_worktree_untracked_artifacts   ✓
  check_readme_required_sections       ✓ (6/6)
  check_backup_ref_byte_equality       ✓ (2/2)
  check_object_bundle_list_heads       ✓

OVERALL: ✓ FULL CONFORMANCE (17/17 checks)
```

### 8.3 What this proves

- The bundle satisfies every clause of [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md).
- Any tool that consumes the bundle per the spec will work.
- A future v1.1 reader will accept this v1.0 bundle.
- A v1.0 reader will accept this v1.0 bundle.

### 8.4 Inducing a failure

To verify the conformance suite actually catches problems, induce one:

```bash
$ rm "$BUNDLE/branches/feature_redact-secrets/diff-vs-merge-base.diff"

$ ./scripts/conformance-check.sh "$BUNDLE"
  check_index_tsv_consistency        ✗ MISSING: branches/feature_redact-secrets/diff-vs-merge-base.diff
  check_branch_diff_sha              ✗ MISSING: branches/feature_redact-secrets/diff-vs-merge-base.diff
OVERALL: ✗ NON-CONFORMANT (2 failures, both MUST-severity)
exit code: 1
```

The conformance suite reliably catches missing artifacts. Restore the bundle to its known-good state:

```bash
$ ./scripts/build-bundle.sh /tmp/test-repo --resume
$ ./scripts/conformance-check.sh "$BUNDLE"
OVERALL: ✓ FULL CONFORMANCE
```

---

## 9. Cross-References

- [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) — the contract the harness verifies
- [TESTING-FUZZING.md](TESTING-FUZZING.md) — orthogonal: stresses bundle robustness vs verifying contract
- [TESTING-METAMORPHIC.md](TESTING-METAMORPHIC.md) — orthogonal: synthesis correctness, not bundle contract
- [SAFETY-MODEL.md](SAFETY-MODEL.md) — the safety chain whose layers conform to the spec
- [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) — recipes whose contract is the spec
- [DECISION-THEORY.md §4](DECISION-THEORY.md#4-worst-case-bounds-on-recovery-success) — recovery bound that assumes spec conformance
- [/testing-conformance-harnesses SKILL.md](../../testing-conformance-harnesses/SKILL.md) — underlying methodology
- [PHASES.md Phase 3](PHASES.md) — bundle creation phase whose output the harness verifies

---

## 10. The Mantra

> **The bundle format is a contract. The conformance harness mechanically verifies every MUST clause. If `conformance-check.sh` returns ✓, downstream tools work. If it returns ✗, the contract is broken, and downstream tools will fail in surprising ways. Run the harness on every bundle. Anchor against the integration test. Tighten the spec when fuzz finds a corner. Never ship a non-conformant bundle.**
