# Interview Flow

Adaptive intake instead of a single-shot questionnaire. The skill asks 1–2 questions at a time, branches based on answers, and converges quickly to a runnable scope decision.

Source: wills-and-estate-planning's `INTERVIEW-FLOW.md` pattern.

---

## Why adaptive

A 12-question intake form forces the user to answer "is this a polyglot monorepo" before they know what the skill will do. By contrast, an adaptive interview:
- Starts with the most-decisive question
- Branches based on the answer
- Asks only what's needed for the chosen path
- Converges in 3–5 questions for typical cases

The result: a faster intake AND better decisions because the user isn't fatigued by irrelevant questions.

---

## Stage 1 — Orient

The first question always:

> **Why are you running cleanup now?**
>
> a) An agent left junk files in this repo (typical post-swarm cleanup)
> b) I'm publishing this repo and want it clean for a public audience
> c) I'm merging two repos and want to consolidate
> d) Routine maintenance / quarterly review
> e) I just discovered committed secrets / want a security pass
> f) Other (describe)

The answer routes to a different second-stage path:

| Answer | Likely mode | First branch |
|--------|-------------|--------------|
| a) Agent swarm aftermath | `full` (typical) | Stage 2A: candidate count |
| b) Publishing | `full` + emphasize secret-scan + readability | Stage 2B: target audience |
| c) Repo merging | usually NOT this skill | Suggest manual `git mv` + ref-rewrite first |
| d) Routine maintenance | `maintenance-review` | Stage 2D: time since last cleanup |
| e) Security pass | `harden-secret-leak` from the start | Stage 2E: known leak or audit? |
| f) Other | `triage-only` first | Stage 2F: free-form description |

---

## Stage 2 — Scope

Branched by Stage 1 answer.

### 2A — Candidate count (after "agent swarm aftermath")

```bash
# Skill runs scripts/inventory-candidates.sh --preview to get a count
N=$(scripts/inventory-candidates.sh "$project" --preview | wc -l)
```

Then asks:

> Found `<N>` candidate files matching at least one junk-smell rule.
>
> a) Looks right; proceed
> b) Looks low; expand the scan to non-toplevel subdirs
> c) Looks high; let me see a sample first

If `b`: expand inventory to walk subdirs more deeply. Re-count.
If `c`: emit `candidates_grouped.md` and let user review before continuing.

### 2B — Target audience (after "publishing")

> Who's the audience for this repo once it's public?
>
> a) Other developers (open-source library, tool, or example)
> b) Researchers (academic / scientific code)
> c) Business stakeholders (demos, marketing artifacts)
> d) Mixed

Affects Phase 5 categorization:
- `a`: emphasize moving plan-docs to `docs/planning/` (developers expect this)
- `b`: emphasize artifact reproducibility (don't delete benchmark snapshots)
- `c`: emphasize visual polish (logo files, screenshots) at root vs. in `assets/`

### 2D — Time since last cleanup (after "routine maintenance")

> When was the last `repo-janitor` cleanup on this repo?
>
> a) Never (this is the first)
> b) Within the last week
> c) 1 week to 1 month ago
> d) >1 month ago / can't recall

If `a`: switch mode to `full` (this is the first run; inheritance doesn't apply).
If `b`/`c`: drift since last run is small; `maintenance-review` mode runs the smell scan and reports drift.
If `d`: drift may be large; consider `full` mode after `triage-only` confirms.

### 2E — Known leak vs. audit (after "security pass")

> Do you know there's a leaked secret, or do you want a sweep?
>
> a) I know about a specific leak and need to remediate
> b) I don't know of any leak; want to audit
> c) An audit told me there's a leak; need details

If `a`: skip directly to `harden-secret-leak` mode; ask for the specific path.
If `b`: run Phase 0/1/2/2.5 only first; if Phase 2.5 finds nothing, terminate with "no leaks found." If Phase 2.5 finds something, escalate.
If `c`: ask for the audit's findings; correlate with Phase 2.5; choose mode.

### 2F — Free-form (after "other")

The user describes their goal in free-form. The skill summarizes back its understanding and asks for confirmation before proceeding. If the goal is clearly outside the skill's scope (e.g., "I want to do a security review of network code"), the skill suggests a different skill (`security-audit-for-saas`, `multi-pass-bug-hunting`).

---

## Stage 3 — Archetype confirmation

Always (regardless of Stage 1 answer).

The skill auto-detected an archetype via `discover-project.sh`:

> Detected archetype: `<archetype>` (e.g., `polyglot-monorepo` with Rust + TypeScript subtrees).
>
> a) Looks right
> b) Wrong — let me pick from the list
> c) Wrong — describe how

If `a`: proceed.
If `b`: present the archetype list (single-rust-crate, polyglot-monorepo, claude-skill-repo, nextjs-saas, python-package, go-cli, mixed-rust-and-frontend, unknown). User picks.
If `c`: free-form. The skill drafts a new entry in REPO-ARCHETYPES.md (not yet committed) and asks the user to validate.

---

## Stage 4 — Protected globs review

