---
name: rust-unsafe-code-exorcist
description: >-
  Audit, classify, and optionally remediate Rust `unsafe` sites. Use
  when removing unsafe blocks, validating unsafe necessity, hardening
  FFI/SIMD, exorcising unsafe, or checking `#![forbid(unsafe_code)]`
  crates. Remediation lands only in the active checkout after approval;
  never use git worktrees. Not for broad UB hunts.
---

<!-- TOC: Quick Start | 30-Second Mental Model | One Rule | Inputs | Scope Governor | Confirmations | Bootstrap | Mode Router | Phase Loop | Parallelism | Classification | Operators | Polish Bar | Project Types | Anti-Patterns | Verification | Source Corpus | Checklist | References | Specialty Workflows | Continuous + Innovation Modes | Scripts | Subagents | Assets | Self-Test -->

# Rust Unsafe Code Exorcist

> **First time using this skill?** Read [README.md](README.md) first — it's the human-friendly orientation. This SKILL.md file is for the coding agent (Claude Code, Codex, or another local agent with shell access) to read; it's long and technical. Quick check before running the audit from inside this skill directory: `bash scripts/check-prerequisites.sh`. Installed path examples: `bash ~/.claude/skills/rust-unsafe-code-exorcist/scripts/check-prerequisites.sh` or `bash ~/.codex/skills/rust-unsafe-code-exorcist/scripts/check-prerequisites.sh`.

> **On Claude Desktop (chat app), not a terminal coding agent?** The skill's audit infrastructure (shell scripts, harness, cron) targets local agents with shell access, such as Claude Code or Codex. See [README.md § Wait — do I have the right product?](README.md) for what to install.

## Quick Start

Most common invocation:

```
/rust-unsafe-code-exorcist /path/to/my-rust-project
```

That's it. After the user authorizes, the skill creates `<project>/.unsafe-audit/` inside the project, runs the 10-phase loop (plus an optional Phase 11 that offers to apply the findings), and outputs `AUDIT_SUMMARY.md` (the user-facing tally) + a defensible audit + beads + a verification harness. Default mode is `audit-only`; existing project source files and Cargo config stay read-only until you authorize a refactor.

**Hard invariant: no git worktrees.** When remediation is authorized, perform edits in the active checkout (or a normal branch created inside that checkout with explicit user approval). Never run `git worktree add`, never create per-cluster worktree directories, and never route subagents through separate checkout copies. If a user or repo wants PRs, make them from ordinary branches in the active checkout after the local diff is reviewed and verified.

Two historical paths still contain the word `worktree` for compatibility with older cross-links: `references/methodology/WORKTREE-REFACTOR-PROTOCOL.md` and `subagents/worktree-implementer.md`. Do not infer permission from those filenames; their contents define the active-checkout protocol and explicitly forbid git worktrees.

If the ask is "find UB anywhere", "Miri sweep", a data-race hunt, or a Rustonomicon UB audit, use `/rust-undefined-behavior-exorcist` instead. This skill inventories and classifies `unsafe` sites.

For a 60-second triage instead of a full audit, see [FAST-TRACK-MODES.md § triage](references/methodology/FAST-TRACK-MODES.md). For paste-ready recipes (incident response, dep upgrade, pre-release gate, continuous mode setup, etc.), see [COOKBOOK.md](references/methodology/COOKBOOK.md). For a 2-minute toy-project smoke test, see [README.md § Try it on a toy project first](README.md).

**Prerequisites.** Required: Rust toolchain, git, bash, jq, node, python3. Recommended: nightly + miri + ast-grep + cargo-expand. Optional: cargo-fuzz, cargo-mutants, hyperfine, kani, br. Run `scripts/check-prerequisites.sh` to see what you have. Full list per OS: [PREREQUISITES.md](references/methodology/PREREQUISITES.md).

## 30-Second Mental Model

You point at a Rust project; each `unsafe` site goes into one of three buckets:

- **(A) STRICTLY_UNAVOIDABLE** — language can't express the safe form. Hardened SAFETY comment + clippy lint.
- **(B) PERF_ONLY** — safe form exists but slower; ship a `safe-only` Cargo feature flag with measured perf delta.
- **(C) REFACTORABLE** — safe form exists; the audit drafts it + a property-based equivalence test.

The audit is reapply-until-quiet: Phase 4 (classify) and Phase 6 (adversarial reclassify) iterate until <5% of sites flip bucket between passes AND zero (A)→(C) flips occur. Phase 7 fresh-eyes review runs three calibrated prompts on the proposed safe rewrites, then a toolchain harness (miri + careful + loom + fuzz + mutants + geiger + tests under default + `safe-only`).

For projects that already declare `#![forbid(unsafe_code)]` (a common-and-getting-more-common state), the buckets are trivially empty in-tree and Phases 4–6 collapse. The audit becomes "verify the forbid is structurally airtight + characterize dep-side reachable unsafe + emit a tailored verify.sh" — the `forbid-soundness` mode handles this fast-path. See SKILL.md § Mode Router.

For the full conceptual model + the audit dir's anatomy + the 32 subagents, see [MENTAL-MODEL.md](references/methodology/MENTAL-MODEL.md). For the cheat sheet (buckets, operators, modes, scripts), see [QUICK-REFERENCE.md](references/methodology/QUICK-REFERENCE.md).

---

> **The One Rule.** Misclassification is the cardinal sin. Anything that turns out to be (B) but is filed as (A) is technical debt cosplaying as physics. Anything that is (C) but is filed as (B) silently freezes the project at a worse Pareto frontier than necessary. Every `unsafe` site MUST receive a first-principles classification with a falsifiable justification — never a vibe.

**What this skill produces.** An in-project audit directory `<project>/.unsafe-audit/`, initialized as its own nested git repo. Inside it:

- `AUDIT_SUMMARY.md` — the user-facing tally, verification status, reviewer confidence, and first recommended actions.
- `unsafe-inventory.jsonl` — every `unsafe` site with rich metadata (full schema: [INVENTORY-SCHEMA.md](references/methodology/INVENTORY-SCHEMA.md)).
- `audit/sites/<crate>/<file>__<line>.md` — one write-up per site.
- `audit/synthesis/{invariants,soundness-surface,refactor-clusters}.md` — global cross-cut views.
- `audit/classification/site-NNNN.md` — per-site **(A) STRICTLY_UNAVOIDABLE / (B) PERF_ONLY / (C) REFACTORABLE** with falsifiable justification.
- `audit/plans/site-NNNN.md` — for (C): full safe rewrite + property / metamorphic / loom / miri equivalence proofs. For (B): `safe-only` Cargo feature implementation + criterion + hyperfine + flamegraph numbers. For (A): hardened SAFETY comment + proof-obligation lint.
- `verify.sh` + `ci-matrix.yml` — composite harness wiring miri + careful + loom + fuzz + mutants + geiger + the project's test suite under default AND `safe-only` features.
- `.beads/beads.jsonl` — task graph per `/beads-workflow`: parent epic per refactor cluster + one bead per site, with dependencies.
- `REVIEWER_RESPONSES.md` — maintainer-empathy fresh-eyes pass output.

Existing project source files are NEVER touched until the user explicitly authorizes refactor execution.

---

## What This Skill Is For

You point this skill at a Rust project (single crate, workspace, or polyrepo, any maturity) and ask one of these:

1. *"Audit every `unsafe` in this project and tell me what's avoidable."*
2. *"Eliminate all the unsafe you can without losing perf, ship the rest behind a `safe-only` feature flag."*
3. *"Convince me this `unsafe` block is actually necessary."*
4. *"Our crate has macro-generated unsafe we can't even see — find it."*
5. *"We depend on `<crate>` which uses unsafe; is that reachable through our safe API?"*
6. *"Build a verification harness so CI guards against new unsoundness."*

The skill answers each by routing through the same kernel (first-principles classification), the same operator library (cognitive moves), and the same 10-phase loop (enumerate → per-site write-up → synthesize → classify → plan → adversarial reclassify → fresh-eyes code review of rewrites → bead conversion → harness → maintainer-empathy review).

The pattern catalog is mined from a corpus of large Rust projects that already live in the target state — purely memory-safe except where genuinely impossible. Source repos: `/dp/asupersync`, `/dp/beads_rust`, `/dp/mcp_agent_mail_rust`, `/dp/pi_agent_rust`, `/dp/rich_rust`, `/dp/frankensqlite`, `/dp/frankentui`, `/dp/franken_engine`, `/dp/frankenlibc`, `/dp/frankenfs`. Their git history, beads, and the agent session corpus accessible via `cass` (locally and on `css` / `csd` / `ts1` / `ts2`) document not just the refactors we landed but the ones we explicitly rejected. Every pattern in this skill traces back to a real lived experience.

> **For users running the skill on YOUR project:** the `/dp/*` paths and `css` / `csd` / `ts1` / `ts2` hostnames above are the SKILL AUTHOR'S local references; they're not on your machine. The skill works fine without them — exemplar mining is optional. You'll see these references throughout the docs as case-study citations (e.g., `[E-001]` from `/dp/asupersync`, `[E-080]` from `/dp/frankenlibc`). They're institutional knowledge, not paths you need. See [PLATFORM-NOTES.md § Exemplar repos](references/methodology/PLATFORM-NOTES.md).

---

## Inputs

