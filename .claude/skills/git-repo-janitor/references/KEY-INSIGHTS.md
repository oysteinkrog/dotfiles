# Key Insights — Quote Bank

Distilled invariants from the kernel + the Apr-27 multi-repo session. These are the lines a future contributor should be able to recite from memory.

---

## On safety

> "An incorrect verdict is recoverable; an unrecorded delete is not."
> — Axiom 2

> "The recovery story has to outlive the run. If you can't undo it byte-for-byte, you can't run it."
> — ⬡ BUNDLE operator

> "Per AGENTS.md: 'When running any approved destructive command, record the exact user text that authorized it. If that record is absent, the operation did not happen.'"
> — ⚠ CONFIRM operator

> "git rm writes a deletion to git history; rm writes a regret to the future."
> — ⊟ REMOVE-WITH-RM operator

---

## On classification

> "Classification by name is gossip; classification by content is evidence."
> — 🔍 CLASSIFY-PURPOSE operator

> "A grep without context is a snitch with no follow-through; surface the line, not just the file."
> — 🔗 REFERENCE-GREP operator

> "Plan docs explain WHY; reports document WHAT happened. The first is precious; the second is usually replaceable."
> — 💎 ASSESS-VALUE operator

> "A file's importance is not visible from its name alone."
> — Axiom 11

---

## On `.gitignore`

> "An ignore rule that hides a tracked file is silent sabotage."
> — 🛡 SHADOWING-AUDIT operator

> "A `.gitignore` rule replaces a Phase 7 delete; a Phase 7 delete replaces a `.gitignore` rule. Prefer the rule when the pattern will recur."
> — 🧮 PATTERN-EXTRACT operator

> "A `.gitignore` glob can shadow tracked files."
> — Axiom 6

> "A force-add bypasses `.gitignore`. The pre-commit hook is the belt-and-suspenders."
> — A7 anti-pattern + secret-leak playbook

---

## On moves

> "A move that breaks no references is a move that wasn't really needed; the right move makes the future structure obvious."
> — 📍 LOCATE-PROPER-HOME operator

> "A reference rewrite via sed is a regex playing pretend; via the Edit tool it's a contract."
> — ↪ REWRITE-REFERENCES operator

> "git mv is a contract: 'this is the same file at a new path'. mv + git add is two separate facts that git has to guess about."
> — ✦ MOVE-WITH-RENAME operator

---

## On secrets

> "A secret in the working tree halts the cleanup and switches modes."
> — Axiom 15

> "A shallow / partial clone silently corrupts a `git filter-repo` run."
> — Axiom 16

> "Even after history rewrite, treat the secret as compromised. Forks and old clones still have it."
> — Secret-leak playbook step 11

> "`signing-*.key` was already in `.gitignore` when the file was committed; someone used `git add -f` to bypass it. So just adding more patterns isn't sufficient."
> — Apr-27 mcp_agent_mail incident

---

## On the categorical plan

> "Users skim 'B = move planning docs (16)' faster than 16 individual decisions."
> — Apr-27 frankensqlite cleanup pattern

> "When references are too pervasive (≥10 hardcoded paths), DEFER the move; better at root than half-broken."
> — The Cat-C deferral rule, frankensqlite session

---

## On gates

> "Gates between commits catch compounding errors before they compound. Gates only at the end catch them after they've made debugging hard."
> — ⊕ GATE-RUN operator

> "Per-commit gates are non-negotiable."
> — Axiom 10

---

## On concurrency

> "Concurrent agents are not adversaries; they're you with amnesia."
> — ↺ WORKING-TREE-DRIFT operator

> "Concurrent agents' working-tree changes are normal."
> — Axiom 8

---

## On the user boundary

> "The user owns deployment and bundle lifecycle."
> — Axiom 13

> "The handoff is not the end of the run; it's the start of the user's next decision."
> — ⌘ HANDOFF operator

---

## On the kernel

> "Almost every serious repo-janitor decision should be stress-tested against these axioms. They are default truths, not mindless scripts."
> — KERNEL preamble

> "When you find yourself wanting to break one, slow down and check whether you've actually identified an exception or whether the kernel is right."
> — KERNEL composition note
