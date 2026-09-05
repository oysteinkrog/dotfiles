---
name: bundle-builder
description: Phase 3 — create the recovery bundle (backup refs + diffs + meta + index + README), verify byte-equality. Gate before destructive phases.
---

# Bundle Builder

Owns Phase 3. The irreversibility gate. This phase MUST complete with byte-equality verified before any classification or destructive action runs. If the bundle is wrong, the entire run is unsafe.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle directory; default `<project-parent>/<basename>-stash-archive-<YYYY-MM-DD>/`

## Workflow

1. Run `scripts/build-bundle.sh {PROJECT}` with `BUNDLE_OVERRIDE` env if user provided a custom path.
2. Verify with `scripts/verify-bundle.sh {PROJECT}`. Exit-non-zero halts the run.
3. Spot-check 3 random inventory rows by re-deriving `git stash show -p --binary` from the row's stable SHA and diffing against the bundle's stored diff:
   ```bash
   awk -F'\t' 'NR > 1 {print $1 "\t" $3}' inventory.tsv | shuf -n 3 |
   while IFS=$'\t' read -r n sha; do
     diff <(git stash show -p --binary "$sha") "$BUNDLE/diffs/$(printf '%03d' "$n").diff"
   done
   ```
   All diffs must be empty.

## Critical rules

- **Use `git stash show -p --binary`, NOT `git format-patch`.** The latter is not the stash recovery diff and can be empty or wrong for stash merge commits; plain `-p` omits tracked binary payloads (see `references/FAILURE-MODES.md` F1/F17).
- **Never delete the bundle**, even on user request. The user manages bundle lifecycle.
- **If verification fails, HALT the run immediately.** Do not attempt to fix bundle artifacts on the fly; surface to user.

## Coordination

- File reservation: `paths=[".git/refs/stash-backup/**", "{BUNDLE}/**"]`, `exclusive=true`, `reason="stash-janitor-phase3"`.
- Thread id: `stash-janitor-<run-id>`.

## Quality gates

- [ ] Every row in `inventory.tsv` has a corresponding `refs/stash-backup/<NNN>` ref
- [ ] Every row has a `<bundle>/diffs/<NNN>.diff`
- [ ] Every row has a `<bundle>/meta/<NNN>.txt`
- [ ] `<bundle>/index.tsv` has the same row count as `inventory.tsv` plus a header
- [ ] `<bundle>/README.md` documents the `git format-patch` footgun
- [ ] `bundle_verification.log` has zero `MISMATCH` and zero `MISSING` lines

## Exit criteria

`verify-bundle.sh` exits 0; main agent posts "bundle complete and verified at <path>" to user.
