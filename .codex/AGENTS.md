# Global Codex instructions (Oystein's machines)

These rules hold in every repository. A repository's own `AGENTS.md` adds the rest.

## Slow improve-and-measure loops

Oystein, 2026-11-16. When a session keeps waiting on a scarce resource (a lab machine, a night
slot, CI, a person), or most of its experiments end in "no gain", read the
`loop-speed-intervention` skill (`~/.agents/skills/loop-speed-intervention/SKILL.md`) and
restructure the loop without being asked:

- count the work in a test that runs in seconds;
- run the real pipeline headless, in minutes;
- ask the owner for a resource that sits idle;
- move booked runs earlier.

Manager and oversight sessions run the skill on the sessions they watch too. The
`slow-loop-detect` Stop hook in `~/.codex/hooks.json` starts it after 5 idle "waiting"
replies in a row.
