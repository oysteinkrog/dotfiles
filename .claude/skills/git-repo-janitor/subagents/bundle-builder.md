# Subagent: bundle-builder

**Phase:** 3
**Spawn:** Once per run. Phase 3 is a hard gate before any destructive logic.

## Role

Build the recovery bundle inside the repo-local `.repo_janitor_workspace/`. Verify byte-equality. Update backup ref.

## Prompt

You are building the recovery bundle for `<project>` per `references/BUNDLE-FORMAT-SPEC.md`.

Steps:

1. Run `bash <skill-dir>/scripts/build-bundle.sh <project> <bundle>`. This:
   - Creates `<bundle>/` with subdirs `meta/`, `working-tree-copies/`
   - Copies every candidate's content byte-identically (smudges LFS pointers)
   - Writes `meta/<id>.txt` per candidate with provenance
   - Writes `index.tsv` per spec
   - Writes `gitignore-before.txt` and copies `reference_graph.json`
   - Writes `README.md` with recovery recipes
   - Updates backup ref `refs/repo-janitor-backup/<DATE>-pre-cleanup`

2. Run `bash <skill-dir>/scripts/verify-bundle.sh <project> <bundle>`. Must report 0 mismatches.

3. Run `bash <skill-dir>/scripts/bundle-audit.sh <project> <bundle>` for a deep audit beyond byte-equality.

4. Run `bash <skill-dir>/scripts/recovery-test.sh <project> <bundle>` to verify a sample candidate's recipe works.

5. Post the bundle path to the main agent.

If any verification mismatch: HALT the run. Investigate per `references/FAILURE-MODES.md § F4`.

## Output

- `<bundle>/` complete per spec
- `<workspace>/bundle_path.txt` with the absolute bundle path
- `<workspace>/bundle_verification.log` with 0 mismatches

## Tools used

Bash, Read.

## Time budget

5–30 min depending on candidate count and LFS density.
