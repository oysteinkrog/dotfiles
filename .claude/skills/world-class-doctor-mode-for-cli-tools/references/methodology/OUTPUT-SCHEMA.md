# Output Schema — Per-Run Artifacts

Every invocation of `<tool> doctor` (default `diagnose`, or `fix`) creates `.doctor/runs/<ISO8601>__<run-id>/` inside the target repo. This file pins what's inside.

The directory is **append-only** — once written, doctor never edits it. Only `doctor gc --before <date>` can prune entire run directories, and only with `--yes` and an explicit cutoff.

`<run-id>` is `sha256(target_sha + ISO8601_utc_seconds)[..6]` — deterministic up to the second so concurrent runs in the same second naturally collide and the second one bumps the seconds counter.

---

## Layout

```
.doctor/
├── runs/
│   └── 2026-05-06T14-23-07Z__a3f9b2/
│       ├── report.json                  ← findings + summary; matches CLI-SURFACE.md schema
│       ├── report.md                    ← human-readable narrative
│       ├── scorecard.json               ← per-detector × per-dimension scores this run
│       ├── actions.jsonl                ← one line per mutate() call
│       ├── backups/                     ← verbatim backups (preserves dir layout, mtime, mode)
│       ├── stderr.log                   ← captured stderr (rotated per run)
│       ├── stdout.json                  ← copy of report.json (or fix output) for replay
│       └── undo.sh                      ← idempotent shell script that calls `doctor undo <id>`
├── latest -> runs/2026-05-06T14-23-07Z__a3f9b2     ← symlink (atomically updated)
└── scorecard_history.jsonl              ← one line per run; trend analysis input
```

`.doctor/` is added to `.gitignore` of the target repo on first run if missing.

---

## `report.json`

See [CLI-SURFACE.md § JSON shapes § diagnose --json](CLI-SURFACE.md). Same shape regardless of whether the doctor was invoked with `--fix`, but `fix` runs add `actions_taken`, `bytes_backed_up`, `actions_jsonl_path`, `backups_dir`, `undo_command`.

`schema_version` is required. Schema URL is in `capabilities --json::report_schema`.

---

## `report.md`

A human-readable narrative version of `report.json`. The format is:

```markdown
# `br doctor` — 2026-05-06T14:23:07Z (run a3f9b2)

**Status:** findings present (`exit 1`)
**Duration:** 412 ms
**Target SHA:** deadbeef...
**Subsystems checked:** state_files, configs, schemas, caches, concurrency_primitives

## Summary

3 findings (1 P0, 2 P2). All are auto-fixable.

## Findings

### P0 — fm-db-schema-version-mismatch (state_files)

The on-disk database schema is at version 7 but this binary was built against
version 8. Running with version 8 logic against a version 7 schema will
silently corrupt new rows.

- Evidence: `.beads/beads.db` — sqlite_master row "schema_version=7"; expected 8.
- Remediation: `br doctor --fix --only fm-db-schema-version-mismatch`
- Auto-fixable: yes (writes `.beads/beads.db` via the project's migration path)

### P2 — fm-jsonl-tombstone-drift (state_files)

...

## What to do next

```bash
br doctor --fix          # Fix all 3 findings, with backups.
br doctor explain fm-db-schema-version-mismatch  # See full evidence.
br doctor undo 2026-05-06T14-23-07Z__a3f9b2  # If --fix went wrong.
```
```

---

## `scorecard.json`

```jsonc
{
  "schema_version": "1.0",
  "run_id": "2026-05-06T14-23-07Z__a3f9b2",
  "tool": "br",
  "doctor_version": "1.0.0",
  "started_at": "2026-05-06T14:23:07Z",
  "scoring_method": "frequency_x_blast_radius_weighted_average",
  "by_failure_mode": {
    "fm-db-schema-version-mismatch": {
      "agent_intuitiveness":     950,
      "agent_ergonomics":        950,
      "automation_degree":       1000,
      "data_safety":             1000,
      "idempotence":             1000,
      "reversibility":           1000,
      "diagnostic_specificity":  900,
      "blast_radius_containment": 950,
      "observability":           1000,
      "test_coverage_of_repair": 1000,
      "median":                  983,
      "evidence": {
        "fixture": "tests/doctor_fixtures/fm-db-schema-version-mismatch/",
        "spec":    ".doctor_workspace/analysis/repair_specs/fm-db-schema-version-mismatch.md",
        "test":    "tests/doctor_fixtures/run_all.sh::fm-db-schema-version-mismatch"
      }
    }
  },
  "aggregate": {
    "score":              927,
    "median_per_fm":      900,
    "p10":                820,
    "p50":                900,
    "p90":                990,
    "weight_method":      "frequency_x_blast_radius"
  },
  "deltas": {
    "vs_pass_n_minus_1": {
      "median_per_fm":  +35,
      "regressions":    [],
      "improvements":   ["fm-db-schema-version-mismatch:+200", "fm-jsonl-tombstone-drift:+150"]
    }
  }
}
```

The aggregate `score` is computed by `scripts/scorecard.py` using:

```
aggregate = sum_over_FM(median_per_FM × frequency_FM × blast_radius_FM) /
            sum_over_FM(frequency_FM × blast_radius_FM)
```

Frequency is from CASS mining; blast radius is from the rubric. Both are clamped to [0.5, 2.0] to limit pathological reweighting.

---

## `actions.jsonl`

One line per `mutate()` call. Each line:

```jsonc
{"path":".beads/issues.jsonl","op":"WriteFile","before_hash":"sha256:abc...","after_hash":"sha256:def...","started_at_ns":12345678,"finished_at_ns":12399999,"run_id":"2026-05-06T14-23-07Z__a3f9b2","fixer_id":"fm-jsonl-tombstone-drift","ok":true}
```

If a mutation failed and was rolled back inside `mutate()`, the line records `ok: false` and includes `error: "..."` and `rolled_back: true`. The `actions.jsonl` is the single source of truth for `doctor undo` — undo reads it in reverse order.

The file is append-only; `mutate()` `fsync`s after each line.

### Per-op fields

In addition to the common fields shown above, op-specific fields appear:

- `Rename` ops include `"rename_to": "<destination-path>"` (the target path from `Op::Rename { to: ... }`). `doctor undo` reads `rename_to` and reverses the move.
- Failed mutations (rolled-back) include `"error": "<message>"` and `"rolled_back": true` alongside `"ok": false`.
- `Chmod` ops should include the previous mode in the `before_hash` (or a separate `before_mode` field) so undo can restore. The optional `Chown` variant (rarely implemented; see [MUTATE-CHOKEPOINT.md § The op enum](MUTATE-CHOKEPOINT.md)) follows the same pattern with `before_owner`. Implementations may extend the schema here per their needs.

Concrete examples for each op (WriteFile, DbMigrate failed+rolled-back, SymlinkAtomic, Rename) are in [`assets/actions-jsonl-line-template.json`](../../assets/actions-jsonl-line-template.json) — copy-paste-ready shapes for an emitter implementation.

---

## `backups/`

Verbatim file backups, organized to mirror the repo's directory layout:

```
backups/
├── .beads/
│   ├── beads.db         ← byte-identical copy as of `before_hash`
│   └── issues.jsonl
└── ~/.config/<tool>/    ← if the doctor wrote into XDG_CONFIG_HOME
    └── config.toml
```

Permissions and mtime are preserved (`shutil.copy2` / `cp --preserve` / `os.Chmod` after copy). For DB-row backups, the path is `backups/__db__/<table>/<rowkey>.json` containing the original row + a `_meta` block with column types.

---

## `undo.sh`

A self-contained POSIX-compatible shell script that calls `<tool> doctor undo <run-id>`. Idempotent.

```bash
#!/usr/bin/env bash
set -euo pipefail

# undo.sh — restore from .doctor/runs/2026-05-06T14-23-07Z__a3f9b2/backups/
# Generated by br doctor 1.0.0 at 2026-05-06T14:23:07Z.

cd "$(dirname "$0")/../../.."   # cd to repo root

# Idempotence: if the actions.jsonl has been replayed, exit 0.
if br doctor ls --json | jq -er '.runs[] | select(.run_id=="2026-05-06T14-23-07Z__a3f9b2") | .undo_complete' | grep -q true; then
    echo "undo already complete for run 2026-05-06T14-23-07Z__a3f9b2" >&2
    exit 0
fi

br doctor undo 2026-05-06T14-23-07Z__a3f9b2 --strict "$@"
```

The script is gitignored under `.doctor/`. It's regenerated each run.

---

## `latest`

A symlink to the most recent run directory. Updated atomically via `mutate(SymlinkAtomic { target: <new-run-dir> })` (which uses `symlink` to a temp name + `rename` for atomicity).

`<tool> doctor undo latest` resolves the symlink and undoes that run.

---

## `scorecard_history.jsonl`

One line per `<tool> doctor` run (or just `<tool> doctor health` if cheap-mode is wired). Each line:

```jsonc
{"run_id":"2026-05-06T14-23-07Z__a3f9b2","started_at":"2026-05-06T14:23:07Z","tool_version":"0.4.7","doctor_version":"1.0.0","ok":false,"total_findings":3,"by_severity":{"P0":1,"P2":2},"aggregate_score":927,"actions_taken":0,"duration_ms":412,"health_p95_ms":187,"panics_caught":0}
```

`scripts/scorecard.py` reads this for trend analysis. CI compares the latest line against an earlier baseline and fails the build if `aggregate_score` dropped > 50 points without an explicit acknowledgment in `regression_alerts.md`.

---

## `stderr.log`

Captured stderr from the run, suitable for forensic review. Rotated per run; never written to outside `<run-dir>`.

When `--robot` or `--json` is set, `stderr.log` still receives diagnostic output; only stdout is forced to be data-only.

---

## `stdout.json`

A copy of the JSON written to stdout for replay / forensic / agent-replay purposes. Identical to `report.json` for `diagnose` runs and to the merged report+actions for `fix` runs.
