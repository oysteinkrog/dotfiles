# Key Insights — The Quote Bank

Distilled wisdom from the asupersync run, related git-internals docs, and the broader corpus of agentic git workflows. Each entry is a quotable, transferable insight that future runs can stand on.

Following the operationalizing-expertise pattern: the goal is *quotable invariants*, not paraphrase. When a worker is unsure about an edge case, they should be able to find the relevant quote and apply it directly.

---

## §I-1 — On the bundle as the irreversibility boundary

> "The bundle is the only thing standing between the user and lost work — treat it like radiation shielding."

**Source:** OPERATOR-LIBRARY.md §⬡ BUNDLE prompt module
**Application:** Phase 3 verification is a hard gate. Don't sample — verify every entry. The cost of a per-stash byte-equality check is microseconds; the cost of a wrong bundle is irrecoverable work.

---

## §I-2 — On the canonical footgun

> "`git format-patch -1 stash@{N}` is not the stash recovery diff. Always use `git stash show -p --binary` for tracked/index changes, and recover untracked files from `stash@{N}^3`."

**Source:** asupersync session, FAILURE-MODES.md F1
**Application:** every recovery README must document this. Every triage worker that consumes the bundle's diffs must trust them — the bundle generation pipeline guarantees they came from `git stash show -p --binary`.

---

## §I-3 — On working-tree drift

> "Treat changes that appeared during the run as if you committed them yourself."

**Source:** AGENTS.md "Note for Codex/GPT-5.5"
**Application:** never stash, revert, or overwrite concurrent agents' work. If the apply conflicts with concurrent changes, surface — don't auto-resolve. The 3-way merge handles context drift; user/coordinator handles intent collision.

---

## §I-4 — On supersession evidence

> "A symbol existing on main is not proof of supersession. Verify the signature; if 30%+ diverge, flip the verdict."

**Source:** TRIAGE-RUBRIC.md § Same-signature verification
**Application:** the asupersync run's `lock_until(Instant)` vs. main's `lock_until(Duration)` is the canonical example. Same name, different semantics, NOT superseded. Sample three random introduced functions and compare param lists before classifying.

---

## §I-5 — On index drift

> "Indexes shift after every drop. Drop highest-index-first within each verdict bucket. Re-resolve before each drop."

**Source:** ANTI-PATTERNS.md A4, FAILURE-MODES.md F3
**Application:** Phase 9 cleanup_plan.tsv is built bucket-ordered, descending by `n` within each bucket. drop-confirmed.sh re-resolves the message before each drop and halts on shift.

---

## §I-6 — On the verbatim authorization

> "Without `cleanup_authorization.txt` containing the user's exact phrase, the action did not happen."

**Source:** AGENTS.md "Document the confirmation"
**Application:** "yes" is too vague. "yes I understand and want to drop all 124 stashes per the plan above" is the minimum. Re-ask if the user types something shorter.

---

## §I-7 — On phase 6 sequencing

> "Each apply changes the 3-way base for later applies. Sequential by definition. Re-fingerprint downstream candidates between applies — some flip to `superseded` after their content lands."

**Source:** OPERATOR-LIBRARY.md §⊞ RE-FINGERPRINT
**Application:** never apply two keepers that introduce the same fingerprint. The first lands; the second now sees its content on HEAD; verdict flips automatically when re-fingerprinted.

---

## §I-8 — On compounding error in recovery

> "Per-apply gates aren't paranoid. Compounding errors across recoveries are an order of magnitude harder to debug than per-keeper failures. Pay the cost upfront."

**Source:** Axiom 9, OPERATOR-LIBRARY.md §⊕ RECOVER
**Application:** test + typecheck + lint + UBS after EVERY apply. apply_log.tsv:gates_status proves it. If any gate fails, revert the apply and surface — don't proceed to the next keeper.

---

## §I-9 — On designing around DCG

> "DCG blocks `rm -rf`. The skill is designed never to need it. Bundle lifecycle is the user's responsibility."

**Source:** ANTI-PATTERNS.md A10, asupersync session
**Application:** when DCG blocks something, the skill takes that as evidence the design is correct, not as a problem to bypass. The bundle stays in place at end of run.

---

## §I-10 — On the four-layer reversibility chain

> "Backup ref + bundle diff + meta + index = four layers. The backup ref and bundle content are the restorable layers; meta and index make that recovery auditable. Both Layer 1 (refs in `.git/`) and Layer 2 (bundle on disk) must be lost for a single drop to become hard to recover."

**Source:** SAFETY-MODEL.md
**Application:** the skill never deletes both Layer 1 and Layer 2. Any operation that would touch one is independent of the other. `git stash drop` only affects the live stash log, not backup refs.

---

## §I-11 — On stash families and supersession-by-newer

> "When 5+ stashes share the same fingerprint family (e.g., `wip-BACK-1742-*`), only the most recent has any chance of being canonical. Treat the rest as `superseded-by-newer-stash`."

**Source:** STASH-SMELLS.md Smell 1, asupersync session (89 of 94 wip-BACK-* were superseded)
**Application:** before fingerprinting, group stashes by message family. Within a family, sort by date desc; only the head needs full triage. The tail get `superseded-by-newer-stash` with high confidence.

---

## §I-12 — On `git apply --3way` over `git stash apply`

> "`git stash apply` mutates state directly. On conflict, the working tree is dirty AND the stash is still in the list. `git apply --3way` operates on a verifiable diff and leaves the working tree clean on `--check` failure."

**Source:** ANTI-PATTERNS.md A2, OPERATOR-LIBRARY.md §✧ APPLY-3WAY
**Application:** never `git stash apply`/`pop`. Always `git apply --3way --check <bundle>/diffs/<n>.diff` first; only on clean check, actually apply.

---

