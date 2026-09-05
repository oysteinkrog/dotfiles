# Extended `/dp/` Exemplars

Beyond the 8 canonical exemplars in [exemplars.md](exemplars.md), the `/dp/` tree contains many more projects with patterns worth absorbing. Each entry below: the project, the agent-ergonomic surface it ships, the lift to take into the doctor methodology.

---

## `dsr` (Doodlestein Self-Releaser)

**Path:** `/dp/doodlestein_self_releaser/`

Releases binaries when GitHub Actions is throttled. Surface includes `dsr release`, `dsr verify-build`, `dsr publish`. Failure modes: build-host SSH key drift, missing release artifact, signature mismatch.

**Lift for doctor methodology:**
- The `dsr` install workflow uses bundled trust anchors — informs Pattern 11 (installer doctor).
- `dsr` has a per-platform manifest similar to our installer-pattern trust manifest.
- `dsr verify-build` semantics (verify a build's reproducibility) parallel `<tool> doctor verify-install`.

**File pointer:** `/dp/doodlestein_self_releaser/SKILL.md`, `/dp/doodlestein_self_releaser/src/act_runner.sh`.

---

## `ntm` (Multi-agent tmux orchestrator)

**Path:** `/dp/ntm/`

Spawns swarms of AI coding agents in tmux panes. Each pane has its own state, the orchestrator has cluster state. Failure modes: stale pane references, dead PIDs in roster, marching-orders queue corruption.

**Lift:**
- Pattern 4 (daemon-cli) example: `ntm` runs an orchestrator daemon; `ntm doctor` (when built) would probe pane liveness.
- "Robot-mode" surface in `ntm` is similar to `caam robot` — informs `--robot-*` flag conventions.
- Per AGENTS.md `ntm` has well-documented "robot-mode state" — agents call `ntm robot-state --json` to inspect cluster state without touching panes.

**File pointer:** `/dp/ntm/cmd/ntm/`, AGENTS.md § ntm.

---

## `wezterm` (Terminal multiplexer for agent swarms)

**Path:** `/dp/wezterm/` (forked from upstream)

Manages tmux-style multiplexed sessions; user runs huge swarms (512GB RAM). Failure modes: mux server unresponsive, scrollback bloat, persistent session corruption.

**Lift:**
- `wezterm cli` is a strong "robot mode" example: every command is JSON-emitting and non-interactive when stdout is piped.
- The mux-server health-check pattern — `wezterm cli list --format=json` — is a Pattern 4 example: the daemon stays running, the CLI client probes it.
- Sessions are persistent state files; `wezterm` has its own recovery semantics worth absorbing into Pattern 4 recipes.

**File pointer:** `/dp/wezterm/wezterm-cli/`, AGENTS.md § wezterm.

---

## `installer-workmanship` skill outputs

**Path:** `/dp/agentic_coding_flywheel_setup/install.sh` and the `installer-workmanship` skill.

Production-grade `curl | bash` installers. Failure modes: incomplete install, modified shell rcs, partial extraction.

**Lift:**
- The installer's signed manifest pattern → Pattern 11 trust manifest.
- The shell-rc-line idempotence pattern (each install run produces the same rc state) directly maps to Axiom 4.
- Tests at `/dp/doodlestein_self_releaser/tests/integration/test_commands.bats` show the bats-based test pattern that pairs with bash installer doctors.

**File pointer:** `/dp/agentic_coding_flywheel_setup/scripts/lib/doctor_fix_spec.md`.

---

## `agentic_coding_flywheel_setup` (acfs)

**Path:** `/dp/agentic_coding_flywheel_setup/`

Provisions Ubuntu machines into the agentic-coding fleet. Multi-binary (acfs CLI + helper scripts). State lives across `~/`, `/etc/`, systemd units.

**Lift:**
- Multi-realm doctor: needs to verify state in HOME, /etc, systemd. Each realm has its own write_scopes. Cross-realm coordination via shared mutate().
- The fleet provisioning playbook (manual installer steps for SSH/Tailscale/ACFS/WezTerm) is a Pattern 10 absorb-playbook target.
- Test files at `/dp/agentic_coding_flywheel_setup/tests/unit/test_doctor_fix.sh` are existing fixtures we'd reuse.

**File pointer:** `/dp/agentic_coding_flywheel_setup/AGENTS.md`, `acfs.manifest.yaml`.

---

## `frankensearch` integration patterns

**Path:** `/dp/frankensearch/` and `frankensearch-integration-for-rust-projects` skill.

Hybrid two-tier search engine. Failure modes: index corruption, embedder cache drift, RRF fusion config invalid.

**Lift:**
- Doctor for a project that *embeds* frankensearch: detect index health, embedder version skew, fusion config drift.
- The skill's "search broken" / "search stalled" trigger phrases are exactly the kind of doctor finding remediation we want to surface.

**File pointer:** `frankensearch-integration-for-rust-projects/SKILL.md` in this same skill repo.

---

## `tsap_mcp_server` (Python MCP server)

**Path:** `/dp/tsap_mcp_server/`

MCP server for shell command exploration. Daemon CLI (Pattern 4). Failure modes: socket bind failures, tool registry drift, prompt cache corruption.

**Lift:**
- Python recipe (recipes/python.md) reference: this is a real Python MCP server using the daemon pattern.
- Failure-mode classes overlap with Pattern 4: socket health, watchdog, in-memory state.

**File pointer:** `/dp/tsap_mcp_server/src/tsap/`.

---

## `pi_agent_rust` (Pluggable extension agent)

**Path:** `/dp/pi_agent_rust/`

Rust agent with extension framework. Failure modes: extension manifest drift, plugin version skew, session state corruption.

**Lift:**
- Plugins subsystem in our cross-language failure-mode catalog.
- The `pi-agent-rust` skill documents the workflow for editing this project — informs Phase 4 implementer prompts in this skill.

**File pointer:** `/dp/pi_agent_rust/AGENTS.md`, `examples/ext_workloads.rs`.

---

## `frankenterm` (TUI showcase)

**Path:** `/dp/frankenterm/`

TUI demo project. Has its own `doctor_frankentui` command (Pattern 6: TUI-first). Tests at `tests/e2e/e2e_50pane_stress.py`, `e2e_20pane_integration.py`.

**Lift:**
- TUI doctor needs special handling: never launch the TUI in `<tool> doctor`. The skill's `frankentui` skill describes the doctor pattern for TUI demos.
- Stress tests at 50-pane scale inform performance (PERFORMANCE.md) bounds for daemon doctors.

**File pointer:** `/dp/frankenterm/AGENTS.md`, `frankentui` skill.

---

## `mcp_agent_mail_ios_app` (mobile sidecar)

**Path:** `/dp/mcp_agent_mail_ios_app/`

iOS app + Python sidecar for agent-mail. Daemon Python sidecar; tools registry; routing.

**Lift:**
- Mobile-host pattern: doctor for a sidecar that talks to a remote (mobile) app.
- Python implementation reference for Pattern 4 + Pattern 9 (distributed) combined.

**File pointer:** `python/mobile_sidecar/app.py`, `flywheel/tools_registry.py`.

---

## `xf` (twitter archive miner)

**Path:** `/dp/xf/`

Already cited as canonical exemplar (`xf doctor`). Extended observations:

- The `xf doctor` test pattern in `/dp/xf/tests/cli_e2e.rs` shows the round-trip test discipline at scale.
- `xf` has its own `robot_docs.rs` and `completions.rs` — informs the `robot-docs` and shell-completion-script aspects of our CLI surface.

---

## `native_pdf_extractor_ios_app`

**Path:** `/dp/native_pdf_extractor_ios_app/`

iOS app with Python tooling sidecar. Failure modes: PDF schema drift, OCR cache corruption.

**Lift:**
- Mobile-app companion CLI doctor pattern.
- Python at `Tooling/native_pdf_cli/native_pdf_cli/cli.py` demonstrates a CLI with deeply structured failure modes (PDF integrity).

---

## `flywheel_private` (control plane + tools)

**Path:** `/dp/flywheel_private/`

Multi-binary toolkit (Pattern 2): `fwc`, `fcp-host`, `fwh-cli`. Each has e2e tests at `control_plane/e2e/`.

**Lift:**
- E2E test patterns: `fwh-cli/src/commands/utilities.ts`, `beads.e2e.ts`. Real-world TS E2E reference for our recipes/typescript.md.
- The `flywheel-connector-final-testing` skill documents the live-service test strategy.

---

## `coding_agent_session_search` (cass)

**Path:** `/dp/coding_agent_session_search/`

Already cited. Extended:

- `cass` is the meta-tool: it's how we *mine* the corpus. Pattern 7 (AI-coding-agent CLI).
- `cass` has well-developed `--robot`, `capabilities --json`, `robot-docs guide` surfaces — gold standard for the four-verb shape (Q-005, Q-026).

---

## How to use this catalog

When applying the skill to a NEW project, the archaeologist's first sweep includes:

1. Read this file. Identify projects of similar shape.
2. For each match, read its source code, AGENTS.md section, and existing tests.
3. Extract the failure modes those projects have already encoded — they're the user's institutional knowledge.

The corpus grows over time. New `/dp/` projects with strong agent surfaces should be added here with one paragraph each.
