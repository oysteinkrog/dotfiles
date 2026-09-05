# Verification-First Overlay

**Source axiom:** Axiom 17. The kernel is *evergreen*; many operational details are *volatile* across git versions, LFS versions, OS, and shell environments. Treating volatile knowledge as evergreen is the most common way the skill makes wrong recommendations.

This overlay names what to verify, when, and against what primary source. It applies on top of every phase of the kernel; the `◑ VERIFY-LIVE` operator is the in-line invocation.

---

## What's evergreen vs. what's volatile

### Evergreen (trust the kernel and the references)

- The 25 axioms (numbered 0 through 24) in SKILL.md.
- The seven verdicts and the decision flow in TRIAGE-RUBRIC.md.
- The smell taxonomy in FILE-SMELLS.md.
- The bundle structure in BUNDLE-FORMAT-SPEC.md.
- The four recovery layers in SAFETY-MODEL.md.
- The phase ordering in PHASES.md.
- The composition rules ("moves before deletes before gitignore").
- AGENTS.md's permanent rules (RULE 0, RULE 1, irreversible-action discipline, no-script-based-changes, no-file-proliferation, working-tree-drift handling).

### Volatile (verify before recommending)

- **Git's defaults**: `diff.renames`, `merge.renameLimit`, `core.autocrlf`, `core.ignorecase`, `core.precomposeunicode` (macOS), `gc.auto`, `pack.deltaCacheLimit`. Some changed between 2.20 → 2.45.
- **`git mv` rename detection**: threshold defaults moved between 2.18 (introduction of stable `diff.renames` semantics) and 2.40+. Always preserves moves explicitly, but follow-on tools (`git log --follow`, GitHub PR view) may fail to recognize moves where content drifted significantly between commit boundaries.
- **`git filter-repo`**: plugin contract changed in 2.36. Behavior on shallow clones changed in 2.40. Behavior with replace-refs changed in 2.42.
- **`git lfs smudge`** behavior changed when LFS upgraded internal pointer format; older clones may have a mix of pointer-format-v1 and pointer-format-v2 files.
- **Partial-clone interaction with `git rev-list`** changed in 2.40+; commits that are "promised but not fetched" can show up in unexpected places.
- **`.gitignore` precedence rules** when nested `.gitignore` files exist at multiple depths. The agent should not assume git's traversal order; always run `git check-ignore -v` to see which rule actually fires.
- **Submodule behavior**: `submodule.<name>.shallow`, `submodule.<name>.fetchRecurseSubmodules`, `protocol.file.allow` (changed in 2.38 to default to user-only).
- **`git push --force-with-lease`** behavior with `<refname>:<expected>` syntax (added in 2.30, expanded in 2.39).
- **GitHub-specific behavior**: default-branch rename, the way GitHub Pages sees moved files, what shows up in PR diff vs. file view.
- **Pre-commit hook framework specifics**: husky v8 vs. husky v9 hook discovery; lefthook config schema differences; pre-commit (Python tool) vs. `.git/hooks/`-direct.
- **OS-specific commands**: `stat -c%s` (GNU coreutils) vs. `stat -f%z` (BSD/macOS); `sed -i ''` (BSD) vs. `sed -i` (GNU); `readlink -f` (GNU) vs. `realpath` (BSD).

---

## Mandatory verification triggers

The `◑ VERIFY-LIVE` operator MUST run when any of these are true:

| Trigger | What to verify | Primary source |
|---------|----------------|---------------|
| The skill is about to recommend `git filter-repo` (secret-leak playbook) | Local git version supports the plugin invocation we use; origin has been synced (Axiom 16) | `git filter-repo --version`; `git --version`; `git rev-list --count <branch>` vs. `git rev-list --count origin/<branch>` |
| Local git is < 2.20 | Whether the recommended Phase 6 commands work on this version | `git --version`; `git help <subcommand>` |
| LFS-tracked files among candidates | LFS version; whether `git lfs smudge` produces the actual blob | `git lfs --version`; check `cat <file>` first 4 bytes vs. `version https://git-lfs.github.com/spec/v1` (pointer marker) |
| Submodules present | Whether submodule pointers are in a clean state; whether they're `(rewind)` or fast-forward | `git diff --submodule=log`; `git diff --submodule=short` |
| `core.autocrlf=true` detected | Whether Phase 3 byte-equality checks will drift due to line-ending normalization | `git config --get core.autocrlf` |
| User reports `.gitignore` "not working" | Which rule actually fires for a given path | `git check-ignore -v <path>` |
| Phase 6 reference rewrite touches macOS-specific extended attributes (resource forks, `._<file>` files) | Whether the rewrite will trigger Finder rename behavior | `xattr -l <file>`; `ls -l@ <file>` |
| The user is running on Windows (Git Bash, WSL, native Powershell, or MinGW) | Path separator handling, file mode (executable bit), CRLF | `uname`; `git config --get core.filemode` |
| Pre-commit framework is `husky v9` or `lefthook` | The skill's `.githooks/pre-commit` install procedure works with their config | `cat .husky/_/h` (husky v9 helper); `cat lefthook.yml` |

