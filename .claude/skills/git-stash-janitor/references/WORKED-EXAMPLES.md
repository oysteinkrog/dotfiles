# Worked Examples — The Asupersync 127-Stash Session

This is the canonical worked example for this skill. The user opened `/data/projects/asupersync` in zsh and saw `*127` in the prompt. They thought it meant 127 commits ahead of origin. It was 127 stashes — accumulated from many concurrent agent sessions.

Each cognitive move is annotated with its operator. The annotations are how the operator library's cards are made memorable for future runs.

---

## Phase 0 / 1 — Reconnaissance

```
USER: what does this mean in my zsh prompt: ` /data/projects/asupersync on  main ! ? *127`?

AGENT: Let me check what the indicators mean.

[★ INVENTORY — first reach for the actual count]
$ git -C /data/projects/asupersync stash list | wc -l
127

$ git rev-list --count @{u}..HEAD
0

$ git status -sb
## main...origin/main
 M src/mysql/mod.rs
 M src/mysql/protocol.rs
?? .stash_temp/

The `*127` in your prompt is the stash counter. Your repo has 127 stashes,
not 127 commits ahead. You're 0 commits ahead of origin/main; the working
tree shows 2 modified files and 1 untracked path — those came from concurrent
agent sessions per AGENTS.md and shouldn't be disturbed.
```

The user then asked the agent to do the triage. The first move was project reconnaissance.

```
[Phase 1 PROFILE — read the rules]
$ cat AGENTS.md  # read in full
$ cat README.md  # read in full
$ git symbolic-ref refs/remotes/origin/HEAD
refs/remotes/origin/main
$ cat Cargo.toml | grep -E '^name|^version'
name = "asupersync"
$ rg --files | grep -E '^(\.github/workflows|Makefile|justfile)' | head
.github/workflows/ci.yml
.github/workflows/release.yml

# Sample recent commit messages
$ git log -50 --format='%s' | head -10
fix(mutex): correct deadlock recovery in lock_until
feat(mysql): add OK packet validation
chore: bump tokio to 1.40
...

→ project_profile.json:
  primary_branch: main
  test_command: cargo test --workspace
  typecheck_command: cargo check --workspace
  lint_command: cargo clippy --workspace -- -D warnings
  format_command: cargo fmt --check
  ubs_available: true (per AGENTS.md)
  dcg_available: true (rm -rf, git reset --hard blocked)
  pre_commit_hooks: husky-rust + pre-commit
  commit_message_convention: conventional + ticket-id (BACK-NNNN)
  stash_message_conventions:
    - "^wip-BACK-\\d+" (most common)
    - "^autostash"
    - "^other-agent-broken"
    - "^temp-pre-push"
    - "^full-tree-reset-stash"
```

---

## Phase 2 — Inventory

```
[★ INVENTORY — capture every stash]
$ git stash list --format='%gd|%H|%P|%ci|%an|%s' > inventory.raw

# Then per stash, capture shortstat and untracked-files presence:
for n in $(seq 0 126); do
  git stash show --stat "stash@{$n}"
  git rev-parse "stash@{$n}^3" 2>/dev/null && echo "has_untracked=true"
done

→ inventory.tsv (127 rows)
→ inventory_grouped.md (7 families):
  - wip-BACK-* (94 stashes)
  - autostash (12)
  - pre-deadlock-fix (9)
  - other-agent-broken (8)
  - temp-pre-push (3)
  - full-tree-reset-stash (1)

AGENT to USER: I found 127 stashes. The dominant pattern is `wip-BACK-NNNN`
(94 stashes — many parallel agent attempts at the same tickets) plus 12
autostashes (almost certainly recoverable from reflog), 9 pre-deadlock-fix
saves (likely superseded by the polished landing), 8 other-agent-broken
(garbage label), 3 temp-pre-push (presumably the push succeeded), and 1
full-tree-reset-stash (almost certainly garbage). Proceed with Phase 3
(recovery bundle)?

USER: yes
```

---

## Phase 3 — Recovery Bundle