## §I-13 — On the recovery branch as isolation

> "Keepers land on `stash-recovery-<DATE>`, not on the primary. The user reviews and merges. If every gate passed wrong, the user can explicitly decide to discard the recovery branch."

**Source:** ANTI-PATTERNS.md A12, SAFETY-MODEL.md Layer 6
**Application:** the recovery branch is the run's blast-radius limit. Never push it. Never merge it from the skill. The user owns the merge decision.

---

## §I-14 — On the sound of silence

> "If `cleanup_log.tsv` doesn't exist, no cleanup happened — regardless of what the agent said in conversation. The artifact is the source of truth."

**Source:** Polish Bar P10
**Application:** every claim in the handoff report must be backed by a workspace artifact. Counts come from .tsv files, not from agent memory. Phase 11 audits cross-check this.

---

## §I-15 — On the user's mistake (the motivating session)

> "The user thought `*127` in their zsh prompt meant 127 commits ahead of origin. It was 127 stashes. Many users genuinely don't know how many stashes they have."

**Source:** asupersync session, WORKED-EXAMPLES.md
**Application:** Phase 0 reports `git stash list | wc -l` to the user *before* asking them to commit time. The number itself is often the most important Phase 0 output.

---

## §I-16 — On verdict surfacing

> "Confidence < 0.7 forces user surface. The rubric is statistical; the user is the ground truth."

**Source:** TRIAGE-RUBRIC.md § Confidence calibration
**Application:** Phase 5 sorts within each verdict bucket by confidence ascending — the most ambiguous rows are most prominent. Users typically want to see their borderlines first.

---

## §I-17 — On the format-patch-vs-stash-show-p contract

> "The bundle's `diffs/<NNN>.diff` came from `git stash show -p --binary <index.tsv:sha>`. The bundle README says so. Anyone who builds tooling on the bundle should trust this contract."

**Source:** BUNDLE-FORMAT-SPEC.md (and OPERATOR-LIBRARY.md §⬡ BUNDLE)
**Application:** verify-bundle.sh's byte-equality check enforces the contract. Third-party tooling can rely on `git stash show -p --binary` semantics for the diffs.

---

## §I-18 — On the autostash-recoverable-from-reflog pattern

> "An autostash entry is the failed-or-abandoned half-state of a successful rebase. The reflog has the canonical outcome. Drop the autostash; cherry-pick from reflog if recovery needed."

**Source:** STASH-SMELLS.md Smell 3
**Application:** for autostash messages, run `git reflog show <branch>` looking for `rebase finished` / `rebase --autostash applied`. If present, the content is on the branch — autostash is garbage.

---

## §I-19 — On binary stashes

> "Binary fixtures don't fingerprint. Fall back to file-existence + size delta + extension heuristics. Generated artifacts (target/, dist/, *-lock.json) are always garbage; lockfiles regenerate."

**Source:** STASH-SMELLS.md Smell 12, FAILURE-MODES.md F17
**Application:** Phase 4 worker for empty fingerprint AND binary diff content → `unknown`, surface to user. Never auto-classify binary stashes as novel.

---

## §I-20 — On idempotence as a polish-bar dimension

> "Run the skill on a clean repo. It should produce zero commits and report 'nothing to do'. If it doesn't, Phase 4's logic has a bug."

**Source:** POLISH-BAR.md P8
**Application:** the smoke test verifies this. Resumption-on-empty must return `0 stashes triaged` cleanly.

---

## §I-21 — On the skill's source corpus

> "Every Anti-Pattern, Failure Mode, and Operator card in this skill traces back to a real session or a verified git-internals quirk. The kernel is empirical, not aspirational."

**Source:** WORKED-EXAMPLES.md, FAILURE-MODES.md
**Application:** when extending the skill, every new card needs a source citation. New patterns without traceable provenance are speculation, not knowledge.

---

## §I-22 — On the user-lens review

> "After a successful run, ask: 'did this save the user time, or did it just make work for them to review?' If the answer isn't clearly the former, the rubric or operator design needs adjustment."

**Source:** Phase 11 (optional) intent
**Application:** Phase 11 produces `skill_feedback.md`. Re-runs of this skill on similar projects should consume that feedback to tune the rubric, prompt modules, or default modes.

---

## §I-23 — On the difference between "the stashes are gone" and "the run succeeded"

> "Success is measured by recovered commits + verified bundle + clean handoff, not by `git stash list | wc -l == 0`. A run that drops 100 stashes without recovering the genuinely useful 1 is a failure."

**Source:** Polish Bar overall framing
**Application:** the handoff report leads with recovered commits, not with drop counts. The user should leave the run knowing what was *recovered*, not just what was deleted.

---

## §I-24 — On honest revert

> "If the apply succeeded but gates failed, attempt `git apply -R <diff>`. If revert fails, surface the dirty state honestly — don't pretend it's clean. The user knows when their tree is broken."

**Source:** apply-keeper.sh fix from fresh-eyes review
**Application:** never silently `2>/dev/null` a revert failure. The status in `apply_log.tsv` reflects reality.

---

## §I-25 — On the kernel as the audit trail

> "When you find yourself wanting to break a kernel axiom, slow down and check whether you've actually identified an exception or whether the kernel is right. The kernel was learned the hard way."

**Source:** Kernel preamble
**Application:** every exception to a kernel axiom that ships in code should be documented in FAILURE-MODES.md or ANTI-PATTERNS.md with the case study that drove it.

---

## How to use this quote bank

- When writing a new operator card, anchor it to one or more of these quotes.
- When a phase gate fails, find the relevant quote and reference it in the user-facing message.
- When a user pushes back on a polish-bar dimension, point at the quote that justifies it.
- When extending the skill, propose new quotes — they're how this skill propagates wisdom.
