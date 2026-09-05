# AUDIT-DIRECTORY-LAYOUT.md — The Persistent Artifact Directory

Every audit pass is a **single git commit** in a subdirectory of the project. The directory is sacred history; never delete a prior pass.

---

## Top-level layout

```
<project>/beads_compliance_audit/   # auto-added to project .gitignore by bootstrap-audit.sh
├── .git/                          # init-ed at bootstrap; tracked separately from the project
├── .gitignore                     # excludes raw/ from index? NO — raw logs ARE the evidence
├── README.md                      # what this dir is, how to read it, who owns it
├── manifest.json                  # latest pass metadata; stays at root
├── rubric.md                      # the EXACT scoring rubric used (project-specific tunings here)
├── REPORT.md                      # latest master report (overwritten each pass)
├── synthesis.md                   # latest cross-bead findings (overwritten each pass)
├── remediation.md                 # latest reopen/follow-up bead actions (overwritten each pass)
├── trends.md                      # cross-pass score trends (appended each pass)
├── passes/
│   └── <ISO-8601-UTC>/            # one directory per pass; never deleted
│       ├── manifest.json          # immutable snapshot of pass metadata
│       ├── REPORT.md              # snapshot
│       ├── synthesis.md           # snapshot
│       ├── remediation.md         # snapshot
│       ├── convergence.json       # Phase 10 output for this pass
│       ├── inventory.jsonl        # raw `br list --json` dump
│       ├── doctor.json            # raw `br doctor --json` dump
│       ├── cycles.json            # raw `br dep cycles --json` (must be `[]`)
│       ├── dag.json               # bv --robot-graph (if available)
│       └── beads/
│           ├── bd-abc123/
│           │   ├── show.json      # raw `br show <id> --json`
│           │   ├── git_xref.txt   # commits mentioning the bead ID
│           │   ├── spec.json
│           │   ├── evidence.json
│           │   ├── compliance.json
│           │   ├── theater.json
│           │   ├── test_depth.json
│           │   ├── scorecard.md
│           │   └── raw/
│           │       ├── tests_unit.stdout
│           │       ├── tests_unit.stderr
│           │       ├── coverage.json
│           │       ├── fuzz.stdout
│           │       └── ...
│           └── bd-def456/
│               └── ...
└── scripts/                       # symlinks to this skill's runner scripts (optional convenience)
```

---

## Naming conventions

- **Pass IDs:** ISO-8601 UTC, hyphen-separated for filesystem safety: `2026-05-05T12-00-00Z`. The colons in standard ISO are problematic on Windows; replace with hyphens.
  - **Collision suffix:** when two passes start in the same UTC second (e.g. portfolio audits triggering concurrent bootstraps), `bootstrap-audit.sh` appends `_<4-hex>` (16-bit `$RANDOM` slice) until `mkdir` succeeds atomically: `2026-05-05T12-00-00Z_a3f4`. `validate-audit-dir.py`'s `PASS_DIR_RE` accepts both forms; downstream parsers must too. This protects the "audit dirs are sacred" invariant — without the suffix, the second pass's `mkdir -p` would silently succeed on an existing dir and the writes would race-clobber the first pass's manifest, scorecards, and convergence.json.
- **Bead directories:** use the bead ID verbatim (e.g., `bd-abc123`). Never rename — the ID is the cross-reference key.
- **Raw log files:** `<test-type>.<stream>` — e.g., `tests_unit.stdout`, `fuzz.stderr`, `e2e.log`.
- **Scorecard:** always `scorecard.md`; never date-stamp it inside the pass dir (the pass dir already has the date).

---

## Git policies for the audit dir

- Each pass = exactly **one commit** at the end of the run. Mid-pass commits scramble history.
- Commit message format:
  ```
  audit pass <ISO-UTC>: <total_beads> beads, <false_closed_count> false-closed, score median <X>

  Phase 1: ...
  Phase 9: created <N> completion-debt beads, reopened <M>
  Convergence: <true|false>
  ```
- **Never push to the project's remote** unless the user explicitly opts in. The audit dir is local-by-default. Even though it lives inside the project tree, `bootstrap-audit.sh` writes a `.gitignore` entry so the project's git never sees it.
- **Never** `git reset --hard` or `git rebase` history — every pass must remain visible.
- `.gitignore` for the audit dir is intentionally minimal:
  ```
  # Nothing — raw logs are evidence and must be tracked.
  # Exception: oversized binary blobs (>10MB) get LFS or a manifest entry.
  ```
- If a raw log is too large for git (>10MB), write a `.lfs-pointer` or summarize it in `compliance.json` with `stdout_path: "raw/<file>.summary.txt"` and a separate `raw/<file>.full.txt.sha256` checksum.

---

## How to read the audit dir

For someone (human or agent) opening this dir cold:

1. Read `README.md` first — it summarizes what this dir is and who maintains it.
2. Read top-level `REPORT.md` for the latest verdict.
3. Read `trends.md` for the score-over-time picture.
4. Drill into `passes/<latest>/` for per-bead detail.
5. Drill into `passes/<latest>/beads/<id>/scorecard.md` for a specific bead.
6. Follow citations from the scorecard into `evidence.json`, `theater.json`, etc.
7. Cross-reference `synthesis.md` for integration-level findings.

Every artifact has enough self-context to stand alone. No artifact says "see prior conversation" — everything is written down.

---

## Resuming an audit

When the user invokes the skill on a project that already has an audit dir:

1. Read top-level `manifest.json` to understand the prior state.
2. Confirm with user: "Audit dir exists with N prior passes; latest was <UTC> with verdict <X>. Run a new pass?"
3. If yes → create a new `passes/<new-UTC>/` and start at Phase 1 with the new pass.
4. If the user wants to **resume an interrupted pass** (rare), look for the latest pass dir with `manifest.json#phase_status` showing not-all-complete and continue from there. Note in the new manifest that this pass was resumed.

---

## Multi-project audit collections

If you audit many projects, the audit dir lives inside each project at `<project>/beads_compliance_audit/`:

```
~/projects/
├── frankensqlite/beads_compliance_audit/
├── beads_rust/beads_compliance_audit/
└── ntm/beads_compliance_audit/
```

A meta-script can roll up `REPORT.md` from each into a portfolio view:

```bash
for dir in ~/projects/*/beads_compliance_audit; do
  jq -r '"\(.project_path): \(.bead_counts.closed) closed, \(.convergence.new_false_closed_count) new false-closed"' "$dir/manifest.json"
done
```
