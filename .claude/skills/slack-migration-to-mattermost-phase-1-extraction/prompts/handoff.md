Use the Phase 1 skill to run the `handoff` stage.

1. Run `./migrate.sh handoff`. This emits `handoff.md` (human-readable), `handoff.json` (machine-readable contract for Phase 2), and `unresolved-gaps.md`.
2. Read `handoff.json` and summarize: counts, final ZIP path + SHA256, sidecar channels, and the `known_gaps[]` disposition breakdown (native-importable / sidecar-only / manual-rebuild / unrecoverable).
3. Compute `shasum -a 256 workdir/artifacts/import-ready/mattermost-bulk-import.zip` and confirm it matches `handoff.json.final_package.sha256` exactly. (If it doesn't match, Phase 2 will refuse the bundle.)
4. Tell me which Phase 2 stage to run next (`intake`) and exactly what to set in Phase 2's `config.env` for `HANDOFF_JSON` and `IMPORT_ZIP`.
