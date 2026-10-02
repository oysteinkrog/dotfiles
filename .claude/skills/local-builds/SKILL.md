---
name: local-builds
description: How to patch, build and install open source software on this desktop through ~/src/localbuilds and the localbuild command. Use before editing, rebuilding or installing any patched or source-built upstream project (Wine, DXVK, FrankenTerm, cass and the like), before copying a binary into ~/.local/bin or a Wine prefix, when adding a new patch or fork, or when the user says "patch", "rebuild", "local build", "localbuild", "custom build" or "our Wine".
---

# Local builds

Every patched or source-built upstream project on this machine has a recipe in
`~/src/localbuilds` (public repo `oysteinkrog/localbuilds`). `localbuild` builds it in a
fresh worktree and installs it. Read `~/src/localbuilds/README.md` for the full layout;
this skill is the working procedure.

## Before you start

1. `localbuild status` shows every recipe, what is installed and any problem (unsaved
   edits, unpushed fork commits, recipe changed since install).
2. `cat ~/src/localbuilds/INDEX.md` lists the recipes. Read the recipe's `README.md` and
   `recipe.sh` before changing it.
3. Other sessions may be building too. Builds lock per build ID and installs lock per
   install root, so two sessions cannot clobber each other, but check `status` first.

## Change a patches-mode recipe (Wine and similar)

```sh
localbuild build wine@taskslinger           # fresh worktree, series applied
cd "$(localbuild shell wine@taskslinger)"   # edit here, never in ~/src/wine
localbuild build wine@taskslinger --dev     # rebuild with your edits; cannot be installed
# test it ...
localbuild patch-save wine@taskslinger <slug> -m "<module>: <what it fixes>"
```

Then in `~/src/localbuilds`:

1. Edit the new patch file's message: say why, and add `Upstream-Status: local-only`.
2. Add a row for it in the recipe `README.md`.
3. `localbuild index`, then commit with a pathspec.
4. `localbuild build wine@taskslinger && localbuild install wine@taskslinger`.

## Change a fork-mode recipe (FrankenTerm and similar)

1. Work in `~/src/<name>` on a branch off the fork branch named in the recipe README.
   Other sessions may share that checkout: never reset, rebase or switch its branch under
   them. If you need your own history, use `git worktree add` outside any grove directory.
2. Commit and push to the fork (`git push fork <branch>`).
3. `localbuild bump <name> <full commit>`, `localbuild build <name>`, test, commit the
   recipe, `localbuild install <name>`.

## Add a new project

1. `mkdir ~/src/localbuilds/recipes/<name>`, write `recipe.sh` (see `lib/common.sh` header
   for the fields), `README.md` whose first line says what it is, and either `series` plus
   `patches/` or a `PKGBUILD`.
2. Prefer `KIND=pkg` (pacman package) for ordinary tools. Use `KIND=tree` only when the
   software needs side-by-side copies.
3. Use `MODE=fork`: fork the upstream on GitHub under oysteinkrog, put each change on a
   branch as a commit with a message that says why. Use `MODE=patches` only when there is no
   git repository to fork.
4. Build, install, `localbuild index`, commit.

## Never

- Run `make`, `cargo build` or `configure` in `~/src/<name>` for something that gets
  installed. Use `localbuild build`.
- Copy a binary into `~/.local/bin`, `/usr/local/bin` or a Wine prefix by hand.
- Leave an edit only in a build tree or a `~/.cache` source tree. Save it with
  `patch-save` (or commit and push it to the fork) before you stop.
- Put hostnames, IPs, serials or account names into localbuilds. The pre-commit hook checks
  against `~/work/Life/setup/localbuilds/private-words.txt`. Naming or linking the company
  forks is fine.
- Put a change the company product (Swing Catalyst) needs into localbuilds. Those go on a
  `swing-catalyst/*` branch of the InitialForce fork and are built by the monorepo's
  `tools/wine` scripts.

## After a system upgrade

Run `localbuild check`. It warns when the system moved under a recipe, for example a Wine
upgrade past the pinned release. Installed copies keep working; move the pin with
`localbuild bump` when you have time to rebase the patches.
