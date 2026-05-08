Use the Phase 1 skill to run the `transform` stage.

1. Run `./migrate.sh transform`. This invokes `mmetl check slack` and then `mmetl transform slack` with the flags the skill knows about.
2. If mmetl panics on a specific message: add `--discard-invalid-props` to `MMETL_EXTRA_FLAGS` in config.env and re-run.
3. Remember: mmetl is Linux/macOS only. If we're on Windows, stop — either use WSL or move Phase 1 to a Mac/Linux box.
4. After success, show me: number of JSONL lines, number of channels referenced, number of users, and any warnings in the transform log.