> Auto-derived protected_globs (the skill will NEVER touch these): <list>.
>
> Anything to add? You can add but not remove the archetype defaults.

User can add. Skill records additions in `phase0_scope_decision.md` under "user-supplied protected_globs."

---

## Stage 5 — Reference-rewrite policy

> When I move planning docs etc., I'll need to update references in code. How aggressive should I be?
>
> a) auto-rewrite-with-confirmation (default): I edit each ref via the Edit tool, surface for confirmation
> b) surface-only: I list each ref; you do the rewrites manually
> c) auto-rewrite-trusted-formats: markdown links and YAML/TOML auto, code imports surface

Defaults to `a`. Captures in `project_profile.json`.

---

## Stage 6 — Quality gates confirmation

> I'll run these gates after every commit:
> - test: `<test_command>`
> - typecheck: `<typecheck_command>`
> - lint: `<lint_command>`
> - build: `<build_command>`
>
> Any adjustments? (e.g., "skip the build, it's slow" or "use cargo nextest instead of cargo test")

Captures in `project_profile.json`.

---

## Stage 7 — Concurrent agent check

> Are other agents working in this repo right now?
>
> a) No
> b) Yes, but I want to proceed (skill will use Agent Mail file reservations)
> c) Yes, let me pause them first

If `b`: install advisory file reservations.
If `c`: skill halts; user pauses; user resumes when ready.

---

## Stage 8 — Final confirmation

The skill summarizes:

```
Plan summary:
- Mode: <mode> (per Stage 1)
- Tier: T<N> (per file count) + <M> complexity points (per overlay)
- Archetype: <archetype> (per Stage 3)
- Protected globs: <count>
- Reference policy: <policy>
- Quality gates: <count>
- Concurrent-agent handling: <reservation policy>
- Estimated scope: <wall-time> for ~<candidate-count> candidates
- Recovery branch: repo-janitor-<DATE>
- Bundle path: <bundle-path>
- Required user gates: <count> (Phase 5 plan, Phase 7 deletes, Phase 8 gitignore)

Type "go" to proceed, or describe any adjustment.
```

User says go; skill starts Phase 1.

---

## Branching efficiency

For typical "agent swarm aftermath" runs, the interview is:
- Stage 1 (a) → Stage 2A (a) → Stage 3 (a) → Stage 4 (no additions) → Stage 5 (a) → Stage 6 (no adjust) → Stage 7 (a) → Stage 8 (go)

= 8 questions, but most are simple yes/confirm. ~2 minutes typical.

For "security pass with known leak":
- Stage 1 (e) → Stage 2E (a, with path provided) → Stage 8 (go)

= 3 questions. ~30 seconds.

For "publishing" (more nuance):
- Stage 1 (b) → Stage 2B (a) → Stage 3 (b, pick from list) → Stage 4 (add some) → Stage 5 (a) → Stage 6 (no adjust) → Stage 7 (a) → Stage 8 (go)

= 8 questions, but with more careful answers. ~5 minutes.

---

## Interview state

The interview's state lives in `<workspace>/interview_log.md`:

```markdown
## Interview log — repo-janitor-2026-05-08

**Stage 1:** Why running now? → "(a) Agent swarm aftermath"
**Stage 2A:** Candidate count? → "Looks right; proceed" (87 candidates)
**Stage 3:** Archetype? → "Looks right; polyglot-monorepo"
**Stage 4:** Add protected globs? → "Add `data/seed.db` (hand-curated fixture)"
**Stage 5:** Reference policy? → "auto-rewrite-with-confirmation"
**Stage 6:** Quality gates? → "Use `cargo nextest` instead of `cargo test`"
**Stage 7:** Concurrent agents? → "No"
**Stage 8:** Confirm? → "go"

**Total intake time:** 4 minutes
```

The log preserves user intent for future maintenance reviews.

---

## When the interview is wrong

If the user's answer at any stage doesn't match a branch, the skill:
1. Asks a clarifying question
2. If still ambiguous, falls back to free-form (Stage 2F equivalent)
3. If the skill genuinely can't determine the path, halts and asks the user to describe what they want

The interview is heuristic; it's not a contract.

---

## Resume after interruption

If the interview is interrupted:
- `interview_log.md` records what's been answered
- On resume, the skill says "we got to Stage <N>; continue from there?"
- User confirms; skill resumes from the next stage

---

## Multi-repo batch interview

For batch mode, Stage 1 has an additional answer:

> g) Multi-repo: I want to clean N repos in one orchestration

If `g`, skip Stages 2-7 per-repo; instead ask:
- Which repos? (skip-list-first; explicit include list)
- Default mode for each?
- Any per-repo overrides?

The batch interview converges in 2-3 questions and then runs the per-repo interviews ASYNCHRONOUSLY (in parallel where possible) for each included repo.

---

## Why this matters

A user-facing checklist that ASKS the right next question (not just "fill in 12 fields") feels much more like a senior engineer triaging the cleanup than a tax form. The wills-and-estate-planning-skill proved this in a much higher-stakes domain; we adopt the same pattern here.
