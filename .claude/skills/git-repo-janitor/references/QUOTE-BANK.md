# Quote Bank

A structured corpus of distilled invariants. Each entry has a §n anchor, a quote, a source, tags, and operator anchors. Operators in OPERATOR-LIBRARY.md cite §n entries; references to "Source: §X" elsewhere in the skill point here.

This complements KEY-INSIGHTS.md (which is the punchier mantra collection); the quote bank is the structured corpus.

---

## §1. Safety and irreversibility

**§1.1** — "An incorrect verdict is recoverable; an unrecorded delete is not."
- Source: SKILL.md Axiom 2; the kernel composition rule
- Tags: safety, irreversibility, planning
- Operator anchors: ⬡ BUNDLE, ⚠ CONFIRM

**§1.2** — "The recovery story has to outlive the run."
- Source: ⬡ BUNDLE operator card; SAFETY-MODEL.md
- Tags: safety, recovery, persistence
- Operator anchors: ⬡ BUNDLE, ⌘ HANDOFF

**§1.3** — "Per AGENTS.md: 'When running any approved destructive command, record the exact user text that authorized it. If that record is absent, the operation did not happen.'"
- Source: AGENTS.md "Mandatory explicit plan"; ⚠ CONFIRM operator card
- Tags: authorization, audit, AGENTS.md
- Operator anchors: ⚠ CONFIRM

**§1.4** — "git rm writes a deletion to git history; rm writes a regret to the future."
- Source: ⊟ REMOVE-WITH-RM operator card
- Tags: git-craft, deletion
- Operator anchors: ⊟ REMOVE-WITH-RM

**§1.5** — "git mv is a contract: 'this is the same file at a new path'. mv + git add is two separate facts that git has to guess about."
- Source: ✦ MOVE-WITH-RENAME operator card
- Tags: git-craft, moves, rename detection
- Operator anchors: ✦ MOVE-WITH-RENAME

**§1.6** — "A reference rewrite via sed is a regex playing pretend; via the Edit tool it's a contract."
- Source: ↪ REWRITE-REFERENCES operator card; AGENTS.md "No Script-Based Changes"
- Tags: refactor, scripts, AGENTS.md, anti-pattern
- Operator anchors: ↪ REWRITE-REFERENCES

---

## §2. Classification and triage

**§2.1** — "Classification by name is gossip; classification by content is evidence."
- Source: 🔍 CLASSIFY-PURPOSE operator card
- Tags: triage, classification
- Operator anchors: 🔍 CLASSIFY-PURPOSE

**§2.2** — "A grep without context is a snitch with no follow-through; surface the line, not just the file."
- Source: 🔗 REFERENCE-GREP operator card
- Tags: triage, evidence
- Operator anchors: 🔗 REFERENCE-GREP, ⌖ FALSE-POSITIVE-CHECK

**§2.3** — "Plan docs explain WHY; reports document WHAT happened. The first is precious; the second is usually replaceable."
- Source: 💎 ASSESS-VALUE operator card
- Tags: triage, value-assessment
- Operator anchors: 💎 ASSESS-VALUE

**§2.4** — "A file's importance is not visible from its name alone."
- Source: SKILL.md Axiom 11
- Tags: triage, false-positive, kernel
- Operator anchors: 🔍 CLASSIFY-PURPOSE, 🔗 REFERENCE-GREP, ⌖ FALSE-POSITIVE-CHECK

**§2.5** — "A move that breaks no references is a move that wasn't really needed; the right move makes the future structure obvious."
- Source: 📍 LOCATE-PROPER-HOME operator card
- Tags: structure, moves
- Operator anchors: 📍 LOCATE-PROPER-HOME

**§2.6** — "When references are too pervasive (≥10 hardcoded paths), DEFER the move; better at root than half-broken."
- Source: WORKED-EXAMPLES.md § frankensqlite Cat-C deferral
- Tags: deferral, monorepo, planning
- Operator anchors: 📍 LOCATE-PROPER-HOME, ⊠ NEGATIVE-DECISION

---

## §3. `.gitignore` and shadowing

**§3.1** — "An ignore rule that hides a tracked file is silent sabotage."
- Source: 🛡 SHADOWING-AUDIT operator card
- Tags: gitignore, anti-pattern
- Operator anchors: 🛡 SHADOWING-AUDIT

