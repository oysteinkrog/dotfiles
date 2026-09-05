# Flywheel Tools — Detection And Auto-Install

The skill assumes several flywheel tools exist on the user's machine. When any is missing, Phase 0 bootstrap detects it and offers the canonical curl-bash one-liner. This file is the install catalog.

All one-liners are sourced from https://github.com/Dicklesworthstone/curl_bash_one_liners_for_flywheel_tools and the individual tool repos. They are author-controlled (Dicklesworthstone). The skill never runs them without explicit user confirmation.

---

## The catalog

| Tool | Purpose | Used by this skill | Install one-liner |
|---|---|---|---|
| `br` (beads_rust) | Issue tracking + dep graph | Phase 9 beads handoff, Phase 12 final beads | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh?$(date +%s)" \| bash` |
| `bv` (beads_viewer) | Bead graph triage TUI | Phase 9 validation (`bv --robot-insights`) | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh?$(date +%s)" \| bash` |
| `cass` (coding_agent_session_search) | Past-session search | Phase 0 priors, Phase 6 idea-wizard | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh?$(date +%s)" \| bash -s -- --easy-mode --verify` |
| `ubs` (ultimate_bug_scanner) | Fast Rust linter | Phase 10 fresh-eyes gates | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/main/install.sh?$(date +%s)" \| bash -s -- --easy-mode` |
| `rch` (remote_compilation_helper) | Offload heavy builds | Phase 3 + Phase 11 soak (any >5min run) | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh?$(date +%s)" \| bash -s -- --easy-mode` |
| `jsm` (jeffreys-skills.md CLI) | Skill installation | Phase 0 helper-skill bootstrap | `curl -fsSL "https://jeffreys-skills.md/install.sh?$(date +%s)" \| bash` |
| `ntm` (tmux session manager) | Multi-agent fan-out | Phase 1-3 parallel orchestration (Swarm tier) | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh?$(date +%s)" \| bash -s -- --easy-mode` |
| `dcg` (destructive_command_guard) | Safety hook | Recommended for any session running this skill | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/master/install.sh?$(date +%s)" \| bash -s -- --easy-mode` |
| `sbh` (storage_ballast_helper) | Disk-pressure defense | Recommended for Phase 11 soak (long fuzz campaigns) | `curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/storage_ballast_helper/main/scripts/install.sh \| bash` |
| `dsr` (doodlestein_self_releaser) | Local release fallback | Phase 14 release if GH Actions is down | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/doodlestein_self_releaser/main/install.sh?$(date +%s)" \| bash` |
| `slb` (simultaneous launch button) | Two-person rule for destructive ops | Optional — for orgs requiring peer approval on yanks | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/slb/main/scripts/install.sh?$(date +%s)" \| bash` |
| `xf` (file operations CLI) | Twitter archive search | Not required by this skill (listed for completeness) | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/xf/main/install.sh?$(date +%s)" \| bash -s -- --easy-mode` |
| MCP Agent Mail | Multi-agent coordination | Phase 1-11 file reservations + messaging | `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh?$(date +%s)" \| bash -s -- --yes` |

---

## Detection logic

The `scripts/install-toolchain.sh` script Phase 0 invokes this detection. Three modes:

```bash
# Default — interactive: detect, print, ask per-tool (needs TTY).
scripts/install-toolchain.sh "$WORKSPACE"

# Non-interactive, install EVERYTHING missing in one shot. Use this when the
# user has explicitly said "auto-install whatever's missing" or "blanket
# approval". Skips per-tool prompts entirely.
scripts/install-toolchain.sh "$WORKSPACE" --yes

# Non-interactive, install nothing. Just write the JSON inventory.
# Safe for agents to run unattended; use this first to probe what's
# present before deciding whether to ask the user about installs.
scripts/install-toolchain.sh "$WORKSPACE" --inventory-only

# Every install attempt is followed by a per-tool SMOKE TEST (e.g.,
# `cargo +nightly miri --version` for miri). The result is captured in
# phase0_toolchain_inventory.json under each tool's `smoke_test_passed`
# field. Tools that install but fail their smoke are listed in the
# top-level `broken_post_smoke` array and reported to stderr. Investigate
# before the orchestrator relies on the tool.
```

The script behavior for each tool:

1. Check if the binary is on `PATH` (`command -v <tool>`).
2. If installed, record version (`<tool> --version`).
3. If missing, mark for offer.

**Auto-detected by the script:** `br`, `bv`, `cass`, `ubs`, `rch`, `jsm`, `ntm`, `dcg`, `sbh`, `dsr`, `slb`.

**NOT auto-detected** (listed here for completeness — install manually if needed):
- `xf` — not used by this skill; included for ecosystem context.
- **MCP Agent Mail** — runs as an MCP server, not a CLI binary; there's no canonical `command -v` target to probe. If the skill needs MCP tools (`mcp__mcp-agent-mail__*`) for Phase 1–11 coordination and they're absent from the deferred-tools list, install with the one-liner above and add the server to the MCP client config manually.

