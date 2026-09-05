# Contract Migrations

Each major-version bump of `doctor_contract_version` is documented here. `scripts/migrate-contract.sh --from <a> --to <b>` reads this file and applies the mechanical changes.

## Format

Each transition is a section heading of the form `## <from> → <to>`. Inside, list one directive per line:

- `rename: <old>=<new>` — verbatim string substitution across `*.md`, `*.json`, `*.sh`, `*.py` (excluding CHANGELOG.md and this file).
- `rename-flag: --old-flag=--new-flag` — same as `rename:` but signals the change is a CLI flag rename (cosmetic; same applied behavior).
- `rename-exit-code: <code>:<old_name>=<new_name>` — renames the exit-code symbolic name in `capabilities --json::exit_codes` and templates.
- `field-required-add: <schema>.<field>:<default>` — INFORMATIONAL only; the script logs that an agent must hand-add the field to all schemas, templates, and per-recipe examples. Mechanical addition is unsafe (would corrupt JSON examples that have specific intent).

## Conventions

- `<from>` and `<to>` follow `MAJOR.MINOR` (no patch). A patch bump never requires migration.
- A single transition section MAY contain multiple directives; they apply in document order.
- Name each transition explicitly. To migrate `1.0 → 3.0`, run `1.0 → 2.0` and then `2.0 → 3.0`; the helper does not infer or apply intermediate sections.
- This file is the source-of-truth. Humans add transitions; the script applies them.

---

## 1.0 → 2.0

_(no transition recorded yet — the contract is still at 1.0. When 2.0 ships, list the directives here. Example placeholder shown below; remove when populating real entries.)_

```
EXAMPLE-PLACEHOLDER (delete this code block when 2.0 ships)

- rename-flag: --legacy=--quick
- rename-exit-code: 6:online_required=network_required
- field-required-add: report.json.confidence:1.0
```

---

## 2.0 → 3.0

_(future)_

---

## How to add a transition

1. Decide the contract change (e.g., rename `--legacy` to `--quick`).
2. Open this file.
3. Add (or extend) the appropriate `## <from> → <to>` section.
4. List the directives in document order.
5. Run `scripts/migrate-contract.sh --from <from> --to <to> --dry-run` to preview changes.
6. Re-run without `--dry-run` to apply.
7. Commit the docs changes + the bumped `doctor_contract_version` in `assets/capabilities-template.json` together.