**§3.2** — "A `.gitignore` rule replaces a Phase 7 delete; a Phase 7 delete replaces a `.gitignore` rule. Prefer the rule when the pattern will recur."
- Source: 🧮 PATTERN-EXTRACT operator card
- Tags: gitignore, pattern-extraction
- Operator anchors: 🧮 PATTERN-EXTRACT

**§3.3** — "A `.gitignore` glob can shadow tracked files."
- Source: SKILL.md Axiom 6
- Tags: gitignore, kernel
- Operator anchors: 🛡 SHADOWING-AUDIT

**§3.4** — "A force-add bypasses `.gitignore`. The pre-commit hook is the belt-and-suspenders."
- Source: ANTI-PATTERNS.md A7; INCIDENT-PLAYBOOK.md § Step 7
- Tags: gitignore, secrets, anti-pattern
- Operator anchors: ⩚ VULNERABLE-FILE-FILTER

**§3.5** — "`.gitignore` only affects untracked files. Adding `*.bak` does NOT untrack already-tracked `*.bak` files. They keep accumulating commits silently."
- Source: SKILL.md Top-5-Mistakes #2; GITIGNORE-CRAFT.md
- Tags: gitignore, semantics
- Operator anchors: 🛡 SHADOWING-AUDIT

---

## §4. Secrets and high-stakes operations

**§4.1** — "A secret in the working tree halts the cleanup and switches modes."
- Source: SKILL.md Axiom 15
- Tags: secrets, kernel, halt
- Operator anchors: ⩚ VULNERABLE-FILE-FILTER

**§4.2** — "A shallow / partial clone silently corrupts a `git filter-repo` run."
- Source: SKILL.md Axiom 16
- Tags: secrets, filter-repo, gotcha
- Operator anchors: ◑ VERIFY-LIVE

**§4.3** — "Even after history rewrite, treat the secret as compromised. Forks and old clones still have it."
- Source: INCIDENT-PLAYBOOK.md Step 11
- Tags: secrets, mitigation
- Operator anchors: ⌘ HANDOFF

**§4.4** — "`signing-*.key` was already in `.gitignore` when the file was committed; someone used `git add -f` to bypass it. So just adding more patterns isn't sufficient."
- Source: INCIDENT-PLAYBOOK.md § mcp_agent_mail Apr-27 incident
- Tags: secrets, force-add, gitignore-bypass
- Operator anchors: ⩚ VULNERABLE-FILE-FILTER, 🛡 SHADOWING-AUDIT

---

## §5. Categorical plan and user gating

**§5.1** — "Users skim 'B = move planning docs (16)' faster than 16 individual decisions."
- Source: WORKED-EXAMPLES.md § Apr-27 frankensqlite
- Tags: UX, plan-presentation
- Operator anchors: 🧮 PATTERN-EXTRACT, ⌘ HANDOFF

**§5.2** — "The handoff is not the end of the run; it's the start of the user's next decision."
- Source: ⌘ HANDOFF operator card
- Tags: handoff, mode-chaining
- Operator anchors: ⌘ HANDOFF

**§5.3** — "Mode handoffs are explicit; mode escalation is a recorded decision, not a drift."
- Source: SKILL.md Axiom 21; OPERATING-MODES.md
- Tags: modes, escalation
- Operator anchors: ⌘ HANDOFF

**§5.4** — "Drift between modes is the most common way users lose context."
- Source: OPERATING-MODES.md § Mode-handoff template
- Tags: modes, UX
- Operator anchors: ⌘ HANDOFF

---

## §6. Concurrency and multi-agent realities

**§6.1** — "Concurrent agents are not adversaries; they're you with amnesia."
- Source: ↺ WORKING-TREE-DRIFT operator card
- Tags: concurrency, AGENTS.md
- Operator anchors: ↺ WORKING-TREE-DRIFT

**§6.2** — "Concurrent agents' working-tree changes are normal."
- Source: SKILL.md Axiom 8; AGENTS.md "Note for Codex/GPT-5.5"
- Tags: concurrency, kernel, AGENTS.md
- Operator anchors: ↺ WORKING-TREE-DRIFT

