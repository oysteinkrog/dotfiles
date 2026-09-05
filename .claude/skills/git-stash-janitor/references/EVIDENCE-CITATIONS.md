# Evidence Citations — How to Cite What You Found

Every triage row has an `evidence_on_main` field. Every conflict resolution has a context.md file. Every handoff statement has a workspace artifact backing it. This file is the citation style guide.

---

## Why citations matter

The user reviews the triage table in Phase 5. Their default question on every row is *"how do you know?"* If the agent can answer with a file:line citation that takes the user straight to the evidence, the verdict is trustworthy. If the agent can only say "it looks superseded", it isn't.

---

## Citation forms

### Form A: file:line (preferred for code)

```
src/mutex.rs:317
src/mysql/protocol.rs:218-245
```

Use when:
- Verifying a symbol exists on main
- Pointing at a line that proves supersession
- Citing a refactor that obsoleted the stash

The line number is to the primary branch, not the stash. If you cite a range, the range is the surrounding context the user would want to see.

### Form B: commit SHA + path

```
abc1234:src/parser.rs
def5678:tests/parser_test.rs:42
```

Use when:
- Citing a specific commit that landed the polished version
- Referencing a commit that's not on the current primary branch tip (e.g., from `git log --since` historical context)
- Pointing at the original stash (e.g., `<bundle>/diffs/034.diff` references stash sha `8a3d2c9`)

### Form C: bead / issue id

```
BACK-1742
PR-234
fixes #2071
br-1m86f
```

Use when:
- The stash message references a ticket
- The polished version landed via a specific PR
- The recovery commit closes a related issue

### Form D: bundle artifact path

```
<bundle>/diffs/034.diff
<bundle>/meta/034.txt
<workspace>/conflicts/stash_034.context.md
```

Use when:
- Pointing at the original stash content (the diff is the truth, not the agent's recall)
- Referencing the recovery context for a manual conflict resolution
- Linking the handoff report to its supporting workspace files

### Form E: prefix-match (for garbage prefix verdict)

```
prefix-match: other-agent-broken
```

Use when:
- The verdict is `garbage` based on message prefix alone
- No fingerprint analysis was needed (the prefix is sufficient)

### Form F: signature-divergence (for flipped-from-superseded verdicts)

```
signature-divergence: stash has lock_until(Instant); main:src/mutex.rs:317 has lock_until(Duration)
```

Use when:
- A symbol exists on main with the same name but different signature
- The verdict is forcibly NOT `superseded` even though name-grep found a match

---

## Per-verdict required citations

| Verdict | Required citation form(s) |
|---------|---------------------------|
| `superseded` | A (file:line on main where the symbol resolves) AND, when sample-signatures match, F's converse: `signature-match: stash and main agree on (Instant) -> Result<()>` |
| `garbage` (by prefix) | E (prefix-match: <prefix>) |
| `garbage` (by content) | A or B citing the polished version that superseded the entire stash |
| `novel-and-accretive` | "no symbols found on main" + the apply-check status (clean) |
| `partially-novel` | Per-hunk: A for superseded hunks, "novel" for the keepers |
| `novel-but-stale` | A or D showing the file no longer exists; B showing the commit that removed it (if known) |
| `unknown` | Honest description of why: "empty fingerprint", "binary diff", "language not supported by rubric" |

---

## How to discover citations

### For `superseded` verdicts

```bash
# Path-scoped grep first (faster, more accurate)
git grep -n -F 'lock_until' main -- 'src/**/*.rs'
# Returns: src/mutex.rs:317:    pub fn lock_until(deadline: Instant) -> Result<()>

# Whole-repo if path-scoped finds nothing
git grep -n -F 'lock_until' main
```

The output gives you the file:line citation directly.

### For `partially-novel` per-hunk evidence

For each hunk in the diff:
1. Identify the hunk's introduced symbols
2. Run grep for each symbol
3. The hunk's verdict = max-confidence match

### For `novel-but-stale` evidence

```bash
# Show the file's history on main
git log --all --oneline -- src/cli/legacy.rs | head -5
# If the file appears, find when it was removed
git log --diff-filter=D --all --oneline -- src/cli/legacy.rs
# Returns: deadbeef src/cli/legacy.rs deleted in PR #198
```

The deletion commit is the citation: "B: deadbeef removed src/cli/legacy.rs".

### For signature-divergence

```bash
# Pull the signature from the stash (from the bundle's diff)
grep -E '^\+.*fn lock_until' <bundle>/diffs/034.diff
# Pull the signature from main
git grep -E 'fn lock_until' main -- 'src/**/*.rs'
# Compare param lists; if they differ, signature-divergence is real
```

---

## Citation density per phase

| Phase | Typical citation density |
|-------|-------------------------|
| 4 (triage) | One citation per row in `triage.tsv:evidence_on_main` |
| 5 (decision table) | One citation per row in `triage_decision.md` |
| 6 (commit messages) | 2–4 citations per recovery commit (stash sha, bundle diff, PR # if known, file:line) |
| 8 (fresh-eyes findings) | One citation per finding (which file, which line) |
| 9 (cleanup_log.tsv) | The dropped ref + verdict — both are self-citations |
| 10 (handoff report) | Recovered commits → SHA citations; recovery recipes → bundle paths; counts → tsv files |

---

## Anti-Patterns in Citation

| ✗ | Why |
|---|-----|
| "looks superseded" with no citation | Unverifiable; user can't audit |
| Citing only the symbol name | User has to grep themselves; do the grep for them |
| Citing without verifying the path/sha exists | Breaks user trust on first dead link |
| Citing the WORKSPACE files for the user but not for yourself | Self-discipline matters; cite for your own future-readability too |
| Multi-line citations in TSV files | TSV is one row; truncate or reference an external file (`see conflicts/stash_034.context.md`) |
| Stale citations (file:line that pointed somewhere relevant 3 commits ago but no longer does) | Cite against `origin/<primary>` at run-start, not against HEAD which may have moved |

---

## Example: full citation chain for a recovered commit

In `triage.tsv`:
```
34  novel-and-accretive  0.92  no symbols on main; apply-check clean  clean  defensive_ok_packet_length_cap fn (mysql)
```

In `triage_decision.md`:
```markdown
| 34 | wip-BACK-1742-mysql-ok | 1 | 0.92 | no symbols on main; apply-check clean | apply --3way (1 hunk) |
```

In the resulting commit message:
```
recover defensive MySQL OK-packet length-cap from stashed WIP

Originally drafted in stash@{34} (sha 8a3d2c9, dated 2026-04-29).
[...]

Recovered via: git apply --3way <bundle>/diffs/034.diff
```

In `apply_log.tsv`:
```
34  stash@{34}  def987  2  passed  78  none
```

In `handoff_report.md`:
```markdown
## Recovered commits

| sha | from stash | message |
|-----|------------|---------|
| def987 | stash@{34} | recover defensive MySQL OK-packet length-cap from stashed WIP |
```

Every step has a citation that the next step can verify against. The chain is auditable end-to-end.
