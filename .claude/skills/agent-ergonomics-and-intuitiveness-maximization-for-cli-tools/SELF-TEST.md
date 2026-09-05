# Self-Test

## Trigger phrases (should activate this skill)

- "Audit this CLI for agent ergonomics"
- "Make `<tool>` agent-friendly"
- "Score `<tool>` for how usable it is by an AI agent"
- "Add a `--robot-*` mode to my CLI"
- "Add `capabilities --json` and `robot-docs` to this tool"
- "Why does an agent always pick the wrong flag for `<tool>` — fix the intent inference"
- "Re-run the agent-ergonomics audit on `<tool>` and tell me which surfaces regressed"
- "Compare the pre-pass and post-pass agent simulations and tell me what got better"
- "Mine my prior agent sessions for places where this CLI's error messages didn't teach me anything, and prioritize those"
- "Build me a scorecard with a heatmap of every flag and exit code in this binary"
- "First command an agent tries should just work — make it so for `<tool>`"
- "Apply the highest-leverage agent-ergonomic fixes to `<tool>` and re-score"
- "Run the agent-in-the-loop simulation against the new build of `<tool>`"
- "Score this single flag — `<tool> foo --bar` — and tell me what to fix"

## Trigger phrases (should NOT activate this skill — adjacent or off-target)

- "Build a documentation site for this CLI" — use `/documentation-website-for-software-project`
- "Write a README for this CLI" — use `/readme-writing`
- "Make this CLI faster" — use `/extreme-software-optimization` (perf, not ergonomics)
- "Add a TUI to this CLI" — use `/tui-glamorous` (ergonomics audit may follow once the TUI has a robot mode)
- "Refactor this CLI's internals" — use `/simplify-and-refactor-code-isomorphically`
- "Find bugs in this CLI" — use `/multi-pass-bug-hunting` or `/ubs`
- "Configure shell completion for this tool" — adjacent; this skill scores completion as a self_documentation surface but does not generate it
- "Set up CI for this CLI" — use `/gh-actions`
- "Release this CLI" — use `/release-preparations`

## Scope-creep regression probes

These prompts should activate the skill but keep optional references dormant unless the stated trigger appears.

| Prompt | Expected scope decision |
|--------|-------------------------|
| "Just add `--json` to the `list` subcommand of `<tool>`" | `single-surface-rescore` mode; touch only the named surface; skip CASS deep mining and multi-model triangulation |
| "Audit `<tool>` for agent ergonomics" | `audit-only`; do not change code; in-tree workspace at `<target>/agent_ergonomics_audit/`; **never create a new branch**; **never create a sibling directory** |
| "Audit AND apply" / "apply this skill comprehensively to `<tool>`" | `full`; commit directly to current branch (typically `main`); **never create a new branch**; in-tree workspace; ask for triangulation appetite; meet Ambition Bar before Phase 10 |
| "Re-run the audit on `<tool>` against my latest changes" | `re-score-only`; compare pass-N to pass-N-1 only |
| "Why is the agent failing canonical task X with `<tool>`?" | Run Phase 3 + Phase 9 only on that task; skip full inventory if surfaces unchanged |

Validation question for each probe: did the response propose `audit/phase0_scope_decision.md` with mode, target, and a "not doing" list? If not, the skill regressed.

## Smoke test on a tiny CLI

```bash
# 1. Pick a tiny example CLI to audit
mkdir -p /tmp/agent-ergo-smoke && cd /tmp/agent-ergo-smoke
cat > demo.sh <<'EOF'
#!/bin/bash
case "${1:-}" in
  list) echo "item1"; echo "item2";;
  add)  echo "added";;
  rm)   echo "deleted";;
  *)    echo "Usage: demo.sh <list|add|rm>"; exit 1;;
esac
EOF
chmod +x demo.sh

# 2. Run discover-cli from this skill against the tiny example
SKILL=<repo>/.claude/skills/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools
bash "$SKILL/scripts/discover-cli.sh" /tmp/agent-ergo-smoke

# Expected output: language=bash, binaries=[demo.sh], no robot mode detected,
# recommended mode=full (small surface, big uplift available).
```

