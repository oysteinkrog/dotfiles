---
name: mock-code-finder
description: >-
  Find stubs, mocks, placeholders, TODOs, and fake code in a project. Use when "find mocks",
  "find stubs", "find placeholders", "check for fake code", or auditing for incomplete code.
---

<!-- TOC: Problem | THE EXACT PROMPTS | Quick Start | Detection Methods | Beads vs TODO | Compilation | Resolution | Checklist | References -->

# Mock Code Finder

> **Core Insight:** Long-running multi-agent projects accumulate stubs, mocks, placeholders, and TODO code that silently degrades the codebase. Systematic multi-method detection finds what grep alone misses.

## The Problem

Unless you've specifically looked for them, chances are that you've accumulated various forms of "mocks" or fake placeholder code somewhere in your project. Single-keyword grep misses structural stubs (short functions that do nothing substantive). AST analysis alone misses TODO comments. You need both, plus heuristics.

---

## THE EXACT PROMPTS

### Phase 1: Discovery

```
First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code and technical architecture and purpose of the project.

Then, I need you to search every last INCH of this ENTIRE repo, looking intelligently for ANY signs or indicators that functions, methods, classes, etc. are "stubs" or "mocks" or "placeholders" or "TODO" or otherwise rather than 100% real, working, fully-functioning code.

You can apply a variety of methods for checking for this, but it's imperative that you not miss ANY instances of this sort of thing. One clever way might be to use ast-grep to find and measure the length of any functions/methods/classes/etc. in terms of lines, characters, etc. to look for things that look suspicious because they appear to be too short to do anything substantive.

First compile the comprehensive listing of all such placeholders/mocks/stubs and a short explanation or justification for why you're convinced they qualify as incomplete/placeholders that must be completed. Once we have this table of suspects, we can then decide how to address and resolve them all in a totally comprehensive, optimal, clever way.
```

### Phase 2a: Resolution (Short List — ~4 items or fewer)

```
OK good, now I need you to come up with an absolutely comprehensive, detailed, and granular plan for addressing each and every single one of those placeholders/mocks/stubs that you identified in the most optimal and clever and sophisticated way possible. THEN: please resolve ALL of those actionable items now. Keep a super detailed, granular, and complete TODO list of all items so you don't lose track of anything and remember to complete all the tasks and sub-tasks you identified or which you think of during the course of your work on these items!
```

### Phase 2b: Resolution (Long List — 5+ items, project uses beads)

```
OK good, now I need you to come up with an absolutely comprehensive, detailed, and granular plan for addressing each and every single one of those placeholders/mocks/stubs that you identified in the most optimal and clever and sophisticated way possible.

THEN: please take ALL of that and elaborate on it and use it to create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.) The beads should be so detailed that we never need to consult back to the original markdown plan document. Remember to ONLY use the `br` tool to create and modify the beads and add the dependencies.
```

### Phase 3: Bead Refinement (iterate 2-3 times)

```
Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Make sure to ONLY use the `br` cli tool for all changes, and you can and should also use the `bv` tool to help diagnose potential problems with the beads.
```

---

## Quick Start

### Step 0: Detect Project Tooling

```bash
# Check for beads
if [ -d ".beads" ] && command -v br &>/dev/null; then
  echo "BEADS_AVAILABLE=true"  # Use Phase 2b workflow
else
  echo "BEADS_AVAILABLE=false" # Use Phase 2a workflow
fi
```

### Step 1: Understand the Project

```bash
cat AGENTS.md README.md   # DOCUMENTATION FIRST — always!
```

Then use Explore agent for full architecture understanding.

### Step 2: Multi-Method Scan

Run all detection methods in parallel (see [DETECTION-METHODS.md](references/DETECTION-METHODS.md)):

```bash
# Text-based detection (ripgrep)
rg -n "TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER|MOCK|DUMMY|FAKE|TEMP|TEMPORARY" \
  --type-not json --type-not lock -g '!target/' -g '!node_modules/' -g '!.git/' .

rg -n "unimplemented!|todo!|panic!\(\"not implemented|NotImplementedError|raise NotImplementedError" .

rg -n "pass$|return None$|return \{\}$|return \[\]$|return \"\"$|return 0$" \
  --type py --type rust --type ts --type js .

# Structural detection (ast-grep) — find suspiciously short functions
ast-grep run -l Rust -p 'fn $NAME($$$) { $SINGLE_STMT }' --json 2>/dev/null
ast-grep run -l Rust -p 'fn $NAME($$$) -> $RET { todo!() }' --json 2>/dev/null
ast-grep run -l Python -p 'def $NAME($$$):
    pass' --json 2>/dev/null
ast-grep run -l TypeScript -p 'function $NAME($$$) { return; }' --json 2>/dev/null
```

