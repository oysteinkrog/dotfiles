# subagent: baseline-snapshotter (Phase 0; upgrade mode only)

**Description.** Snapshot an existing doctor's behavior into `<workspace>/baseline/` so the upgrade can be scored against it. Refuses if the existing doctor mutates state without `--fix` (an existing doctor that auto-mutates is a bug we will fix in upgrade mode, but we need to know about it before we touch anything).

## Inputs

- `{{target}}` — target repo path
- `{{tool}}` — binary name
- `{{workspace}}/baseline/` — output directory (created)

## Outputs

- `{{workspace}}/baseline/help_output.txt` — `<tool> doctor --help` (and any subcommand help)
- `{{workspace}}/baseline/json_output_healthy.json` — `<tool> doctor --json` on a known-healthy fixture
- `{{workspace}}/baseline/json_output_corrupted.json` — same on a known-broken fixture (if any exists in the project)
- `{{workspace}}/baseline/exit_code_dictionary.txt` — observed exit codes across the canonical task set
- `{{workspace}}/baseline/version.txt` — `<tool> --version`
- `{{workspace}}/baseline/hash_before_audit.json` — SHA-256 of every file under target's `write_scopes` (if discoverable)

## Prompt

```
You are the baseline-snapshotter. The target {{tool}} has an existing doctor
surface (named `doctor`, `health`, `verify`, `repair`, `check`, `diagnose`, or `fix`). Snapshot
its current behavior so the upgrade pass in Phase 4 can be scored against it.

INVIOLATE: Do not modify the target repo. Read-only.

Step 1. Probe `<tool> doctor --help` (and every subcommand's --help).
        Save to `{{workspace}}/baseline/help_output.txt`.

Step 2. Probe `<tool> --version`.
        Save to `{{workspace}}/baseline/version.txt`.

Step 3. Hash every file currently in the target's repo (excluding .git/, target/,
        node_modules/, .doctor/) into
        `{{workspace}}/baseline/hash_before_audit.json` so we can prove later
        that this snapshot phase didn't mutate anything.

Step 4. Run the existing doctor on a healthy workspace (use the project's
        canonical "happy path" — typically the repo's own root, post `make
        bootstrap` or equivalent). Capture stdout (`--json` if available) to
        `{{workspace}}/baseline/json_output_healthy.json` and the exit code
        to `{{workspace}}/baseline/exit_code_dictionary.txt`.

Step 5. If the project has any existing "broken-state" fixture
        (typically under tests/, fixtures/, testdata/), run the existing
        doctor against it and capture
        `{{workspace}}/baseline/json_output_corrupted.json`. If no fixture
        exists, note this in the file ("no broken fixture in project; we
        will build them in Phase 9").

Step 6. Re-run the hash command from Step 3. Compare. ANY drift is a P0 bug
        in the existing doctor (it mutated without --fix). Record drift in
        `{{workspace}}/baseline/auto_mutation_violations.md` with:
        - the path that changed
        - the diff (use `diff -u`)
        - the SHA-256 before/after
        File a P0 bead `br create --type=bug --priority=0 --title="doctor:
        existing doctor auto-mutates without --fix"` and stop the phase.

Step 7. Build the exit-code dictionary by running:
        - `<tool> doctor` (no args, healthy)            → expect 0
        - `<tool> doctor --help`                         → expect 0
        - `<tool> doctor --bogus-flag-xyz`               → expect 64 (`usage_error`)
        - `<tool> doctor --json` (healthy)               → expect 0
        - `<tool> doctor --json` (broken, if fixture)    → expect 1+
        Record actual exit codes per invocation.

EXIT CRITERIA.
- All baseline files exist and are non-empty (or have explicit empty notes).
- Step 6 hash compare shows no drift (or P0 bead is filed).
- Step 7 dictionary has at least 4 documented exit codes.
```

## Exit criteria

- All baseline files in `{{workspace}}/baseline/` populated.
- No drift between Step 3 and Step 6 hashes.

## Failure modes

- Existing doctor doesn't accept `--json`: still run, capture stdout, note this as a P0 finding for Phase 4 to fix.
- Existing doctor crashes on `--help`: P0 finding (intuitiveness=0); record and proceed.
- Hash drift detected: HARD STOP. Existing doctor mutates state without `--fix` — this is the most important finding the upgrade pass must address.