## Smoke test on this skill itself

```bash
SKILL=<repo>/.claude/skills/agent-ergonomics-and-intuitiveness-maximization-for-cli-tools

# 1. Verify SKILL.md frontmatter is parseable
head -10 "$SKILL/SKILL.md" | grep -E '^name:|^description:'

# 2. Verify all referenced methodology files exist
for f in OPERATING-MODES PHASES AGENT-PROMPTS KICKOFF-PROMPTS OPERATORS POLISH-BAR \
         ORCHESTRATION SKILL-FALLBACKS TRIANGULATION IO-CONTRACTS \
         INTENT-CORPUS-GENERATION ANTI-PATTERNS TROUBLESHOOTING \
         LANGUAGE-RECIPES MEGA-COMMAND-DESIGN ERROR-REWRITING-COOKBOOK \
         JSON-SCHEMA-PATTERNS OBSERVABILITY-AND-TELEMETRY-SURFACES \
         CLI-ARCHETYPES MCP-SERVER-AUDIT MULTI-TOOL-FAMILY-AUDIT \
         DEPRECATION-PATTERNS SCHEMA-EVOLUTION \
         HOOKS-INTEGRATION CI-INTEGRATION CONTINUOUS-IMPROVEMENT \
         CASS-MINING-RECIPES-DEEP \
         OPERATIONALIZING-EXPERTISE-TRACK-A AGENT-API-DESIGN-PRINCIPLES \
         VERIFICATION-FIRST SELF-APPLICATION \
         MULTI-PASS-BUG-HUNTING-FOR-ERGONOMICS WORKED-OPERATOR-COMPOSITIONS \
         AGENT-PROFILES CONFIG-AS-CODE-PATTERNS \
         PLUGIN-AND-EXTENSION-SURFACES CRASH-RECOVERY-AND-RESUMABILITY \
         DECISION-TREES FAILURE-MODE-CATALOG POLISH-BAR-DEEP \
         BEADS-WORKFLOW NTM-AND-AGENT-MAIL-INTEGRATION METRICS-AND-TIMESERIES \
         TUI-MODE-AUDIT DSL-AND-SDK-AUDIT; do
  test -f "$SKILL/references/methodology/$f.md" || echo "MISSING: methodology/$f.md"
done

# 3. Verify all referenced rubric files exist
for f in SCORING-RUBRIC PRIORITY-FORMULA SURFACE-CLASSES REGRESSION-TEST-PATTERNS \
         RUBRIC-EXTENSIONS; do
  test -f "$SKILL/references/rubric/$f.md" || echo "MISSING: rubric/$f.md"
done

# 4. Verify all referenced exemplar files exist
for f in CANONICAL-EXEMPLARS COUNTER-EXAMPLES CASS-FINDINGS QUOTE-BANK WORKED-EXAMPLES \
         CANONICAL-TASK-LIBRARY CANONICAL-EXEMPLARS-DEEP CASE-STUDIES; do
  test -f "$SKILL/references/exemplars/$f.md" || echo "MISSING: exemplars/$f.md"
done

# 4b. Verify CHEAT-SHEET.md exists at top of references/
test -f "$SKILL/references/CHEAT-SHEET.md" || echo "MISSING: references/CHEAT-SHEET.md"

# 5. Verify all referenced subagents exist
for f in cass-miner surface-inventorist scorer scorer-tiebreaker \
         intent-stresser-naive intent-stresser-savvy intent-runner \
         recommender synthesizer triangulator applier regression-test-author \
         re-scorer fresh-eyes self-doc-hardener canonical-task-simulator \
         handoff-writer idea-generator \
         cli-archetype-classifier parity-auditor family-cross-cut-auditor \
         migration-planner canonical-task-author skill-self-applier \
         cheat-sheet-builder benchmark-collector decision-tree-walker; do
  test -f "$SKILL/subagents/$f.md" || echo "MISSING: subagents/$f.md"
done

# 6. Verify all scripts are executable
for s in "$SKILL"/scripts/*.sh "$SKILL"/scripts/*.mjs; do
  [ ! -x "$s" ] && echo "NOT EXECUTABLE: $s"
done

# 7. Verify tools/ helpers exist + executable
for s in "$SKILL"/tools/*.sh; do
  [ ! -x "$s" ] && echo "NOT EXECUTABLE: $s"
done

# 8. Verify assets exist
for f in intake-prompt manifest-template surface-record-template recommendation-template applied-change-template scorecard-template handoff-template regression-test-template canonical-task-template; do
  ls "$SKILL/assets/$f."* 2>/dev/null | head -1 | grep -q . || echo "MISSING asset stem: $f"
done

# 9. Validate manifest template is valid JSON
cat "$SKILL/assets/manifest-template.json" | jq . > /dev/null || echo "manifest-template.json not valid JSON"

# 10. Validate jsonl templates are one-line jsonl per line
for f in "$SKILL"/assets/*-template.jsonl; do
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | jq . > /dev/null 2>&1 || { echo "INVALID JSONL: $f"; break; }
  done < "$f"
done
```

