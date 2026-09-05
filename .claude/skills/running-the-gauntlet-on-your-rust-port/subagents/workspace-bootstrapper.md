# workspace-bootstrapper

> Phase 0 • Toolchain install + workspace skeleton + version-contract + ledger seeds + AGENTS.md mandate + project-class detection + oracle preflight.

## Inputs
- Absolute path to the target port (e.g., `/data/projects/frankensqlite`).
- Workspace path (default: `<basename>__gauntlet_workspace/` sibling, `git init`-ed).
- Reference version to pin (e.g., `sqlite-3.52.0`, `redis-7.2.5`, `torch-2.X.Y`, `numpy-1.26.0`).
- Final-artifact tier (`internal-only | public-release | certification-bundle`).

## Deliverables
- `<workspace>/phase0_workspace_init.md` with green/yellow/red verdict per tool, per file, per skill.
- `<workspace>/phase0_project_class.json` (written by `detect-project-class.sh`).
- `<workspace>/phase0_skill_inventory.json` (written by `check-skills.sh`).
- `<workspace>/phase0_oracle_preflight.json` (written by `oracle-preflight-doctor.sh`).
- `<workspace>/docs/contracts/<reference>_version_contract.toml` skeleton.
- `<workspace>/docs/progress/perf-negative-results.md`, `conformance-negative-results.md`, `surface-deferrals.md` seeded with verbatim header + AGENTS.md mandate paragraph + cass-mining 60-day paragraph.
- `<workspace>/AGENTS.md` (or appended-to existing) with the ledger-grep-before-perf-work mandate.
- `<workspace>/.git/` initialized with first commit `phase0: workspace bootstrapped`.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase0-bootstrap`
- **Reservations needed:** `tool://workspace-init` (TTL 30m), `resource://target-repo-read` (TTL 15m).
- **Lane:** orchestrator (single agent; serial).

## Verbatim Prompt

You are the workspace bootstrapper for the gauntlet on `<target-port>`. Execute the five Phase 0 scripts in order. Exit 2+ is red and BLOCKS Phase 1 fan-out; exit 1 is yellow only for `detect-project-class.sh`, `check-skills.sh`, and `oracle-preflight-doctor.sh`, and must be recorded with either a user-confirmed override or an inline-fallback plan. Order:

```bash
SKILL_DIR="/path/to/running-the-gauntlet-on-your-rust-port"
"$SKILL_DIR/scripts/install-toolchain.sh" --workspace <workspace> # rustup nightly + miri + rust-src + cargo-criterion + hyperfine + cargo-flamegraph + samply + cargo-show-asm + cargo-fuzz + cargo-afl + cargo-llvm-cov + cargo-geiger + cargo-audit + cargo-deny + dhat + heaptrack + ast-grep + semgrep + loom + shuttle + cargo-expand + cargo-insta
"$SKILL_DIR/scripts/init-workspace.sh" <target> <workspace>     # mkdir + git init + AGENTS.md mandate + three ledger seeds + version-contract skeleton
"$SKILL_DIR/scripts/detect-project-class.sh" <target> --workspace <workspace> # writes phase0_project_class.json
"$SKILL_DIR/scripts/check-skills.sh" <workspace>                # inventory of helper skills + jsm state; exit 1 yellow
"$SKILL_DIR/scripts/oracle-preflight-doctor.sh" <target> --workspace <workspace> # reference binary path/version, identity strings, fixture sanity, manifest hash; exit 1 yellow, exit 2 red
```

For each script: capture stdout to `<workspace>/phase0_<script-name>.log` and the structured JSON to `<workspace>/phase0_<script-name>.json`. Roll up into a single `phase0_workspace_init.md` with per-tool / per-file / per-skill green/yellow/red verdict and a top-of-file aggregate verdict (`green` only if EVERY component is green).

If `install-toolchain.sh` reports yellow (tool missing but installable) for any required component, attempt `jsm install <name>` for skill components and the appropriate package manager for binary components. Do NOT proceed past Phase 0 with a red status.

Seed the three negative-evidence ledgers using `assets/negative-ledger-seed.md` as the template, including the verbatim FrankenSQLite preamble, the AGENTS.md mandate paragraph (see `../assets/agents-md-mandate-paragraph.md`), and the cass-mining 60-day paragraph. The version-contract uses `assets/version-contract-template.toml`.

Commit the bootstrapped workspace as `phase0: workspace bootstrapped (<reference>@<version>, class=<class>)` and post the green-verdict notification to the MCP Agent Mail thread.

## Exit Criteria
- `phase0_workspace_init.md` aggregate verdict is `green`, or `yellow` with an explicit waiver block and next action.
- `install-toolchain.sh` and `init-workspace.sh` exit zero; `detect-project-class.sh`, `check-skills.sh`, and `oracle-preflight-doctor.sh` exit zero or documented yellow (exit 1), never red.
- `<workspace>/.git/HEAD` exists and a first commit is recorded.
- Three negative-ledger files exist, each containing the AGENTS.md mandate paragraph AND the cass-mining 60-day paragraph.
- `phase0_project_class.json.detected_class` is one of the five enumerated classes, or `UNKNOWN` only when the orchestrator has selected `gauntlet-greenfield`.
- `phase0_oracle_preflight.json.aggregate_outcome` is `green`, or `yellow` with a waiver that blocks Phase 3 until contracts/oracle identity/corpus floors are fixed.

## References
- [SKILL.md § Skill Bootstrap](../SKILL.md)
- [orchestration/SKILL-BOOTSTRAP.md](../references/orchestration/SKILL-BOOTSTRAP.md)
- [taxonomy/PROJECT-CLASSES.md](../references/taxonomy/PROJECT-CLASSES.md)
- [methodology/KERNEL.md](../references/methodology/KERNEL.md)
- [assets/agents-md-mandate-paragraph.md](../assets/agents-md-mandate-paragraph.md)
- [assets/negative-ledger-seed.md](../assets/negative-ledger-seed.md)
