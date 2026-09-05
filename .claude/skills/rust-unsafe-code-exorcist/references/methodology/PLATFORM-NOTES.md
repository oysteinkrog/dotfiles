# PLATFORM-NOTES.md — Windows / macOS / Linux

The audit is developed primarily on Linux + macOS. Windows works but needs WSL2 for the verification harness. This file documents the specifics.

---

## Linux (primary; everything works)

Tested on Ubuntu 22.04+ and Fedora 38+. Other distros (Arch, Debian, NixOS, etc.) work fine.

```bash
# Required:
sudo apt update && sudo apt install -y git jq nodejs python3 build-essential curl
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# Recommended:
rustup toolchain install nightly
rustup +nightly component add miri rust-src
cargo install ast-grep cargo-expand cargo-fuzz cargo-mutants flamegraph hyperfine --locked
cargo +nightly install --locked cargo-geiger
cargo +nightly install cargo-careful
```

**Cron for continuous mode:**

```bash
crontab -e
# Add: 0 6 * * * /path/to/skill/scripts/cron-drift-check.sh /path/to/audit-dir /path/to/project
```

**Performance:** miri benefits from RAM; verify.sh on a 200-site audit runs ~30 min on 16GB / Ryzen 7 / SSD.

---

## macOS (primary; everything works)

Apple silicon (M1/M2/M3) and Intel both fine.

```bash
# Homebrew makes this easy:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install git jq node python rustup-init gh
rustup-init -y

# Recommended:
rustup toolchain install nightly
rustup +nightly component add miri rust-src
cargo install ast-grep cargo-expand cargo-fuzz cargo-mutants flamegraph hyperfine --locked
cargo +nightly install --locked cargo-geiger
cargo +nightly install cargo-careful
```

**Cron for continuous mode:** macOS uses `launchd` officially but `crontab -e` works.

**Apple silicon specifics:**

- All Rust crates work; some have aarch64-specific code paths.
- The audit benches per-target; aarch64-apple-darwin is in the default CI matrix.
- miri is supported on aarch64 since Rust 1.71 (mid-2023).

**Performance:** Apple silicon is fast on the audit; verify.sh on the same 200-site audit runs ~20 min on an M1 Pro.

---

## Windows

Three options, easiest first:

### Option 1 (recommended): WSL2

```powershell
# In PowerShell as admin:
wsl --install
```

After install + reboot, open WSL (Ubuntu by default). Follow the Linux instructions above inside WSL.

Pros: everything works exactly like Linux.
Cons: your project lives inside WSL's filesystem; Windows tools see it as `\\wsl$\Ubuntu\home\you\...`.

### Option 2: Git Bash + native Rust

Install:

- https://git-scm.com/downloads (Git Bash)
- https://rustup.rs/ → choose MSVC toolchain
- https://nodejs.org/
- https://jqlang.github.io/jq/download/

Then open Git Bash (not PowerShell) and follow the Linux instructions.

Pros: stays on Windows-native filesystem.
Cons:
- bash scripts mostly work but some POSIX features differ.
- miri on Windows MSVC has known issues with FFI-heavy crates.
- cargo-fuzz needs MSVC libfuzzer; complex setup.
- loom works fine.

### Option 3: PowerShell + native Rust (limited)

Same Rust install as Option 2. The audit's classification + plan-drafting phases work through Claude Code on PowerShell. The verification harness (verify.sh + miri + fuzz) needs bash and won't run natively.

Use this if you just want to TRY the skill; switch to WSL when you want the full audit.

---

## Per-OS test matrix

Here's what works on each platform:

| Feature | Linux | macOS | Windows WSL | Windows native (bash) | Windows native (PowerShell) |
|---------|-------|-------|-------------|----------------------|---------------------------|
| Enumerate unsafe | ✓ | ✓ | ✓ | ✓ | ✓ (with adjustments) |
| Per-site write-ups | ✓ | ✓ | ✓ | ✓ | ✓ |
| Classification | ✓ | ✓ | ✓ | ✓ | ✓ |
| miri (stacked + strict-provenance + tree-borrows) | ✓ | ✓ | ✓ | ⚠ FFI-heavy crates flaky | ✗ |
| cargo-careful | ✓ | ✓ | ✓ | ✓ | ⚠ via Git Bash only |
| loom | ✓ | ✓ | ✓ | ✓ | ⚠ via Git Bash only |
| cargo-fuzz | ✓ | ✓ | ✓ | ⚠ complex MSVC setup | ✗ |
| cargo-mutants | ✓ | ✓ | ✓ | ✓ | ⚠ |
| cargo-geiger | ✓ | ✓ | ✓ | ✓ | ✓ |
| verify.sh (full harness) | ✓ | ✓ | ✓ | ⚠ partial | ✗ |
| cron (continuous mode) | ✓ | ✓ | ✓ (inside WSL) | ✗ (use Task Scheduler) | ✗ (use Task Scheduler) |
| GitHub Actions auditor | ✓ | ✓ | ✓ | ✓ | ✓ (runs in cloud anyway) |