---

## Verification log

Every verification produces an entry in `<workspace>/verification_log.md`:

```markdown
## VERIFY-LIVE: <trigger>
- run_at: 2026-05-08T17:00:00Z
- subagent: bundle-builder
- command: git filter-repo --version
- output: 2.45.0
- decision: COMPATIBLE — proceeding with `--invert-paths --path` invocation
- source: https://github.com/newren/git-filter-repo (consulted 2026-05-08)
```

The `◑ VERIFY-LIVE` operator emits these records; the verifications are reviewable and re-runnable.

---

## Primary-source hierarchy

When information conflicts:

1. **Live tool output** (`git --version`, `git config --get X`, `git help <subcommand>` SECTION). Most authoritative for the local environment.
2. **Official documentation** (git-scm.com manual pages, kernel.org's Pro Git book, the tool's `--help` output).
3. **Release notes** (`git log` of the project's official changelog, GitHub Releases page).
4. **Cited blog posts with date** (only when the date is recent and the author is a known maintainer).
5. **Last resort**: skill memory (the kernel + references). If the answer isn't in 1–4, surface to user; don't fabricate.

When sources conflict, prefer the more recent and the more specific. A 2024 blog from Junio Hamano beats a 2018 blog from a generic platform.

---

## Evidence envelope template

Every recommendation that depends on volatile behavior carries an evidence envelope in the rationale:

```
RECOMMENDATION: Run `git filter-repo --invert-paths --path 'signing-X.key'`
EVIDENCE:
  - git --version: 2.45.0 (verified 2026-05-08T17:00:00Z)
  - git filter-repo --version: 2.45.0 (verified ditto)
  - origin sync verified: local 793 commits == origin/main 793 commits
  - mirror backup created at /tmp/<repo>-backup-20260508T170000Z.git
SOURCE: git-filter-repo(1) man page; git release notes 2.36+
ALTERNATIVES CONSIDERED: BFG Repo-Cleaner (rejected: not available; older tool)
```

If the recommendation can't carry an evidence envelope, the skill surfaces "I don't have enough verified info to make this recommendation; here's what I'd need to verify." Better to halt than to fabricate.

---

## Handling source conflicts

When two sources disagree (e.g., the user's `git --version` says 2.30 but a blog post says "this only works in 2.36+"):

1. **Believe the live tool**: 2.30 is what's on this machine. The recommendation must work on 2.30 or it doesn't apply.
2. **Document the conflict in `verification_log.md`**.
3. **Surface to user with the alternatives**: "Your git is 2.30; the recommended `--filter` flag was added in 2.36. Options: (a) upgrade git to 2.36+, (b) use the older `--path` syntax, (c) skip this operation."
4. **Never fabricate compatibility**: don't say "should work on 2.30" without verification.

---

## Known-baseline verification (when this overlay was last verified)

Skill maintainers update this section quarterly. Last verified: 2026-05-08.

| Subject | Version | Note |
|---------|---------|------|
| `git` rename-detection threshold default | 50% (configurable via `diff.renames`) | Stable from 2.18; expanded knobs in 2.40 |
| `git filter-repo` invocation | `--invert-paths --path X` | Stable from 2.36; same syntax used through 2.45 |
| `git lfs smudge` pointer-format | v1 + v2 supported in 3.4+ | Older clients may emit v1-only |
| `git push --force-with-lease=<refname>:<expected>` | Supported | Added 2.30, refined 2.39 |
| Submodule `(rewind)` marker in `git diff --submodule=log` | Stable | Output format is parseable but not strictly versioned |
| `core.autocrlf` | OS default: `auto` on Windows, `false` elsewhere | Affects Phase 3 byte-equality |
| `protocol.file.allow` default | `user` (changed from `always` in 2.38.1) | Affects `git submodule update --init` from local paths |

When the next quarterly review happens, the maintainer re-runs `◑ VERIFY-LIVE` against each row and updates the table.

---

## How operators integrate

Three operators use this overlay directly:

- **`◑ VERIFY-LIVE`** — the explicit invocation; emits the evidence envelope.
- **`✓ ASSESS-VALUE`** — a degenerate verification: "is this file's content really what its name suggests?"
- **`◐ VERIFY-ON-MAIN`** (from sibling stash-janitor) — verification against a specific branch, useful when the user asks "is this junk on main but kept on a feature branch?"

Other operators implicitly depend on the overlay. `🛡 SHADOWING-AUDIT` relies on `git ls-files <pattern>` semantics, which are stable but verifiable. `↪ REWRITE-REFERENCES` relies on the user's git config not silently normalizing the file (`autocrlf`), which is a verifiable invariant.

---

## When to skip the verification

For *evergreen* recommendations, skip the overlay. For *volatile* recommendations, the overlay is mandatory. The honest test: if a future reader of `verification_log.md` could disprove the recommendation by changing the live state, the recommendation needed an evidence envelope.
