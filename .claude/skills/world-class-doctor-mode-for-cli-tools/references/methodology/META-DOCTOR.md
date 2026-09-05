# The Meta-Doctor — Validating the Skill Itself

Pattern 12 from the cookbook. This skill builds doctors; the skill *itself* is a kind of structured artifact that benefits from the same kernel: detect-then-fix, single-chokepoint, byte-for-byte traceability of changes, fixture-pinned tests.

A meta-doctor is `world-class-doctor-mode-for-cli-tools/scripts/validate-skill.sh` (script that performs the role of `<this-skill> doctor` against another skill, including itself).

---

## Failure-mode catalog (skill-internal)

### `references_integrity` subsystem

```
fm-references-integrity-broken-link
  symptoms: SKILL.md links to references/methodology/X.md which doesn't exist.
  detector: walk Markdown links; for each relative link, assert target exists.
  fixer: refuse — broken link is the symptom; the fix is to either create
         the target or remove the link. Manual remediation lists offenders.

fm-references-integrity-quote-id-rot
  symptoms: An artifact cites Q-NNN but Q-NNN doesn't exist in QUOTE-BANK.md
            (or has been retired without a back-reference update).
  detector: scan all .md files for "Q-NNN" patterns; check QUOTE-BANK.md.
  fixer: refuse — manual remediation.

fm-references-integrity-corpus-path-rot
  symptoms: CORPUS.md cites /dp/<path> that no longer exists locally.
  detector: parse CORPUS.md; check each cited path with `test -e`.
  fixer: refuse — could be the user's machine missing /dp; or the path
         genuinely moved. Manual remediation per case.

fm-references-integrity-circular-link
  symptoms: A cycle in references/methodology/*.md references.
  detector: build the link graph; check for cycles.
  fixer: refuse — circular reference is rarely actually wrong but worth
         flagging. Manual review.
```

### `frontmatter` subsystem

```
fm-frontmatter-name-mismatch
  symptoms: SKILL.md frontmatter `name` doesn't match the directory name.
  detector: parse YAML frontmatter; compare with basename.
  fixer: rewrite the frontmatter via mutate(). Always idempotent.
         (One of the few auto-fixable meta-issues.)

fm-frontmatter-description-too-long
  symptoms: SKILL.md frontmatter `description` exceeds 220 characters
            (the harness's display budget).
  detector: parse frontmatter; count chars.
  fixer: refuse — content edit is the user's call.

fm-frontmatter-description-missing-trigger-words
  symptoms: The description doesn't mention the verbs / nouns most likely
            to trigger this skill (per skill-authoring guidance).
  detector: regex against a heuristic word list.
  fixer: refuse — content edit.
```

### `subagents_consistency` subsystem

```
fm-subagents-consistency-orphan
  symptoms: SKILL.md references subagents/X.md but X.md doesn't exist.
  detector: parse SKILL.md links to subagents/; check existence.
  fixer: refuse — content edit.

fm-subagents-consistency-unreferenced
  symptoms: subagents/X.md exists but no other artifact references it.
  detector: build cross-reference graph.
  fixer: refuse — could be a deliberate keep-around for future use.

fm-subagents-consistency-prompt-not-self-contained
  symptoms: A subagent's prompt references "the calling agent's context"
            without specifying what context. The receiving fresh-context
            agent would not have it.
  detector: heuristic regex for unresolved {{vars}} in subagent prompts.
  fixer: refuse — manual rewrite.
```

### `scripts` subsystem

```
fm-scripts-not-executable
  symptoms: scripts/X.sh exists but isn't `+x`.
  detector: stat each scripts/*.sh and *.py.
  fixer: chmod +x via mutate() with Op::Chmod.

fm-scripts-shebang-missing
  symptoms: scripts/X.sh first line isn't `#!/usr/bin/env bash`.
  detector: read first line.
  fixer: refuse — auto-prepending shebangs is presumptuous; manual edit.

fm-scripts-set-euo-pipefail-missing
  symptoms: scripts/X.sh lacks `set -euo pipefail`.
  detector: grep first 10 lines.
  fixer: refuse — manual edit.
```

### `assets` subsystem

```
fm-assets-template-malformed
  symptoms: assets/manifest-template.json isn't valid JSON, or
            assets/repair-spec-template.md is missing a required section.
  detector: jq parse / regex section check.
  fixer: refuse — manual edit.

fm-assets-template-references-undefined-id
  symptoms: A template's example uses a Q-NNN ID that doesn't exist.
  detector: same as Q-ID-rot above.
  fixer: refuse — manual edit.
```

---

## Surface

```text
scripts/validate-skill.sh <skill-dir>
    Run all skill-internal detectors. Read-only. Exit 0 if clean, 1 with
    violations on stderr if not.
