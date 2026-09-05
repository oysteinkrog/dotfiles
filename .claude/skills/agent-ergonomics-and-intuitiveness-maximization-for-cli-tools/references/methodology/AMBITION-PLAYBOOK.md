# AMBITION-PLAYBOOK — How to actually ship 10+ substantive changes

## Table of Contents

- [How to use this playbook](#how-to-use-this-playbook)
- [The 30+ patterns](#the-30-patterns)
- [How to extend this playbook](#how-to-extend-this-playbook)
- [When to use this playbook vs. existing recommendations](#when-to-use-this-playbook-vs-existing-recommendations)

The Ambition Bar (SKILL.md § "Ambition Bar (the 'That's it??' gate)") sets the *target*. This file is the *playbook* — the concrete, ready-to-apply recommendation patterns that historically ship in a single ambitious pass without breaking anything.

> **Why this file exists.** When the Ambition Bar self-prompt runs and the agent re-enters Phase 4/5, the question becomes "what NEW recommendations should I now ship?" Without a concrete playbook, the agent re-scans the existing recommendations.jsonl for low-hanging fruit it skipped — but the issue usually wasn't fruit-skipping, it was that Phase 4 hadn't surfaced enough recs to begin with. This file is the mental model expansion: 30+ commit-shaped recommendations the agent can match against the surface inventory, picking the ones that apply.

---

## How to use this playbook

1. **First pass (when Ambition Bar fires):** Walk through the 30+ patterns below. For each, ask: "Does this surface in `<tool>`?" If yes and the rec isn't already in `recommendations.jsonl`, add it.
2. **Score each:** Use the priority formula (`frequency × score_gap × blast_radius`). Patterns marked **(P0)** below are typically high-leverage on every CLI; **(P1)** are common; **(P2)** are situational.
3. **Ship the top-N** that close the Ambition Bar gap — usually 5–10 new commits. Phase 5 lands them; Phase 6 re-scores; Phase 7 fresh-eyes.
4. **Reuse:** This playbook updates over time. When a new pattern recurs in ≥ 3 audits, add it here.

---

## The 30+ patterns

### Output and parseability (Axiom 4, 8)

**P0-1: Add `--json` to read-side commands.**
- **Trigger:** Read-side command emits human text only.
- **Diff sketch (Rust + clap):** Add `#[arg(long)] json: bool` to the command struct; in the handler, branch `if self.json { println!("{}", serde_json::to_string(&result)?); } else { /* existing human output */ }`.
- **Regression test:** Pipe stdout to `jq .` and verify zero parse errors.
- **Dimensions affected:** output_parseability (+250–400), agent_ease_of_use (+150).

**P0-2: Split stdout (data) from stderr (diagnostics).**
- **Trigger:** `<tool> X --json | jq …` requires `grep -v` to filter log lines.
- **Diff sketch:** Replace `println!` with `eprintln!` for everything that isn't the requested data. Use `tracing` / `log` / `pino` to make this explicit.
- **Regression test:** `verify-stdout-stderr-split.sh <tool> <subcommand>` exits 0.
- **Dimensions affected:** output_parseability (+300–500), composability (+200).

**P0-3: Stable output ordering.**
- **Trigger:** `<tool> list` returns entries in hashmap iteration order (different across runs).
- **Diff sketch:** Sort by a deterministic key before output (typically the entity ID, name, or insertion order). Document the order in `--help` and the `capabilities` schema.
- **Regression test:** Run twice, diff bytes — should be empty.
- **Dimensions affected:** determinism_and_reproducibility (+300), composability (+150).

**P0-4: Honor `SOURCE_DATE_EPOCH` for timestamps.**
- **Trigger:** Output contains wall-clock timestamps that vary across runs even with same input.
- **Diff sketch:** Read `SOURCE_DATE_EPOCH` env var; if set, use it as the timestamp source. Document in `capabilities`.
- **Regression test:** Run twice with `SOURCE_DATE_EPOCH=0` set; output bytes must match.
- **Dimensions affected:** determinism_and_reproducibility (+250–400).

**P1-5: Move timestamps from free text to JSON fields.**
- **Trigger:** `<tool> list` text output includes raw `[2026-05-09T12:00:00Z]` prefixes; the JSON output mirrors this in a free-form `message` field.
- **Diff sketch:** In JSON output, move the timestamp to a typed `timestamp: ISO8601` field; keep the free-text rendering for human output only.
- **Regression test:** `<tool> list --json | jq '.[].timestamp'` returns ISO8601 strings.
- **Dimensions affected:** determinism_and_reproducibility (+150), output_parseability (+100).

### Self-documentation (Axiom 9, 10)

**P0-6: Add `<tool> capabilities --json`.**
- **Trigger:** No `capabilities` subcommand exists.
- **Diff sketch:** New subcommand returning `{version, contract_version, feature_flags, commands, exit_codes, env_vars}`. The schema is in `JSON-SCHEMA-PATTERNS.md`. Frame: "every other surface references this contract."
- **Regression test:** Output is valid against `assets/schemas/capabilities.json`.
- **Dimensions affected:** self_documentation (+400–600), agent_intuitiveness (+200), composability (+150).

**P0-7: Add `<tool> robot-docs guide` (or `--robot-help`).**
- **Trigger:** No in-tool agent-targeted handbook.
- **Diff sketch:** New subcommand printing a paste-ready agent handbook: invocation patterns, common errors with fixes, exit-code dictionary, mega-command shapes, env vars. Embedded as a static string in source.
- **Regression test:** `<tool> robot-docs guide | wc -l` exceeds 50 lines AND mentions `--json`, `--robot-*`, `capabilities`, exit codes.
- **Dimensions affected:** self_documentation (+400–600), agent_ease_of_use (+250).

**P0-8: Add a mega-command (`--robot-triage` shape).**
- **Trigger:** No single command returns multiple useful slices in one call.
- **Diff sketch:** Per `MEGA-COMMAND-DESIGN.md`. Returns `{quick_ref, recommendations, commands, project_health}` with copy-paste-ready follow-up commands embedded.
- **Regression test:** Schema-pinned via `<tool> --robot-schema | jq '.commands."<mega>"'` AND determinism test.
- **Dimensions affected:** agent_ergonomics (+400–600), agent_intuitiveness (+250), self_documentation (+150).

**P1-9: Cross-reference `--help` to all robot surfaces.**
- **Trigger:** `<tool> --help` doesn't mention `--json`, `capabilities`, `robot-docs`.
- **Diff sketch:** Add a "Robot & Planning" section to `--help` listing the four entry points with one-line descriptions.
- **Regression test:** `<tool> --help` contains all four surface names.
- **Dimensions affected:** self_documentation (+200), agent_intuitiveness (+150).

**P1-10: Add a discovery footer to long output.**
- **Trigger:** Multi-screen output (e.g. `<tool> insights`) ends without telling the agent what to do next.
- **Diff sketch:** Add a `## Next` section listing 3–5 follow-up commands ("To act on this, run `<tool> X`").
- **Regression test:** Long-output commands all have a `## Next` section in their JSON envelope's `commands` field.
- **Dimensions affected:** agent_ergonomics (+150), self_documentation (+100).

### Errors and intent inference (Axiom 6, 7)

**P0-11: Add Levenshtein-1 typo correction on flags.**
- **Trigger:** `<tool> X --jsno` (typo for `--json`) emits `error: unknown flag '--jsno'` with no suggestion.
- **Diff sketch:** Per language: clap (`infer_long_args=true` + custom error), cobra (`SuggestionsMinimumDistance=1`), click (`difflib.get_close_matches`), commander (`showSuggestionAfterError`).
- **Regression test:** `<tool> X --jsno` stderr contains `did you mean: --json`.
- **Dimensions affected:** intent_inference (+300–500), error_pedagogy (+250).

**P0-12: Rewrite errors to name the exact corrected command.**
- **Trigger:** Error messages say "see --help" or "invalid input" without saying what to do.
- **Diff sketch:** Per `ERROR-REWRITING-COOKBOOK.md` — 17 before/after templates. Each error has 3 parts: (a) what failed, (b) where, (c) the exact corrected command.
- **Regression test:** Per error category, runtime invocation produces stderr containing a copy-pasteable command suggestion.
- **Dimensions affected:** error_pedagogy (+300–500), agent_intuitiveness (+200).

**P0-13: Recognize agent intent aliases.**
- **Trigger:** Agent types `<tool> triage` (forgetting `--robot-triage` is the canonical name); error.
- **Diff sketch:** Recognize bare-verb aliases (`triage`, `next`, `plan`, `insights`) and route to the canonical `--robot-*` form, emitting a one-line stderr deprecation: `note: 'triage' is an alias for '--robot-triage'; using --robot-triage`.
- **Regression test:** Each alias produces same stdout as canonical form.
- **Dimensions affected:** intent_inference (+250–400), agent_intuitiveness (+200).

**P1-14: Common typo dictionary.**
- **Trigger:** Common misspellings (`--colour` for `--color`, `--licence` for `--license`, `--json5` for `--json`) error out instead of inferring.
- **Diff sketch:** Hardcode a small alias table per `INTENT-CORPUS-GENERATION.md`. Emit deprecation note + use the corrected form.
- **Regression test:** Each alias works AND emits the deprecation note.
- **Dimensions affected:** intent_inference (+200), error_pedagogy (+150).

**P1-15: Missing-required-arg → suggest the exact command.**
- **Trigger:** `<tool> create` (missing `--name`) emits `error: required argument '--name' not provided`.
- **Diff sketch:** Replace error with `error: '<tool> create' requires '--name <NAME>'.\n\nExample: <tool> create --name my-thing\n\nFor all options, run: <tool> create --help`.
- **Regression test:** stderr contains "Example:" and a copy-pasteable command.
- **Dimensions affected:** error_pedagogy (+250), agent_intuitiveness (+150).

### Exit codes and contracts (Axiom 5)

**P0-16: Document exit-code dictionary.**
- **Trigger:** `<tool> --help` doesn't list exit codes; `<tool> capabilities --json` doesn't include `exit_codes`.
- **Diff sketch:** Define a dictionary: `0=success, 1=user-input-error, 2=safety-block, 3=tool-environment-error, 4=upstream-failure, 5=conflict, 64=usage-error (BSD)`. Document in `capabilities`. Add to `--help`.
- **Regression test:** `<tool> capabilities --json | jq '.exit_codes'` returns the dictionary; `<tool> --help | grep -i 'exit code'` finds the section.
- **Dimensions affected:** output_parseability (+200), composability (+200), self_documentation (+150).

**P0-17: Replace exit-1-for-empty-result with exit-0 + empty array.**
- **Trigger:** `<tool> list --json` returns `[]` but exits 1 because "no results."
- **Diff sketch:** Exit 0 with `[]`; reserve exit 1 for actual user-input errors.
- **Regression test:** `<tool> list --filter 'nothing-matches' --json` exits 0 with `[]`.
- **Dimensions affected:** composability (+250), output_parseability (+150).

**P1-18: Distinct exit codes for distinct failures.**
- **Trigger:** Every failure emits exit 1; agent can't programmatically retry.
- **Diff sketch:** Map error categories to distinct codes per the dictionary. Network failure → 4. Lock conflict → 5. User typo → 1.
- **Regression test:** Synthetic failure injections produce the documented codes.
- **Dimensions affected:** composability (+250), error_pedagogy (+100).

### Safety and dangerous ops (Axiom 11)

**P0-19: Gate every irreversible op behind explicit `--yes`/`--confirm`.**
- **Trigger:** `<tool> delete X` deletes without confirmation.
- **Diff sketch:** Add `--yes` flag (or `--confirm <token>`). Without it, print a plan + safe alternative (`--dry-run`) and exit non-zero.
- **Regression test:** `<tool> delete X` (no `--yes`) emits `error: irreversible; pass --yes to confirm or --dry-run to preview` and exits non-zero.
- **Dimensions affected:** safety_with_recovery (+400–600), error_pedagogy (+150).

**P0-20: Add `--dry-run` to mutating commands.**
- **Trigger:** Mutating command has no preview mode.
- **Diff sketch:** `--dry-run` flag that renders the would-be effect (e.g. "would delete: A, B, C") without actually doing anything. Exit 0 means the dry-run completed; the actual operation requires running again without `--dry-run --yes`.
- **Regression test:** `<tool> delete X --dry-run` emits the plan AND `<tool> delete X --dry-run; ls X` shows X still exists.
- **Dimensions affected:** safety_with_recovery (+300), agent_ergonomics (+150).

**P1-21: Name the safe alternative in every dangerous-op error.**
- **Trigger:** Error from a dangerous op says "blocked" without naming `--dry-run` or alternatives.
- **Diff sketch:** Every dangerous-op error stderr contains "Safe alternative: `<command>`".
- **Regression test:** Dangerous-op error stderr matches `Safe alternative: .+`.
- **Dimensions affected:** error_pedagogy (+200), safety_with_recovery (+150).

### Composability (Axiom 13)

**P0-22: Honor `NO_COLOR` / `CI` / non-TTY for color output.**
- **Trigger:** ANSI codes appear in piped stdout.
- **Diff sketch:** Detect non-TTY via `isatty(STDOUT_FILENO)`. Honor `NO_COLOR=1`, `CI=true`, `TERM=dumb`. Add `--no-color` flag.
- **Regression test:** `verify-non-tty-discipline.sh` exits 0.
- **Dimensions affected:** composability (+300–400), determinism_and_reproducibility (+100).

**P1-23: Suppress progress bars in non-TTY.**
- **Trigger:** Long-running command's progress bar pollutes piped stdout.
- **Diff sketch:** Move progress to stderr AND suppress entirely in non-TTY (or with `--quiet`).
- **Regression test:** `<tool> long-op | head` doesn't include `\r` (carriage return for live updates).
- **Dimensions affected:** composability (+200).

**P1-24: Honor `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` for state.**
- **Trigger:** `<tool>` writes to `~/.<tool>` instead of `$XDG_CONFIG_HOME/<tool>` etc.
- **Diff sketch:** Per platform conventions; fall back to `~/.config/<tool>` if XDG vars unset on Linux/Mac.
- **Regression test:** `XDG_CONFIG_HOME=/tmp/xdg <tool> X; ls /tmp/xdg/<tool>` shows config files.
- **Dimensions affected:** composability (+150), determinism_and_reproducibility (+50).

### Mega-command and triage shapes (Axiom 10)

**P1-25: Add `<tool> doctor --json`.**
- **Trigger:** No structured health check.
- **Diff sketch:** Per `MEGA-COMMAND-DESIGN.md` DIAGNOSE shape. Returns `{checks: [{name, status, message, fix}], summary: {ok|warn|fail}}`.
- **Regression test:** Schema-pinned; runs in < 2s.
- **Dimensions affected:** self_documentation (+200), agent_ergonomics (+150).

**P1-26: Add `<tool> --robot-plan --json`.**
- **Trigger:** No structured "what should I do next" surface.
- **Diff sketch:** Per `MEGA-COMMAND-DESIGN.md` PLAN shape. Returns ranked actions with `unblocks`, `effort_estimate`, `commands`.
- **Regression test:** Output deterministic + schema-pinned.
- **Dimensions affected:** agent_ergonomics (+250), agent_intuitiveness (+150).

**P2-27: Add `<tool> schema <verb> --json` for per-verb schema export.**
- **Trigger:** Different verbs return different shapes; agents can't introspect.
- **Diff sketch:** `<tool> schema list --json` returns the JSON schema for `list`'s output. Per-verb introspection.
- **Regression test:** Every read-side verb has a schema; `<tool> X --json` validates against `<tool> schema X --json`.
- **Dimensions affected:** self_documentation (+200), regression_resistance (+150).

### Regression resistance (Axiom 17)

**P0-28: Pin `--help` text with a snapshot test.**
- **Trigger:** No test catches drift in help text.
- **Diff sketch:** `tests/help_snapshot.test.sh`: `diff <(./bin --help) testdata/help.txt`.
- **Regression test:** N/A (this IS a regression test; it pins drift).
- **Dimensions affected:** regression_resistance (+250).

**P0-29: Pin `capabilities --json` schema.**
- **Trigger:** Capabilities schema can drift across versions without notice.
- **Diff sketch:** `tests/capabilities_schema.test.sh`: validate `<tool> capabilities --json` against `tests/capabilities.schema.json`.
- **Regression test:** Same as above; pinned by the test.
- **Dimensions affected:** regression_resistance (+300), self_documentation (+100).

**P1-30: Per-applied-rec golden test.**
- **Trigger:** Phase 5 commits without locking the new behavior.
- **Diff sketch:** Every applied rec lands `audit/regression_tests/R-NNN__<short>.test.{sh,rs,py,ts}`. Required by Phase 5 exit criteria.
- **Regression test:** N/A.
- **Dimensions affected:** regression_resistance (+200) per applied rec.

### Ergonomics polish (multi-dimension)

**P1-31: Bare invocation shows useful help, not a TUI.**
- **Trigger:** Bare `<tool>` launches an interactive TUI; agents hang.
- **Diff sketch:** Detect non-TTY; emit help. In TTY, optionally launch TUI but only with `--tui` flag explicit.
- **Regression test:** `echo '' | <tool>` exits 0 with help on stdout.
- **Dimensions affected:** agent_intuitiveness (+400), composability (+200), error_pedagogy (+100).

**P1-32: Verb names match agent intuition.**
- **Trigger:** `<tool> rm` (instead of `delete`); `<tool> ls` (instead of `list`); etc. Agents type the natural verb and miss.
- **Diff sketch:** Add aliases for the alternative verb names. Document in `capabilities.commands`.
- **Regression test:** Both forms work and produce identical output.
- **Dimensions affected:** agent_intuitiveness (+200), intent_inference (+150).

**P2-33: Sub-second hot path on canonical first invocation.**
- **Trigger:** `<tool> --robot-triage` takes > 2s on a small project.
- **Diff sketch:** Per-project profile to find the bottleneck (often startup dependency loading or filesystem walks). Cache or defer where safe.
- **Regression test:** `time <tool> --robot-triage` reports < 1s on the canonical fixture.
- **Dimensions affected:** agent_ergonomics (+150).

**P2-34: Idempotency keys on mutating ops.**
- **Trigger:** Re-running `<tool> create X` after a partial failure creates a duplicate.
- **Diff sketch:** Accept `--idempotency-key <KEY>` (or `--id <ID>`); mutating ops with the same key + same payload are no-ops on retry.
- **Regression test:** Run twice with same key; second run reports "already applied" with exit 0.
- **Dimensions affected:** safety_with_recovery (+200), composability (+100).

**P2-35: Stable handles for every entity.**
- **Trigger:** `<tool> create X` returns `id: 17` (auto-increment); a re-run on a different machine returns `id: 23`.
- **Diff sketch:** Use content-derived IDs (UUIDv5, sha256 of canonical form) instead of auto-increment.
- **Regression test:** Same input on different machines produces same ID.
- **Dimensions affected:** determinism_and_reproducibility (+200), composability (+150).

---

## How to extend this playbook

When a Phase 5 in some pass produces a recommendation that ISN'T in this list, ask:

1. **Is the pattern general or project-specific?** General → add to playbook. Project-specific → leave as a one-off rec.
2. **Has the pattern shipped in ≥ 2 audits?** Yes → add. No → wait until the second occurrence.
3. **Does the pattern have a clean diff sketch (≤ 30 lines)?** Yes → add. No → it's an architectural change, file as a different recommendation type.

For each new pattern, capture:
- ID (P0/P1/P2 + a number).
- Trigger (what surfaces it on).
- Diff sketch (concrete code change).
- Regression test (the lock).
- Dimensions affected with score deltas.

The playbook lives or dies by the concreteness of the diff sketches. "Improve error messages" is too vague to ship; "Replace error 'invalid input' with 'invalid input: <field>; expected <type>; got <value>; example: <command>'" is shippable.

---

## When to use this playbook vs. existing recommendations

**Playbook-driven Phase 4 (during Ambition Bar second-round):**
- Walk the playbook top-to-bottom.
- For each P0 pattern: check the surface inventory; add a rec if applicable AND not already in `recommendations.jsonl`.
- For each P1 pattern: same, weighted by surface frequency.
- Skip P2 unless specifically relevant.
- This re-fills the rec queue for Phase 5.

**Inventory-driven Phase 4 (initial pass):**
- Walk the surface inventory; for each surface, ask "does this fail any Polish Bar test?"
- Where the answer is yes, generate a rec with diff sketch.
- Cross-reference the playbook to check if the rec aligns with a known pattern (use the same diff-sketch idiom).
- If the surface produces a rec NOT in the playbook, that's a candidate to add to the playbook (per the extension rules above).

The playbook is a **bias** — it tilts the agent toward known-shippable patterns when the natural bias is "polite scorecard, stop." Inventory-driven Phase 4 is the **discovery** mode; playbook-driven Phase 4 is the **shipping** mode. Both are needed.
