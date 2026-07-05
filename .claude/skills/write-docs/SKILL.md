---
name: write-docs
description: Write and edit project docs (README/markdown) as a glossary of principles, not a mirror of the code. Use when creating or revising a README; when a doc enumerates exact scenes, scenarios, helpers, class ids, file lists, or command/flag matrices the code already holds; when trimming narrative or changelog out of a doc; or when deduplicating overlapping docs and wiring a root doc to its sub-docs.
---

# Write Docs

A doc is a **glossary**: it names the moving parts, says why each exists, and
carries the principles a reader can't derive by grepping. The code is the source
of truth for *what exists right now* — the doc must never race it. Before writing
any line, ask the one question that governs this skill: **could the reader get
this faster and more reliably by reading the code?** If yes, point them at the
code instead of copying it in.

## Keep vs shed

Keep — a reader cannot grep their way to these:

- The WHY: why a thing exists, the principle behind a split, the taxonomy file
  names don't reveal.
- Non-obvious discoveries: platform quirks, "if you remove this, X breaks
  because Y", a contract two files silently share.
- Pointers to where things live, and what KIND of thing lives there plus the
  rule for what belongs.

Shed — the code or its git history already holds these, so a copy only rots:

- Exact rosters: scene names, scenario tables, helper lists, class ids, file
  lists, command/flag matrices.
- Narrative and changelog: "we renamed X", "the old Y was removed as a dup",
  what was tried and abandoned.
- Exact counts, tick values, current constants, line numbers — anything that
  just restates the code.

## Point, don't transcribe

Where you're tempted to list specifics, name the folder or the single file that
owns them and send the reader there — **prefer a folder over a file, a
source-of-truth registry over a transcribed copy.** Describe a helper module by
the *kind* of helper it holds and the rule for what belongs in it, not its
current roster. One concrete touchstone is fine to ground a principle; a full
inventory is the smell. "The matchups live in the table that defines them; the
ids key off the class registry" stays true after the next edit — reproducing
either does not.

## One home per fact

Every fact has exactly one canonical home; every other doc links to it.
Repetition across docs is a maintenance bug — copies drift and the reader can't
tell which is current. A root/global doc gets a short section plus pointers to
the sub-docs; sub-docs cross-link back to that hub and to each other. When two
docs explain the same thing, pick the hub and cut the other to a pointer.

## Edit pass

When trimming an existing doc, delete on sight: enumerations of
code-discoverable items, changelog and narrative, and any sentence that restates
the code. Then read what survives as a stranger with no conversation history —
every remaining line should be a principle, a why, or a pointer. If a line would
be just as true and just as useful as a link, make it the link.