**§6.3** — "On a multi-agent VPS, a multi-repo run will dirty repos faster than a single agent can commit them. The orchestrator must do multiple commit rounds, not one."
- Source: BATCH-MODE.md § wisdom from cass session B
- Tags: concurrency, multi-repo, batch
- Operator anchors: 📦 BATCH-ORCHESTRATE

---

## §7. Verification and confidence

**§7.1** — "Volatile git behavior must be verified live, not assumed."
- Source: SKILL.md Axiom 17
- Tags: verification, kernel
- Operator anchors: ◑ VERIFY-LIVE

**§7.2** — "Coverage matrices reveal what the agent didn't consider."
- Source: SKILL.md Axiom 18
- Tags: coverage, audit, kernel
- Operator anchors: ⊞ COVERAGE-MATRIX

**§7.3** — "A blank cell is a bug, not a default."
- Source: COVERAGE-MATRIX.md
- Tags: coverage, audit
- Operator anchors: ⊞ COVERAGE-MATRIX

**§7.4** — "Confidence is per-recommendation, computed from four dimensions, lowest-dimension caps."
- Source: SKILL.md Axiom 19; CONFIDENCE-SCORING.md
- Tags: confidence, scoring
- Operator anchors: (rubric, not an operator)

**§7.5** — "If you can't carry an evidence envelope, halt instead of fabricating."
- Source: VERIFICATION-FIRST.md § Evidence envelope template
- Tags: verification, integrity
- Operator anchors: ◑ VERIFY-LIVE

---

## §8. Per-commit gates and per-batch rhythm

**§8.1** — "Gates between commits catch compounding errors before they compound. Gates only at the end catch them after they've made debugging hard."
- Source: ⊕ GATE-RUN operator card
- Tags: gates, quality
- Operator anchors: ⊕ GATE-RUN

**§8.2** — "Per-commit gates are non-negotiable."
- Source: SKILL.md Axiom 10
- Tags: gates, kernel
- Operator anchors: ⊕ GATE-RUN

**§8.3** — "First pass misses ~10–15% of references; second pass catches them."
- Source: WORKED-EXAMPLES.md § Apr-27 frankensqlite ref-rewrite lesson
- Tags: refactor, refs, real-world
- Operator anchors: 🔗 REFERENCE-GREP, ↪ REWRITE-REFERENCES, ⊞ COVERAGE-MATRIX

---

## §9. The user boundary

**§9.1** — "The user owns deployment and bundle lifecycle."
- Source: SKILL.md Axiom 13; SAFETY-MODEL.md
- Tags: boundary, kernel
- Operator anchors: ⌘ HANDOFF

**§9.2** — "The skill never pushes the recovery branch; the user pushes."
- Source: ANTI-PATTERNS.md A9
- Tags: boundary, anti-pattern
- Operator anchors: ⌘ HANDOFF

**§9.3** — "The skill never deletes the bundle; the user manages bundle lifecycle."
- Source: SAFETY-MODEL.md § Layer 2
- Tags: boundary, recovery
- Operator anchors: ⌘ HANDOFF

**§9.4** — "Verbatim authorization is per-plan, not per-action."
- Source: SKILL.md Axiom 9
- Tags: authorization, AGENTS.md
- Operator anchors: ⚠ CONFIRM

---

## §10. Phantom deletions and accidental destructions

**§10.1** — "A phantom-deletion is a restoration request, not a commit-me-up request."
- Source: SKILL.md Axiom 24
- Tags: phantom-deletion, restoration, real-world
- Operator anchors: ⌖ FALSE-POSITIVE-CHECK

**§10.2** — "Naïve 'stage everything modified' would have committed 1,527 deletions of files the user actually wanted to keep."
- Source: WORKED-EXAMPLES.md § frankenterm phantom-deletion incident
- Tags: phantom-deletion, real-world, anti-pattern
- Operator anchors: ⌖ FALSE-POSITIVE-CHECK

---

## §11. Disk pressure and operational realities

**§11.1** — "Before any large cleanup, check `df -h` on `/`, `/tmp`, `/var/tmp`, `~/.cargo`, `~/.cache`. The 49 GB `/tmp/rch/frankenterm` cache nearly broke a 13-repo run."
- Source: BATCH-MODE.md § disk-pressure pre-flight; cass session B finding
- Tags: pre-flight, disk-pressure
- Operator anchors: (pre-flight check, not an operator)