```
[⬡ BUNDLE — the irreversibility gate]
$ BUNDLE=/data/projects/asupersync-stash-archive-2026-05-01
$ mkdir -p $BUNDLE/{diffs,meta,stashed-untracked}

AGENT: Saving 127 stashes...

awk -F'\t' 'NR > 1 {print $1 "\t" $3}' .stash_janitor_workspace/inventory.tsv |
while IFS=$'\t' read -r n sha; do
  npad=$(printf '%03d' "$n")
  git update-ref "refs/stash-backup/$npad" "$sha"

  # NOT git format-patch — it is not the stash recovery diff.
  git stash show -p --binary "$sha" > "$BUNDLE/diffs/$npad.diff"

  git log -1 --format='%H%n%P%n%ci%n%an%n%s' "$sha" \
    > "$BUNDLE/meta/$npad.txt"

  if git rev-parse "${sha}^3" >/dev/null 2>&1; then
    git archive --format=tar "${sha}^3" \
      | tar -x -C "$BUNDLE/stashed-untracked/$npad/"
  fi
done

# Index + README
> $BUNDLE/index.tsv
> $BUNDLE/README.md  # documents the format-patch footgun

# Verify byte-equality:
[verification step — gate]
for n in $(seq 0 126); do
  npad=$(printf '%03d' $n)
  live=$(awk -F'\t' -v n="$n" 'NR > 1 && $1 == n {print $3; exit}' .stash_janitor_workspace/inventory.tsv)
  back=$(git rev-parse "refs/stash-backup/$npad")
  [[ "$live" == "$back" ]] || { echo "MISMATCH n=$n"; exit 1; }

  ls=$(git stash show -p --binary "$live" | sha256sum | awk '{print $1}')
  bs=$(sha256sum $BUNDLE/diffs/$npad.diff | awk '{print $1}')
  [[ "$ls" == "$bs" ]] || { echo "DIFF MISMATCH n=$n"; exit 1; }
done

→ All 127 verifications passed.
→ bundle_verification.log: 0 MISMATCH lines.

AGENT to USER: Bundle complete at /data/projects/asupersync-stash-archive-2026-05-01/
with 127 backup refs + 127 diffs + 127 meta files. Verified byte-equal to
live stashes. The recovery story is now fully reversible from this bundle
even after stashes are dropped.
```

---

## Phase 4 — Triage Fan-Out

The agent partitioned 127 stashes into 7 batches of ~18 each, spawning 7 workers in parallel. Each worker, per stash:

```
[✦ FINGERPRINT, then ◐ VERIFY-ON-MAIN]

stash@{0}:
  message: wip-BACK-1742-mutex-lock-until
  fingerprint: { fns: [lock_until, recover_lock], types: [], tests: [] }
  verify_on_main:
    lock_until: src/mutex.rs:317 ✓ same signature
    recover_lock: src/mutex.rs:412 ✓ same signature
  apply_check: clean
  → superseded, conf 0.97, evidence: src/mutex.rs:317,412

stash@{34}:
  message: wip-BACK-1742-mysql-ok-packet-defensive
  fingerprint:
    fns: [defensive_ok_packet_length_cap, parse_ok_packet_safe]
    tests: [test_ok_packet_length_overflow_returns_err]
  verify_on_main: NONE FOUND
  apply_check: clean
  → novel-and-accretive, conf 0.92

stash@{67}:
  message: other-agent-broken
  → garbage, conf 0.99

stash@{82}:
  message: full-tree-reset-stash
  → garbage, conf 0.99

stash@{107}:
  message: autostash
  reflog check: rebase finished cleanly at HEAD~5
  → garbage, conf 0.95 (reflog has the rebase result; the autostash
                         is superseded by the rebase outcome)

stash@{12}:
  message: wip-BACK-1742-mysql-defensive
  fingerprint: { fns: [defensive_ok_packet_length_cap] }   # same as 34!
  verify_on_main: NONE FOUND on main, but stash@{34} also introduces it
  → superseded-by-newer-stash (vs stash@{34}), conf 0.95
```

The triage merger merged 7 batch tsvs into the master `triage.tsv`.

---

## Phase 5 — Merge & Confirm

