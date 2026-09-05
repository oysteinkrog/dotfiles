# Forensic Report Template

Used by the archaeologist subagent for `novel-but-stale` rows. The output goes to `<workspace>/forensic_<NPAD>.md` and informs the user's Phase 5 decision.

---

```markdown
# Forensic reconstruction: stash@{N}

## Stash metadata

- sha: {full_sha}
- parent: {parent_sha}
- date: {iso_date}
- author: {author}
- has_untracked: {true|false}
- message: {message}

## Diff fingerprint

- Functions introduced: {list}
- Types introduced: {list}
- Tests introduced: {list}
- Files touched (new): {list}
- Files touched (modified): {list}
- Files touched (deleted): {list}

## Parent's reachability

- Parent {parent_sha} is {reachable|unreachable} from current {primary_branch}.
- Parent's branches (if reachable): {branches}
- Parent's commit message: "{commit_subject}"

## Surrounding activity

Activity in the {stash_date} ± window:

\```
{git log --since=... --until=... output}
\```

Sibling stashes (same author, ±2 hours):
\```
{related stash entries from inventory}
\```

## Beads context

If message contains a ticket id:

- Ticket: {ticket_id}
- Title: {ticket_title}
- Status: {ticket_status}
- Closed by: {pr_or_commit}
- Linked PR description: {description excerpt}

## Reconstruction

The developer ({author}) appears to have been working on {goal}. Evidence:
- {Evidence point 1}
- {Evidence point 2}
- {Evidence point 3}

The work {was|was not} continued elsewhere:
- {If continued: where it landed; what's different from this stash}
- {If abandoned: when the parent's branch was deleted; whether the user explicitly threw it away}

## Why it's "novel-but-stale"

- Files referenced no longer exist on {primary_branch}: {list}
- OR Apply-check rejects all hunks because surrounding context drifted by {N} lines

## Recommendation

**{rewrite-on-current-main | drop-with-note | surface-to-user-undecided}**

Confidence: {0.0-1.0}

### If `rewrite-on-current-main`:

The stash's intent ({summary}) is genuinely additive over current main.
A rewrite would:
- Replace {old structure} with {equivalent in new structure}
- Map symbol {old_name} → {new_name on current main}
- Preserve {invariant}

This is a separate task; the recovery commit would be authored fresh by
a developer or follow-up agent. The bundle and backup ref remain so the
original is recoverable as a reference.

### If `drop-with-note`:

The work was clearly abandoned in favor of {polished version landed at <SHA>}
or because {context that no longer exists}. The diff is preserved in the
bundle for forensic purposes; no recovery is recommended.

### If `surface-to-user-undecided`:

The forensic evidence is ambiguous: {what's unclear}.
The user should make the call based on {key question they need to answer}.
```

---

## Authoring discipline

- **Cite every claim.** Every statement in the reconstruction must be traceable to a specific git output, branch listing, or beads entry.
- **State confidence.** Don't hedge with "maybe" or "possibly"; assign a number.
- **Don't propose code.** The archaeologist's job is intent + recommendation, not implementation.
- **Stand alone.** A reader who hasn't seen the stash's diff should be able to understand the reconstruction.

---

## When to use which recommendation

- **`rewrite-on-current-main`** — when the stash represents genuinely useful work that's nontrivially equivalent to current main, AND the user is willing to invest in a rewrite. Confidence ≥ 0.8.
- **`drop-with-note`** — when the work was abandoned, superseded, or the underlying problem no longer exists. Confidence ≥ 0.8.
- **`surface-to-user-undecided`** — when the evidence is ambiguous. Confidence < 0.8 OR conflicting evidence.

The user is the final arbiter. The forensic report informs their decision but doesn't substitute for it.
