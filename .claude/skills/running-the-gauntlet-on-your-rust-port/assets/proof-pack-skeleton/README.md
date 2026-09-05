# Proof Pack Skeleton

Copy this directory into `artifacts/<bead_id>/proof_pack/` to scaffold a profile-first optimization proof pack per [pattern:150-PROFILE-FIRST-CARD](../../references/patterns/150-PROFILE-FIRST-CARD.md).

## Required contents

```
artifacts/<bead_id>/proof_pack/
├── README.md                      (this file)
├── baseline_profile.flame.svg     <-- cargo flamegraph, BEFORE change
├── baseline_profile.samply.json   <-- samply record, BEFORE
├── candidate_profile.flame.svg    <-- AFTER change
├── candidate_profile.samply.json
├── delta_summary.json             <-- machine-readable per-frame delta
├── correctness.txt                <-- "all oracle E2E pass; selections= byte-identical"
├── invariant_check.txt            <-- "INV-1..INV-7 e-values < 1/α"
├── rerun.sh                       <-- literal command to reproduce, paste-ready
├── rollback.md                    <-- exact commands to revert this change
├── criterion/                     <-- cargo criterion output
├── hyperfine/                     <-- hyperfine output
├── alloc_census/                  <-- dhat-rs / heaptrack output
├── syscalls/                      <-- strace -c output
└── smoke/                         <-- minimal smoke test outputs
```

## The 19-field card

Every proof pack accompanies a profile-first card with all 19 required fields. See [pattern:150-PROFILE-FIRST-CARD](../../references/patterns/150-PROFILE-FIRST-CARD.md) for the schema. Render the card as `card.md` in this directory.

## Required env keys in baseline

Every entry in `baseline_profile.samply.json` and `candidate_profile.samply.json` MUST embed these env keys (verifiable via `jq '.env'`):

- `RUSTFLAGS`
- `FEATURE_FLAGS`
- `MODE` (must be `release-perf`; never `release`)
- `GIT_SHA`
- `PLATFORM`

## Gate
`scripts/apply-ratchet.sh` will reject any kept perf entry whose proof pack is missing any of the required files.