```
AGENT to USER: triage_decision.md (summary):

KEEP — novel-and-accretive (1)
| n  | message                              | files | evidence |
|----|--------------------------------------|-------|----------|
| 34 | wip-BACK-1742-mysql-ok-packet-def... | 2     | none on main |

KEEP-WITH-SPLIT — partially-novel (0)

MANUAL — novel-but-stale (0)

DROP — superseded (89)  [89-row collapsed table]

DROP — superseded-by-newer-stash (24)  [collapsed]

DROP — garbage (12)  [collapsed]

DROP — autostash-recoverable-from-reflog (1)  [stash@{107}]

Total: 127 (1 keep + 126 drop after applies)

Proposed actions:
  Phase 6: apply stash@{34} on stash-recovery-2026-05-01 branch
  Phase 9 (after authorization): drop in order garbage → superseded →
    superseded-by-newer → applied-keeper, highest index first per bucket

[⚠ CONFIRM]

To proceed to Phase 6 (apply 1 keeper, run cargo test), please confirm.

USER: yes proceed with phase 6, but no destructive cleanup yet
```

---

## Phase 6 — Apply The Keeper

```
[↺ WORKING-TREE-DRIFT]
$ git status --porcelain=v2 > wt_pre_apply_034.txt
# Two files modified that I didn't touch (concurrent agents).
# Per AGENTS.md, treat as if committed by me. Proceed.

$ git show-ref --verify --quiet refs/heads/stash-recovery-2026-05-01 \
  && git checkout stash-recovery-2026-05-01 \
  || git checkout -b stash-recovery-2026-05-01 origin/main

[✧ APPLY-3WAY]
$ git apply --3way --check $BUNDLE/diffs/034.diff
error: while searching for:
  if let Ok(payload_len) = parse_packet_header(&buf[0..4]) {
      if buf[4] == OK_BYTE {
          ...
      } else if buf[4] == ERR_BYTE {
          ...

error: patch failed: src/mysql/protocol.rs:218
error: src/mysql/protocol.rs: patch does not apply

# Conflict! Surface to user with context.

AGENT to USER:
  Apply-check failed for stash@{34} on src/mysql/protocol.rs.

  The stash modifies an `if/else if` block (lines 218–245 in the stash's
  parent commit). On main today (src/mysql/protocol.rs:218 onward), that
  block has been refactored into a `match buf[4] {}` expression.

  Hypothesis: this is a refactor (if/else if → match) that landed
  cleanly on main while the stash was sitting unmerged. The 3-way base
  has drifted ~430 lines.

  Stash's intent: cap OK-packet payload length to MAX_PAYLOAD before
  consuming it (defensive guard against malformed upstream packets).

  Proposed manual resolution: port the cap into the `match` arm for
  OK_BYTE in the new structure:

  --- src/mysql/protocol.rs (new structure) ---
  match buf[4] {
      OK_BYTE => {
          // INSERT: defensive_ok_packet_length_cap(payload_len)?;
          parse_ok_packet(payload_len, &buf[5..])
      }
      ERR_BYTE => parse_err_packet(payload_len, &buf[5..]),
      _ => Err(ProtocolError::UnknownPacketType(buf[4])),
  }

  And also add the test: tests/protocol_test.rs::test_ok_packet_length_overflow_returns_err

  OK to proceed with that resolution?

USER: yes that's right
```

The agent then applied the resolution via the Edit tool (no sed/awk):

```
[Edit tool — manual resolution preserving main's structure]
src/mysql/protocol.rs:222 — added the defensive_ok_packet_length_cap call
src/mysql/protocol.rs:108 — added the helper fn from the stash's diff
tests/protocol_test.rs — appended the test from the stash's diff

[⊕ RECOVER — run gates]
$ cargo check --workspace
   Compiling asupersync v0.1.0
   Finished in 14.2s
   ✓

$ cargo test --workspace
   Compiling ...
   running 247 tests
   test test_ok_packet_length_overflow_returns_err ... ok
   ... (all pass)
   ✓

$ cargo clippy --workspace -- -D warnings
   Finished in 8.1s
   ✓

$ cargo fmt --check
   ✓

$ ubs src/mysql/protocol.rs tests/protocol_test.rs
   No issues found.
   ✓

$ git add src/mysql/protocol.rs tests/protocol_test.rs
$ git commit -m "recover defensive MySQL OK-packet length-cap from stashed WIP

Originally drafted in stash@{34} (sha 8a3d..., dated 2026-04-29).
The fail-closed guard caps OK-packet payload length to MAX_PAYLOAD
before the consumer reads it; without the cap, a malformed packet
from an upstream proxy could trigger a panic in the framing parser.
The polished version of this stash never landed because the agent
that authored it crashed before pushing.

The original stash predated the if/else if → match refactor on
main; this commit preserves the stash's intent (the length cap and
fail-closed test) inside main's current match-expression structure.

Recovered via: git apply --3way <bundle>/diffs/034.diff (with manual
resolution for the refactor conflict)."

→ apply_log.tsv: n=34, ref=stash@{34}, new_commit_sha=def987,
  files_changed=2, gates_status=passed, duration_s=78
```

