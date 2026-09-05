# Subagent: leak-scanner

**Phase:** 2.5
**Spawn:** Once per run. Non-negotiable.

## Role

Scan candidates for committed secrets. Halt the routine flow if any real secret is found.

## Prompt

You are scanning for committed secrets in `<project>`. Phase 2.5 is non-negotiable and must run on every invocation.

Steps:

1. Read `<workspace>/candidates.tsv`.

2. For each candidate, apply secret-smell rules from `references/FILE-SMELLS.md § Secret leakage`:
   - **Filename match**: `signing-*.key`, `*.pem`, `id_rsa*`, `*.token`, `*credentials*.json`, `.env` (without `.example`), etc.
   - **Content fingerprint** (only on filename hits): 32/64-byte raw, `BEGIN PRIVATE KEY`, known prefix patterns (`xoxb-`, `sk-`, `ghp_`, `AKIA[A-Z0-9]{16}`, `AIza[A-Za-z0-9_-]{35}`, etc.).

3. For each suspect, capture provenance:
   ```bash
   git log --oneline --all --diff-filter=A -- <path>     # introducing commit
   git rev-parse origin/<branch> 2>/dev/null              # was it pushed?
   ```

4. Write findings to `<workspace>/secret_findings.tsv` with columns:
   `path, smell, content_hash, introduced_in_sha, last_touched_at, pushed_to_origin, exposure_window_days, resolution`
   (resolution starts as `pending`; updates after user confirmation)

5. **If ANY entry has a real-secret hit (filename match + content fingerprint match):**
   - HALT the routine cleanup flow.
   - Surface the finding with full context to the user (every detail in the row).
   - Switch to `references/INCIDENT-PLAYBOOK.md § Secret Leak Recovery`.

6. **If only filename-only suspects** (e.g., 0-byte placeholder, `.pub` without `.key`, content matches a placeholder string like `YOUR_TOKEN_HERE`):
   - Tag as `secret-suspect` smell.
   - Continue to Phase 3 with deferred user-confirm at Phase 5.

## Output

`<workspace>/secret_findings.tsv` (may be empty).

## Tools used

Read, Bash (with `git log`, `head`, `od`, `base64 -d`), Grep.

## Time budget

1–3 min.
