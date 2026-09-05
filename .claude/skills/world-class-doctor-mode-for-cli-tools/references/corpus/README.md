# Cross-project FM corpus

`known-fms.jsonl` is a curated, hand-vetted set of failure modes that recur across the user's `/dp` projects. Phase 1 archaeology agents query this file via `scripts/query-corpus.py` to seed their FM inventory before doing target-specific analysis.

## File format

One JSON object per line. Fields:

| Field | Type | Required | Purpose |
|-------|------|----------|---------|
| `fm_id` | string | yes | Canonical FM ID (`fm-<subsystem>-<slug>`). |
| `subsystem` | string | yes | One of the canonical subsystems (see GLOSSARY.md). |
| `languages` | list[string] | yes | Languages this FM is known to apply to. Phase 1 filters by intersection with the target's language. |
| `frequency_across_projects` | int | yes | How many distinct projects in the source corpus exhibited this FM. |
| `severity_hint` | string | yes | `P0|P1|P2|P3` — the most severe instance observed. |
| `example_messages` | list[string] | yes | Up to 3 verbatim CHANGELOG/AGENTS.md/incident lines that motivated this entry. |
| `source_projects` | list[string] | yes | Project basenames where this FM was observed. |
| `detector_hint` | string | yes | One-line operational hint: WHAT to check, in agent-actionable terms. |
| `fixer_hint` | string | yes | One-line operational hint: HOW to fix (or "NOT auto-fixable" + manual_remediations note). |

## Curation policy

Entries are added when ANY of:

1. **Cross-project recurrence** — the FM appears in 2+ projects' CHANGELOGs with materially-similar root cause.
2. **High severity in one project** — even if seen only once, P0 entries are kept (e.g., sqlite WAL/SHM drift) because they're the kind of bug a doctor MUST cover.
3. **Architectural pattern** — the FM is a known class (per KERNEL axioms or AGENTS.md guidance) that any doctor in the target's language ecosystem should detect.

Entries are NOT added when:

1. The fix was project-specific UI polish, not a real failure-mode class.
2. The CHANGELOG line was vague (e.g., "various fixes", "stability improvements").
3. The bug was in `cargo`/`go`/dependency code, not in the project's own state.

## Generating / refreshing

Two paths:

1. **Auto-mine baseline**: `scripts/build-corpus.py /tmp/corpus-mine --out references/corpus/known-fms.jsonl` aggregates per-project `mine-changelog.py` outputs. The result is noisy (lots of frequency-1 entries; over-classified to `network` subsystem). **Use this only as a starting point.**

2. **Hand-curated commits** (canonical): the maintainer reviews the auto-mined output, picks ~20-50 high-quality entries, normalizes wording, adds `detector_hint` / `fixer_hint`, and commits the curated file. This is what currently ships. New entries are added as new projects surface novel-but-recurring FMs.

The corpus is intended to grow slowly and intentionally. Better 30 high-signal entries than 300 noisy ones — Phase 1 archaeologists copy from this file as a starting point, so quality matters more than coverage.

## Integration

| Phase | Consumer | How |
|-------|----------|-----|
| Phase 0 | SKILL.md bootstrap | `scripts/query-corpus.py --language "$(jq -r .language phase0_cli.json)" > known_fms_for_language.jsonl` |
| Phase 1 | `subagents/archaeologist.md` | Reads `known_fms_for_language.jsonl` as a SEED list. Each archaeologist (one per subsystem) filters for entries matching its `{{subsystem}}`. Many will already apply to the target verbatim; some will need adaptation; the archaeologist still runs target-specific analysis to catch novel FMs. |
| Phase 2 | `subagents/repair-spec-author.md` | When a corpus FM applies, the spec author can lift the `detector_hint` and `fixer_hint` directly. |

The corpus does NOT replace target-specific analysis — it's a starting point that gives the archaeologist a 50-70% head start on common cases. Novel FMs (target-specific business logic, unusual subsystems) still require manual enumeration.