---

## Phase 7 — Partial Splits (None this run)

No `partially-novel` rows. Phase skipped cleanly.

---

## Phase 8 — Fresh Eyes

Three review prompts, each in a separate agent. Round 1: round 1 found one minor issue (the stash's helper used `u32` for length but main's MAX_PAYLOAD is `u64`; the agent fixed it to `u64`). Round 2: clean. Round 3: clean. Two consecutive clean rounds → terminate.

```
[fresh_eyes_log.md, abridged]

Round 1: 1 finding (u32→u64 type alignment); fixed; cargo test green.
Round 2: 0 substantive findings.
Round 3: 0 substantive findings.

Termination condition met (≥2 clean rounds + gates green).
```

---

## Phase 9 — Destructive Cleanup (Gated)

```
[⚠ CONFIRM]

AGENT: I'm about to run the following destructive commands in this order
(highest stash index first within each bucket, because indexes shift after
each drop). All 127 stashes will be dropped, but every one is recoverable
from refs/stash-backup/* and the bundle at
/data/projects/asupersync-stash-archive-2026-05-01/.

Bucket 1 — garbage (12):
  git stash drop stash@{82}    # full-tree-reset-stash
  git stash drop stash@{67}    # other-agent-broken
  ... (10 more) ...

Bucket 2 — autostash-recoverable-from-reflog (1):
  git stash drop stash@{107}

Bucket 3 — superseded-by-newer-stash (24):
  git stash drop stash@{124}   # superseded by stash@{34}
  ... (23 more) ...

Bucket 4 — superseded (89):
  git stash drop stash@{125}   # superseded by main:src/mutex.rs:317
  ... (88 more) ...

Bucket 5 — applied-keeper (1, dropped last):
  git stash drop stash@{34}    # already applied as commit def987

To proceed, paste this verbatim:
  yes I understand and want to drop all 127 stashes per the plan above

USER: yes I understand and want to drop all 127 stashes per the plan above
        (recorded to cleanup_authorization.txt with timestamp)

AGENT executes:
  About to run: git stash drop stash@{82}
  (n=82 in inventory.tsv: "full-tree-reset-stash", verdict garbage)
  $ git stash drop stash@{82}
  Dropped stash@{82} (e23a...)
  → cleanup_log.tsv: n=82, pre_drop_index=82, ref_dropped=...,
    verdict=garbage, timestamp_utc=2026-05-01T17:42:11Z

  About to run: git stash drop stash@{67}
  ... (continues, one per row, restating verbatim, until all 127 drops done)

Final state:
  $ git stash list | wc -l
  0

  $ ls .git/refs/stash-backup/ | wc -l
  127  # all backup refs intact

[Aside: at one point the agent considered cleaning up the bundle's working files
with `rm -rf $BUNDLE/patches/`. DCG correctly blocked it. The agent didn't
fight the block — bundle lifecycle is the user's responsibility. The .patch
files remain in place as part of the audit trail. This is the canonical
"design around the guard, don't fight it" example.]
```

---

## Phase 10 — Handoff

