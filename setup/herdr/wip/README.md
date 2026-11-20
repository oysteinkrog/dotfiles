# Work in progress: not installed by herdr-setup

`herdr-setup install` copies only `files/` and applies `patches/`. Nothing in this folder
reaches a machine until it moves there.

- `space-freeze/`: the Freeze/Thaw mod for the krog layout. `freeze.sh` does the work on the
  machine that owns the space; `main.js` is the space menu and the confirm dialog. When done,
  move it to `files/mods/space-freeze/`.
- `space-folders.main.js`: the space-folders `main.js` with the hooks for it (space menu opens
  space-freeze, snowflake on frozen rows, 60 s refresh). When done, turn it into
  `patches/space-folders.patch` (diff against upstream 63a78b2 plus the current patch).

"Freeze" here means the programs exit and are resumed later. It is not the cgroup freeze of
freeze-job.sh, where a process stays in memory.
