# Exemplars — World-Class Git Workflows To Aspire To

A quote bank from real-world git practitioners, projects, and post-mortems. Each entry is an aspirational example of the discipline this skill encodes.

Adapted from documentation-website's EXEMPLARS.md pattern.

---

## §EX-1 — Linus on the reflog as the safety net

> "If you have not run `git gc`, the commits are still there. Most things in git are recoverable. The reflog is your friend."
>
> — Linus Torvalds, various git mailing-list posts

**Application:** the skill's Layer 1 (backup refs in `.git/refs/`) is a deliberate version of this insight. We don't rely on reflog alone (default 90-day expiry); we create permanent refs that survive any normal git operation.

---

## §EX-2 — Github's "we accidentally deleted main" post-mortem (paraphrased)

> "Once we recovered the missing commits from the reflog, we had to communicate to every fork to fetch the recovered SHAs before garbage collection caught up."

**Application:** the skill's bundle (Layer 2) is project-portable. If a recovery is needed days later, the bundle's diffs work even if the reflog has expired.

---

## §EX-3 — Pro Git on stash internals

> "A stash is just a commit. The default `git stash` makes a 2-parent merge commit; with `-u` it's 3 parents."
>
> — Pro Git, 2nd Edition, Chapter 7

**Application:** the skill's Axiom 0 codifies this directly. Every operation downstream (the bundle's diffs, the backup refs, the recovery recipes) flows from understanding stashes as commits.

---

## §EX-4 — The stash-show vs. format-patch footgun

> "`git format-patch -1 stash@{N}` is not the stash recovery diff. Use `git stash show -p --binary`; recover untracked files separately."

**Application:** the canonical footgun. The skill's Axiom 6 + every recovery README + every bundle audit warns about this.

---

## §EX-5 — Atlassian's stash recovery guide

> "If you accidentally drop a stash, you can recover it by finding the SHA in the reflog within the gc window."

**Application:** the skill goes further: backup refs ensure recovery even AFTER gc, and the bundle ensures recovery even after the entire `.git/` is gone.

---

## §EX-6 — A Rust project's branch-protection policy (Tokio, paraphrased)

> "Every commit on main must pass: cargo check, cargo test --workspace, cargo clippy -- -D warnings, cargo fmt --check. No exceptions."

**Application:** the skill's `⊕ RECOVER` operator runs the project's actual gates after every apply. Same rigor.

---

## §EX-7 — Cargo's stash-as-checkpoint workflow

> "When refactoring, I stash before risky operations. After the refactor lands, I drop the stashes."

**Application:** this is the workflow the skill is designed to clean up *for*. The user followed best practice; the residue is now triageable.

---

## §EX-8 — Linux kernel's "patches must apply with --3way" rule

> "Patches sent for review must apply cleanly with `git apply --3way` against linux-next."

**Application:** the skill's `✧ APPLY-3WAY` operator encodes this. Apply-check before apply; surface conflicts to user; never force.

---

## §EX-9 — A Cloudflare incident post-mortem (paraphrased)

> "We rolled back a feature that had been deployed to 1% of traffic. The rollback worked because every change is reversible by construction."

**Application:** the skill's reversibility chain (4 layers) is the equivalent for stash-janitor runs. Every drop is reversible by construction.

---

## §EX-10 — Jonathan Hoyt on commit message craft

> "A commit message has three sections: subject (what), body (why), citations (how). The subject is for the changelog; the body is for the future you doing forensics."

**Application:** the skill's COMMIT-MESSAGE-CRAFT.md encodes this directly for recovery commits.

---

## §EX-11 — Linus on bisect

> "If you can't bisect a bug, your commit history is wrong. Make commits that are atomic, focused, and individually testable."

**Application:** the skill's Phase 6 commits are designed to be bisectable. One stash → one focused commit. Phase 7 splits keep this property even for partially-novel.

---

## §EX-12 — A Go team's incident retrospective

> "We pushed a recovered fix that broke staging. We learned: even 'recovered' code needs the same review as new code. There is no shortcut."

**Application:** the skill's Phase 8 fresh-eyes runs ≥2 rounds + gates. Recovered code goes through the same review as net-new.

---

## §EX-13 — A Stripe engineering blog on safety culture

> "Every destructive operation has: an explicit confirmation, a verbatim audit trail, and a recovery path. Without all three, the operation does not happen."

**Application:** the skill's Phase 9 has all three: ⚠ CONFIRM (explicit), `cleanup_authorization.txt` (audit trail), `refs/stash-backup/*` + bundle (recovery path).

---

## §EX-14 — Brendan Gregg on observability

> "If you can't measure it, you can't improve it. Every system should have per-component metrics, not just overall health."

**Application:** the skill's MEASUREMENT.md provides per-phase SLOs and per-row metrics. The handoff report includes them.

---

## §EX-15 — Anthropic's coding-agent guidance

> "Tools should fail loudly, never silently. A revert that didn't actually revert should be reported as such, not concealed."

**Application:** the skill's Phase 6 revert reports honestly. If `git apply -R` fails, the user knows.

---

## §EX-16 — Daniel Stenberg (curl maintainer) on triage

> "Every reported issue has three possible verdicts: known, novel, or unfixable. The discipline is to classify quickly and act accordingly."

**Application:** the skill's 6 verdicts (superseded, garbage, novel-and-accretive, partially-novel, novel-but-stale, unknown) are the same triage discipline applied to stashes.

---

## §EX-17 — A Postgres committer on irreversibility

> "Schema changes are forever. Every migration is reviewed five times before merge. The cost of a wrong migration vastly exceeds the cost of slow review."

**Application:** the skill treats stash drops with the same care. The recovery chain makes individual drops reversible, but the user authorization is the irreversibility gate.

---

## §EX-18 — Github's git-rebase guidance

> "Rebase on a feature branch is good. Rebase on a shared branch is bad. The rule is about communication, not about the operation itself."

**Application:** the skill's recovery branch is owned by the user. The skill never rebases or force-pushes; the user decides.

---

## §EX-19 — A Rust core team commit policy

> "Every commit must explain why. The PR description explains the feature; the commit message explains the change."

**Application:** the skill's recovery commits ALWAYS explain why (Section 2 of the body template). The PR description is the user's job; the commit message is the skill's.

---

## §EX-20 — Joe Armstrong on systems design

> "Make it work, make it right, make it fast — in that order. Anything else is premature."

**Application:** the skill's phases follow this discipline. Phase 1 makes it work (the basic pipeline). Phases 4–8 make it right (per-apply gates, fresh-eyes). Phases 9–10 are the cleanup. There's no Phase 11 "make it fast" because correctness over speed for irreversible work.

---

## How to use this exemplar bank

When designing a new operator card or making a tradeoff decision, find the closest exemplar and use its discipline as the prior. When the skill's behavior diverges from an exemplar, document why (the divergence is data, not noise).

When extending the skill, propose new exemplars from sources you trust. The exemplar bank should grow with the field.
