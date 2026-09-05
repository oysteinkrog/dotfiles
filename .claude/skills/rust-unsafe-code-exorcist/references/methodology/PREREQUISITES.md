# PREREQUISITES.md — What You Need Before Running

Run [scripts/check-prerequisites.sh](../../scripts/check-prerequisites.sh) to check your machine. It only reads; never installs without asking.

---

## Required (the skill won't run without these)

| Tool | Why | How to install |
|------|-----|----------------|
| **Local coding agent** | Runs the skill and shell scripts | Claude Code: https://docs.claude.com/claude-code. Codex or another local agent also works if it has local skill support and shell access. |
| **Rust toolchain** | The project you're auditing is Rust | https://rustup.rs/ (`rustup --version` should work) |
| **bash** | Most scripts are bash | macOS/Linux: built-in. Windows: install [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) or [Git Bash](https://git-scm.com/downloads). |
| **git** | The audit dir is a new git repo | macOS: `brew install git`. Linux: `apt install git`. Windows: included with WSL or Git Bash. |
| **jq** | JSON processing in scripts | macOS: `brew install jq`. Linux: `apt install jq`. Windows (WSL): `apt install jq`. |
| **node.js** | A few scripts are `.mjs` | macOS: `brew install node`. Linux: `apt install nodejs`. Windows: https://nodejs.org/ |
| **python3** | Validators are Python | macOS/Linux: usually pre-installed. Verify: `python3 --version`. |

---

## Strongly recommended (the audit's harness needs these)

| Tool | Why | Install |
|------|-----|---------|
| **Rust nightly toolchain** | miri + careful + tree-borrows need nightly | `rustup toolchain install nightly` |
| **miri** | UB detection (the audit's primary soundness check) | `rustup +nightly component add miri rust-src && cargo +nightly miri setup` |
| **rust-src on nightly** | miri needs the source | (installed by above command) |
| **ast-grep** | AST-aware code search (replaces grep for soundness audit) | `cargo install ast-grep --locked` |
| **cargo-expand** | Reveals macro-generated unsafe (much hidden unsafe lives in macros) | `cargo install cargo-expand --locked` |
| **cargo-geiger** | Counts unsafe occurrences across deps | `cargo +nightly install --locked cargo-geiger` |

---

## Useful for deeper audits (optional; skill degrades gracefully without them)

| Tool | Why | Install |
|------|-----|---------|
| **cargo-careful** | Runtime UB detection at native speed (miri at interp speed) | `cargo +nightly install cargo-careful` |
| **cargo-fuzz** | Input-space exploration (libfuzzer) | `cargo install cargo-fuzz --locked` |
| **cargo-mutants** | Verifies your tests actually pin behavior | `cargo install --locked cargo-mutants` |
| **cargo-flamegraph** | Profile-driven perf measurement (for (B) sites) | `cargo install flamegraph --locked` |
| **hyperfine** | End-to-end CLI timing (for (B) sites) | `cargo install --locked hyperfine` |
| **gh (GitHub CLI)** | For PR-comment integration in CI mode + archeology | macOS: `brew install gh`. Linux: see https://cli.github.com/. |
| **loom** (dev-dep, not a binary) | Concurrency model checking (added to your crate's Cargo.toml as needed) | The skill adds `[dev-dependencies] loom = "0.7"` per concurrency-touching crate. |
| **kani** | Bounded model checker for highest-stakes formal proof | `cargo install --locked kani-verifier && cargo kani setup` |

---

## Useful but advanced (skip on first run)

| Tool | Why |
|------|-----|
| **`br` (beads_rust)** | Issue tracker the audit converts plans into. `cargo install beads_rust` |
| **`bv`** | Graph-aware triage on the bead graph. `cargo install beads_viewer` |
| **MCP Agent Mail server** | Multi-agent coordination. Only needed for Swarm-tier audits with many concurrent agents. |
| **NTM (tmux orchestrator)** | Drives swarm-tier audits. Skip unless you've already adopted it. |
| **`cass` (Cross-Agent Session Search)** | Mines past agent conversations. Only useful if you have prior agent history. |
| **`ubs` (Ultimate Bug Scanner)** | Additional pre-commit static analysis. Optional but high-signal: catches a separate class of bugs the audit's other tools miss. The enumerator integrates with `ubs` per-crate (`ubs --only=rust src/`). Without `ubs` the audit still runs; you lose one verification axis. |
| **`jsm` (Jeffrey's Skills Manager)** | Install helper skills from the catalog. https://jeffreys-skills.md |

### Installing `ubs` specifically

`ubs` is the recommended companion for `rust-unsafe-code-exorcist` — the audit's enumerator calls it when present and skips silently when not. To install:

**Path A — via jsm (preferred if jsm is on PATH).**

```bash
jsm install ubs       # adds the ubs CLI + the `/ubs` skill
ubs --version         # verify
```

**Path B — via cargo (no jsm).**

```bash
cargo install ubs --locked
ubs --version
```

**Path C — via curl (no jsm, no cargo install).**

```bash
# from the project README (https://github.com/Dicklesworthstone/ubs)
curl -fsSL https://ubs.sh/install.sh | sh
ubs --version
```

After install, re-run `scripts/check-prerequisites.sh`; the `ubs` row should now show ✓.

### About `jsm` + the local skill registry

`jsm` is the install/update manager for skills published on https://jeffreys-skills.md. The audit's `intake-prompt.md` Q8 asks whether to install missing referenced skills via `jsm install <name>`. If `jsm` is installed and authenticated, every public helper skill the audit references (`/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/extreme-software-optimization`, `/multi-pass-bug-hunting`, `/multi-model-triangulation`, `/idea-wizard`, `/beads-workflow`, `/beads-br`, `/beads-bv`, `/ubs`, `/agent-mail`, `/cass`, `/testing-real-service-e2e-no-mocks`, `/testing-metamorphic`, `/testing-fuzzing`, `/testing-conformance-harnesses`, `/deadlock-finder-and-fixer`) can be installed in one command.

To install `jsm` itself: visit https://jeffreys-skills.md/install or run `curl -fsSL https://jsm.sh/install.sh | sh`.

Without `jsm` the audit degrades gracefully — every referenced skill has an inline fallback in [SKILL-FALLBACKS.md](SKILL-FALLBACKS.md). The audit doesn't block on missing optional skills; it notes them in `phase0_skill_inventory.json` and proceeds with the fallback playbook.

---

## Platform-specific notes

### macOS

```bash
# Homebrew makes most of this easy:
brew install git jq node python rustup-init gh
rustup-init -y
rustup toolchain install nightly
rustup +nightly component add miri rust-src
cargo install ast-grep cargo-expand cargo-fuzz cargo-mutants flamegraph hyperfine --locked
cargo +nightly install --locked cargo-geiger
cargo +nightly install cargo-careful
```

Apple silicon (M1/M2/M3): everything works. Some Rust crates have specific aarch64 paths; the audit handles per-target.

### Linux (Ubuntu/Debian)

```bash
sudo apt update && sudo apt install -y git jq nodejs python3 build-essential curl
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup toolchain install nightly
rustup +nightly component add miri rust-src
cargo install ast-grep cargo-expand cargo-fuzz cargo-mutants flamegraph hyperfine --locked
cargo +nightly install --locked cargo-geiger
cargo +nightly install cargo-careful
```

Linux is the default-supported platform for the audit (miri, loom, fuzz all run natively).

### Windows

**Strongly recommended:** install [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) and follow the Linux instructions inside WSL.

Native Windows attempt (not recommended):

- bash scripts won't run natively — use Git Bash (https://git-scm.com/downloads).
- miri works on Windows but with caveats (some POSIX tests fail).
- cargo-fuzz needs MSVC + libfuzzer; setup is non-trivial.
- The audit's `verify.sh` and the shell scripts assume POSIX shell; they need bash compatibility.

If you're committed to native Windows: most of the audit (enumeration, classification, plan-drafting) works through a local coding agent on PowerShell, but the verification harness won't.

See also [PLATFORM-NOTES.md](PLATFORM-NOTES.md) for the long version.

---

## Quick check (after install)

```bash
bash ~/.claude/skills/rust-unsafe-code-exorcist/scripts/check-prerequisites.sh
# or, for Codex installs:
bash ~/.codex/skills/rust-unsafe-code-exorcist/scripts/check-prerequisites.sh
```

Output is a per-tool table:

```
✓ rustc 1.84.0 (stable)
✓ rustc nightly-2026-05-13 (nightly)
✓ cargo 1.84.0
✓ cargo-miri (rustc nightly)
✗ cargo-careful — install: cargo +nightly install cargo-careful
✓ ast-grep 0.30
✓ cargo-expand 1.0
...
```

Run the proposed install commands for any `✗` entries you want.

---

## What if I don't install everything?

The skill degrades gracefully. Each fast-track / mode has a different set of HARD requirements:

| Mode | Hard requirements |
|------|-------------------|
| `triage` (60-second) | bash, ast-grep, jq, node.js (`cargo-geiger` optional but recommended) |
| `audit-only --quick` | + Rust toolchain |
| `audit-only` (full) | + nightly + miri + cargo-expand |
| `audit-and-refactor` | + cargo-fuzz + cargo-mutants + `gh` for PR opening |
| `harden-incident` | + ALL of the above (incidents demand full verification) |
| `pre-release-soundness-gate` | + ALL of the above + cargo-public-api + cargo-semver-checks |
| `continuous mode` | + cron (macOS/Linux) or scheduled task (Windows) |
| `inverse audit` | + cargo-fuzz (libfuzzer support) |

You can always start with `triage` to see what the skill does WITHOUT installing the full toolchain.

---

## What if installation fails?

| Error | Cause | Fix |
|-------|-------|-----|
| `error: toolchain 'nightly' is not installed` | nightly missing | `rustup toolchain install nightly` |
| `error: no override and no default toolchain set` | no Rust at all | https://rustup.rs/ |
| `cargo: command not found` | Rust not on PATH | `source "$HOME/.cargo/env"` (Linux/macOS) or restart terminal |
| `cargo install fails with "could not compile"` | usually a dep conflict; sometimes outdated crate | `rustup update` then retry |
| `jq: command not found` (Windows) | not on PATH | https://jqlang.github.io/jq/download/ |
| `npm not found / node not found` | Node.js missing | https://nodejs.org/ |
| `Permission denied: cargo install` | tries to write to system dir | Don't use `sudo cargo install`. Make sure `cargo` is in your user PATH. |

For deeper troubleshooting see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## I want the absolute minimum to try this skill

```bash
# Required only:
brew install git jq node python   # or apt equivalent
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
cargo install ast-grep --locked
```

That's enough to run `triage` mode on a small project and see what the skill finds. Add the rest as you need them.