Legend: ✓ works fully, ⚠ works with caveats, ✗ doesn't work.

---

## ARM (aarch64) — Linux + macOS + Raspberry Pi

The audit benches per-target by default. ARM platforms (aarch64-unknown-linux-gnu, aarch64-apple-darwin, aarch64-unknown-none-eabihf) are fully supported:

- miri works on aarch64 since Rust 1.71.
- All cargo extensions work.
- Cross-compilation (e.g., x86_64 host, aarch64 target) works for the audit phases; verify.sh needs a real device or QEMU.

For embedded Rust (`no_std`, no allocator):

- The audit's pattern bundle [55-EMBEDDED-PATTERNS.md](../patterns/55-EMBEDDED-PATTERNS.md) covers volatile MMIO, PAC, embedded-hal.
- Some tools (miri, fuzz) can't run on bare-metal targets; the audit documents the limitation.

---

## Cloud / CI runners

The skill's CI integration ([CI-INTEGRATION.md](CI-INTEGRATION.md)) targets:

| Provider | Status |
|----------|--------|
| GitHub Actions | ✓ Primary target. Template at [assets/gh-actions-auditor.yml.template](../../assets/gh-actions-auditor.yml.template). |
| GitLab CI | ✓ Same commands work; adapt the YAML wrapper. |
| CircleCI | ✓ Same idea. |
| Jenkins | ✓ Use shell steps. |
| Buildkite | ✓ Same. |
| Other | The audit's commands are portable bash; any CI that runs bash + Rust works. |

---

## Exemplar repos

You'll see references throughout the docs to `/dp/asupersync`, `/dp/beads_rust`, `/dp/mcp_agent_mail_rust`, `/dp/pi_agent_rust`, `/dp/rich_rust`, `/dp/frankensqlite`, `/dp/frankentui`, `/dp/franken_engine`, `/dp/frankenlibc`, `/dp/frankenfs`.

**Important:** these are the SKILL AUTHOR'S local paths. You don't have any of them on your machine.

They're referenced as CASE-STUDY EXAMPLES — patterns the author shipped that the skill encodes. The skill works on YOUR project without needing the author's exemplars; the audit will surface "this pattern matches `[E-NNN]` in EXEMPLAR-CATALOG.md" only as institutional-memory references.

Similarly, `css`, `csd`, `ts1`, `ts2` are the author's remote machines for prior agent-session history. The skill defaults to localhost-only for CASS mining; the remote-host mining is optional (gated on `cass --host` availability) and SKIPPED if you don't have those hosts.

---

## File-path conventions

The skill uses:

- **`<project>`** — your Rust project directory.
- **`<audit-dir>`** — typically `<project>/.unsafe-audit/`, an in-project folder.
- **`$SKILL`** or `~/.claude/skills/rust-unsafe-code-exorcist/` / `~/.codex/skills/rust-unsafe-code-exorcist/` — the skill's installation directory.
- **`/tmp/`** in examples — a Unix temp dir. Windows: substitute `%TEMP%\` (PowerShell) or `$env:TEMP\` or use WSL.

The audit dir is intentionally contained under the project as `.unsafe-audit/`. It is a nested audit repo; existing source files and Cargo config stay clean until refactor authorization.

---

## Editor / IDE notes

The skill doesn't require any specific editor. But if you use one of these:

- **VS Code / Cursor / Helix** — rust-analyzer works fine on the audit dir's draft code (`audit/plans/`).
- **JetBrains RustRover** — same.
- **Vim / Neovim** — clear sailing.

For reviewing the audit's per-site write-ups (Markdown), any editor or `gh markdown-preview` works.

---

## Network requirements

The audit is mostly offline:

- Toolchain install needs network (one-time).
- `cargo` commands use the registry (https://crates.io); offline modes work with `--offline` after a previous online build.
- Multi-model triangulation needs API access (OpenAI / Gemini / Grok keys).
- Continuous mode's notifications channel may need network (GitHub API, Slack webhook, mail).

For air-gapped environments: use `audit-only` mode + skip the triangulation; the audit produces a defensible result without external network.

---

## Permissions / sudo

The audit DOES NOT need sudo. All tools install to your home directory's `~/.cargo/bin`. The audit dir is in your home dir or wherever you choose.

The skill explicitly refuses to use sudo (per AGENTS.md no-destructive-ops rule; sudo can do irreversible things).

If you're tempted to `sudo cargo install` because of a permission error: fix the underlying issue (your cargo dir's permissions) instead. Almost always the fix is `chown -R $USER ~/.cargo`.

---

## Quick OS-check command

```bash
bash ~/.claude/skills/rust-unsafe-code-exorcist/scripts/check-prerequisites.sh
# or, for Codex installs:
bash ~/.codex/skills/rust-unsafe-code-exorcist/scripts/check-prerequisites.sh
```

Output includes your OS + per-tool availability + install commands for what's missing.