Caveats:
- `ntm --version` errors (cobra-style CLI; use `ntm version` subcommand instead). The script falls through with empty version metadata; tool detection still succeeds.
- `dcg --version` returns just a bare version number (no tool prefix); the script's `head -1` captures it correctly.
- **`cargo-geiger`** is fragile on multi-project workstations: it can chase a transitive path-dependency to a directory that does not exist (e.g., a sibling project's source tree that was deleted or never checked out) and crash mid-scan with `Io NotFound: <path>/src/lib.rs`. If this happens, fall back to the `rg`-based inventory in [TROUBLESHOOTING.md §cargo-geiger](TROUBLESHOOTING.md#cargo-geiger). For `#![forbid(unsafe_code)]` projects the geiger pass adds little value and can be skipped with rationale.
4. Print the inventory table with status (✓ installed, [ ] missing).
5. For each missing tool, ask the user **per-tool** whether to install via the canonical one-liner.
6. If confirmed: run the one-liner via `eval` (hints are author-controlled, see AGENTS.md compliance note in the script).
7. Record installations in `phase0_toolchain_inventory.json` under `flywheel_tools_installed_this_run`.

---

## Per-tool: when this skill needs it

### Hard requirements (skill blocks without these)

- **`rustup` / nightly Rust / `miri` / `rust-src`** — Phase 3 dynamic sweep. Without these, no Miri, no real audit.
- **`br` (beads_rust)** — Phase 9 beads handoff. The skill produces a bead graph; without `br` the handoff fails.
- **`bv` (beads_viewer)** — Phase 9 validation gates (`bv --robot-insights`). Without it, the dep-cycle / has-test / has-docs checks can't run.

### Soft requirements (skill degrades gracefully)

- **`cass`** — Phase 0 project priors. If missing, the skill skips the prior-mining step.
- **`ubs`** — Phase 10 fresh-eyes static gate. If missing, the gate is skipped (note in `phase10_fresh_eyes_log.md`).
- **`rch`** — Phase 3 + Phase 11 offload. If missing, soak campaigns run locally (or are deferred to Quick mode).
- **`jsm`** — Phase 0 helper-skill bootstrap. If missing, inline fallbacks (see TOOLING.md §"Operating without helper skills").
- **`ntm`** — Phase 1-3 Swarm-tier orchestration. If missing, the skill runs in Solo/Pair/Squad tier instead.
- **MCP Agent Mail** — multi-agent coordination. If missing, the skill runs in single-agent mode with no file reservations (slower but correct).

### Recommended but not used by the skill

- **`dcg`** — recommended as a general safety hook. The skill doesn't directly invoke it.
- **`sbh`** — recommended for long Phase 11 soak campaigns (disk-pressure defense). The skill doesn't directly invoke it.
- **`dsr`** — fallback release infra. Used only if GH Actions is throttled.
- **`slb`** — two-person rule. Used only by orgs that require it for yanks/disclosures.

---

## Sample Phase-0 transcript

```
$ scripts/install-toolchain.sh /data/projects/frankensqlite/.ub-exorcism/2026-05-14-frankensqlite-1

=== Toolchain inventory ===
  [✓] rustup            rustup 1.27.1
  [✓] nightly           rustc 1.87.0-nightly
  [✓] miri              (installed)
  [✓] rust_src          (installed)
  [✓] cargo-fuzz        cargo-fuzz 0.12.0
  [ ] kani              (hint: cargo install --locked kani-verifier)

=== Flywheel tools inventory ===
  [✓] br                br 0.2.6
  [✓] bv                (installed)
  [✓] cass              cass 0.4.2
  [ ] ubs               (hint: curl-bash one-liner — see references/FLYWHEEL-TOOLS-INSTALL.md)
  [✓] rch               rch 1.0.24
  [✓] jsm               jsm 0.3.5
  [ ] ntm               (recommended for Swarm tier)
  [✓] dcg               0.5.1
  [ ] sbh               (recommended for Phase 11 soak)

Hard requirements: all present. ✓
Soft requirements: `ubs` missing; Phase 10 static gate will be skipped.
Recommended: `ntm`, `sbh` missing; the skill will adapt.

Install `ubs` via:
  curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/main/install.sh?$(date +%s)" | bash -s -- --easy-mode
? [y/N] y
... [install output] ...
  [✓] ubs installed: UBS Meta-Runner v5.2.76

Install `ntm` via:
  curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh?$(date +%s)" | bash -s -- --easy-mode
? [y/N] n  (skipped — proceeding without Swarm tier)

Install `sbh` via:
  curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/storage_ballast_helper/main/scripts/install.sh | bash
? [y/N] y
... [install output] ...
  [✓] sbh installed: sbh 0.4.22

Wrote inventory: <workspace>/phase0_toolchain_inventory.json
```

---

## AGENTS.md compliance

The install one-liners use `curl | bash` which AGENTS.md does NOT explicitly forbid (it's not a destructive git command). But:
- The skill ALWAYS asks per-tool before running
- The hints are author-controlled (Dicklesworthstone repos, all under his control)
- The skill never installs without explicit user `y` response
- The `eval` invocation in `install-toolchain.sh` is documented (the hint strings are static literals defined just above, never user input)

If the user is uncomfortable with `curl | bash` patterns:
- Refuse the install (`n` at the prompt)
- Install the tool manually (each repo has alternative install methods like cargo, brew, scoop)
- The skill records "user-declined-install" in the inventory and continues with degraded functionality

---

## Cross-references

- `scripts/install-toolchain.sh` — the script that uses this catalog
- [TOOLING.md §Operating without helper skills](TOOLING.md#operating-without-helper-skills) — inline fallbacks when soft requirements are missing
- [INTEGRATIONS.md](INTEGRATIONS.md) — how each tool composes with the skill
- https://github.com/Dicklesworthstone/curl_bash_one_liners_for_flywheel_tools — upstream catalog