**§11.2** — "The bundle of a 100k-file repo can be GB. Plan for it."
- Source: TIER-TRIAGE.md § T5
- Tags: scalability, bundle
- Operator anchors: ⬡ BUNDLE

---

## §12. Multi-repo orchestration

**§12.1** — "Multi-repo runs are skip-list-first, not allow-list-first."
- Source: SKILL.md Axiom 23; BATCH-MODE.md
- Tags: batch, multi-repo, kernel
- Operator anchors: 📦 BATCH-ORCHESTRATE

**§12.2** — "Push two refs per repo, sometimes. `git push origin main && git push origin main:master` is the policy for the main:master mirror set. The skill must fail loudly when a repo is in the mirror set and only one push succeeded."
- Source: BATCH-MODE.md § branch-policy registry; cass session B finding
- Tags: branch-policy, push, mirror
- Operator anchors: ⌘ HANDOFF

**§12.3** — "Use `--force-with-lease`, never `--force`."
- Source: BATCH-MODE.md § force-push policy; INCIDENT-PLAYBOOK.md § Secret Leak
- Tags: force-push, safety
- Operator anchors: (operational rule)

---

## §13. Integrity and provenance

**§13.1** — "Provenance is an artifact-level invariant."
- Source: SKILL.md Axiom 22
- Tags: provenance, kernel, audit
- Operator anchors: ⊙ PROVENANCE-WRAP

**§13.2** — "Every artifact in `.repo_janitor_workspace/` opens with `produced_at | produced_by | source_phase | confidence | inputs_hash`."
- Source: SOURCE-COVERAGE-MAP.md; ⊙ PROVENANCE-WRAP operator card
- Tags: provenance, header, format
- Operator anchors: ⊙ PROVENANCE-WRAP

---

## §14. Resumability and idempotence

**§14.1** — "A clean run produces the same artifacts as a busy run, just with empty bodies."
- Source: SKILL.md Axiom 20
- Tags: idempotence, kernel
- Operator anchors: (re-entry pattern)

**§14.2** — "Re-running on a freshly-cleaned repo produces no commits and reports 'nothing to do'."
- Source: SKILL.md Polish-Bar Dimension 10
- Tags: idempotence, polish-bar
- Operator anchors: (polish-bar)

**§14.3** — "Every phase writes its artifacts before exiting. On re-entry, the skill can resume."
- Source: PHASES.md § Idempotence & Resumability; RESUMABILITY.md
- Tags: resumability, format
- Operator anchors: (re-entry pattern)

---

## §15. The kernel itself

**§15.1** — "Almost every serious repo-janitor decision should be stress-tested against these axioms. They are default truths, not mindless scripts."
- Source: SKILL.md KERNEL preamble
- Tags: kernel, framing
- Operator anchors: (entire kernel)

**§15.2** — "When you find yourself wanting to break one, slow down and check whether you've actually identified an exception or whether the kernel is right."
- Source: SKILL.md KERNEL composition note
- Tags: kernel, discipline
- Operator anchors: (entire kernel)

**§15.3** — "These 25 axioms (numbered 0 through 24) compose."
- Source: SKILL.md (post-kernel composition section)
- Tags: kernel, composition
- Operator anchors: (composition matrix)

---

## How operators cite the bank

In OPERATOR-LIBRARY.md, each operator's quote-bank line should reference §n entries:

```markdown
**Quote bank:** §1.4 (git rm vs rm), §1.5 (git mv contract), §3.5 (gitignore semantics)
```

When extending the skill (adding a new pattern), the maintainer cites the new §n.# entries in the operator card.

---

## Adding to the bank

When a new lesson is captured (e.g., a new failure mode discovered in a real run):

1. Pick a section (§1-§15) that fits or create a new §N.
2. Pick the next free .M number in that section.
3. Add the entry with quote, source, tags, operator anchors.
4. Update operator cards that should cite it.
5. Update SKILL.md's Source Corpus table.

Every new pattern should pass through the quote bank — that's how provenance is maintained.

---

## When entries become stale

If a quote refers to a tool/version/practice that has changed:

- Mark it with `[STALE — see updated §N.M]` and add a new entry.
- Don't delete the original (it's a record of the historical truth).
- Update operator cards to cite the new entry.

This preserves the audit trail of how the skill evolved.