- **Target project path** (default: cwd) — absolute path to a Rust project, OR a git URL we should clone into `/tmp/<basename>`.
- **Mode** (auto-detected from project state, user-overridable; see [Mode Router](#mode-router)).
- **Audit directory** — default in-project `<project>/.unsafe-audit/`. The skill creates and `git init`s it as a nested audit repo; existing project source files stay read-only for everything up to a Phase 8 user-authorized refactor pass.
- **Toolchain profile** — `stable-only` (skip miri/loom) | `full` (nightly + miri + loom + fuzz + mutants — default and strongly recommended).
- **Perf budget** — `strict` (any measurable regression on the canonical bench suite fails the bar) | `5%` (default) | `10%` | `none` (favor safety unconditionally).
- **Execution authorization** — `audit-only` (default; no edits to project repo) | `refactor-on-approve` (user reviews the selected plan, then authorizes an active-checkout refactor pass; git worktrees are forbidden).

## Scope Governor

This skill is an unsafe-audit skill. It uses adjacent process tools, but it must not become a general Rust-refactoring, perf-tuning, or CI manual.

Before Phase 1, write `<audit-dir>/phase0_scope_decision.md` with:

- mode, toolchain profile, perf budget, execution authorization;
- crates / workspaces in scope and explicitly out of scope (with rationale);
- dependency crates whose unsafe is reachable through this project's public API — these MUST be in scope for the soundness-surface analysis even if we never modify them;
- conditional pattern bundles activated by the project's actual unsafe surface (FFI? SIMD? async? lock-free? allocator?);
- a short **not doing** list (e.g., "not changing the public API of `frankensqlite::Connection`", "not migrating off `libc` to nix").

Default to the smallest scope that fully covers the user request. A single-file audit stays a single-file audit unless the unsafe surface there shares invariants with surfaces in other crates.

Use progressive disclosure:

1. Always read `SKILL.md`, [OPERATING-MODES.md](references/methodology/OPERATING-MODES.md), [PHASES.md](references/methodology/PHASES.md), [CLASSIFICATION-RUBRIC.md](references/methodology/CLASSIFICATION-RUBRIC.md), [POLISH-BAR.md](references/methodology/POLISH-BAR.md), and only the pattern bundles the scope decision activates.
2. Read [CASS-MINING.md](references/methodology/CASS-MINING.md) only when prior unsafe-refactor sessions on similar codebases (most likely the listed exemplar repos) could change the plan.
3. Read pattern bundles only when their activation criteria fire (e.g., `60-FFI-PATTERNS.md` only if the project has `extern` blocks; `20-SIMD-AND-PERF.md` only if SIMD intrinsics or `std::arch` appear).

If a helper reference is not activated, document it as skipped in the scope decision; do not silently import its practices.

---

## Up-Front Confirmations (Ask Before Starting)

Use the intake template at `assets/intake-prompt.md` verbatim. The summary:

1. **Project path?** Confirm the absolute path. If a git URL, ask whether to clone to `/tmp/<basename>` and operate on that ordinary clone.
2. **Audit directory OK?** Default: in-project `<project>/.unsafe-audit/`. Confirm OK to create and `git init`. The skill writes every artifact there; existing project files stay untouched until Phase 8 + explicit authorization.
3. **Mode?** Show the auto-detected mode (Mode Router heuristic) and let the user override.
4. **Toolchain profile + perf budget + execution authorization?** Defaults: `full` toolchain, `5%` budget, `audit-only`.
5. **Missing tooling?** `ast-grep`, `cargo-geiger`, `cargo-careful`, `cargo-expand`, `cargo-fuzz`, `cargo-mutants`, `cargo-flamegraph`, `hyperfine`, nightly toolchain, `miri` component, `loom` (dev-dep). Propose exact install one-liners; install only after user confirmation. See [VERIFICATION-FIRST.md](references/methodology/VERIFICATION-FIRST.md).
6. **`ubs` available?** If `/ubs` skill and binary are installed, use them. If skill is missing and the user has `jsm` authenticated, offer `jsm install ubs`. If neither, install `ubs` per its README and proceed.
7. **Exemplar corpus accessible?** `/dp/asupersync` etc. Confirm whether to also mine remote hosts (`css`, `csd`, `ts1`, `ts2`) via `cass --host`.
8. **Resuming a prior run?** If `<audit-dir>/` already exists, offer to re-enter the phase loop where it left off (idempotent) or treat as a fresh run.
9. **CASS available?** If `/cass` is installed and indexed, run `subagents/cass-miner.md` BEFORE Phase 1 only when prior unsafe-refactor context could change scope, classification, or implementation ordering.

After the user answers, send the matching kickoff prompt from [KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md) verbatim.

Missing helper skills (`/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/extreme-software-optimization`, `/multi-pass-bug-hunting`, `/multi-model-triangulation`, `/idea-wizard`, `/beads-workflow`, `/beads-br`, `/beads-bv`, `/ubs`, `/agent-mail`, `/cass`, `/testing-real-service-e2e-no-mocks`, `/testing-metamorphic`, `/testing-fuzzing`, `/testing-conformance-harnesses`, `/deadlock-finder-and-fixer`): if `jsm` is installed + authenticated, offer `jsm install <name>` for each. Don't block a phase on a missing polish skill — fall back to the inline playbook in [SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md).

---

## Skill Bootstrap (Phase 0.5 — right after inputs, before Phase 1)

> **Path placeholders.** Throughout this document:
> - `<project>` — the absolute path to the Rust project being audited (the one the user passed in step 1 of intake).
> - `<audit-dir>` — `<project>/.unsafe-audit/` by default. The skill writes every artifact here.
> - `<skill-dir>` — the install location of this skill. Common installs are `~/.claude/skills/rust-unsafe-code-exorcist/` and `~/.codex/skills/rust-unsafe-code-exorcist/`. To resolve at runtime from inside a script, use the script's own directory; from agent context, prefer the actual skill directory you opened instead of assuming one home path.

**Step ordering matters.** The bootstrap scripts that take `<audit-dir>` write
artifacts under it; they reject scratch paths like `/tmp/...` via the shared
`audit-dir-guard.sh`. Create the in-project audit dir BEFORE running them:

```bash
# 1. Create the audit dir (the user must authorize this — it lives inside the project)
mkdir -p <project>/.unsafe-audit

# 2. Exclude it from the project's main git tracking (keeps PR diffs clean)
cp <skill-dir>/assets/audit-dir-gitignore.template <project>/.unsafe-audit/.gitignore
grep -qxF "/.unsafe-audit/" <project>/.git/info/exclude 2>/dev/null || \
  printf '%s\n' "/.unsafe-audit/" >> <project>/.git/info/exclude  # or add once to .gitignore if preferred

# 3. NOW the bootstrap scripts will accept it:
./scripts/check-skills.sh <project>/.unsafe-audit
# Prints helper-skill inventory + writes phase0_skill_inventory.json

./scripts/install-toolchain.sh --check <project>/.unsafe-audit
# Audits ast-grep / cargo-geiger / cargo-careful / cargo-expand / cargo-fuzz /
# cargo-mutants / cargo-flamegraph / hyperfine / nightly + miri + loom; writes
# phase0_toolchain.json and proposes per-missing-tool install one-liners (the
# user must approve before any install runs)
```

**`check-prerequisites.sh` is different** — it doesn't write artifacts so it
can (and should) be run BEFORE the audit dir exists, as the very first step
to learn what's installed.

### Offering to install missing tools

After the toolchain check, if `phase0_toolchain.json` lists missing components
the agent SHOULD ask the user whether to install them. Use your agent's normal
user-input mechanism; if no structured prompt tool is available, ask directly
in chat:

> *"The toolchain check found N missing component(s): {miri, cargo-geiger, ...}.
> Without them the audit will be DEGRADED (e.g., no dep-side baseline without
> cargo-geiger). Would you like me to install them now?*
> *  1. Install all missing tools — the install commands are documented in
>     phase0_toolchain.json. Each install gets a per-step confirmation.*
> *  2. Install only the ones critical for my mode (e.g., cargo-geiger for
>     forbid-soundness or dependency-soundness modes).*
> *  3. Skip installs — accept the degraded audit and document the gaps."*

If the user authorizes installs, run them with `bash <skill-dir>/scripts/install-toolchain.sh <audit-dir>` (no `--check` flag — this triggers the interactive install prompt). The script handles per-tool installation and re-checks the inventory afterward. **Never** install a tool without showing the install command and getting user confirmation. Each install is logged to `<audit-dir>/phase0/installs.log`.

If the user declines installs, proceed with the audit in degraded mode — the scripts produce explicit DEGRADED status reports rather than silently dropping signal (see `cargo-tree-soundness.sh` for the canonical example).

If skills are missing and `jsm` is installed + authenticated:

```bash
./scripts/install-referenced-skills.sh <audit-dir>
```

If `jsm` isn't installed, point the user at the official installer; the pipeline degrades gracefully with the inline fallbacks in [SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md).

Full bootstrap detail (subscription checks, headless OAuth, offline fallback, remote-host cass mining): **[SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md)** and **[CASS-MINING.md](references/methodology/CASS-MINING.md)**.

---

## Mode Router

Pick the primary mode first. The phase loop is the same; the **stop conditions and required artifacts** differ.

| Mode | Use when | Must finish with |
|------|----------|------------------|
| `audit-only` | Existing project; user wants a defensible report only | Inventory + per-site write-ups + classification + refactor plans + beads, no edits to project repo |
| `audit-and-refactor` | User wants selected (C) refactors landed + (B) feature-flagged + (A) hardened in the project repo | All of `audit-only` + active-checkout refactor pass; PRs are optional and use ordinary branches, never git worktrees |
| `harden-incident` | A specific unsoundness was reported (CVE, miri finding, prod crash, fuzz finding) | RCA-driven scoped audit + targeted refactor + regression bead/test pinned to the incident, then expand to a full `audit-only` |
| `dependency-soundness` | Project itself is mostly safe but pulls in unsafe-heavy deps | Soundness-surface map: which dep-unsafe is reachable from our public API + per-dep mitigation (wrap / replace / file upstream issue) |
| `forbid-soundness` | Project already declares `#![forbid(unsafe_code)]` (or `[lints.rust] unsafe_code = "forbid"`); audit verifies the forbid is structurally airtight and characterizes dep-side reachable unsafe | Forbid verification (attribute + Cargo lint + zero `allow(unsafe_code)` + zero source-level declarations + clean `cargo expand` accounting) + dep soundness surface map + tailored `verify.sh` + bead candidates |
| `verify-only` | Project already passed a prior audit; we want to assemble the CI verification harness only | `verify.sh` + CI matrix entry for `safe-only` + miri/loom/fuzz/mutants/geiger config |
| `pre-release-soundness-gate` | Before cutting a public crate release | Inventory + classification + harness clean + delta bead from prior audit baseline |
| `dual-feature-migration` | Add `safe-only` feature flag to a previously perf-only crate | (B) sites converted + CI matrix builds + measured perf deltas published |

Auto-detect heuristics (run by `scripts/detect-mode.sh`): count of `unsafe` in src, presence of `extern "C"` / `std::arch::*` / `MaybeUninit` / `Pin::new_unchecked`, dev-dep presence of `loom` / `criterion` / `cargo-fuzz`, existence of `safe-only` or similar feature, and recent commits with `unsafe|miri|loom|UB|soundness` in the message. The detector picks the mode and shows its reasoning; the user can override.

Full mode definitions, exit criteria, and required artifacts: **[OPERATING-MODES.md](references/methodology/OPERATING-MODES.md)**.

---

## The Phase Loop (Mandatory)

```
Phase 1  ENUMERATE          ast-grep + cargo-geiger + cargo expand + rustdoc JSON
                            + ubs + cargo tree, per crate, parallel
Phase 2  PER-SITE WRITE-UP  same agent that enumerated a section writes its
                            audit/sites/<crate>/<file>__<line>.md
Phase 3  SYNTHESIZE         cluster sites by invariant; build soundness-surface;
                            detect cross-site Send/Sync dependencies
Phase 4  CLASSIFY           (A) / (B) / (C) per CLASSIFICATION-RUBRIC; iterate
                            until two passes flip <5% of sites and zero (A)→(C)
Phase 5  PLAN-DRAFT         full safe rewrite per (C); safe-only impl per (B);
                            hardened SAFETY comment + proof obligation per (A);
                            final harmonization pass for contradictions
Phase 6  ADVERSARIAL        fresh-eyes reclassifier tries to defeat every (A);
                            tries to find safe-equivalent for every (B); tries
                            to break the equivalence claim of every (C); repeat
                            until two consecutive passes produce only marginal
                            reclassifications
Phase 7  FRESH-EYES CODE    the three verbatim review prompts against the
                            proposed safe rewrites; then run miri / careful /
                            loom / fuzz / mutants / geiger in this order
Phase 8  BEAD CONVERSION    /beads-workflow shape: parent epic per cluster,
                            implementation bead per (C) site, feature-flag-and-
                            CI-matrix bead per (B), SAFETY-comment-hardening bead
                            per (A); commit the audit repo
Phase 9  VERIFY HARNESS     verify.sh + CI matrix entry; if any pre-existing UB
                            surfaces, file as `pre-existing-ub` bead, NEVER fold
                            silently into the refactor plan
Phase 10 MAINTAINER-LENS    fresh agent reads the whole audit cold and answers:
                            "would I land these as the project maintainer?";
                            /idea-wizard generates alternative strategies the
                            original audit missed; /multi-model-triangulation
                            second-opinions the highest-risk (C) sites; write
                            REVIEWER_RESPONSES.md and revise plans
Phase 11 REMEDIATION-OFFER  (optional, user-gated) after AUDIT_SUMMARY.md is
                            written, ask the user if they want the agent to
                            apply the findings: install missing tools, file
                            candidate beads, apply (C) refactors, add (B)
                            safe-only feature, harden (A) SAFETY comments,
                            wire CI. See § "Phase 11 — Remediation Offer"
                            below for the exact prompt + per-finding-class
                            sub-flows.
```

**Phases 4 and 6** are *reapply-until-quiet* — keep spawning passes until an entire pass produces only marginal classifications/reclassifications (operational definition: fewer than 5% of sites flip bucket AND zero (A)→(C) reclassifications occur in two consecutive passes). Phase 7's two clean rounds (rewrite review) are the explicit termination gate before Phase 8.

**Phase 7 fresh-eyes prompts** — use verbatim. They are calibrated.

1. *"Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover."*
2. *"I want you to sort of randomly explore the proposed-rewrite files in this audit, choosing some to deeply investigate and trace their interaction with the surrounding crate, then do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, dropped error paths, lifetime sloppiness, panics-in-Drop, accidental allocator changes, async cancellation leaks, missing Drop-glue, or silent O() regressions, then systematically and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file."*
3. *"Ok can you now turn your attention to reviewing the rewrites written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!"*

Repeat until two consecutive rounds come up clean except for trivial changes. Then run, in this exact order:

```bash
cargo +nightly miri test                        # UB detection
cargo +nightly miri run --bin <each>            # for binaries miri can execute
cargo +nightly careful test                     # additional UB detection at runtime
cargo test --features loom_concurrency_tests    # any concurrency-touching rewrite
cargo fuzz run <target> -- -max_total_time=60   # for any new or widened pub surface
cargo mutants --in-place=false                  # tests must pin behavior, not vibes
cargo +nightly geiger                           # unsafe delta vs baseline
```

Fix every finding meticulously, preserving behavior, perf, and public API where possible. See [TOOLCHAIN-RUNBOOK.md](references/methodology/TOOLCHAIN-RUNBOOK.md) for the full sequencing and known-issue catalog (e.g., miri's `-Zmiri-disable-isolation` for tests that touch the filesystem; loom suite scoping via `RUSTFLAGS="--cfg loom"`).

### Mode variants on the phase loop

| Mode | Phases run | Key omissions / additions |
|------|-----------|---------------------------|
| `audit-only` | 1 → 10 (no project-repo edits) | Phase 8 commits only the audit repo + bead store; Phase 9 still builds harness but doesn't wire CI in project repo |
| `audit-and-refactor` | 1 → 10 + Phase 8.5 active-checkout refactor pass | After bead conversion, implement the authorized cluster/site in the active checkout or an ordinary branch; rerun Phase 7 against `<project>` |
| `harden-incident` | 1 (scoped to blast radius) → 4 → 5 (scoped) → 7 → 8 → expand to full audit-only | Skip parts of 3 outside the blast radius; expand later |
| `dependency-soundness` | 1 (deps + local) → 3 (soundness-surface emphasis) → 4 → 5 (wrap-or-replace plans for deps; SAFETY hardening of project-side bridges) → 7 → 8 → 9 | (C) work mostly = "wrap the dep's safe-API in a stricter abstraction"; some sites resolve to "file upstream issue" rather than land code |
| `forbid-soundness` | 1 (verify forbid + run `cargo expand` accounting) → 3 (dep-soundness-surface, in-tree synthesis is trivially empty) → skip 4–6 (no in-tree sites to classify or adversarially defeat) → 7 (run the verification harness) → 8 (file dep-hygiene + harness-wiring beads) → 9 (tailored `verify.sh` from `assets/verify-forbid-soundness.sh.template`) → 10 (maintainer review) | (A)/(B)/(C) in-tree counts are all 0 by definition; macro-expanded unsafe is informational only (built-in derives are exempt via `#[allow_internal_unsafe]`); the audit's value lives in dep characterization + drift detection — see [PROJECT-TYPES.md § Forbid-soundness](references/methodology/PROJECT-TYPES.md) and `references/patterns/40-MACRO-GENERATED-UNSAFE.md § Compiler-emitted derive unsafe` |
| `verify-only` | 9 (build harness from existing audit) → 10 (review) | Read prior audit dir; assemble harness + CI matrix only |
| `pre-release-soundness-gate` | 1 → 9 (full audit + harness) | Acceptance: `cargo +nightly geiger` delta vs baseline ≤ 0; all (A) sites have hardened SAFETY comments; CI matrix green on `default` AND `safe-only` |
| `dual-feature-migration` | 1 (scoped to perf-path) → 4 → 5 (B-only) → 7 → 8 → 9 | Skip (A) and (C) outside the perf path |

Full per-phase playbook with exact prompts: **[PHASES.md](references/methodology/PHASES.md)** and **[AGENT-PROMPTS.md](references/methodology/AGENT-PROMPTS.md)**.

---

## Phase 11 — Remediation Offer (optional, user-gated)

After `AUDIT_SUMMARY.md` is written, the agent presents the findings and offers to fix them. **This phase NEVER runs without explicit user authorization** — it goes beyond the initial `audit-only` authorization the user gave at intake.

### The opening prompt (two-tier)

Some agent input tools cap option counts, and presenting all sub-flows at once is also cognitively heavy on the user. Use a two-tier prompt instead:

**Tier 1 — overall posture** (one user question, 4 options):

| Option label | What it triggers |
|---|---|
| `Apply everything practical` | Run all sub-flows that have actionable findings for this project's mode. Skip empty buckets automatically. |
| `Selective — let me choose per category` | Drop into Tier 2 (iterate the sub-flows below, each as its own question). |
| `Just preparatory work` | Run only the sub-flows that don't edit source code: tools (1), beads (2), CI wiring (6). Sub-flows 3, 4, 5 are skipped. |
| `Skip remediation` | Stop here; the audit remains in `audit-only` posture. |

Phrase the question:

> *"The audit is complete and `AUDIT_SUMMARY.md` is in `<audit-dir>/`. You authorized this run as `audit-only`. The findings are:*
> *  - In-tree: A=<n_a> / B=<n_b> / C=<n_c>*
> *  - Dep-side: <n_deps> dep classes with unsafe; <m> missing tools*
> *  - Candidate bead commands: <n_beads> in `phase8_bead_commands.sh`*
> *How would you like to proceed?"*

Fill in the actual counts before asking. Suppress option 3 ("Just preparatory work") if NONE of sub-flows 1, 2, or 6 would do anything (no missing tools AND no candidate beads AND no CI wiring needed).

**Tier 2 — per-sub-flow drill-down** (only fires if user picked `Selective`).

Iterate the sub-flow list below. For each sub-flow with at least one actionable finding for this project, ask one binary user question:

> *"Apply sub-flow #N — <one-line description>? This will <one-line side effect>."*

Options: `Yes, apply this sub-flow` / `Skip this sub-flow` / `Stop iterating; revert to no remediation`.

**Sub-flow catalog** (used by both tiers):

1. **Install missing toolchain components** — cargo-geiger, miri, cargo-careful, etc. (Side effect: `rustup`/`cargo install` invocations against the user's toolchain.)
2. **File candidate beads** from `<audit-dir>/phase8_bead_commands.sh` via `br create` and `br dep add`. (Side effect: writes to the project's `.beads/` store.)
3. **Apply (C) REFACTORABLE rewrites** — full safe replacements with property tests. (Side effect: edits the active checkout after explicit approval; may create an ordinary branch/PR if the user asked for that; never creates git worktrees.)
4. **Add the `safe-only` feature flag** for (B) PERF_ONLY sites. (Side effect: edits `Cargo.toml` `[features]`, wraps (B) sites with `#[cfg(feature = "safe-only")]`, adds a CI matrix entry.)
5. **Harden (A) SAFETY comments** with proof-obligation skeletons. (Side effect: edits source files to add hardened SAFETY blocks above each (A) site.)
6. **Wire `verify.sh` into CI** — adds `.github/workflows/unsafe-audit.yml` from `assets/gh-actions-auditor.yml.template`. (Side effect: workflow file added. Honor any CI_SUPPLY_CHAIN.md policy.)

**Mode-aware suppression.** When asking Tier 1 or Tier 2, suppress sub-flows that have nothing to do:

- `forbid-soundness` mode: suppress 3, 4, 5 (no in-tree sites). Emphasize 1, 2, 6.
- `dependency-soundness` mode: 3 and 4 usually empty; 5 may still apply to project-side FFI bridges.
- `audit-only` with non-zero in-tree unsafe: all six available.
- `verify-only`: suppress 2, 3, 4 (already done in prior audit); 1 and 6 may apply.

### Sub-flow per selection

#### 1. Install missing toolchain components

```bash
bash <skill-dir>/scripts/install-toolchain.sh <audit-dir>
# This script:
#   - re-reads phase0_toolchain.json
#   - shows the list of missing tools with install commands
#   - interactively prompts "Install missing tools now? [y/N]"
#   - on yes: runs each install command, then re-checks
```

**Agent behavior in agent sessions (no TTY):** the interactive prompt won't work. Two safe paths:

1. **`--install-confirmed` flag (preferred when installing more than one tool).** This is a script flag that bypasses the interactive prompt and logs each install to `<audit-dir>/phase0/installs.log`. Use only AFTER you've shown the user the install list through the active agent's user-input mechanism and they authorized it.

   ```bash
   # 1. Show the user the install list and get authorization
   #    (for tools that support multi-select, present missing tools as choices)
   # 2. If they authorize, run:
   bash <skill-dir>/scripts/install-toolchain.sh --install-confirmed <audit-dir>
   ```

2. **Direct `cargo install` (preferred for single tools).** Read `<audit-dir>/phase0_toolchain.json`, show the user the missing tools, then run each authorized tool's `install_cmd` directly via Bash. Capture output to `<audit-dir>/phase0/installs.log`.

Never `echo y |` into the interactive prompt — that bypasses the per-tool review the user expects. Use `--install-confirmed` (which is explicit about its bypass-with-prior-authorization semantics) or direct `cargo install` instead.

After installs complete, **re-run** the relevant scripts (`cargo-tree-soundness.sh`, `enumerate-unsafe.sh`, `verify.sh`) to update the artifacts that were previously degraded. Document the upgrade in `<audit-dir>/phase11/post-install-deltas.md`.

#### 2. File candidate beads via `br create`

```bash
# Either run the generator if it exists:
node <skill-dir>/scripts/generate-bead-graph.mjs <audit-dir>
# Review, then execute the generated commands script when authorized:
bash <audit-dir>/phase8_bead_commands.sh

# Verify after (use 'br list' not 'br ready' — newly-filed beads may have
# dependencies that exclude them from ready):
br list --json | jq '[.issues[] | select(.labels[]? // empty | test("^unsafe-audit-"))] | length'
```

**Agent behavior:** ask which beads to create (show the generated `br create` / `br dep add` commands from `phase8_bead_commands.sh`). Default to all generated commands unless the user requests a narrower subset; if subsetting, preserve the parent/child dependency commands for every selected bead. After creation, **run `br sync --flush-only`** so the JSONL is up to date, then tell the user the bead IDs.

#### 3. Apply (C) REFACTORABLE rewrites

This is the heart of `audit-and-refactor` mode. Git worktrees are forbidden here. Per authorized cluster or site (from `<audit-dir>/audit/synthesis/refactor-clusters.md`):

1. Confirm the active checkout is the intended project and run `git status --short`. Preserve all existing user/peer edits; never stash, reset, clean, or overwrite unrelated files.
2. If the user wants a PR and branch creation is allowed, create or switch to an ordinary branch in the active checkout, e.g. `git switch -c unsafe-exorcist/<cluster-id>`. If branch changes are not appropriate, work on the current branch and make the diff reviewable with explicit file lists.
3. Reserve the exact files to be edited with Agent Mail when available; claim/update beads when the project uses beads.
4. Apply the safe rewrites from `<audit-dir>/audit/plans/site-<id>.md` directly in `<project>` using incremental manual edits.
5. Run the property-based equivalence test from the same plan.
6. Run miri / loom / fuzz / mutants on the rewrite (the verify.sh harness against `<project>`).
7. If GREEN: commit or open a PR only according to the user's repo workflow and link the bead.
8. If RED: file the failure as a `pre-existing-ub` bead per [PRE-EXISTING-UB-PROTOCOL.md](references/methodology/PRE-EXISTING-UB-PROTOCOL.md); do NOT widen the refactor scope.

**Use the existing `subagents/worktree-implementer.md` prompt only as the legacy file path for this role.** Its contents now enforce the active-checkout protocol above and must not create git worktrees.

Stop conditions for the agent:
- All user-authorized (C) sites/clusters processed and verified, OR
- User says stop after N clusters, OR
- A pre-existing-ub finding requires user triage.

#### 4. Add `safe-only` feature flag

Per cluster, follow `references/patterns/20-SIMD-AND-PERF.md § Safe-only feature flag`:

1. Add `safe-only = []` to `[features]` in `Cargo.toml`.
2. Wrap each (B) site with `#[cfg(feature = "safe-only")]` for the safe path and `#[cfg(not(feature = "safe-only"))]` for the unsafe perf path.
3. Add the CI matrix entry from `<skill-dir>/assets/ci-matrix.yml.template`.
4. Run `bench-before-after.sh` per site to publish the measured perf delta.

#### 5. Harden (A) SAFETY comments

Per (A) site in `<audit-dir>/audit/classification/`:

1. Read the existing SAFETY comment (or note its absence).
2. Use `<skill-dir>/scripts/generate-safety-skeleton.sh` to produce a fillable template.
3. Edit the project source in-place to add the hardened SAFETY comment.
4. (Optional) Add a custom clippy lint per `references/methodology/CLIPPY-LINT-AUTHORING.md` that enforces the proof obligation at compile time.

#### 6. Wire `verify.sh` into CI

**Read `docs/CI_SUPPLY_CHAIN.md` in the project root first.** If the project requires CI workflow review (e.g., per beads_rust's AGENTS.md), STOP and ask the user to handle CI wiring manually — DO NOT modify `.github/workflows/` unilaterally.

If no such policy exists, emit `.github/workflows/unsafe-audit.yml` from `<skill-dir>/assets/gh-actions-auditor.yml.template`, with the runners + cargo invocation customized to the project.

### Phase 11 end state

Whatever the user chose, write `<audit-dir>/PHASE11_LOG.md` documenting:
- Which sub-flows ran
- What artifacts changed (with file paths)
- Which beads got created
- What's still TODO (especially "user must decide on CI wiring")

Then write the final `AUDIT_SUMMARY.md § Remediation Outcome` section with a tally of fixed vs filed vs skipped findings.

---

## Parallelism Model

The repo's unsafe surface partitions naturally along crate boundaries (workspaces) or module boundaries (single crate). Phase 1 enumeration runs one agent per crate; the same agent that enumerated a partition writes the Phase 2 per-site files for that partition (continuity of context > marginal parallelism gains).

```
┌──────────────────────────────────────────────────────────────────────┐
│  PARTITION (Phase 1, by main agent)                                  │
│  ─> cargo metadata --format-version 1 | jq '.workspace_members'      │
│     assign one enumerator+writer per crate/module                    │
└────────────────┬─────────────────────────────────────────────────────┘
                 │
   ┌─────────────┼──────────────┬──────────────┬───────────────────┐
   ▼             ▼              ▼              ▼                   ▼
┌─────────┐  ┌─────────┐    ┌─────────┐    ┌─────────┐         ┌─────────┐
│ Crate A │  │ Crate B │    │ Crate C │    │ Crate D │   ...   │ Crate N │
│ Phase 1 │  │ Phase 1 │    │ Phase 1 │    │ Phase 1 │         │ Phase 1 │
│ Phase 2 │  │ Phase 2 │    │ Phase 2 │    │ Phase 2 │         │ Phase 2 │
└────┬────┘  └────┬────┘    └────┬────┘    └────┬────┘         └────┬────┘
     │            │              │              │                    │
     └────────────┴──────────────┴──────────────┴────────────────────┘
                                 │
                                 ▼
                       ┌──────────────────────┐
                       │ Phase 3 SYNTHESIZE   │  single agent, global view:
                       │ (invariants,         │  clusters by shared invariant;
                       │  soundness-surface,  │  reachability-from-safe-API;
                       │  refactor-clusters)  │  cross-site Send/Sync deps
                       └──────────┬───────────┘
                                  ▼
                       ┌──────────────────────┐
                       │ Phase 4 CLASSIFY     │  iterative; reapply until
                       │ A/B/C buckets        │  two passes are marginal
                       └──────────┬───────────┘
                                  ▼
                       Phase 5 PLAN-DRAFT swarm (parallel per cluster)
                                  ▼
                       Phase 6 ADVERSARIAL swarm (parallel; different agents)
                                  ▼
                       Phase 7 FRESH-EYES swarm (parallel + multi-model)
```

**Coordination.** Use [MCP Agent Mail](../agent-mail/SKILL.md) file reservations whenever two agents could touch the same `audit/sites/<...>.md` (especially during the iterative Phase 4/6 passes). Thread id: `unsafe-exorcist-<run-id>-<phase>-<crate>`.

**Orchestration tier** — pick based on workspace size + unsafe density:

| Tier | Shape | When |
|------|-------|------|
| Solo | 1 worker, serial phases | Single crate, <20 unsafe sites |
| Pair | 2 workers, fan-out only on Phase 1/2 | Single crate, 20–100 sites |
| Squad | 4–6 workers, parallel by crate; multi-model on Phase 7 | Workspace, 100–500 sites |
| Swarm | 8–12+ workers, beads-driven + multi-model triangulation in Phase 6 and Phase 7 | Polyrepo or deeply-recursive macro-generated unsafe |

Triangulation (Claude + Codex + Gemini) is reserved for Phase 6 adversarial reclassification and Phase 7 fresh-eyes review of the proposed safe rewrites, where independent reads produce the highest signal. See **[ORCHESTRATION.md](references/methodology/ORCHESTRATION.md)**.

---

## Three-Bucket Classification (the Cardinal Sin to Get Wrong)

Every `unsafe` site MUST be in exactly one bucket, with a falsifiable written justification. The full rubric (anti-patterns of misclassification, examples, the falsification test per bucket) is in **[CLASSIFICATION-RUBRIC.md](references/methodology/CLASSIFICATION-RUBRIC.md)**. Summary:

### (A) STRICTLY_UNAVOIDABLE

> There is no safe-Rust formulation that achieves the same goal correctly and acceptably. The `unsafe` is upholding a soundness invariant that the language's type system cannot express today.

Canonical examples (see [00-CANONICAL-UNAVOIDABLE.md](references/patterns/00-CANONICAL-UNAVOIDABLE.md)):

- FFI into C/C++/system libraries (`extern "C" { ... }`), raw syscalls via `libc`
- `mmap`/`io_uring`/`epoll` edge-triggered surfaces
- Atomic primitives that the safe wrappers don't expose (e.g., `fence`, `atomic_load_unsynchronized`)
- Intrinsics required for soundness of a higher-level safe abstraction (e.g., `core::hint::unreachable_unchecked` where exhaustiveness is proved upstream)
- Allocator implementations (`GlobalAlloc::alloc`)
- Certain `Pin` projection helpers in async runtimes
- Code that bridges to the language runtime itself

**Falsification test** — to be filed as (A), the write-up MUST include the form:

> "This is unavoidable BECAUSE <citing Rust Reference / RFC / nomicon section / concrete failed safe experiment>. The following alternatives FAIL for this specific reason: 1. <alt> → <why>. 2. <alt> → <why>. 3. <alt> → <why>."

Vague "for performance" claims are NOT (A) — those are (B). "Because that's how everyone does it" is NOT a justification.

### (B) PERF_ONLY

> The `unsafe` exists purely for measurable, profiled, regression-tested speed. The safe formulation is known to exist and be correct; the question is whether the perf delta is worth the safety cost.

Canonical examples (see [20-SIMD-AND-PERF.md](references/patterns/20-SIMD-AND-PERF.md), [30-CONCURRENCY-PATTERNS.md](references/patterns/30-CONCURRENCY-PATTERNS.md)):

- SIMD intrinsics where `std::simd` / `wide` / autovectorization-friendly loops would suffice
- `slice::get_unchecked` / `slice::get_unchecked_mut` for indexed hot loops
- Hand-rolled prefetch (`core::intrinsics::prefetch_*`)
- Hot-path lock-free sequences (CAS loops) where `arc-swap` / `crossbeam` would do
- `Box::from_raw` / `Box::into_raw` round-trips inside an arena allocator

**Obligation** — every (B) site MUST get:

1. A strictly memory-safe alternative implementation gated behind a Cargo feature flag (suggested name: `safe-only` or `no-unsafe`).
2. Measured before/after numbers from `cargo bench` (criterion) AND end-to-end timing (`hyperfine`) AND flamegraph diff (`cargo-flamegraph`). Numbers go in `audit/plans/site-<id>.md` and the bead.
3. A CI matrix entry that builds and tests under `--features safe-only` (or whatever name the project picks).
4. If the perf claim turns out to be folklore (no measurable regression from the safe alternative, within the user's chosen perf budget), the site graduates from (B) to (C). Document the graduation.

### (C) REFACTORABLE

> There is at least one plausible, isomorphic-or-nearly-so safe rewrite. The skill drafts the full safe replacement code (not pseudocode) and proves behavioral equivalence via property-based tests, metamorphic tests, `loom` (for concurrency-touching rewrites), and `miri` (for UB detection).

Canonical examples (see [10-POINTER-MIGRATIONS.md](references/patterns/10-POINTER-MIGRATIONS.md), [40-MACRO-GENERATED-UNSAFE.md](references/patterns/40-MACRO-GENERATED-UNSAFE.md)):

- Raw pointer → `NonNull` → `Pin<&mut T>` → fully owned safe type
- `mem::transmute<T, U>` where `zerocopy` / `bytemuck` would do
- Hand-written `MaybeUninit::assume_init` patterns where `init_array` + safe initializer suffices
- `unsafe impl Send/Sync` where a sound auto-derive holds after a small refactor
- Macro-generated unsafe inside `derive` macros where a safer derive crate exists (e.g., `zerocopy-derive`)
- Manual `UnsafeCell` patterns where `Cell` / `RefCell` / `OnceCell` suffices

**Obligation** — every (C) site MUST get:

1. Full safe replacement code (not pseudocode, not a sketch).
2. A property-based equivalence test (`proptest` / `quickcheck`) generating inputs that exercise the full state space — including the failure modes the old unsafe code handled.
3. A metamorphic test (per `/testing-metamorphic`) where applicable, encoding invariants of the form "for any input x, `f(transform(x)) == transform(f(x))`".
4. A `loom` model test if the rewrite touches concurrency.
5. A `miri` run that exercises the rewrite under the same inputs the property test generates.
6. An estimate of risk (Low / Medium / High) and the API-surface change (if any).

### Iteration discipline

Phase 4 reapplies the classifier until two consecutive passes have <5% bucket flips AND zero (A)→(C) flips. Phase 6 then reapplies an *adversarial* reclassifier (a fresh agent that hasn't seen the prior classification) that tries to defeat every (A) by proposing a safe alternative, hunts for missed safe-equivalents in (B), and constructs inputs that would break the equivalence claim of (C). The adversarial pass also reapplies until quiet.

The cumulative effect: by the time you exit Phase 6, every (A) has survived an adversarial defeat attempt, every (B) has survived an alternative-search, and every (C) has survived a stress-test of its equivalence claim.

---

## Cognitive Operators (Unsafe-Thinking Moves)

Composable moves. Apply them to any `unsafe` block, `unsafe fn`, `unsafe impl`, FFI surface, or proposed safe rewrite. Each operator is a question that, if it fails, names the section to fix. See **[OPERATORS.md](references/methodology/OPERATORS.md)** for the full card library with triggers, failure modes, and prompt modules.

| Glyph | Name | Question | Fix-section |
|-------|------|----------|-------------|
| `⊙` | **Invariant-Locator** | "What is the soundness invariant this `unsafe` is upholding, and who enforces it?" | `CLASSIFICATION-RUBRIC` §invariant-discovery |
| `⊕` | **Reachability-From-Safe** | "Is this `unsafe` reachable from a safe public API? If so, the invariant must be enforced before the unsafe runs." | `references/patterns/50-SEND-SYNC-IMPLS.md` |
| `⊗` | **Falsifiable-Justification** | "Have I stated, in a form a reviewer can attack, WHY a safe alternative fails?" | `CLASSIFICATION-RUBRIC` §(A)-falsification |
| `⌖` | **Macro-X-Ray** | "Does `cargo expand` reveal `unsafe` inside macro output that the source code never shows?" | `references/patterns/40-MACRO-GENERATED-UNSAFE.md` |
| `⏱` | **Profile-Or-It-Didn't-Happen** | "Do I have a `cargo bench` + `hyperfine` + flamegraph showing the perf delta, or is this folklore?" | `references/patterns/20-SIMD-AND-PERF.md` |
| `🔒` | **Panic-In-Drop-Trace** | "If a panic unwinds through this unsafe, what state does it leave the world in?" | `references/patterns/00-CANONICAL-UNAVOIDABLE.md` §unwinding |
| `🔁` | **Async-Cancellation-Trace** | "If the future containing this unsafe is dropped at an await point, is every invariant restored?" | `references/patterns/80-PIN-PROJECTIONS.md` |
| `⚖` | **Send-Sync-Audit** | "Does this `unsafe impl Send/Sync` quietly assume an invariant enforced elsewhere?" | `references/patterns/50-SEND-SYNC-IMPLS.md` |
| `🪟` | **FFI-Boundary-Contract** | "What does the C side promise? What does the Rust side promise? Is there a written contract?" | `references/patterns/60-FFI-PATTERNS.md` |
| `🗄` | **Init-Order-Discipline** | "Does `MaybeUninit::assume_init*` run only after every field has been written?" | `references/patterns/70-UNINIT-AND-TRANSMUTE.md` |
| `⊞` | **Loom-Reachable-Interleaving** | "Have I exhausted the interleavings under `loom` that could violate the invariant?" | `references/methodology/TOOLCHAIN-RUNBOOK.md` §loom |
| `🧪` | **Equivalence-Witness** | "Do I have a property-based test where the unsafe version and the safe rewrite produce identical output on the same input?" | `references/patterns/10-POINTER-MIGRATIONS.md` §equivalence |
| `🔐` | **Soundness-Surface-Marker** | "Is this `unsafe` reachable from `pub`? If yes, it lives on the project's soundness surface." | `references/methodology/PHASES.md` §3 |
| `📐` | **Allocator-Identity** | "Did the proposed safe rewrite quietly change the allocator (e.g., `Vec` instead of arena)?" | `references/patterns/00-CANONICAL-UNAVOIDABLE.md` §allocator |
| `🪞` | **Bidirectional-Geiger** | "Has `cargo +nightly geiger` delta vs baseline been computed? Does it match the planned change?" | `references/methodology/TOOLCHAIN-RUNBOOK.md` §geiger |
| `⚑` | **Pre-Existing-UB-Isolator** | "Did Phase 9 turn up UB that wasn't in scope? File it as a separate `pre-existing-ub` bead — never fold it into the refactor plan." | `references/patterns/90-OPERATIONS.md` §pre-existing-UB |
| `⤴` | **Drop-Glue-Sanity** | "After the rewrite, does every owned resource still run its destructor on every exit path (panic, return, await drop)?" | `references/patterns/00-CANONICAL-UNAVOIDABLE.md` §unwinding |

Operators are deliberately overlapping — a single FFI block typically deserves four or five. Application order in Phase 5/6: see [OPERATORS.md § Composition cheat-sheet](references/methodology/OPERATORS.md#composition-cheat-sheet).

---

## The Polish Bar (Non-Negotiable)

A "good unsafe audit" is not "we enumerated the unsafe and grouped it." Every site must pass:

| Dimension | Test |
|-----------|------|
| **Invariant named** | The write-up names the exact soundness invariant the `unsafe` upholds and who enforces it. |
| **Falsifiable justification** | For (A), the form "unavoidable BECAUSE <X>, alternatives FAIL FOR <Y>" is present and survives Phase 6 adversarial review. |
| **Profile-or-it-didn't-happen** | For (B), `cargo bench` + `hyperfine` + flamegraph numbers are pasted into the plan; perf delta is within the user's budget either way. |
| **Equivalence witness** | For (C), a property-based test exists that exercises the failure modes of the old unsafe code, AND a `miri` run is clean on the rewrite. |
| **Macro-expanded view** | Every unsafe site that originated in macro output is verified against `cargo expand` output, not just source text. |
| **Soundness-surface marker** | Every site flagged as reachable from a `pub` API has a SAFETY comment that names the caller-side proof obligation. |
| **Send/Sync audit** | Every `unsafe impl Send/Sync` write-up names the field-level invariants the impl assumes and traces who enforces them. |
| **Drop-glue sanity** | The rewrite has been traced for panic-in-Drop and async-cancellation paths; every owned resource has its destructor proved to run on every exit. |
| **Allocator identity preserved** | The rewrite did not silently swap a custom allocator (arena / bump / slab) for the global allocator. |
| **Pre-existing-UB separated** | Any UB discovered in code that was NOT in scope for refactor is filed as `pre-existing-ub-N` bead, not folded into the refactor plan. |
| **Bead acceptance criteria** | Each bead's acceptance criteria are exact `cargo` invocations a maintainer can copy-paste. |
| **Maintainer-empathy review** | Phase 10 reviewer has read the audit cold and answered "would I land this?" — and the response is filed in `REVIEWER_RESPONSES.md`. |

If a site fails the bar, it's a Phase 5 / 6 rework target — not a "ship it." Full rubric, per-bucket checklists, and verification queries: **[POLISH-BAR.md](references/methodology/POLISH-BAR.md)**.

---

## Project-Type Defaults

Phase 0 detection picks a template. See **[PROJECT-TYPES.md](references/methodology/PROJECT-TYPES.md)** for the per-shape adjustments. Defaults in this skill are calibrated for the *primary* shape (the one the exemplar corpus was mined from):

| Shape | Default partition | Default tier | Emphasis bundles |
|-------|------------------|--------------|------------------|
| **Forbid crate** (already declares `forbid(unsafe_code)`) | Single agent (in-tree is empty by definition) | Solo | 40-MACRO (for `cargo expand` accounting) + 00-CANONICAL (for dep-side allocator/FFI patterns); Phases 4–6 collapse. See [PROJECT-TYPES.md § Forbid-soundness](references/methodology/PROJECT-TYPES.md). |
| Single binary crate | One agent per top-level `src/<module>` | Solo / Pair | 40-MACRO + 70-UNINIT + 00-CANONICAL |
| Single library crate | One agent per top-level `src/<module>` | Pair | 10-POINTER + 50-SEND-SYNC + 40-MACRO |
| Workspace (≤10 members) | One agent per crate; synthesis owns the cross-crate Send/Sync | Squad | All bundles activate; emphasis on `dependency-soundness` |
| Workspace (>10 members) | One agent per `[workspace.members]` group | Swarm | + `60-FFI-PATTERNS` if any member has `extern` |
| Polyrepo | Clone all and treat as workspace; or run one audit per repo and synthesize a meta-soundness-surface | Swarm | Cross-repo soundness-surface synthesis |
| FFI-heavy crate (e.g., `frankenlibc`-style) | One agent per `extern` block | Pair / Squad | 60-FFI dominates; (A) bucket will be large; the work is hardening, not removal |
| SIMD-heavy crate (e.g., portions of `rich_rust`) | One agent per target-arch (`x86_64`, `aarch64`, …) | Pair / Squad | 20-SIMD dominates; (B) bucket will be large; `safe-only` feature is the main deliverable |
| Async-runtime crate | One agent per `Pin`-projection cluster | Squad | 80-PIN dominates; loom suite is mandatory |
| Allocator / arena crate | One agent per allocation strategy | Squad | 00-CANONICAL §allocator dominates; miri stacked-borrows mode mandatory |

Full per-shape playbook: **[PROJECT-TYPES.md](references/methodology/PROJECT-TYPES.md)**.

---

## Anti-Patterns (Never Do)

| ✗ | Why | Fix |
|---|-----|-----|
| Enumerate `unsafe` with `grep -r 'unsafe'` | Misses macro-generated unsafe, comment hits, and string-literal hits; doesn't differentiate `unsafe fn` from `unsafe { }` from `unsafe impl` | Use `ast-grep` per kind + `cargo expand` for macro coverage; see [enumerate-unsafe.sh](scripts/enumerate-unsafe.sh) |
| File something as (A) "because perf" | Perf-only sites are (B), not (A); (A) is for soundness-impossibility, not speed | Reclassify to (B); produce the safe-only impl and the perf numbers |
| File something as (B) without numbers | "It's faster" is folklore; the project deserves a measurement | Run `cargo bench` + `hyperfine` + flamegraph; paste numbers in the plan; if no regression, graduate to (C) |
| File something as (C) without a property-based equivalence test | "Looks equivalent" is not equivalent | Add `proptest` / `quickcheck`; exercise the failure modes of the old unsafe; run under miri |
| "Optimize" by rewriting an entire file with a replacement | Per AGENTS.md, no destructive rewrites; use incremental `Edit` only | Cluster the refactor into per-site edits; preserve all surrounding content |
| Skip Phase 6 (adversarial reclassification) | (A) judgments without an adversarial defeat attempt drift into folklore | Run the adversarial agent; iterate until quiet |
| Silently fold a pre-existing UB finding into the refactor plan | Conflates "we made it worse" with "we found something old" | File as `pre-existing-ub-N` bead; never bundle |
| Rewrite SIMD using `std::simd` without measuring | `std::simd` is good but not magic; some vectorizations regress on older targets | Run cross-target benches (x86_64-v2/v3/v4, aarch64-neon) before claiming equivalence |
| Replace a custom allocator (arena / bump) with `Vec` "for safety" | Silent allocator identity change is a behavioral regression | Preserve allocator semantics with `bumpalo` or similar safe arena; document the choice |
| Refactor `unsafe impl Send/Sync` without auditing every field | The impl quietly assumes invariants enforced elsewhere; removing it can be a soundness regression | Audit field-level Send/Sync; if removable, prove it via `static_assertions::assert_impl_all!` |
| Touch existing project source files before user authorization | The audit dir is the contract; source files and Cargo config are read-only until Phase 8+ + explicit user OK | Stay in `<audit-dir>/`; produce plans; commit to the audit dir; ask before touching project files |
| Skip `cargo expand` on `derive`-heavy crates | Macro-generated unsafe is invisible to source-text greps | Run `cargo expand` per crate as part of Phase 1 enumeration |
| Use `cargo +nightly miri test` once and call the rewrite proven | Miri sometimes can't run tests that touch the filesystem / network; some UB only triggers on specific stacked-borrows configurations | Use `-Zmiri-disable-isolation` and `-Zmiri-strict-provenance` per the runbook; run both default and strict modes |
| Decide a `safe-only` build is "too slow" without a published comparison | Without numbers, "too slow" is a guess | Publish flamegraph + criterion + hyperfine for both feature sets; let the user decide |
| Pin classification on what the SAFETY comment claims | The SAFETY comment may be stale; trust the call graph | Trace each invariant through the call graph; verify the SAFETY claim is still true today |
| Replace `unsafe` with `expect()` everywhere | Panics in Drop and async-cancellation paths can themselves cause UB / leaks | Reach for `Result` + `?` first; reserve `expect` for true unreachables documented in the SAFETY comment |

Full anti-pattern catalog with rejection rationale and the exemplar-repo precedents: **[references/patterns/90-OPERATIONS.md § Patterns tried and rejected](references/patterns/90-OPERATIONS.md#patterns-tried-and-rejected)**.

---

## Verification-First (mandatory)

The methodology in this skill is evergreen. Toolchain availability and behavior change with nightly drift, miri changes, and crate releases. Read **[VERIFICATION-FIRST.md](references/methodology/VERIFICATION-FIRST.md)** before finalizing any recommendation that depends on a specific miri / nightly / loom / cargo-fuzz / cargo-mutants / cargo-geiger version.

Core rule: do not claim a rewrite is sound until it has passed `cargo +nightly miri test` AND `cargo +nightly careful test` AND (where applicable) `loom` AND the verify.sh harness, all logged in `<audit-dir>/verification-log.md`. A green miri run on a single commit is not a proof of soundness for the rewrite — it's a successful experiment.

The verification harness lives in **[references/patterns/90-OPERATIONS.md § verify.sh](references/patterns/90-OPERATIONS.md#verifysh)** with paste-ready commands for every tool listed above, plus CI matrix templates for GitHub Actions.

---

## Source Corpus (Track A from /operationalizing-expertise)

This skill IS a Track A artifact:

- **Corpus** — the exemplar repos `/dp/asupersync`, `/dp/beads_rust`, `/dp/mcp_agent_mail_rust`, `/dp/pi_agent_rust`, `/dp/rich_rust`, `/dp/frankensqlite`, `/dp/frankentui`, `/dp/franken_engine`, `/dp/frankenlibc`, `/dp/frankenfs` — read both present-day source and git history (commits that removed `unsafe`, swapped raw pointers for `Pin<&mut T>`, replaced manual SIMD with `std::simd` or `wide` behind a feature flag, factored an FFI surface into a thin unsafe shim).
- **Quote bank** — `references/source/EXEMPLAR-CATALOG.md` indexes each repo's canonical patterns with anchors of the form `[E-NNN]`.
- **Triangulated kernel** — the classification rubric in [CLASSIFICATION-RUBRIC.md](references/methodology/CLASSIFICATION-RUBRIC.md).
- **Operator library** — 17 operators in [OPERATORS.md](references/methodology/OPERATORS.md).
- **Validators** — the audit scripts in `scripts/` plus the `verify.sh` template in [90-OPERATIONS.md](references/patterns/90-OPERATIONS.md).

When extending the skill: add the source pattern to `EXEMPLAR-CATALOG.md` with a `[E-NNN]` ID, propose a kernel addition (rare), or add a new operator card. See [SOURCE-CORPUS.md](references/methodology/SOURCE-CORPUS.md) for the extension protocol.

Most accretive mining channel: **`cass`** session history. The exemplar repos accumulated their refactor reasoning over many agent sessions. Run `cass search` (locally and on `css` / `csd` / `ts1` / `ts2` via `cass --host`) per the recipes in [CASS-MINING.md](references/methodology/CASS-MINING.md) to surface the reasoning behind refactors that landed AND the ones we rejected.

---

## Pre-Flight & End Checklist

- [ ] Project path confirmed; in-project audit dir named, created, `git init`-ed
- [ ] `phase0_scope_decision.md` written: mode + toolchain profile + perf budget + execution authorization + crates in/out of scope + dep crates whose unsafe is reachable
- [ ] Helper skills inventoried; missing ones offered via `jsm install` (non-blocking)
- [ ] Toolchain inventoried; missing tools proposed with exact install one-liners (user must approve)
- [ ] Phase 1 enumeration produced `unsafe-inventory.jsonl`; rows include kind, public-API exposure, macro-origin, FFI flag, intrinsic flag
- [ ] Phase 2 per-site write-ups produced under `audit/sites/`; every inventory row has a corresponding `.md`
- [ ] Phase 3 synthesis produced `invariants.md`, `soundness-surface.md`, `refactor-clusters.md`
- [ ] Phase 4 classification reapplied until marginal (<5% bucket flips AND zero (A)→(C) flips for two consecutive passes)
- [ ] Phase 5 plans drafted: full safe rewrite per (C), `safe-only` impl per (B), hardened SAFETY + proof obligation per (A); final harmonization done
- [ ] Phase 6 adversarial reclassification reapplied until quiet
- [ ] Phase 7 fresh-eyes review ran ≥2 clean rounds; miri + careful + loom + fuzz + mutants + geiger run in order; every finding fixed
- [ ] Phase 8 bead graph generated; `<audit-dir>/.beads/` committed
- [ ] Phase 9 `verify.sh` runs green on `default` + `safe-only`; `pre-existing-ub` beads filed separately for findings outside scope
- [ ] Phase 10 maintainer-empathy review filed in `REVIEWER_RESPONSES.md`; plans revised per feedback; `/idea-wizard` ran; `/multi-model-triangulation` ran on highest-risk (C) sites
- [ ] Phase 11 (optional, only if user authorized): remediation outcome logged in `<audit-dir>/PHASE11_LOG.md`; `AUDIT_SUMMARY.md § Remediation Outcome` updated with fixed/filed/skipped tally; for sub-flows that touched project source files, the changes are in the active checkout or an ordinary branch according to the user's repo workflow (not landed on `main` unilaterally)

---

## Reference Index

### Methodology
| Need | File |
|------|------|
| Mode definitions + exit criteria | [OPERATING-MODES.md](references/methodology/OPERATING-MODES.md) |
| Per-phase playbook with exit criteria | [PHASES.md](references/methodology/PHASES.md) |
| Exact prompts for each parallel subagent | [AGENT-PROMPTS.md](references/methodology/AGENT-PROMPTS.md) |
| Per-mode kickoff prompts (verbatim) | [KICKOFF-PROMPTS.md](references/methodology/KICKOFF-PROMPTS.md) |
| (A) / (B) / (C) rules + falsification tests + worked examples | [CLASSIFICATION-RUBRIC.md](references/methodology/CLASSIFICATION-RUBRIC.md) |
| **Inventory schema** — per-field documentation of `unsafe-inventory.jsonl` + `kind` enum | [INVENTORY-SCHEMA.md](references/methodology/INVENTORY-SCHEMA.md) |
| **Hybrid classifications** — protocol for sites mixing bucket characteristics (e.g., (A) FFI + (B) inner perf code) | [HYBRID-CLASSIFICATIONS.md](references/methodology/HYBRID-CLASSIFICATIONS.md) |
| **Rejected patterns catalog** — refactors we tried and chose NOT to land + measured rationale (consult before re-proposing) | [REJECTED-PATTERNS.md](references/methodology/REJECTED-PATTERNS.md) |
| Operator cards + composition cheat-sheet | [OPERATORS.md](references/methodology/OPERATORS.md) |
| Polish-bar verification queries | [POLISH-BAR.md](references/methodology/POLISH-BAR.md) |
| Per-shape adjustments (single crate / workspace / polyrepo / FFI-heavy / SIMD-heavy / async / allocator) | [PROJECT-TYPES.md](references/methodology/PROJECT-TYPES.md) |
| Multi-agent orchestration tiers | [ORCHESTRATION.md](references/methodology/ORCHESTRATION.md) |
| Inline fallbacks for missing skills | [SKILL-FALLBACKS.md](references/methodology/SKILL-FALLBACKS.md) |
| Multi-model triangulation harness | [TRIANGULATION.md](references/methodology/TRIANGULATION.md) |
| Verification-first protocol (toolchain discipline) | [VERIFICATION-FIRST.md](references/methodology/VERIFICATION-FIRST.md) |
| Toolchain runbook (miri / careful / loom / fuzz / mutants / geiger) | [TOOLCHAIN-RUNBOOK.md](references/methodology/TOOLCHAIN-RUNBOOK.md) |
| Source corpus structure (Track A: corpus + quote bank + kernel + operators + validators) | [SOURCE-CORPUS.md](references/methodology/SOURCE-CORPUS.md) |
| CASS mining recipes (per unsafe class + per exemplar repo + remote-host mining) | [CASS-MINING.md](references/methodology/CASS-MINING.md) |
| **CASS deep recipes** — per-failure-class multi-pass query packs | [CASS-MINING-DEEP.md](references/methodology/CASS-MINING-DEEP.md) |
| **Strict vs permissive provenance** — how to write code that passes both | [PROVENANCE-MODEL.md](references/methodology/PROVENANCE-MODEL.md) |
| **Stacked vs Tree Borrows** — when each model applies + how to satisfy both | [STACKED-VS-TREE-BORROWS.md](references/methodology/STACKED-VS-TREE-BORROWS.md) |
| **Incident response** — 5-phase playbook for soundness incidents (CVE / miri-finding / prod-crash) | [INCIDENT-RESPONSE-PLAYBOOK.md](references/methodology/INCIDENT-RESPONSE-PLAYBOOK.md) |
| **Formal verification** — kani / prusti / creusot / flux decision guide + integration | [FORMAL-VERIFICATION.md](references/methodology/FORMAL-VERIFICATION.md) |
| **Dependency soundness protocol** — auditing the dep-side reachable unsafe | [DEP-SOUNDNESS-PROTOCOL.md](references/methodology/DEP-SOUNDNESS-PROTOCOL.md) |
| **Active-checkout refactor protocol** — Phase 8.5 implementation discipline; legacy filename, git worktrees forbidden | [WORKTREE-REFACTOR-PROTOCOL.md](references/methodology/WORKTREE-REFACTOR-PROTOCOL.md) |
| **Pre-existing UB protocol** — triage rules for UB outside refactor scope | [PRE-EXISTING-UB-PROTOCOL.md](references/methodology/PRE-EXISTING-UB-PROTOCOL.md) |
| **Citation index** — what to cite for each common (A) justification | [LANGUAGE-REFERENCES.md](references/methodology/LANGUAGE-REFERENCES.md) |
| **Clippy lint authoring** — encoding proof obligations as compile-time lints | [CLIPPY-LINT-AUTHORING.md](references/methodology/CLIPPY-LINT-AUTHORING.md) |
| **Common failure cases** — F-001..F-016+ symptom-to-fix catalog | [COMMON-FAILURE-CASES.md](references/methodology/COMMON-FAILURE-CASES.md) |
| **API stability + migration** — non-breaking / breaking-trivial / breaking-deep classification | [API-STABILITY-AND-MIGRATION.md](references/methodology/API-STABILITY-AND-MIGRATION.md) |
| **IDEAS roadmap** — /idea-wizard output applied to the skill; backlog of accretive ideas | [IDEAS.md](references/methodology/IDEAS.md) |
| **Continuous mode** — drift detection; nightly cron; ongoing accretive value | [CONTINUOUS-MODE.md](references/methodology/CONTINUOUS-MODE.md) |
| **Risk scoring** — `BLAST × LIKELIHOOD × DISCOVERABILITY` quantified bead prioritization | [RISK-SCORING.md](references/methodology/RISK-SCORING.md) |
| **Soundness debt dashboard** — stakeholder-facing debt tracking | [SOUNDNESS-DEBT.md](references/methodology/SOUNDNESS-DEBT.md) |
| **CI integration** — auditor-in-CI; PR gates; per-PR drift comments | [CI-INTEGRATION.md](references/methodology/CI-INTEGRATION.md) |
| **Differential audit** — version A vs B; upgrade-decision; regression-detection | [DIFFERENTIAL-AUDIT.md](references/methodology/DIFFERENTIAL-AUDIT.md) |
| **Inverse audit** — fuzz-guided from pub API; finds bugs forward audit missed | [INVERSE-AUDIT.md](references/methodology/INVERSE-AUDIT.md) |
| **Soundness archeology** — mine project git history + beads + cass for past decisions | [SOUNDNESS-ARCHEOLOGY.md](references/methodology/SOUNDNESS-ARCHEOLOGY.md) |
| **Cross-crate contracts** — workspace-level soundness contracts + verification | [CROSS-CRATE-CONTRACTS.md](references/methodology/CROSS-CRATE-CONTRACTS.md) |
| **Audit-driven test generation** — auto-generate property tests from per-site write-ups | [AUDIT-DRIVEN-TEST-GEN.md](references/methodology/AUDIT-DRIVEN-TEST-GEN.md) |
| **SECURITY.md generation** — auto-generate the project's security policy from audit | [SECURITY-MD-GENERATION.md](references/methodology/SECURITY-MD-GENERATION.md) |
| **Project-level soundness log** — append-only lifetime history of audits + incidents | [PROJECT-LEVEL-CHANGELOG.md](references/methodology/PROJECT-LEVEL-CHANGELOG.md) |
| **Incident forward-propagation** — one incident finds many adjacent sites | [INCIDENT-FORWARD-PROPAGATION.md](references/methodology/INCIDENT-FORWARD-PROPAGATION.md) |
| **Domain-specific overlays** — cryptography, embedded, kernel, etc. mode overlays | [DOMAIN-MODES.md](references/methodology/DOMAIN-MODES.md) |
| **MENTAL-MODEL** — the 30-second + 5-minute conceptual model | [MENTAL-MODEL.md](references/methodology/MENTAL-MODEL.md) |
| **QUICK-REFERENCE** — cheat sheet (buckets, operators, modes, scripts) | [QUICK-REFERENCE.md](references/methodology/QUICK-REFERENCE.md) |
| **COOKBOOK** — 12 paste-ready end-to-end recipes (full audit, incident response, dep upgrade, etc.) | [COOKBOOK.md](references/methodology/COOKBOOK.md) |
| **TROUBLESHOOTING** — common errors + fixes (skill loading, toolchain, jq, beads, CI, continuous mode) | [TROUBLESHOOTING.md](references/methodology/TROUBLESHOOTING.md) |
| **FAST-TRACK-MODES** — `triage` (60s), `audit-only --quick` (10m), `dashboard-only`, `drift-check` | [FAST-TRACK-MODES.md](references/methodology/FAST-TRACK-MODES.md) |
| **ARCHETYPES** — where this skill fits in the public skill-shape taxonomy (Methodology + Orchestration + Safety hybrid) | [ARCHETYPES.md](references/methodology/ARCHETYPES.md) |
| **PREREQUISITES** — required + recommended + optional tools, with per-OS install commands | [PREREQUISITES.md](references/methodology/PREREQUISITES.md) |
| **PLATFORM-NOTES** — Linux / macOS / Windows / WSL / ARM / embedded specifics + the per-OS test matrix | [PLATFORM-NOTES.md](references/methodology/PLATFORM-NOTES.md) |
| **GLOSSARY** — terms a non-Rust expert will encounter (unsafe, miri, loom, fuzz, mutants, geiger, …) | [GLOSSARY.md](references/methodology/GLOSSARY.md) |
| **README** (at skill root) — the human-friendly orientation for first-time users | [README.md](README.md) |
| **TESTING** — three-layer verification (trigger / smoke / harness self-test) + per-model trigger checks | [TESTING.md](references/methodology/TESTING.md) |
| **DECISION-TREE** — ASCII flowcharts for "which mode? which phase? which operator? which subagent?" | [DECISION-TREE.md](references/methodology/DECISION-TREE.md) |
| **EXAMPLES** — 10 most-common before/after refactor recipes with property tests | [EXAMPLES.md](references/methodology/EXAMPLES.md) |
| **ANTI-PATTERNS-FOR-USERS** — common mistakes users make (vs the existing agent-facing anti-patterns) | [ANTI-PATTERNS-FOR-USERS.md](references/methodology/ANTI-PATTERNS-FOR-USERS.md) |
| **MODEL-DIFFERENCES** — Haiku / Sonnet / Opus task-by-task recommendations + per-model failure modes | [MODEL-DIFFERENCES.md](references/methodology/MODEL-DIFFERENCES.md) |

### Patterns (mined from exemplar repos + extensions)
| Need | File |
|------|------|
| The (A) canonical-unavoidable catalog — what STAYS unsafe and why | [00-CANONICAL-UNAVOIDABLE.md](references/patterns/00-CANONICAL-UNAVOIDABLE.md) |
| Raw pointer → `NonNull` → `Pin<&mut T>` → owned safe type migration | [10-POINTER-MIGRATIONS.md](references/patterns/10-POINTER-MIGRATIONS.md) |
| SIMD: `std::simd` / `wide` / autovec / `safe-only` feature flag | [20-SIMD-AND-PERF.md](references/patterns/20-SIMD-AND-PERF.md) |
| **Intrinsics + compiler hints** — `core::intrinsics::*`, `core::hint::*_unchecked`, `core::ptr::*` raw ops | [25-INTRINSICS-AND-COMPILER-HINTS.md](references/patterns/25-INTRINSICS-AND-COMPILER-HINTS.md) |
| **`UnsafeCell` patterns** — Cell/RefCell/OnceCell graduations + manual UnsafeCell footguns | [27-UNSAFECELL-PATTERNS.md](references/patterns/27-UNSAFECELL-PATTERNS.md) |
| Concurrency: `arc-swap`, `crossbeam`, `indexmap`, `dashmap` safe alternatives | [30-CONCURRENCY-PATTERNS.md](references/patterns/30-CONCURRENCY-PATTERNS.md) |
| **Atomic orderings** — `Relaxed` / `Acquire` / `Release` / `AcqRel` / `SeqCst` audit | [35-ATOMICS-AND-ORDERINGS.md](references/patterns/35-ATOMICS-AND-ORDERINGS.md) |
| Macro-generated `unsafe`: `zerocopy-derive`, `bytemuck-derive`, `derive-deftly` | [40-MACRO-GENERATED-UNSAFE.md](references/patterns/40-MACRO-GENERATED-UNSAFE.md) |
| **WASM + cxx interop** — wasm-bindgen, cxx, pyo3, napi-rs patterns | [45-WASM-AND-CXX.md](references/patterns/45-WASM-AND-CXX.md) |
| `unsafe impl Send/Sync` audit + safer derives | [50-SEND-SYNC-IMPLS.md](references/patterns/50-SEND-SYNC-IMPLS.md) |
| **Embedded patterns** — volatile MMIO, PAC, embedded-hal, ISR-shared state | [55-EMBEDDED-PATTERNS.md](references/patterns/55-EMBEDDED-PATTERNS.md) |
| FFI surfaces — thin unsafe shim pattern + boundary contract | [60-FFI-PATTERNS.md](references/patterns/60-FFI-PATTERNS.md) |
| **Allocator patterns deep** — bumpalo, slab, slotmap, gen-arena; preserved-identity rewrites | [65-ALLOCATOR-PATTERNS-DEEP.md](references/patterns/65-ALLOCATOR-PATTERNS-DEEP.md) |
| `MaybeUninit` + `transmute` + init-order discipline | [70-UNINIT-AND-TRANSMUTE.md](references/patterns/70-UNINIT-AND-TRANSMUTE.md) |
| **Lock-free patterns** — vetted crate swaps + epoch-based reclamation | [75-LOCK-FREE-PATTERNS.md](references/patterns/75-LOCK-FREE-PATTERNS.md) |
| `Pin` projections + async-runtime patterns | [80-PIN-PROJECTIONS.md](references/patterns/80-PIN-PROJECTIONS.md) |
| **Custom proc-macro unsafe** — derive macros emitting unsafe; hygiene + contract enforcement | [85-PROC-MACRO-UNSAFE.md](references/patterns/85-PROC-MACRO-UNSAFE.md) |
| Ops: `verify.sh`, CI matrix, bead integration, pre-existing-UB protocol, anti-patterns rejected | [90-OPERATIONS.md](references/patterns/90-OPERATIONS.md) |
| **Symptom-to-pattern index** — reverse lookup table by failure symptom / unsafe-kind / project shape | [95-INDEX.md](references/patterns/95-INDEX.md) |
| **Cryptography audit overlay** — constant-time, secret-zeroing, side-channel | [100-CRYPTOGRAPHY-AUDIT.md](references/patterns/100-CRYPTOGRAPHY-AUDIT.md) |
| **Tagged pointer migration** — strict-provenance API for legacy `as usize` patterns | [130-TAGGED-POINTER-MIGRATION.md](references/patterns/130-TAGGED-POINTER-MIGRATION.md) |

### Source corpus (read-only evidence)
| Need | File |
|------|------|
| Per-exemplar-repo canonical patterns + commit anchors + bead anchors | [EXEMPLAR-CATALOG.md](references/source/EXEMPLAR-CATALOG.md) |
| CASS query packs that surfaced each pattern | [CASS-QUERY-PACK.md](references/source/CASS-QUERY-PACK.md) |

---

## Specialty Workflows (Quick Index)

These workflows compose the above references into the highest-value end-to-end audits:

| Workflow | Start here | Then |
|----------|------------|------|
| **Reactive incident response** | [INCIDENT-RESPONSE-PLAYBOOK.md](references/methodology/INCIDENT-RESPONSE-PLAYBOOK.md) — 5-phase playbook | [regression-test-author.md](subagents/regression-test-author.md), [incident-rca-template.md](assets/incident-rca-template.md) |
| **Add safe-only feature to perf-only crate** | [20-SIMD-AND-PERF.md § safe-only feature](references/patterns/20-SIMD-AND-PERF.md) | [PROJECT-TYPES.md § SIMD-heavy crate](references/methodology/PROJECT-TYPES.md), [cargo-toml-features-template.toml](assets/cargo-toml-features-template.toml) |
| **Pre-cargo-publish soundness gate** | [OPERATING-MODES.md § pre-release-soundness-gate](references/methodology/OPERATING-MODES.md) | [LANGUAGE-REFERENCES.md](references/methodology/LANGUAGE-REFERENCES.md), [CLIPPY-LINT-AUTHORING.md](references/methodology/CLIPPY-LINT-AUTHORING.md), [changelog-writer.md](subagents/changelog-writer.md) |
| **Dependency-side unsafe audit** | [DEP-SOUNDNESS-PROTOCOL.md](references/methodology/DEP-SOUNDNESS-PROTOCOL.md) | [upstream-issue-filer.md](subagents/upstream-issue-filer.md), [upstream-issue-template.md](assets/upstream-issue-template.md) |
| **Active-checkout refactor execution** | [WORKTREE-REFACTOR-PROTOCOL.md](references/methodology/WORKTREE-REFACTOR-PROTOCOL.md) | [worktree-implementer.md](subagents/worktree-implementer.md), [workspace-refactor-checklist.md](assets/workspace-refactor-checklist.md) |
| **Formal verification of high-stakes (C)** | [FORMAL-VERIFICATION.md](references/methodology/FORMAL-VERIFICATION.md) | [kani-prover.md](subagents/kani-prover.md), [kani-proof-template.rs](assets/kani-proof-template.rs) |
| **Macro-generated unsafe deep dive** | [40-MACRO-GENERATED-UNSAFE.md](references/patterns/40-MACRO-GENERATED-UNSAFE.md) | [85-PROC-MACRO-UNSAFE.md](references/patterns/85-PROC-MACRO-UNSAFE.md) |
| **Async runtime / Pin self-ref hardening** | [80-PIN-PROJECTIONS.md](references/patterns/80-PIN-PROJECTIONS.md) | [pin-projection-auditor.md](subagents/pin-projection-auditor.md), [STACKED-VS-TREE-BORROWS.md](references/methodology/STACKED-VS-TREE-BORROWS.md) |
| **Lock-free / atomic-ordering audit** | [35-ATOMICS-AND-ORDERINGS.md](references/patterns/35-ATOMICS-AND-ORDERINGS.md) | [75-LOCK-FREE-PATTERNS.md](references/patterns/75-LOCK-FREE-PATTERNS.md) |
| **Embedded / volatile MMIO refactor** | [55-EMBEDDED-PATTERNS.md](references/patterns/55-EMBEDDED-PATTERNS.md) | [60-FFI-PATTERNS.md](references/patterns/60-FFI-PATTERNS.md) (vendor SDK) |
| **Allocator-aware (C) refactor** | [65-ALLOCATOR-PATTERNS-DEEP.md](references/patterns/65-ALLOCATOR-PATTERNS-DEEP.md) | [allocator-identity-auditor.md](subagents/allocator-identity-auditor.md) |
| **Symptom → pattern lookup** | [95-INDEX.md](references/patterns/95-INDEX.md) | [COMMON-FAILURE-CASES.md](references/methodology/COMMON-FAILURE-CASES.md) |

---

## Continuous + Innovation Modes (v3)

Beyond one-shot audit, the skill operates as a **continuous safety platform**. The audit's value compounds over time. The unifying narrative + the roadmap of ideas: [IDEAS.md](references/methodology/IDEAS.md). Top accretive modes:

| Mode / Capability | Start here | Implementation |
|-------------------|------------|----------------|
| **Continuous drift detection** | [CONTINUOUS-MODE.md](references/methodology/CONTINUOUS-MODE.md) | `scripts/cron-drift-check.sh` + `subagents/drift-detector.md` + `assets/continuous-mode.toml.template` |
| **Quantified risk scoring** | [RISK-SCORING.md](references/methodology/RISK-SCORING.md) | `scripts/compute-risk-score.mjs` + `subagents/risk-scorer.md` + `assets/risk-score-rubric.md` |
| **Soundness debt dashboard** | [SOUNDNESS-DEBT.md](references/methodology/SOUNDNESS-DEBT.md) | `assets/soundness-debt-dashboard.md.template` (auto-regenerated) |
| **Auditor-in-CI** | [CI-INTEGRATION.md](references/methodology/CI-INTEGRATION.md) | `assets/gh-actions-auditor.yml.template` |
| **Differential audit (version A vs B)** | [DIFFERENTIAL-AUDIT.md](references/methodology/DIFFERENTIAL-AUDIT.md) | `scripts/diff-audit-vs-baseline.sh` |
| **Inverse audit (fuzz from pub API)** | [INVERSE-AUDIT.md](references/methodology/INVERSE-AUDIT.md) | `subagents/inverse-auditor.md` |
| **Soundness archeology** | [SOUNDNESS-ARCHEOLOGY.md](references/methodology/SOUNDNESS-ARCHEOLOGY.md) | `scripts/git-history-soundness-mine.sh` + `subagents/archeologist.md` |
| **Cross-crate contracts (workspace)** | [CROSS-CRATE-CONTRACTS.md](references/methodology/CROSS-CRATE-CONTRACTS.md) | `subagents/contract-verifier.md` |
| **Audit-driven test generation** | [AUDIT-DRIVEN-TEST-GEN.md](references/methodology/AUDIT-DRIVEN-TEST-GEN.md) | `subagents/test-generator.md` |
| **SECURITY.md auto-generation** | [SECURITY-MD-GENERATION.md](references/methodology/SECURITY-MD-GENERATION.md) | `subagents/security-md-author.md` + `assets/SECURITY.md.template` |
| **Project-level soundness log** | [PROJECT-LEVEL-CHANGELOG.md](references/methodology/PROJECT-LEVEL-CHANGELOG.md) | `scripts/generate-soundness-changelog.sh` + `assets/project-level-changelog.md.template` |
| **Incident forward-propagation** | [INCIDENT-FORWARD-PROPAGATION.md](references/methodology/INCIDENT-FORWARD-PROPAGATION.md) | (methodology; uses existing subagents) |
| **Domain-specific overlays** | [DOMAIN-MODES.md](references/methodology/DOMAIN-MODES.md) | [100-CRYPTOGRAPHY-AUDIT.md](references/patterns/100-CRYPTOGRAPHY-AUDIT.md), [130-TAGGED-POINTER-MIGRATION.md](references/patterns/130-TAGGED-POINTER-MIGRATION.md) |

The full ideation roadmap (including proposed-but-not-yet-implemented extensions like per-target soundness matrix, audit replay, refactor risk forecasting, "Why is this safe?" doc generation, cross-project pattern memory, refactor-risk-forecast operator, trust-ledger for downstream verification): [IDEAS.md](references/methodology/IDEAS.md).

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/check-skills.sh` | Detect referenced helper skills across Claude, Codex, and project-local skill dirs + jsm state; write `phase0_skill_inventory.json` |
| `scripts/audit-dir-guard.sh` | Shared path guard sourced by artifact-writing scripts; rejects audit dirs outside the audited project |
| `scripts/install-referenced-skills.sh` | Bulk-install missing skills via jsm |
| `scripts/install-toolchain.sh` | Audit + propose install one-liners for ast-grep / cargo-geiger / cargo-careful / cargo-expand / cargo-fuzz / cargo-mutants / cargo-flamegraph / hyperfine / nightly + miri + loom |
| `scripts/detect-mode.sh` | Auto-detect Mode Router heuristic; emit recommended mode + reasoning |
| `scripts/enumerate-unsafe.sh` | Run ast-grep per unsafe-kind + cargo-geiger + cargo expand + rustdoc JSON + ubs per crate; emit raw Phase 1 artifacts under `<audit-dir>/phase1/` |
| `scripts/generate-inventory.mjs` | Normalize Phase 1 output into `<audit-dir>/unsafe-inventory.jsonl` with project-relative paths and stable site IDs |
| `scripts/cargo-tree-soundness.sh` | Walk `cargo tree`; flag deps whose unsafe is reachable through this project's public API |
| `scripts/cass-mine.sh` | Run the CASS query pack from [CASS-MINING.md](references/methodology/CASS-MINING.md) locally and against remote hosts (`css` / `csd` / `ts1` / `ts2`) |
| `scripts/run-miri.sh` | `cargo +nightly miri test` with default and strict-provenance + disable-isolation profiles; tee output to `verification-log.md` |
| `scripts/run-careful.sh` | `cargo +nightly careful test` |
| `scripts/run-loom.sh` | `RUSTFLAGS="--cfg loom" cargo test --features loom_concurrency_tests` per concurrency-touching site |
| `scripts/run-fuzz.sh` | `cargo fuzz run <target> -- -max_total_time=60` per new/widened public surface |
| `scripts/run-mutants.sh` | `cargo mutants --in-place=false` to verify tests actually pin behavior |
| `scripts/run-geiger.sh` | `cargo +nightly geiger`; diff vs baseline from `phase0` |
| `scripts/build-safe-only-matrix.sh` | Build + test under `--features safe-only`; emit a CI matrix entry for `.github/workflows/` |
| `scripts/bench-before-after.sh` | `cargo bench` + `hyperfine` + `cargo flamegraph` for one (B) site; emit before/after numbers into the plan |
| `scripts/classify-new.sh` | Diff-only CI guard for newly-added unsafe-related Rust lines; emits a tentative PR-comment table or JSONL |
| `scripts/generate-bead-graph.mjs` | Convert `audit/plans/*.md` into a `br create` script: parent epic per cluster + impl bead per site, with `br dep add` dependency edges |
| `scripts/verify.sh` | The composite harness: miri + careful + loom + fuzz + mutants + geiger + the project's test suite under default AND `safe-only`; emit a single pass/fail summary |
| `scripts/audit-pin-projection-soundness.sh` | Pattern-search for `Pin::new_unchecked` / `map_unchecked_mut` and verify each one has a SAFETY comment that survives the [80-PIN-PROJECTIONS.md] rubric |
| `scripts/audit-transmute-patterns.sh` | Pattern-search for `mem::transmute` and propose `zerocopy` / `bytemuck` swap candidates |
| `scripts/audit-ffi-boundary.sh` | Per `extern "C" { ... }` block, emit the boundary-contract template from [60-FFI-PATTERNS.md] |
| `scripts/audit-allocator-changes.sh` | Detect plans that silently swap a custom allocator for the global one (operator 📐) |
| `scripts/check-polish-bar.sh` | Walk every classification + plan; verify all required polish-bar dimensions are present |
| `scripts/detect-pre-existing-ub.sh` | Triage harness findings into IN-SCOPE vs OUT-OF-SCOPE (pre-existing-ub) |
| `scripts/rustdoc-call-graph-extract.sh` | Extract `pub`-item topology from rustdoc JSON; used by soundness-surface synthesis |
| `scripts/generate-safety-skeleton.sh` | Per (A) site, emit a fillable SAFETY-comment skeleton |
| `scripts/run-kani.sh` | Run kani proofs for sites flagged for formal verification |
| `scripts/check-prerequisites.sh` | **Run first** — per-tool availability check (rust/git/bash/jq/node/python/miri/ast-grep/...) with install hints per missing tool |
| `scripts/validate-corpus.py` | **Maintainer-only** — verify `EXEMPLAR-CATALOG.md` `[E-NNN]` entries: stable IDs, citations, no duplicates (run after editing the catalog) |
| `scripts/validate-operators.py` | **Maintainer-only** — verify `OPERATORS.md` cards have all required sections (run after adding/editing operators) |
| `scripts/cron-drift-check.sh` | Continuous-mode nightly drift detection (per [CONTINUOUS-MODE.md]) |
| `scripts/compute-risk-score.mjs` | Compute `BLAST × LIKELIHOOD × DISCOVERABILITY` per site; emit `audit/synthesis/risk-summary.md` |
| `scripts/diff-audit-vs-baseline.sh` | Differential audit: compare two audits (version A vs B) and emit a diff report |
| `scripts/git-history-soundness-mine.sh` | Soundness archeology: mine project's git history for past decisions |
| `scripts/generate-soundness-changelog.sh` | Auto-append to `<project>/audit/SOUNDNESS-LOG.md` after each audit; refuses missing summaries unless `--allow-incomplete` is explicit |

Scripts either write their documented phase artifact or emit documented stdout for redirection into `<audit-dir>/`; JSON-only behavior is called out per script. Artifact-writing scripts reject audit directories outside the audited project.

---

## Subagents

| Subagent | Phase | Purpose |
|----------|-------|---------|
| `subagents/cass-miner.md` | 0 | Mines user's prior cass sessions for unsafe-refactor patterns; runs locally + against `css` / `csd` / `ts1` / `ts2` |
| `subagents/exemplar-miner.md` | 0 | Reads the exemplar repos' git history + beads; surfaces canonical patterns for the kind of unsafe found in target project |
| `subagents/enumerator.md` | 1 | One per crate; runs ast-grep + cargo-geiger + cargo expand + rustdoc JSON + ubs; emits inventory rows |
| `subagents/site-analyzer.md` | 2 | Same agent that enumerated a section writes the per-site `.md` write-ups |
| `subagents/synthesizer.md` | 3 | Global view: invariant clusters + soundness-surface + cross-site Send/Sync dependencies |
| `subagents/classifier.md` | 4 | (A) / (B) / (C) per CLASSIFICATION-RUBRIC; iterative |
| `subagents/refactor-planner.md` | 5 | Drafts full safe rewrite per (C); safe-only impl per (B); hardened SAFETY + proof obligation per (A) |
| `subagents/adversarial-reclassifier.md` | 6 | Fresh agent; tries to defeat (A); hunts safe-equivalents for (B); stress-tests (C) equivalence claims |
| `subagents/fresh-eyes-reviewer.md` | 7 | The three verbatim review prompts against proposed rewrites |
| `subagents/equivalence-prover.md` | 5 / 7 | Authors property-based + metamorphic + loom + miri tests proving the (C) rewrite matches the unsafe original |
| `subagents/harness-builder.md` | 9 | Builds `verify.sh` + CI matrix entry; wires miri / careful / loom / fuzz / mutants / geiger |
| `subagents/bead-converter.md` | 8 | Converts audit plans into the bead graph per `/beads-workflow` |
| `subagents/maintainer-empathy-reviewer.md` | 10 | Fresh agent reads the audit cold; answers "would I land this as maintainer?"; writes `REVIEWER_RESPONSES.md` |
| `subagents/idea-generator.md` | 10 | `/idea-wizard` shape: alternative refactor strategies the original audit missed |
| `subagents/multi-model-triangulator.md` | 6 / 7 / 10 | Multi-model second opinion (Claude + Codex + Gemini) on highest-risk (C) sites |
| `subagents/safety-comment-author.md` | 5 / 8.5 | Author hardened SAFETY comments for (A) sites; propose clippy lints |
| `subagents/allocator-identity-auditor.md` | 6 / 7 | Verify proposed (C) rewrites preserve allocator identity (operator 📐) |
| `subagents/panic-boundary-auditor.md` | 6 / 7 | Audit every panic-unwinding boundary (FFI, signal handlers, allocators, Drop) |
| `subagents/api-stability-reviewer.md` | 5 / 6 | Classify each (C) plan's API impact; verify migration path |
| `subagents/upstream-issue-filer.md` | dep-soundness | Draft upstream issues for dep-side soundness concerns |
| `subagents/regression-test-author.md` | 4 (harden-incident) | Pin each fix to a named regression test |
| `subagents/changelog-writer.md` | 8.5 / 10 | Write soundness-aware release notes, CHANGELOG, RustSec advisory text |
| `subagents/kani-prover.md` | 5 / 7 | Author kani proofs for highest-stakes (C) rewrites |
| `subagents/worktree-implementer.md` | 8.5 | Legacy filename; implement the authorized bead chain in the active checkout, never in a git worktree |
| `subagents/pin-projection-auditor.md` | 1 / 2 (specialty) | Audit every Pin / pin-project use per [80-PIN-PROJECTIONS.md] |
| `subagents/drift-detector.md` | continuous mode | Nightly drift detection; file drift beads (per [CONTINUOUS-MODE.md]) |
| `subagents/risk-scorer.md` | 4 / 8 | Refine heuristic risk scores per [RISK-SCORING.md] |
| `subagents/inverse-auditor.md` | inverse mode | Fuzz-guided from pub API; surface bugs forward audit missed |
| `subagents/archeologist.md` | 0.5 | Mine project git history + closed PRs + beads + cass for soundness decisions |
| `subagents/contract-verifier.md` | workspace | Verify cross-crate soundness contracts (per [CROSS-CRATE-CONTRACTS.md]) |
| `subagents/test-generator.md` | 5 / 8 | Auto-generate property tests from per-site write-ups |
| `subagents/security-md-author.md` | 10 / per-release | Generate the project's SECURITY.md from the audit |

Subagent prompt templates: **[AGENT-PROMPTS.md](references/methodology/AGENT-PROMPTS.md)**.

---

## Assets

| Asset | Purpose |
|-------|---------|
| `assets/intake-prompt.md` | Verbatim prompt for the up-front confirmations dialog |
| `assets/site-writeup-template.md` | Template for `audit/sites/<crate>/<file>__<line>.md` |
| `assets/classification-template.md` | Template for the per-site (A) / (B) / (C) decision |
| `assets/refactor-plan-template.md` | Template for `audit/plans/site-<id>.md` |
| `assets/bead-template.md` | Template for `br create` of a per-site implementation bead |
| `assets/reviewer-responses-template.md` | Template for `REVIEWER_RESPONSES.md` |
| `assets/verify.sh.template` | Paste-ready harness template |
| `assets/ci-matrix.yml.template` | GitHub Actions matrix template for default + safe-only |
| `assets/safety-comment-skeleton.md` | Hardened SAFETY-comment template for (A) sites; per-pattern customization |
| `assets/clippy-lint-template.toml` | clippy.toml entries encoding proof obligations as compile-time lints |
| `assets/upstream-issue-template.md` | Verbatim issue body for filing dep-soundness concerns upstream |
| `assets/workspace-refactor-checklist.md` | Phase 8.5 active-checkout refactor checklist; legacy filename, no git worktrees |
| `assets/kani-proof-template.rs` | Kani-proof scaffolding for formal verification of (C) rewrites |
| `assets/incident-rca-template.md` | Per-incident root-cause-analysis template (harden-incident mode) |
| `assets/regression-test-template.rs` | Regression-test scaffolding for incident-pinned bug fixes |
| `assets/audit-summary-template.md` | The end-of-audit single-line tally + verification + reviewer-confidence summary |
| `assets/cargo-toml-features-template.toml` | Cargo.toml feature/dep template for the safe-only + loom + kani matrix |
| `assets/continuous-mode.toml.template` | Per-project config for continuous-mode cron (thresholds, notifications, gates, budget) |
| `assets/gh-actions-auditor.yml.template` | GitHub Actions workflow: drift + matrix + miri + careful + loom + fuzz + geiger + gate |
| `assets/risk-score-rubric.md` | The 1-5 rubric for BLAST_RADIUS, LIKELIHOOD, DISCOVERABILITY scoring |
| `assets/soundness-debt-dashboard.md.template` | The stakeholder-facing debt dashboard (auto-regenerated) |
| `assets/SECURITY.md.template` | The project's auto-generated security policy from the audit |
| `assets/project-level-changelog.md.template` | The project's append-only lifetime soundness log |

---

## Self-Test

Trigger phrases that should activate this skill:

- "Audit every `unsafe` in this project"
- "Help me eliminate unsafe from this Rust crate"
- "Run an unsafe code exorcist pass on `/dp/franken_engine`"
- "Find the macro-generated unsafe hiding in this workspace"
- "Add a `safe-only` feature flag and CI matrix for the SIMD path"
- "Convince me this `unsafe` block is actually necessary"
- "Is the unsafe in this dependency reachable from our public API?"
- "Pre-release soundness gate for this crate"
- "Build a verification harness with miri, loom, fuzz, mutants, and geiger"
- "Harden SAFETY comments for every remaining unsafe site"
- "Three-bucket the unsafe in this project: unavoidable, perf-only, refactorable"

Trigger-phrase probe + smoke test on a tiny crate: [SELF-TEST.md](SELF-TEST.md).
