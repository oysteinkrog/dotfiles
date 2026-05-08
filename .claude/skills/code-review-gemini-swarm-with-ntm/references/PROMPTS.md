# Gemini Review Swarm — Full Prompt Bank

All prompts battle-tested across hundreds of real Gemini review sessions. The
main SKILL.md has the core three. This file has every variant, including shorter
forms for context-tight situations and project-specific overrides.

## Core Prompts (canonical)

### P1: Study the Project

```text
First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project.
```

### P2: Explore and Review

```text
I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file.
```

### P3: Cross-Review

```text
Reread AGENTS.md so it is still fresh in your mind. Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!
```

### P4: Continuation Nudge (short form)

```text
Continue your code review. Explore more code files, trace execution flows, and look for bugs or issues. Be thorough and methodical.
```

## Variant Prompts

### P1-specific: Study with Project Path Override

When the Gemini agent needs to be pointed at a specific project path (e.g., in multi-project setups):

```text
First read ALL of the $PROJECT_PATH/AGENTS.md file and $PROJECT_PATH/README.md file super carefully and understand ALL of both. Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the $PROJECT project at $PROJECT_PATH/.
```

### P2-specific: Explore with File Focus

When you want agents to start from specific subsystems:

```text
I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file. Start your investigation from $SUBSYSTEM_PATH.
```

### P3-specific: Cross-Review with Commit Range

When you want agents to focus on a specific commit range:

```text
Reread AGENTS.md so it is still fresh in your mind. Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Focus especially on commits since $COMMIT_REF but don't restrict yourself -- cast a wider net and go super deep!
```

### P-redirect: Switch Project Mid-Session

Used when redirecting a Gemini agent to a different project in the same session:

```text
Stop what you're doing. First read ALL of the /dp/$NEW_PROJECT/AGENTS.md file and /dp/$NEW_PROJECT/README.md file super carefully and understand ALL of both. Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the $NEW_PROJECT project at /dp/$NEW_PROJECT/.
```

### P-verify: Post-Fix Verification Nudge

Send after an agent reports fixes to push it into verification:

```text
Now verify your fixes: run the project's test suite, linter, and formatter. Report whether everything passes. If anything fails, diagnose and fix it before moving on.
```

### P-summary: Request Findings Report

When an agent seems to be done but hasn't written a summary:

```text
Write a GEMINI_REVIEW_SUMMARY.md file documenting all the bugs you found, what you fixed, and what you verified. Include file paths, line numbers, and the root cause of each issue.
```

### P-shutdown: Graceful Session End

```text
Finish the smallest coherent piece of work you are currently in the middle of, document your findings if you haven't already, and then stop cleanly.
```

## Prompt Sequencing Patterns

### Standard Review Round (7 prompts)

```
P1 → P2 → P3 → P4 → P2 → P3 → P4 → P2 → P3
```

### Deep Dive Round (9 prompts, for large codebases)

```
P1 → P2 → P2 → P3 → P4 → P2 → P2 → P3 → P-verify
```

Doubles up on explore passes before cross-review. Use when the codebase is large
enough that a single explore pass can't cover meaningful ground.

### Quick Audit (3 prompts, for small codebases)

```
P1 → P2 → P3
```

Single pass, no repetition. Sufficient for projects under ~5K lines.

## When to Use Which Variant

| Situation | Prompt | Why |
|-----------|--------|-----|
| First prompt of a round | P1 (canonical) | Agent needs full context |
| Standard review pass | P2 (canonical) | Most-tested variant |
| After explore, before next cycle | P3 (canonical) | Catches other agents' mistakes |
| Between iterations 2 and 3 | P4 (continuation) | Saves context, pushes new areas |
| Agent hasn't written summary | P-summary | Forces structured output |
| Agent done, ready for next round | P-shutdown | Clean session end |
| Large codebase, single pass insufficient | P2 twice | More exploration coverage |
| Post-fix, need verification | P-verify | Catches regressions from fixes |
