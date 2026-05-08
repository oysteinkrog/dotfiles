Use the Phase 1 skill to run every stage end-to-end: `setup` → `export` → `enrich` → `transform` → `package` → `verify` → `handoff`.

Between each stage, PAUSE and show me a one-paragraph summary: what ran, what artifacts exist now, what any validator reports said. Do not silently proceed. If any stage emits a red/blocking condition, stop and wait for my instruction.

At the very end, give me:
- the final ZIP path + SHA256
- absolute path of `handoff.json`
- the cp-able `HANDOFF_JSON=` and `IMPORT_ZIP=` lines for Phase 2's config.env