## End-to-end dry-run on a real project (operator validation)

```bash
TARGET=/data/projects/some-cli-tool
SIBLING="${TARGET}/agent_ergonomics_audit"  # legacy variable name; path is in-tree

# Phase 0
bash scripts/preflight.sh "$TARGET"
bash scripts/scaffold-workspace.sh "$SIBLING" "$TARGET"
bash scripts/discover-cli.sh "$TARGET" > "$SIBLING/audit/phase0_cli.json"
bash scripts/check-skills.sh "$SIBLING/audit"

# Phase 1 inventory (recursive --help walk)
bash scripts/inventory_surfaces.sh "$TARGET" > "$SIBLING/audit/surface_inventory.jsonl"

# Phase 2 sample-score one surface (full Phase 2 spawned via subagents).
# The stub scorer emits per-scorer partial rows; aggregate them into the final
# agent_surfaces.jsonl schema before rendering or validating.
bash scripts/score_surface.sh "$TARGET" "subcommand__list" > "$SIBLING/audit/partial/scores_pass1_subcommand__list_scorerA.jsonl"
bash scripts/score_surface.sh "$TARGET" "subcommand__list" > "$SIBLING/audit/partial/scores_pass1_subcommand__list_scorerB.jsonl"
bash scripts/aggregate_scores.sh "$SIBLING" "subcommand__list"

# Render the heatmap + scorecard
bash scripts/render_scorecard.sh "$SIBLING/audit/agent_surfaces.jsonl" > "$SIBLING/audit/scorecard.md"
bash scripts/render_heatmap.sh "$SIBLING/audit/agent_surfaces.jsonl" > "$SIBLING/audit/heatmap.svg"

# Validate the workspace
bash scripts/validate_pass.sh "$SIBLING"
```

The full subagent fan-out (inventory → score → intent stress → recommend → apply → re-score → fresh-eyes → simulate → handoff) is spawned by the main agent reading SKILL.md and following the phase loop.

## Validation checklist (when forking / extending this skill)

- [ ] Frontmatter starts at line 1 (no blank line before `---`).
- [ ] Description is third-person and includes "Use when" triggers + the durable artifact paths.
- [ ] SKILL.md body < ~600 lines (current size is intentionally larger; bulk lives in references).
- [ ] Every reference linked from SKILL.md exists.
- [ ] Every subagent listed in SKILL.md exists.
- [ ] Every script is executable and has a shebang.
- [ ] Every tool in `tools/` is executable.
- [ ] Asset templates parse (JSON valid, JSONL one-per-line valid).
- [ ] No hardcoded `/data/projects/<user-specific>` paths in scripts; use `$1`/`$TARGET`/`$SIBLING`.
- [ ] AGENTS.md compliance: no `rm -rf`, no `git reset --hard`, no `_v2` files, no script-driven code transformations.
