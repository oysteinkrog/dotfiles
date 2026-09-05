# Rust Unsafe Code Exorcist — Read Me First

> If you just downloaded Claude Code or installed this for another local coding agent and you're not sure what to do next, this is the right file. Don't read SKILL.md yet — that file is for the agent to read, not you. This README is for you.

---

## Wait — do I have the right product?

This skill works best in **Claude Code**, the COMMAND-LINE tool that runs in your terminal. It can also be used by other local coding agents such as Codex when the skill is installed in that agent's skill directory and the agent can run shell commands. It is not the same as:

| Product | What it is | Works with this skill? |
|---------|-----------|------------------------|
| **Claude Code** (CLI) | Terminal tool: `claude` command. Has slash commands, skills, subagents. | ✅ YES — this is what this skill is for. |
| **Codex / other local coding agents** | Terminal agents with local skill folders and shell access. | ✅ YES, if installed for that agent and pointed at this skill's scripts. |
| **Claude Desktop** (chat app) | The app you download from claude.ai (Mac/Windows). | ⚠️ Limited — newer versions may load some skills via [Anthropic's Skills feature](https://www.anthropic.com/news/agent-skills), but the shell-script infrastructure this skill ships with needs a terminal agent with shell access. |
| **Claude on web** (claude.ai) | Browser-based chat. | ❌ Won't run the audit scripts. |
| **Claude API** | Programmatic access. | ❌ Won't directly use this skill format. |

**If you downloaded the Claude Desktop chat app** and you're looking at this skill expecting to use it: you also need a terminal coding agent such as Claude Code or Codex with local skill support and shell access. Claude Code is here: https://docs.claude.com/claude-code

(You can use both — Claude Desktop for general chat, a terminal coding agent for project work.)

---

## What this skill does (in one sentence)

It audits every `unsafe` block in a Rust project, classifies each one (must-stay / perf-only / can-be-refactored), and produces a thorough report — without touching your project until you say so.

If you don't write Rust, this skill isn't useful to you. (Yet — see the broader skill collection at https://jeffreys-skills.md.)

If you do write Rust and you have a project with `unsafe` blocks you want audited, you're in the right place.

---

## The 5-minute version

```
1. Make sure Rust is installed (rustup.rs).
2. Open a terminal, cd to your project.
3. Open your local coding agent in that terminal (for Claude Code, run `claude`; for Codex, use your normal Codex launcher).
4. Type: "audit my unsafe code with the rust-unsafe-code-exorcist skill"
5. The agent will ask a few questions, then run the audit.
```

That's it. The audit runs for 30 minutes to 4 hours depending on project size. The result is an in-project folder `<project>/.unsafe-audit/` with a report you can read.

---

## Before you run it — what you'll need

Required:

- **A Rust project** with at least one `unsafe` block (otherwise there's nothing to audit).
- **Rust toolchain** installed via [rustup](https://rustup.rs/) — `rustup --version` should work in your terminal.
- **bash, git, jq, node.js, python3** — most Mac/Linux systems have these; Windows users need [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) (Linux subsystem) or [Git Bash](https://git-scm.com/downloads).
- **Claude Code or another local coding agent** with local skill support and shell access.

Strongly recommended for the full audit:

- **Rust nightly + miri** — for the UB-detection step. Install: `rustup toolchain install nightly && rustup +nightly component add miri rust-src`
- **A few cargo extensions** — `cargo install ast-grep cargo-expand cargo-fuzz cargo-mutants`. The skill will offer to install missing ones when it runs.

For full prereqs with copy-paste install commands per OS, see [references/methodology/PREREQUISITES.md](references/methodology/PREREQUISITES.md).

To check what's already installed and what's missing:

```bash
bash ~/.claude/skills/rust-unsafe-code-exorcist/scripts/check-prerequisites.sh
# or, for Codex installs:
bash ~/.codex/skills/rust-unsafe-code-exorcist/scripts/check-prerequisites.sh
```

(This won't install anything. It just tells you what you're missing.)

---

## Try it on a toy project first

If you don't have a Rust project yet, here's a 2-minute toy that proves the skill works on your machine:

```bash
# 1. Make a toy crate with deliberately-flaggable unsafe code.
mkdir -p /tmp/exorcist-smoke && cd /tmp/exorcist-smoke
cat > Cargo.toml <<'EOF'
[package]
name = "exorcist-smoke"
version = "0.1.0"
edition = "2021"
EOF
mkdir src
cat > src/lib.rs <<'EOF'
pub fn from_be_unsafe(b: [u8; 4]) -> u32 {
    unsafe { std::mem::transmute::<[u8; 4], u32>(b) }.to_be()
}

pub fn first_byte_unchecked(s: &[u8]) -> u8 {
    unsafe { *s.get_unchecked(0) }
}

unsafe impl Send for MyHandle {}
pub struct MyHandle {
    inner: *const u8,
}
EOF

# 2. In the same terminal, open your local coding agent.
#    For Claude Code:
claude

# 3. Type:
#    Run the rust-unsafe-code-exorcist skill on /tmp/exorcist-smoke.
#    Use audit-only mode, quick variant.
```

The audit will run in ~5–10 minutes on this tiny project. The output is in `/tmp/exorcist-smoke/.unsafe-audit/` — open `AUDIT_SUMMARY.md` in there for the result.

(Windows note: replace `/tmp/` with `%TEMP%\` in PowerShell, or use WSL.)

---

## What you'll see when it runs

The audit will:

1. **Ask you a few questions** — confirm the project path, agree to install any missing tools, pick a mode.
2. **Enumerate every `unsafe` site** — using `ast-grep`, `cargo expand`, `cargo geiger`. Takes a few seconds.
3. **Analyze each site** — what it does, what invariants it assumes, where the data comes from. Takes 5–30 min depending on project size.
4. **Classify each site** as (A) must-stay-unsafe, (B) perf-only-with-safe-alternative, or (C) refactorable-to-safe-Rust.
5. **For each (C):** draft the safe rewrite + a property-based test proving it matches.
6. **For each (B):** show measured perf numbers + add a `safe-only` Cargo feature.
7. **For each (A):** harden the SAFETY comment + add a clippy lint where possible.
8. **Run a verification harness** — miri + loom + fuzz + tests. This is the slowest step (often 30 min).
9. **Generate a `AUDIT_SUMMARY.md`** — read this first.

The audit creates `<your-project>/.unsafe-audit/` inside your project. Existing source files stay untouched until you approve a refactor. If you like the proposed changes, you tell the agent to apply the selected plan in the active checkout, optionally using an ordinary branch and PR if that is your repo workflow. The skill must not use git worktrees.

---

## If you get stuck

| Symptom | Where to look |
|---------|---------------|
| "Skill doesn't trigger" | [references/methodology/TROUBLESHOOTING.md § Skill loading issues](references/methodology/TROUBLESHOOTING.md) |
| "Missing tool: cargo-miri / cargo-fuzz / ast-grep" | [references/methodology/PREREQUISITES.md](references/methodology/PREREQUISITES.md) and `scripts/check-prerequisites.sh` |
| "What does (A)/(B)/(C) mean?" | [references/methodology/MENTAL-MODEL.md](references/methodology/MENTAL-MODEL.md) |
| "What's miri / loom / fuzz?" | [references/methodology/GLOSSARY.md](references/methodology/GLOSSARY.md) |
| "I'm on Windows" | [references/methodology/PLATFORM-NOTES.md](references/methodology/PLATFORM-NOTES.md) |
| "I want to see worked examples" | [references/methodology/COOKBOOK.md](references/methodology/COOKBOOK.md) |

---

## What this skill is NOT

- Not a Rust learning resource. It assumes you've written Rust before and seen `unsafe`.
- Not a perf optimizer. It measures, doesn't tune.
- Not autonomous against your code. It writes all findings + plans into `.unsafe-audit/`; touches existing project source only when you authorize it.
- Not a one-shot tool. The "continuous mode" turns it into a partner that watches your project nightly and files alerts when new unsafe sneaks in.

---

## Where to go next (depending on what you want)

| You want to... | Read this |
|----------------|-----------|
| Understand the audit's structure | [references/methodology/MENTAL-MODEL.md](references/methodology/MENTAL-MODEL.md) (1 page) |
| Run an audit on your project | [references/methodology/COOKBOOK.md § Recipe 1](references/methodology/COOKBOOK.md) (paste-ready commands) |
| Get an at-a-glance cheat sheet | [references/methodology/QUICK-REFERENCE.md](references/methodology/QUICK-REFERENCE.md) |
| Just enumerate unsafe (60 seconds) | [references/methodology/FAST-TRACK-MODES.md § triage](references/methodology/FAST-TRACK-MODES.md) |
| Understand the methodology in depth | [SKILL.md](SKILL.md) (this is for the coding agent to read; large) |
| See the full backlog of features | [references/methodology/IDEAS.md](references/methodology/IDEAS.md) |
| Audit's exemplar repos (author-specific) | [Author's exemplar disclaimer](references/methodology/PLATFORM-NOTES.md#exemplar-repos) — the `/dp/*` paths you'll see in some docs are the SKILL AUTHOR'S machine; they're not on yours. The skill works without them. |

---

## What if I just want to look around without running anything?

The skill is large (160+ files). The 10 most-useful for browsing:

1. **`README.md`** — this file.
2. **`SKILL.md`** — the main spine (long; mostly for the coding agent to read).
3. **`references/methodology/MENTAL-MODEL.md`** — the conceptual model in 1 page.
4. **`references/methodology/QUICK-REFERENCE.md`** — cheat sheet.
5. **`references/methodology/COOKBOOK.md`** — worked recipes.
6. **`references/methodology/GLOSSARY.md`** — terms you'll see.
7. **`references/methodology/PREREQUISITES.md`** — what you need installed.
8. **`references/methodology/PLATFORM-NOTES.md`** — Windows/macOS/Linux notes.
9. **`references/methodology/TROUBLESHOOTING.md`** — when things break.
10. **`references/methodology/IDEAS.md`** — the future roadmap (30 ideas).

The other ~150 files are the deep-dive references that the coding agent pulls in when relevant. You don't need to read them.

---

## License + credit

Skill author: see https://jeffreys-skills.md. Per the repo's LICENSE.

This skill is part of a larger collection. If you find it useful, the other skills in the collection (https://jeffreys-skills.md) may also help you.

If you find a bug, a missing prerequisite, or a confusing instruction: please open an issue or send feedback to the skill author. New-user friction is exactly what we want to hear about.

---

Welcome. Now go run that toy example.