```
[⌘ HANDOFF — handoff_report.md]

# Stash Janitor — Handoff Report

**Project:** /data/projects/asupersync
**Run date:** 2026-05-01
**Mode:** Comprehensive
**Recovery branch:** stash-recovery-2026-05-01
**Bundle path:** /data/projects/asupersync-stash-archive-2026-05-01/

## Counts
- Initial stashes: 127
- Triaged: 127
  - novel-and-accretive: 1 (applied → 1 commit on stash-recovery-2026-05-01)
  - superseded: 89 (dropped)
  - superseded-by-newer-stash: 24 (dropped)
  - garbage: 12 (dropped)
  - autostash-recoverable-from-reflog: 1 (dropped)
  - applied-keeper: 1 (dropped after apply)
- Final stashes: 0
- Recovery commits authored: 1

## Recovered commits
| sha    | from stash | message                                                         |
|--------|------------|-----------------------------------------------------------------|
| def987 | stash@{34} | recover defensive MySQL OK-packet length-cap from stashed WIP   |

## Recovery recipes (verbatim)
If you regret any drop, every stash is recoverable:

  # By backup ref (preferred — cherry-pick lands a commit):
  git cherry-pick -m 1 refs/stash-backup/034

  # By bundle diff (when the ref is already pruned):
  git apply --3way /data/projects/asupersync-stash-archive-2026-05-01/diffs/034.diff
  # If index.tsv says has_untracked=true, also copy stashed-untracked/034/.

  # The bundle's index lists every stash:
  cat /data/projects/asupersync-stash-archive-2026-05-01/index.tsv

## Push instructions
The skill never pushes. To land the recovered work:

  git push origin stash-recovery-2026-05-01
  # then open a PR against main for review

## Bundle lifecycle
The bundle at /data/projects/asupersync-stash-archive-2026-05-01/ is yours
to manage. Keep it for at least one release cycle. Once you're sure nothing
was accidentally lost, you can `mv` it to a trash location (DCG would block
`rm -rf`).

## Beads issue
Filed: br-2071 "stash janitor pass on asupersync (127 stashes)" — links to
this report and the bundle.

USER: thanks!

[The user later pushed the recovery branch, opened a PR, merged it.
 The bundle stayed on disk for two weeks before the user deleted it
 manually. No regrets surfaced.]
```

---

## Operator usage table (this session)

| Operator | Used | Where |
|----------|------|-------|
| `★ INVENTORY` | Phase 0 (count check), Phase 2 (full inventory) |
| `✦ FINGERPRINT` | Phase 4, every stash |
| `◐ VERIFY-ON-MAIN` | Phase 4, every stash |
| `⬡ BUNDLE` | Phase 3, the irreversibility gate |
| `⚠ CONFIRM` | Phase 5 (apply gate), Phase 6 (manual resolution OK), Phase 9 (cleanup gate) |
| `✧ APPLY-3WAY` | Phase 6, stash@{34} (failed cleanly, escalated to user) |
| `⇄ SPLIT-HUNKS` | Not used (no partial-novel rows) |
| `⊕ RECOVER` | Phase 6, after the manual resolution |
| `⊙ DROP` | Phase 9, all 127 drops in highest-index-first order per bucket |
| `⌘ HANDOFF` | Phase 10 |
| `⊞ RE-FINGERPRINT` | Not needed (only one keeper applied) |
| `↺ WORKING-TREE-DRIFT` | Phase 6, before the apply (caught concurrent-agent changes; left them alone) |

---

## What this run taught us (codified in this skill)

1. **`git format-patch -1` is not the stash recovery diff.** Always use `git stash show -p --binary` for tracked/index changes and recover untracked files from `stash@{N}^3`. (See FAILURE-MODES F1.)
2. **DCG blocks `rm -rf` even on bundle subdirectories.** Design around it; the bundle is the user's to manage. (See ANTI-PATTERNS A10.)
3. **Drop highest-index-first.** Lower-index drops shift the rest. (See ANTI-PATTERNS A4 and FAILURE-MODES F3.)
4. **Same-name function on main isn't always supersession.** Verify same signature; the stash's `lock_until(Instant)` and main's `lock_until(Duration)` aren't equivalent. (See TRIAGE-RUBRIC § Same-signature verification and FAILURE-MODES F8.)
5. **3-way apply succeeds textually but can produce broken syntax** when a refactor changes structural form (`if/else if` → `match`). Re-read the file; manually port the *intent*, not the surface form, via the Edit tool. (See FAILURE-MODES F4.)
6. **Concurrent agents' working-tree changes during the run are normal.** Treat as if you made them; never disturb. (See ANTI-PATTERNS A8.)
7. **The user often doesn't know the count.** Report `git stash list | wc -l` *before* asking them to commit time to a triage. (The user thought `*127` was 127 commits.)

These lessons are now operationalized as Anti-Patterns A1–A20, Failure Modes F1–F20, and Operator Cards. Future runs benefit from this learning without rediscovering each lesson.