```

The current implementation is intentionally minimal: read-only auditing only, no `--fix` / `--json` / `undo` surface. Auto-fixers are deferred per the "fixer: refuse" disposition on every documented FM (manual remediation is universally the right call for skill-internal issues — content edits should be the human's choice).

---

## Bootstrap recursion (aspirational shape)

A future Pattern-12 self-doctor that fully matches the kernel would have:

- **Single-chokepoint.** All meta-doctor mutations through a `mutate()` (a bash-port of the chokepoint or a shim around an existing language port).
- **Byte-for-byte backups.** Tiny meta-fixes (chmod +x, rename frontmatter field) backed up to `.doctor/runs/<run-id>/backups/`.
- **Reversibility.** `validate-skill.sh undo <run-id>` works.
- **Fixtures.** `tests/meta-doctor-fixtures/` per FM, with the same round-trip discipline.

The current `validate-skill.sh` is the read-only-detector subset of this design. Building the auto-fix path (and undo, fixtures, etc.) is on the roadmap — see [ROADMAP.md](ROADMAP.md) "Doctor's own changelog generator" + "Cross-skill consistency validator".

---

## When to invoke

- Before publishing a new skill (a final pass).
- After running any skill-pack manifest sync (to verify the sync didn't introduce a reference drift).
- As part of CI for this skill repo (gate on every PR).
- After any large refactor of references/ or subagents/.

---

## Implementation status (current)

`scripts/validate-skill.sh` IS implemented and used as a CI-style gate. It currently runs **17 sections of checks** (rounds 53, 55, 56 added sections 9-17):

1. Frontmatter description ≤ 1024 chars + `name` matches directory.
2. Q-NNN citations resolve to QUOTE-BANK.md.
3. Every `subagents/*.md` is referenced from SKILL.md.
4. All `scripts/*.sh` and `*.py` are executable (`+x`).
5. Markdown link targets resolve (no missing relative `.md` targets).
6. No destructive shell patterns (`rm -rf`, `git reset --hard`, `git clean -fd`) outside well-marked exemption blocks.
7. Every `references/methodology/*.md` is referenced from SKILL.md (no orphans).
8. Every backtick-wrapped `` `scripts/<name>` `` reference points at an existing script (or appears on a line marked `planned` / `proposed` / `future` / `removed` / `replaced` / etc. — the keyword list is in the script).
9. No CI-snippet line in docs invokes `./scripts/scorecard.py` (cross-repo bug class — rounds 36/49/51).
10. Every `discover-cli.sh <target>` invocation in docs has `--probe-doctor` (or `# language-only` annotation) — round 52 Bugs 3/4.
11. Docs MUST NOT list `Chown` in the Op enum without an "optional" qualifier — Chown is the optional 8th variant (rounds 43, 52).
12. Doctor-verb-list enumerations MUST include all 7 verbs (doctor/health/verify/repair/check/diagnose/fix), not just the older 5-verb subset (round 19).
13. CI YAML steps running `<tool> doctor --json` MUST handle exit code 1 (findings present) explicitly to avoid `bash -e` abort (round 52 Bug 2).
14. Every shell script under scripts/ has `set -euo pipefail` within first 20 lines (round 16).
15. No scripts/*.sh or scripts/*.py contains hardcoded user-specific absolute paths (`/data/projects/`, `/home/<user>/`, `/Users/<user>/`) outside example-marked comments (round 25).
16. Numerical-claim consistency: `dimension rubric` (10), `canonical/doctor subcommand` (10), `canonical exit code` (11), `canonical Op variant` (7), `axiom kernel` (24), `canonical CASS quer` (13). Round 56.
17. Shell code blocks (` ```bash ` / ` ```sh `) parse cleanly with `bash -n`, exempting blocks with template placeholders or `<!-- noverify -->` markers. Round 56.

**Detectors documented above but NOT yet implemented** (gaps a future round could close):

- `fm-references-integrity-corpus-path-rot`: detect references in CORPUS.md to /dp/<path> that don't exist locally.
- `fm-references-integrity-circular-link`: cycle detection in the methodology graph.
- `fm-frontmatter-description-too-long` (over a 220-char display budget — the meta-doctor only enforces the harder 1024-char API limit currently).
- `fm-frontmatter-description-missing-trigger-words`: heuristic against a word list.
- `fm-subagents-consistency-prompt-not-self-contained`: regex for unresolved `{{vars}}` in subagent prompts.
- `fm-scripts-shebang-missing`: detect `scripts/*.sh` whose first line isn't `#!/usr/bin/env bash`.
- `fm-assets-template-malformed`: jq-parse all `assets/*.json` (with documented JSONL exception per round-23).
- `fm-assets-template-references-undefined-id`: cross-check Q-NNN refs in templates.

These are noted on the ROADMAP. A future round could add them to `scripts/validate-skill.sh` under new sections 18+.
