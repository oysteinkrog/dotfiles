# Gemini Review Swarm — Operations Guide

How to assess review quality, what good Gemini output looks like, and real
examples of the kinds of bugs Gemini agents find.

## What Good Gemini Review Output Looks Like

High-quality Gemini review sessions follow a consistent pattern. The agent:

1. Names specific files and line numbers
2. Explains the root cause (not just symptoms)
3. Shows the buggy code snippet
4. Shows the fix
5. Runs verification (tests, clippy, fmt)
6. Produces a structured "Summary of Actions" at the end

### Example of a High-Quality Finding (from real session)

```
**Bug: Flawed .jsonl Provider Inference Logic (src/discovery.rs)**
- Issue: The infer_provider_for_path function uses the ? operator on
  serde_json::from_str().ok()?. If the first non-empty line is not
  valid JSON, the entire function instantly exits and returns None.
  Also, the loop has an unconditional break on the first iteration,
  so it only ever checks one line.
- Fix: Rewrote the JSONL parser loop to gracefully continue on
  non-JSON lines and scan up to 50 valid JSON lines for a provider
  signature.
```

### Example of Low-Quality Output (noise)

```
I reviewed src/main.rs. The code looks well-structured.
The error handling follows Rust best practices.
I don't see any obvious issues.
Moving on to the next file.
```

This agent is narrating, not reviewing. If you see this pattern after 2+
explore passes, the agent has exhausted its usefulness on this codebase
and should be killed/relaunched.

## Real Bugs Found by Gemini Agents (from real sessions)

These are actual bugs discovered across 185+ review sessions:

### Parser / Logic Bugs
- **JSONL parser early exit**: `?` operator on `from_str().ok()?` caused entire function to return None on first non-JSON line
- **Unconditional break**: Loop only checked first iteration, missing provider signatures on line 2+
- **Tilde expansion failure**: `"~"` (bare) wasn't handled by `strip_prefix("~/")` check
- **Boolean env var parsing**: `STREAMING_INDEX=false` was treated as enabled because code only checked `!= "0"`
- **Timestamp range bug**: Seconds/milliseconds threshold used narrow range (1e9..1e10), rejecting valid pre-2001 timestamps

### Type System / Coordination Bugs
- **Missing agent type cases**: New agent types (Cursor, Windsurf, Aider) added to core types but not to CLI switches, causing silent skips in status, send, interrupt, completion, and dashboard commands
- **Dashboard count bug**: New agent types lumped into `otherCount` and labeled "User" in status output
- **Controller blindness**: Controller agent only counted Claude/Codex/Gemini panes, completely blind to newer agent types

### Rendering / Edge Case Bugs
- **Wide char scrollbar corruption**: Scrollbar widget didn't account for wide Unicode characters, causing cell overwrites
- **Content flattening double-newlines**: `flatten_content` blindly added newlines between parts even when `extract_content_part` returned empty string
- **N-gram search miss**: Edge ngrams started at length 2, causing single-char prefix searches (like "b" matching "bar") to fail

### Concurrency / Resource Bugs
- **Missing flush_async_commits()**: Async write path didn't flush to WAL, causing data loss on crash
- **Reservation persistence gap**: File reservations not persisted across restarts

## Quality Assessment Rubric

When reviewing Gemini agent output in the cron check, rate each agent:

| Signal | Quality | Action |
|--------|---------|--------|
| Names specific files, line numbers, root causes | High | Keep running |
| Finds and fixes real bugs with verification | High | Keep running |
| Explores deeply but finds nothing (with reasoning) | Medium | Acceptable for clean codebases |
| Narrates code structure without finding anything | Low | One more pass, then kill |
| Repeats findings from previous iteration | Low | Kill and relaunch |
| Produces GEMINI_FIXES.md or similar | High | Read it for findings |
| Attempts to delete files | Normal | No-deletion rule blocks it (if configured), ignore |
| Gets stuck on Agent Mail coordination | Low | Should not happen in review-only mode |

## Tracking File Patterns

### File Naming Across Iterations

Real sessions show this progression:

```
Round 1, Iteration 1: GEMINI_REVIEW_SUMMARY.md
Round 1, Iteration 2: GEMINI_DEEP_REVIEW.md
Round 1, Iteration 3: GEMINI_FIXES.md
Round 1, Post-fix:    GEMINI_FIXES_2.md, GEMINI_FIXES_3.md
Round 1, Final:       GEMINI_FINAL_REPORT.md
```

Some agents also write `GEMINI_STATUS.md` to self-track progress with
sections like "Pending: None identified" and "Completed: [list]".

### SESSION_TODO.md

Multi-agent sessions use `SESSION_TODO.md` with numbered sections per agent:

```markdown
## 13. Current Session (Gemini) — Comprehensive Code Review & Scrollbar Fix
- [x] Audit core crates
- [x] Fix scrollbar wide char bug
- [x] Add regression tests

## 14. Current Session (Agent-2) — Text Editor Diagnostic Log
...
```

Each Gemini agent appends its own numbered section. This file provides
cross-agent visibility into who did what.

## Operator Decision Tree

```
Agent output received
│
├─ Contains "Switched to fallback model" → Retire immediately
│
├─ Contains specific file:line fixes → High quality, continue
│
├─ Contains "Summary of Actions" with numbered findings → High quality
│
├─ Contains "I don't see any obvious issues" → Check:
│   ├─ First explore pass → Normal, send continuation
│   └─ Third+ explore pass → Diminishing returns, kill/relaunch
│
├─ Contains test/lint/format output → Agent is verifying, good
│
└─ Contains extensive Agent Mail chatter → Not reviewing, retask
```

## Mixed Swarm Integration

When running Gemini reviewers alongside Claude/Codex implementation agents:

### Recommended Ratios (from real sessions)

| Swarm Size | Claude (impl) | Codex (impl) | Gemini (review) |
|------------|---------------|--------------|-----------------|
| Small (6)  | 3 | 2 | 1 |
| Medium (14)| 5 | 5 | 4 |
| Large (24) | 10 | 10 | 4 |

Gemini scales sub-linearly because review agents cover the same codebase.
4 is typically sufficient even for large swarms -- more just leads to
redundant findings.

### Coordination Rules

- Gemini does NOT register with Agent Mail (avoids communication purgatory)
- Gemini does NOT pick beads from bv (it's not an implementer)
- Gemini DOES read `git log` and `git diff` to find recent changes
- Gemini DOES run tests/linters after making fixes
- Claude/Codex agents should be aware that Gemini may fix code they wrote

### Timing

- Spawn Gemini agents after implementation agents have been working for
  at least 15-20 minutes. Reviewing an empty or barely-started codebase
  wastes Gemini's context window.
- Alternatively, in the pure review-only mode (this skill), all agents
  start simultaneously since the codebase already exists.