### Step 2.5: Behavioral Detection (Learned From Real Sessions)

Beyond keywords and AST, look for **simulated behavior** patterns:

```bash
# Fake work: sleep() used to simulate real operations
rg -n "sleep\(|thread::sleep|time\.sleep|setTimeout.*simul|fake.*delay" \
  --type rust --type py --type ts --type go .

# Hardcoded scores/metrics (should be computed from data)
rg -n "score\s*=\s*[0-9]|rarity.*=\s*[0-9]|count.*=\s*0[^.]" \
  --type rust --type py --type ts .

# Returns 501 Not Implemented (API route stubs)
rg -n "501|Not Implemented|not.yet.implemented" \
  --type ts --type py --type rust .

# Functions that always return the same thing regardless of input
# (trace callers to confirm — if callers depend on real output, it's a stub)
rg -n "fn.*->.*bool.*\{.*true.*\}|fn.*->.*bool.*\{.*false.*\}" --type rust .
```

### Step 2.6: Cross-Reference and Caller Tracing (Critical!)

For each suspect, **trace callers to understand impact**:

```bash
# Find who calls a suspect function
rg -n "function_name\(" --type rust --type ts --type py .

# Check if the stub's callers depend on real output
# Example: batch-enrichment.ts returned `redFlagsDetected: 0` but the
# API route that called it actually counted them — divergent code paths
```

### Step 3: Compile Findings Table

Add a **"Real Blocker?"** column to triage what's fixable now vs blocked:

```markdown
| # | File:Line | Type | Code Snippet | Why It's Suspicious | Real Blocker? |
|---|-----------|------|-------------|---------------------|---------------|
| 1 | src/foo.rs:42 | stub | `fn process() { todo!() }` | Explicit todo! macro | No — just needs implementation |
| 2 | src/bar.rs:100 | placeholder | `fn validate() -> bool { true }` | Always returns true | No — needs real validation logic |
| 3 | lib/baz.py:55 | mock | `def fetch_data(): return {}` | Returns empty dict | Yes — needs API credentials |
| 4 | src/metrics.rs:100 | hardcoded | `dau_count = 0` | Always 0, no real tracking | Yes — needs analytics pipeline |
```

**Categorize each finding as one of:**
- **Just needs code** — No external dependency, can implement now
- **Blocked on infra** — Needs DB schema, API keys, external service (document the blocker)
- **Dead code** — No callers, stub is unreachable (candidate for deletion)
- **Intentional stub** — Abstract base / trait impl / protocol method (false positive, skip)

### Step 3.5: Check Existing Beads (Avoid Duplicate Work)

If the project uses beads, check what's already tracked:

```bash
br list --status=open 2>/dev/null | grep -i "stub\|mock\|placeholder\|todo\|implement"
```

Only create new beads for findings not already tracked.

### Step 4: Resolve (Branch by Tooling)

- **Beads available + 5+ items** → Phase 2b: Create beads with `br`, refine with `bv`
- **No beads or <5 items** → Phase 2a: Plan and resolve with TODO tracking

---

## Detection Methods Summary

| Method | Tool | Catches | Misses |
|--------|------|---------|--------|
| Keyword search | `rg` | TODOs, FIXMEs, explicit stubs | Unlabeled short functions |
| Return value analysis | `rg` | Hardcoded returns, empty returns | Complex fake implementations |
| AST short-function scan | `ast-grep` | Suspiciously tiny functions/methods | Stubs with boilerplate padding |
| Unimplemented macro scan | `rg` + `ast-grep` | `todo!()`, `unimplemented!()`, `NotImplementedError` | Custom placeholder patterns |
| Empty body detection | `ast-grep` | `pass`, `{}`, empty impls | Functions with only logging |
| Cross-reference analysis | `rg` | Functions never called from tests | Well-tested stubs |
| Simulated work detection | `rg` | `sleep()` as fake I/O, simulated ops | Well-disguised simulations |
| Hardcoded score/metric scan | `rg` | `score=3`, `dau=0`, `count=0` | Intentional defaults |
| API route stub scan | `rg` | 501 responses, "Not Implemented" | Routes with partial logic |
| Divergent path detection | `rg` | Same concept, different impl in two files | Intentionally separate paths |
| Stub test detection | `rg -c` | Test files with <5 assertions | Tests with many but shallow assertions |

**Full detection patterns by language:** [DETECTION-METHODS.md](references/DETECTION-METHODS.md)

---

## Beads Workflow (When Available)

When the project has `.beads/` and `br` CLI:

