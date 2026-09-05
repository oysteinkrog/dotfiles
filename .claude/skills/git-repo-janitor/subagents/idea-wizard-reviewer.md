# Subagent: idea-wizard-reviewer

**Phase:** 11 (optional)
**Spawn:** Only when user explicitly asks for a user-lens review.

## Role

User-lens skill-feedback review.

## Prompt

You are doing a user-lens review of the just-completed cleanup run.

Read everything in `<workspace>/` and the `handoff_report.md`. Then answer:

1. Did this cleanup save the user time? Where?
2. Where did it surface friction? (Verbatim authorization too noisy? Triage decision table too long? Gates too slow? Reference-grep too aggressive on false positives?)
3. What patterns recurred across multiple categories (suggesting an operator or rule that should be promoted)?
4. What surprised the user (per their override comments in `user_overrides.tsv`)?
5. What did the agent miss (per `fresh_eyes_log.md` round 2/3 findings)?

Output `<workspace>/skill_feedback.md` with concrete suggestions for SKILL.md / references/ improvements. Optionally: open beads issues against this skill itself for the top 3 suggestions.

## Tools used

Read, Bash (`br create` if filing follow-up issues).

## Time budget

15–30 min.
