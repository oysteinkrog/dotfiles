---
name: semgrep-author
description: Phase 2 — authors custom semgrep rules for project-shape UB patterns ast-grep can't express (cross-function flow).
---

# Semgrep Author

**Invoke with `subagent_type=general-purpose`** — authors semgrep YAML rule files.

For UB shapes that need cross-function dataflow (e.g., "this raw pointer escapes from constructor and is used in another function after the original is dropped"), ast-grep's tree-pattern matching isn't enough. Use semgrep.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{BUCKET}` — the UB-taxonomy bucket whose patterns ast-grep can't cover

## Workflow
1. Identify shapes from `phase2_findings_{BUCKET}.md` that are dataflow-shaped (escape, refcount lifecycle, FFI callback aliasing).
2. Author semgrep rules under `scripts/semgrep-rules/{BUCKET}/` — you'll need to create this directory (and its `{BUCKET}/` subdir) since the skill ships with no pre-authored semgrep rules; the rules are per-project. Example structure:
   ```yaml
   rules:
     - id: rust-ub-ptr-escape-via-from-raw
       languages: [rust]
       severity: WARNING
       message: |
         Pointer from `Box::into_raw` is later used in `from_raw` in a different
         function. Verify the pairing is correct across the call boundary.
       pattern-either:
         - patterns:
             - pattern: |
                 fn $F1(...) {
                   ...
                   let $P = Box::into_raw($BOX);
                   ...
                 }
             - pattern: |
                 fn $F2(...) {
                   ...
                   let $X = unsafe { Box::from_raw($P) };
                   ...
                 }
   ```
3. Run via `semgrep --config=scripts/semgrep-rules/{BUCKET}/`.
4. Append findings to `phase2_findings_{BUCKET}.md` with `Tool: semgrep` tag.

## Outputs
- `scripts/semgrep-rules/{BUCKET}/*.yml`
- Findings appended to `phase2_findings_{BUCKET}.md`

## Quality gates
- [ ] Each rule has a `message` field that names the UB shape
- [ ] False-positive rate is documented for each rule
- [ ] Rules are idempotent (running twice doesn't double-flag)

## Anchors
TOOLING.md §semgrep; refcount-lifecycle and lifetime-escape buckets.
