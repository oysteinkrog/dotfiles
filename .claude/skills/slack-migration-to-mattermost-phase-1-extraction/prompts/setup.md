Use the Phase 1 skill to run the `setup` stage.

1. Make sure `./scripts/doctor.sh` comes back green first. If required items are red, run `./scripts/bootstrap-tools.sh` and re-check.
2. Run `./migrate.sh setup`. This creates the `workdir/artifacts/{raw,enriched,import-ready,reports}/` tree and re-validates tooling.
3. Read the stdout summary from `migrate.sh setup` (it logs which required/optional tools were found). Then re-run `./scripts/doctor.sh` one more time and confirm: required tools resolved, config.env loaded, no empty required fields.
4. Tell me: are we ready for the `export` stage? If not, what's still blocking?
