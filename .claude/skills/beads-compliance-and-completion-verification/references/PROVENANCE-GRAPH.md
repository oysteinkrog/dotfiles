# PROVENANCE-GRAPH.md — Every artifact's source chain

> **Premise:** if a regulator, customer, or future agent asks "where did this verdict come from?" — we answer in seconds, not days. Provenance is the difference between an audit and an opinion.

---

## What we record

For every artifact in the audit dir, the provenance graph captures:

- **Source files** (project-local file paths + line ranges).
- **Commit SHAs** (project + skill versions).
- **Tool versions** (br, rg, jq, python, the shell, the OS).
- **Rubric SHA** at time of generation.
- **Subagent ID** (model + session) that wrote it, if any.
- **Cross-references** (which other artifact cites or derives from it).

This isn't aspirational — it's what `manifest.json`, the `passes/<UTC>/` dirs, and the per-bead JSON files already encode. PROVENANCE-GRAPH formalizes the queries.

---

## The graph schema

Nodes are artifacts; edges are derivations.

```
project_repo:<sha>
        │
        ├── inventory.jsonl  (Phase 1; from `br list --json`)
        │       │
        │       └── per-bead/show.json
        │             │
        │             ├── spec.json       (Phase 2; from extract-spec.py)
        │             ├── evidence.json   (Phase 3; from gather-evidence.sh + project files at <sha>)
        │             ├── compliance.json (Phase 4; from re-running tests in env <env_sha>)
        │             ├── theater.json    (Phase 5; from theater-scan.sh + anomaly-scan.sh)
        │             ├── test_depth.json (Phase 6; from coverage tool + fuzz log + golden diff)
        │             └── scorecard.md    (Phase 8; from rubric.md + above)
        │
        ├── synthesis.md     (Phase 7; from union of per-bead/*.json)
        ├── REPORT.md        (Phase 8; from union of scorecards + synthesis)
        ├── remediation.md   (Phase 9; from REPORT.md + br write actions)
        └── convergence.json (Phase 10; from current pass + prior pass)
```

Every node has metadata:
- `created_at` (ISO-8601 UTC)
- `created_by` (subagent ID or script path + version)
- `derived_from` (list of parent node IDs)
- `derived_via` (the script/subagent name)

This metadata is in the JSON itself; you don't need a separate graph DB.

---

## Querying provenance

### "Why is this bead's score 720?"

1. Read `passes/<UTC>/beads/<bead-id>/scorecard.md`.
2. The scorecard cites: rubric.md sections + spec.json checklist items + evidence.json citations + compliance.json checks + theater.json findings + test_depth.json metrics.
3. Each citation includes `path:line_range` and `commit_sha`.
4. `git show <sha>:<path>` reproduces the exact line range as evidence.

The provenance is **read-through** — you can jump from the score to the source code in 3 hops.

### "Did this audit verdict change after the rubric was updated?"

```bash
# rubric_sha256 in pass <UTC>/manifest.json was abc...
# new rubric_sha256 is def...
# re-score the pass under the new rubric:
python3 scripts/score-bead.py passes/<UTC>/beads/<bead-id> \
  --rubric audit/rubric.md \
  --synthesis passes/<UTC>/synthesis.md
# Compare to the original scorecard.
```

If the score moved, the rubric change had effect; record both scores in `convergence.json` for the next pass.

### "Which closed beads were the top contributors to last release's incident?"

1. Time-machine audit AS-OF the incident commit (`scripts/time-machine-audit.sh /repo <incident-sha>`).
2. Filter the resulting REPORT.md to beads tagged with the affected feature label.
3. For each, walk back through evidence.json → which file:line did this bead claim to fulfill, and was that line still present at the incident SHA?

Phase 9 of POST-MORTEM-MODE.md uses exactly this provenance walk.

---

## Tamper detection

The audit dir is git-tracked; every pass is one commit. Provenance integrity rests on:

- **Commit hashes** — git's content-addressed model means any rewrite is detected by hash mismatch.
- **rubric_sha256** in manifest cross-checks the file (caught by `validate-audit-dir.py`).
- **Append-only log** of remediation actions in `remediation.md` (every line dated).

For high-stakes audits, layer on top:

- **Signed commits** in the audit dir (`git commit -S`); enforce in branch protection.
- **External timestamps** via OpenTimestamps for each pass's HEAD commit (so a rewrite is provably *after* the recorded time).
- **Mirror the audit dir** to a write-once storage (S3 with object-lock; OCI registry with `--immutable`).

See `references/ANTI-CORRUPTION.md` for the full tamper-detection playbook.

---

## Provenance for compliance evidence packs

`COMPLIANCE-EVIDENCE-PACK.md` describes bundling audit artifacts for SOC2 / HIPAA / PCI delivery. The provenance graph is the spine:

```
compliance_evidence/
└── SOC2-CC6.1/
    ├── manifest.json              # which beads, which controls, which artifacts
    ├── audit_passes/              # symlinks to passes/<UTC>/REPORT.md
    ├── source_snapshots/          # git archive of cited files
    └── chain_of_custody.md        # every step + agent + timestamp
```

A regulator can verify any claim by walking the graph; they don't have to take our word for it.

---

## Provenance and the Bayesian extension

`VERIFICATION-UNDER-UNCERTAINTY.md` adds posteriors. Posterior provenance:

- **Prior:** which dataset of historical Phase 4 verdicts produced this prior?
- **Likelihood:** which evidence pack updated the prior?
- **Posterior:** the integrated value, plus the conformal interval.
- **Calibration set:** which spot-check residuals were used?

All of these are first-class provenance nodes. A claim "P(this bead is truly done) = 0.82" without provenance is a hallucination; with provenance, it's a measurement.

---

## Anti-patterns

- **Storing evidence in CI artifacts that expire.** Use the audit dir + git for provenance, not GitHub Actions artifacts (90-day retention).
- **Citing tool versions as ranges** ("rg 13.x"). Always pin the patch version.
- **Reusing UTC timestamps as primary keys.** Two passes in the same second collide. Use timestamp + nanosecond OR timestamp + content hash.
- **Hand-editing scorecards.** Breaks provenance. If you find a wrong scorecard, fix the rubric / evidence and re-run; never edit the artifact.

---

## Operator pairing

`⊧ PROVENANCE` (added in this expansion) — every artifact citation must trace to a source. Pairs with `§ ANCHOR` (anchor to verbatim quotes in the bead body) and `⌬ HARMONIZE` (the score arithmetic must trace through the rubric arithmetic line by line).