1. **Create parent epic:** `br create --title="Resolve all mocks/stubs/placeholders" --type=epic --priority=1`
2. **Create child tasks:** One bead per stub/mock, with detailed comments including:
   - What the stub currently does
   - What it should do (the real implementation)
   - Which files need changing
   - What tests to add
   - Dependencies on other stubs (if resolving one requires another)
3. **Add dependencies:** `br dep add <child> <depends-on>` for implementation ordering
4. **Refine with bv:** `bv --robot-triage` to validate dependency graph, find quick wins
5. **Iterate in plan space:** Review and refine beads 2-3 times before implementing
6. **Include test beads:** Every stub resolution bead should have a companion test bead

---

## Lessons From Real Sessions

Patterns discovered across 7+ repos (midas-edge, frankensearch, mcp-agent-mail-rust, rch, ntm, flywheel-connectors, jeffreysprompts):

| Lesson | Context |
|--------|---------|
| **Caller tracing finds divergent code** | midas-edge: `batch-enrichment.ts` returned `redFlagsDetected: 0` but the API route that consumed it actually counted red flags — two code paths diverged |
| **`sleep()` = fake work** | rch: `run_preflight()` used `sleep()` to simulate SSH operations instead of real SSH commands |
| **Hardcoded scores are stubs too** | midas-edge: `rarityScore = 3` hardcoded instead of computed from historical data |
| **Check existing beads first** | frankensearch, mcp-agent-mail: always run `br list --status=open` before creating new beads to avoid duplicates |
| **Cross-reference with existing epic** | mcp-agent-mail: found an existing epic `br-3h13` for test completeness — added new tracks under it rather than creating a parallel epic |
| **Always return 501 = API stub** | midas-edge: `promo/validate/route.ts` returned 501 Not Implemented with no callers |
| **Measure function body length with jq** | Codex sessions: `ast-grep --json \| jq 'sort_by(.range.end.line - .range.start.line)'` to find suspiciously short functions |
| **Tests expose stubs** | mcp-agent-mail: E2E audit found `null_fields` and `unicode` test files were themselves stubs (only 5-7 real assertions) |

**Full detection patterns with these behavioral checks:** [DETECTION-METHODS.md](references/DETECTION-METHODS.md)

---

## Anti-Patterns

| Don't | Do |
|-------|-----|
| Grep only for "TODO" | Use ALL detection methods — keywords, AST, heuristics |
| Skip project understanding | Read AGENTS.md and README.md first, always |
| Fix stubs without understanding intent | Trace through callers to understand what the real impl should do |
| Create one giant bead | One bead per stub/mock with proper dependencies |
| Start implementing before planning | Iterate in plan space first — it's cheaper |
| Forget tests | Every resolved stub needs tests proving it works |
| Oversimplify the resolution | Real implementations need real logic, not slightly better stubs |

---

## Checklist

- [ ] **Understand project:** Read AGENTS.md, README.md, explore architecture
- [ ] **Detect tooling:** Check for `.beads/` and `br` CLI
- [ ] **Keyword scan:** ripgrep for TODO/FIXME/STUB/MOCK/PLACEHOLDER/etc.
- [ ] **Unimplemented scan:** `todo!()`, `unimplemented!()`, `NotImplementedError`, `pass`
- [ ] **Return value scan:** Hardcoded returns, empty returns, always-true/false
- [ ] **AST scan:** ast-grep for suspiciously short functions/methods/classes
- [ ] **Behavioral scan:** `sleep()` as fake work, hardcoded scores, 501 routes, disabled features
- [ ] **Caller tracing:** For each suspect, trace callers to confirm real dependency on output
- [ ] **Divergent path check:** Look for same concept implemented differently in two places
- [ ] **Stub test check:** Test files with <5 assertions may themselves be stubs
- [ ] **Compile table:** All suspects with file:line, type, snippet, justification, **blocker status**
- [ ] **Categorize:** Just-needs-code / Blocked-on-infra / Dead-code / Intentional-stub
- [ ] **Check existing beads:** Avoid creating duplicates of already-tracked issues
- [ ] **Choose workflow:** Beads (5+ items) or TODO list (<5 items)
- [ ] **Plan resolution:** Comprehensive, detailed plan for each item
- [ ] **Refine plan:** 2-3 iterations in plan space before implementing
- [ ] **Resolve all items:** Implement real code, add tests
- [ ] **Verify:** Run tests, re-scan to confirm zero remaining stubs

---

## References

| Need | File |
|------|------|
| Full detection patterns by language | [DETECTION-METHODS.md](references/DETECTION-METHODS.md) |
| AST-grep patterns for structural analysis | [AST-PATTERNS.md](references/AST-PATTERNS.md) |
| Resolution strategies and examples | [RESOLUTION-STRATEGIES.md](references/RESOLUTION-STRATEGIES.md) |
