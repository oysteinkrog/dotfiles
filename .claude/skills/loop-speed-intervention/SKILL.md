---
name: loop-speed-intervention
description: >-
  Find out why an improve-and-measure loop is slow and restructure it, so each idea gets a
  verdict in seconds or minutes instead of a night. Use when a session or a goal loop keeps
  waiting on a scarce resource (a lab machine, a night slot, CI, a human), when the stop hook
  or a cron check repeats "still waiting" with nothing to act on, when most experiments end in
  "no gain" or "noise", when one verdict takes more than a few hours, when a manager or
  oversight session reviews other sessions' progress, or when the user says the work feels
  slow, says "speed up our loop", "why is this so slow" or "intervention".
---

# Loop speed intervention

A loop is the cycle: pick a target, change code, measure, decide. This skill makes that cycle
faster. It does not make the product faster; it makes finding product speed-ups faster.

The case that made this a skill (load-speed round, Mon 2026-11-16): a session spent about 60
stop-hook turns answering "Waiting for plan 31 at 20:28". The lab PC was free all day, but a
rule kept it to nights. Every idea waited a night for a verdict, and most came back "no gain".
Oystein stepped in and asked for a faster loop. Within an hour:
- a deterministic test on plain Linux .NET reproduced, in 4 s, the take-switch delay that had
  taken three lab nights to pin down;
- one question to Oystein freed the daytime lab, so three verdicts came the same day instead
  of the next morning.

Run this skill before the human has to step in.

## When to run it

Run it when you see any of these. Each one is cheap to check.

| Signal | How to see it |
|---|---|
| Idle waiting | 3 or more turns in a row where you only report that you wait for something external |
| Slow verdicts | The time from "idea ready" to "verdict" is more than about 4 hours |
| Low yield | Half or more of recent experiments ended in "no gain", "noise" or "invalid run" |
| Lost runs | Runs lost to setup: disk full, wrong build, clock gates, a script that refused |
| Many pairs | A measurement needs 10 or more repeats to see an effect, because the timing is noisy |
| Wrong machine | Results on the dev machine do not hold on the target (emulation, Wine, VM, laptop) |
| Bespoke scripts | Each experiment gets its own set of hand-written scripts |
| A rule holds the resource | A scarce resource sits idle because a permission rule keeps it for later |

Manager and oversight sessions: look for these signals in the sessions you oversee (their
logs, their last messages, `ListAgents`), not only in your own.

## Step 1: measure the loop (10 minutes)

Get numbers from the logs before you propose anything. Write them in a short table:

- verdicts per day, and the median hours from "ready" to "verdict";
- the share of runs lost or rerun because of setup, with each cause named;
- the share of experiments that ended in "no gain";
- repeats needed per comparison, and the run-to-run spread;
- idle time: hours the scarce resource sat unused, and hours the agent only waited;
- cases where the cheap machine and the target machine disagreed.

## Step 2: move measurement down the tiers

The main lever. Put each question on the cheapest tier that can answer it.

| Tier | What | Time | Repeats needed |
|---|---|---|---|
| 0 | A test that counts the work: objects built, events raised, queries run, bytes allocated, items late in virtual time | seconds | 1, because a count does not vary |
| 1 | A headless run of the real pipeline, timed, no UI | minutes | about 5 |
| 2 | The full app on the target machine | an hour or more | 10 to 20 |

Rules:
- A wall-clock number is the last resort. First ask what the cost is made of, and count that.
- Use virtual time (test schedulers, fake time providers) for anything with throttles, delays
  or ordering. It makes timing exact and repeatable.
- Run on the native platform when the build allows it. An emulator (Wine, a VM) adds costs the
  target does not have.
- The target machine is for the final check of what needs it: real GPU, real screen, real
  devices. It is not where you look for targets.
- Pick targets from repeated measurements, never from one trace. A single sampled trace cannot
  rank costs below about 50 ms.
- A tier-0 test that reproduces a problem becomes a gate on the fix: it fails before and passes
  after. Ship it with the fix.

## Step 3: remove friction around the scarce resource

- **Ask for the resource:** If a permission rule keeps a free machine idle, ask the owner one
  question (AskUserQuestion) with the numbers. Record the answer with its exact words and its
  scope.
- **One generic runner:** Experiments are data (build A, build B, scenario, repeats), not new
  scripts. Each new script is a new place for a setup failure.
- **Fail before the slot:** Check disk, builds (a string only the new commit has), clocks and
  bookings before the slot starts, not inside it.
- **Stop early:** Use a sequential test or a fixed bar, so a clear result ends the run.
- **Move work forward:** When the resource is free now, move the next booked run to now. Gates
  computed from the real start time make this safe.
- **Keep teammates fed:** Forward job results that do not reach them on their own.

## Step 4: act, then report

- Start the work in the same turn: lanes for the tier-0 and tier-1 tests, the resource
  question, the moved runs. Do not stop at a proposal.
- Tell the user in a short table: the friction found (with numbers), what changed, and the
  first proof that the new loop works.
- Record the change where the next session finds it (the project log, a memory entry, the
  progress page).

## Limits

- Some costs only exist on the target: GPU device creation, layout and drawing, real devices.
  Those stay on tier 2. Tiers 0 and 1 cut how many ideas reach it.
- A count is a proxy. Before trusting it, check once that it moves with the real cost.
- Do not loosen a permission rule yourself. Ask the person who owns it.
