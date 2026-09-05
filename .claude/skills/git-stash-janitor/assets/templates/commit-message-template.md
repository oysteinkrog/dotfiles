# Recovery Commit Message Template

Use this template for Phase 6 / Phase 7 commits. See `references/COMMIT-MESSAGE-CRAFT.md` for the full guide.

---

## Standard recovery commit

```
{prefix} recover {one-line summary} from stashed WIP

Originally drafted in stash@{N} (sha {sha}, dated {date}).
{2-3 sentences explaining the change's motivation: what problem does it
solve, what would break without it, why does it matter}

The polished version of this stash never landed because {reason}.
{Optional 1-2 sentences on the developmental path that left it stashed}

Recovered via: git apply --3way <bundle>/diffs/{NPAD}.diff
{Optional: noting any manual conflict resolution}
```

Where `{prefix}` is one of (per `project_profile.json:commit_message_convention`):
- `feat:` for new functionality
- `fix:` for bug fixes
- `test:` for test-only recovery
- `perf:` for performance improvements
- Or a ticket-id prefix like `BACK-1742:`
- Or no prefix for freeform projects

---

## Split-apply commit (Phase 7)

```
{prefix} recover {summary} from partial stash@{N}

Originally stash@{N} mixed {what landed} with {what's novel}; the
{what landed} portion already merged via PR #{X}. This commit recovers
only the novel hunks.

Hunks recovered: {kept_count} of {total_count}.
- Hunk {i}: {description}
- Hunk {j}: {description}

Hunks dropped (already on main): {dropped_count}
- Hunk {k}: superseded by {citation}

Recovered via: <bundle>/diffs/{NPAD}.split.diff (split from
<bundle>/diffs/{NPAD}.diff to drop superseded hunks).
```

---

## Conflict-resolved commit

```
{prefix} recover {summary} ported through main's {refactor description}

Originally stash@{N}'s diff modifies {old structure} at {file:line of
stash's parent}. On main today, that structure has been refactored
into {new structure} at {current file:line}.

The 3-way apply could have produced syntactically broken code. Instead,
the stash's *intent* ({the actual goal}) was ported into main's current
structure via the Edit tool.

Recovered via: manual resolution; see <workspace>/conflicts/stash_{NPAD}.context.md
for the full surface diff.
```

---

## Bug-fix recovery

```
fix: recover {bug guard / fix} for {affected component}

Originally stash@{N} (sha {sha}, dated {date}). Discovered while
{context}: {short bug description}.

The polished version landed in PR #{X}, but only for {covered case};
this commit applies the same {fix} to {missed case}.

Recovered via: git apply --3way <bundle>/diffs/{NPAD}.diff (clean apply).
Hunks: {n} of {m}. Tests: {test command} passed.
```

---

## Authoring checklist

- [ ] Subject ≤72 chars
- [ ] Subject is present-tense verb + concrete object (not "stash apply")
- [ ] Body has Context, Why-not-landed, How-recovered sections
- [ ] Stash sha + date cited
- [ ] Bundle diff path cited
- [ ] Convention compliance (Conventional / ticket-id / gitmoji / freeform)
- [ ] No `Co-Authored-By` (unless user requested)
- [ ] Stand-alone readable (future-you in 6 months)
