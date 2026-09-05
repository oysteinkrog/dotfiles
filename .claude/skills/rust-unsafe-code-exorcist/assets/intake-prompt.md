# Intake Prompt — verbatim, for the up-front confirmations dialog

Before the audit begins, the orchestrator agent asks the user these questions in order. Use this template verbatim.

---

Hi! I'm about to run an unsafe-audit on your Rust project. Before I start, I need to confirm a few things.

**1. Target project path?**

I'll audit the Rust project at: `<DEFAULT-CWD>`

Is this correct? Answers I accept:
- `yes` — proceed with `<DEFAULT-CWD>` as the project root.
- `give-different-path /abs/path/to/project` — switch to a different local path.
- `clone-from-URL https://github.com/owner/repo[.git]` (HTTPS or `git@github.com:owner/repo.git` SSH) — I'll clone via the protocol given. Default clone target: `/tmp/<basename>` (or `~/audits/<basename>` if `/tmp` is small / tmpfs is constrained). If a directory of the same basename already exists in the chosen target, I'll ask whether to reuse it (treating it as if you'd given `give-different-path`) or to clone fresh into `<basename>-<timestamp>`.

For `clone-from-URL`:
- Branch / tag: defaults to the remote's default branch. Override with `--ref <branch|tag|sha>`.
- Shallow clone: `--shallow` adds `--depth 50` (faster, sufficient for soundness archeology; loses earlier history if Phase 0.5 wants deep mining).
- Auth: HTTPS uses your stored credential helper; SSH uses your ssh-agent. If neither is configured I'll prompt you to run the auth command yourself rather than guess.

After clone:
- The audit dir is created inside the project, e.g. `/tmp/myrepo` → `/tmp/myrepo/.unsafe-audit`.
- The clone is treated identically to a local path (existing source files read-only until Phase 8 explicit refactor authorization).
- If the project root is a sub-directory of the repo (monorepo containing a Rust crate among other things), pass `--subdir <path-within-repo>` to anchor the audit there.

**2. Audit directory?**

I'll create `<project>/.unsafe-audit/` to hold every audit artifact. Existing project source files stay read-only until you explicitly authorize a refactor. I'll `git init` the audit dir as a nested audit repo so every iteration is reviewable.

Important: the outer project's git will see `.unsafe-audit/` as an embedded git repo / untracked dir. The bootstrap script will tell you the exact line to add to your project's `.gitignore` (`/.unsafe-audit`), but it will NOT modify the project's `.gitignore` itself — the audit-only contract requires existing project files (including `.gitignore`) stay untouched. You add the line yourself when you're ready (one-line shell append; the audit-dir README has the exact command).

Is this OK? (yes / give-different-path)

**3. Mode?**

Based on detection (`scripts/detect-mode.sh`), I recommend mode `<DETECTED-MODE>` because: `<REASONING>`.

Options:
- `audit-only` (default): report only, no project-repo changes
- `audit-and-refactor`: report + approved refactors landing in the active project checkout; PRs optional via ordinary branches, never git worktrees
- `harden-incident`: scoped to a specific unsoundness incident
- `dependency-soundness`: focus on dep-side unsafe reachable from our pub API
- `verify-only`: build the CI verification harness from existing audit
- `pre-release-soundness-gate`: ratify for next `cargo publish`
- `dual-feature-migration`: add `safe-only` feature flag to a perf-only crate

Confirm or override? (use-recommended / pick-different)

**4. Toolchain profile?**

- `full` (default and recommended): nightly + miri + careful + loom + fuzz + mutants + geiger.
- `stable-only`: skip miri / loom / careful (less coverage; useful when nightly is broken).

Pick: (full / stable-only)

**5. Perf budget?**

For (B) sites, what's the acceptable perf regression for the safe-only alternative?

- `strict`: any measurable regression fails the bar
- `5%` (default): up to 5% regression on canonical workload
- `10%`: up to 10%
- `none`: favor safety unconditionally

Pick: (strict / 5% / 10% / none)

**6. Execution authorization?**

- `audit-only` (default): no project-repo edits at all
- `refactor-on-approve`: I'll show you each selected plan; you approve before I touch the project repo. Refactors happen in the active checkout or an ordinary branch; git worktrees are forbidden.

Pick: (audit-only / refactor-on-approve)

**7. Missing tooling.**

I checked your machine. Missing tools (if any): `<LIST>`

Proposed install commands:
```
<ONE-LINER PER MISSING TOOL>
```

Should I run them now? (yes / no, I'll install manually / skip-and-degrade)

**8. Helper skills.**

I checked the skills installed for this local coding agent. Missing referenced skills: `<LIST>`.

If you have `jsm` installed and authenticated, I can run `jsm install <name>` for each. Otherwise I'll use the inline fallback playbook in `references/methodology/SKILL-FALLBACKS.md` — every missing skill has a fallback.

Pick: (jsm-install / inline-fallback / skip-some)

**9. Exemplar corpus.**

I plan to mine the exemplar repos (`/dp/asupersync`, `/dp/beads_rust`, …, `/dp/frankenfs`) for canonical patterns relevant to your project. I'll also query CASS across `css`, `csd`, `ts1`, `ts2` if available.

Confirm: (full-mine / local-only / skip-mining)

**10. Resuming?**

I notice `<audit-dir>` already exists / doesn't exist. (`<status>`)

If existing: should I resume the prior run (idempotent) or treat as fresh? (resume / fresh)

---

Once you've answered all 10, I'll kick off Phase 0.5 and proceed through the phases. Audit time depends on the project size; expect roughly:
- Tiny crate (< 20 unsafe sites): 30-60 min
- Workspace (100-500 sites): 2–6 hours
- Polyrepo / very large workspace: half-day to day

The output is a thorough, defensible audit + (optionally) approved active-checkout refactors or PRs.
