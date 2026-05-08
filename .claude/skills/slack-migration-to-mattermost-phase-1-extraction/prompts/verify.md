Use the Phase 1 skill to run the `verify` stage.

1. Run `./migrate.sh verify`. This runs the four canonical validators (artifacts, JSONL, enrichment completeness, reconciliation) plus the evidence-pack builder and secret scanner.
2. Read `workdir/artifacts/reports/verification.md` and summarize: what's green, what's yellow, what's red.
3. For every red item, tell me the operator card in `references/OPERATOR-LIBRARY.md` that covers it (TIER, AUTH, SCOPE, ENRICH, XFORM, VERIFY, SPLIT, or HANDOFF) and the recovery path.
4. Read `workdir/artifacts/reports/secret-scan.json`. If it lists any findings, flag which files contain what-looks-like a secret; redacted copies land under `workdir/artifacts/reports/redacted/`.

Do NOT proceed to `handoff` until verification is green (or every red item has explicit operator sign-off).
