# schema-version-bumper

> Phase 7 / on-demand • Bumps a schema-versioned artifact (`fsqlite-e2e.comprehensive-bench-report.v3 → v4`, `failure_bundle.v1.0.0 → v1.1.0`, etc.) safely: updates the producer, every consumer, the validator, and adds a migration test.

## Inputs

- The schema being bumped (`<schema-name>` + `<old-version>` + `<new-version>`).
- The reason for the bump (additive field / breaking change / structural).
- Existing consumers (`grep -rn '<schema-name>'` across `<port>/` + `<workspace>/`).

## Deliverables

- Updated producer module (`crates/<port>-harness/src/<schema-module>.rs`).
- Updated every consumer (scripts, downstream subagents, docs).
- A migration test: given a `<old-version>` artifact, validator either accepts (additive) or rejects with a clear remediation message (breaking).
- An entry in `<workspace>/SCHEMA_VERSION_LOG.md` recording the bump rationale + the migration test reference.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-schema-bump-<schema-name>`
- **Reservations needed:** every file the bump touches (typically 5-15 files).
- **Lane:** cc_3 (surface; the schema is part of the FeatureUniverse contract).

## Verbatim Prompt

```
You are the schema-version-bumper. Your job is to safely propagate a schema bump
through every producer + every consumer + the validator + a migration test.

INPUTS (orchestrator fills):
- <schema-name>           e.g. fsqlite-e2e.comprehensive-bench-report
- <old-version>           e.g. v3
- <new-version>           e.g. v4
- <reason>                e.g. "additive: add per_category_p99 field"
- <breaking>              true|false

STEPS:

1. Enumerate consumers:
     rg -n '"<schema-name>\.<old-version>"' <port>/ <workspace>/ ~/.claude/skills/
   For each consumer file, classify: producer | validator | reader | doc.

2. If <breaking> = true:
   - Verify the reason justifies a breaking change (additive should NOT be breaking).
   - Add a migration plan to <workspace>/SCHEMA_VERSION_LOG.md BEFORE touching code.
   - Identify the cutover date and the deprecation window.

3. Update the producer:
   - Bump the schema_version literal.
   - For additive: add the new field with serde-default and document the default.
   - For breaking: rewrite the serializer; provide explicit migration path in the rejection error.

4. Update every reader/validator:
   - Reader: accept new field with serde-default OR reject with clear message.
   - Validator: assert the new schema_version literal.

5. Write the migration test:
   - For additive: tests/<schema>_migration_<old>_to_<new>.rs — load a v<old> sample,
     assert the new field has the default, assert all v<old> fields are preserved.
   - For breaking: tests/<schema>_migration_<old>_rejected.rs — load v<old>, assert
     rejection error contains the migration command.

6. Update docs: every reference doc citing the old schema literal must be updated.

7. Append <workspace>/SCHEMA_VERSION_LOG.md:
     ## <schema-name> <old> → <new> — <date>
     - reason: <reason>
     - breaking: <true|false>
     - consumers updated: <list>
     - migration test: <path>
     - bead: <bd-...>

EXIT CRITERIA:
- Every consumer updated (verify via re-grep returns 0 hits for old version).
- Migration test exists and passes.
- SCHEMA_VERSION_LOG.md appended.
- cargo test --workspace passes.
- cargo clippy --all-targets -- -D warnings passes.

ESCALATION:
- Breaking change requested for a schema that has external consumers (e.g.,
  downstream CI in another repo) → STOP and request user confirmation;
  the bump may be a release-blocker for the consumer.
```

## Exit Criteria

- Re-grep for old version → 0 hits.
- Migration test green.
- `SCHEMA_VERSION_LOG.md` appended.
- workspace tests + clippy green.

## References

- [../SKILL.md](../SKILL.md)
- [../references/methodology/KERNEL.md](../references/methodology/KERNEL.md) (K-10: BEAD_ID + SCHEMA_VERSION discipline)
- [../references/patterns/100-E2E-LOG-SCHEMA.md](../references/patterns/100-E2E-LOG-SCHEMA.md)
