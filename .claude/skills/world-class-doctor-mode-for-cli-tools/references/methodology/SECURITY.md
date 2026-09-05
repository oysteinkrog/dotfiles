# Security — What the Doctor Touches and How

A doctor sees everything the project touches: state files, configs, credentials, lockfiles, sockets. It writes verbatim backups of files that may contain secrets. It produces JSON output that may be piped into agent context that gets cached for hours. Three risk classes need explicit handling.

---

## Class 1 — Credentials in backups

The verbatim-backup invariant (Axiom 2) means we copy files byte-for-byte before mutation. If `~/.config/<tool>/credentials` contains an API token, the backup contains the token. The backup lives at `.doctor/runs/<run-id>/backups/`, which:

- Is gitignored on first run (the doctor adds `.doctor/` to `.gitignore` if missing).
- Is mode 0700 (the directory) and 0600 (the files inside) — `mutate()` enforces.
- Lives inside the repo, not in `/tmp`, so it doesn't leak across container boundaries.

But: if the user pushes a commit before the doctor adds `.doctor/` to gitignore (race window of one run), the backup could be checked in. Mitigation:

<!-- noverify -->
```bash
# scaffold-workspace.sh should create .gitignore entry BEFORE the first run.
# The runtime's ensure_gitignore() runs unconditionally at run start, BEFORE
# mutate() is called for the first time:
ensure_gitignore_includes(repo_root, ".doctor/")
```

The `ensure_gitignore_includes` itself goes through `mutate()` — so the `.gitignore` change is backed up too (and undoable).

---

## Class 2 — Secrets in JSON output

Findings can include `evidence` blocks (file:line, hash, or raw bytes for diagnostic clarity). If a fixer reports `Found token "sk-abc..." in commits/HEAD~3:.env`, that token leaks into:

- stdout (visible to the agent's context cache for hours).
- `.doctor/runs/<run-id>/report.json` (gitignored but on disk).
- The agent's transcript / cass index.

Mitigations:

1. **`mutate()` redacts on write.** Every JSON serializer in the doctor module passes through a `redact()` function that runs a regex set against known-token patterns and replaces matches with `<redacted-credential-N-bytes>`:

   ```rust
   pub fn redact_secrets(s: &str) -> String {
       let patterns: [(&Regex, &str); 12] = [
           (&AWS_KEY, "<redacted-aws-key>"),
           (&STRIPE_KEY, "<redacted-stripe-key>"),
           (&GITHUB_PAT, "<redacted-github-pat>"),
           (&GENERIC_BEARER, "<redacted-bearer>"),
           (&JWT, "<redacted-jwt>"),
           // ... 7 more
       ];
       let mut out = s.to_string();
       for (re, replacement) in &patterns {
           out = re.replace_all(&out, *replacement).into_owned();
       }
       out
   }
   ```

   Backups bypass redaction (they need to be byte-identical for undo). Reports go through redaction.

2. **Findings cite hashes, not bytes.** Where possible, the evidence is `sha256:abc...` not the raw bytes. The agent doesn't need the bytes to act; the user can manually cross-reference if needed.

3. **The `--explain` flag warns when expanding might leak.** `<tool> doctor explain fm-credentials-leaked-into-commits` emits a warning to stderr before the expanded evidence: "this finding's evidence includes credential-like patterns; output may contain redacted markers."

---

## Class 3 — Doctor itself becoming a confused deputy

A malicious actor could try to weaponize the doctor:

- **Path traversal in `--only`.** `<tool> doctor --only "../../sensitive_path"` to make the doctor read outside the repo. `mutate()`'s `ensure_in_scope` rejects out-of-scope paths; the same check applies to detector inputs.
- **Symlink escape.** A planted symlink at `.beads/issues.jsonl → /etc/passwd` makes the doctor's read-or-mutate touch `/etc/passwd`. `mutate()` resolves symlinks and re-checks scope BEFORE writing. If the resolved path is out-of-scope, refuse with exit 4.
- **Crafted `actions.jsonl` to confuse `undo`.** A planted `actions.jsonl` with a `path: ../../../etc/passwd` would make `undo` restore `/etc/passwd` from a planted backup. `undo`'s strict mode checks every action's path is in `write_scopes`; rejects out-of-scope.

```rust
fn validate_undo_action(action: &ActionRecord, capabilities: &Capabilities) -> Result<()> {
    let path = canonicalize(&action.path)?;
    ensure_in_scope(capabilities, &path)?;
    let backup_path = run_dir.join("backups").join(&action.path);
    let backup_canonical = canonicalize(&backup_path)?;
    if !backup_canonical.starts_with(&run_dir.canonicalize()?) {
        bail!("backup path escapes run-dir");
    }
    Ok(())
}
```

---

## Defense in depth

| Defense layer | Implements | Catches |
|---------------|------------|---------|
| `mutate()::ensure_in_scope` | Compile-time-known `write_scopes`; runtime check | Path traversal, symlink escape |
| `mutate()::cmp_strict` after backup | Verify backup matches live file | TOCTOU between read and backup |
| `redact_secrets()` on JSON serialization | Regex set against 12 known token patterns | Credentials in stdout / report.json |
| `.gitignore::.doctor/` (auto-added) | Prevent backup commit | Accidental backup-leak via git |
| `chmod 0600` on backup files | mutate() enforces | Local-file-permission leak |
| `chmod 0700` on `.doctor/runs/` | mutate() enforces | Local-dir-permission leak |
| Strict `undo` mode (default) | hash + scope re-validation | Planted `actions.jsonl` exploit |
| Bundled trust anchor (installer pattern) | No network for verification | Supply-chain attack on signature |

---

## Threat model: in-scope and out-of-scope

**In scope:**
- Local-machine attackers with the user's privilege level.
- Race conditions during the doctor's run (TOCTOU).
- Malicious actors who control project state files (e.g., a compromised contributor's PR).

**Out of scope:**
- Root-level attackers (they own the machine; the doctor can't defend).
- Kernel exploits (the doctor's atomicity primitives presume `rename(2)` works as POSIX specifies).
- Side-channel attacks on the credential-redaction regex (an attacker who knows the regex set can craft a token that doesn't match — by design we accept some false negatives).

---

## Compliance considerations

For projects subject to compliance regimes (SOC 2, HIPAA, PCI):

- **Backups containing PHI/PII/cardholder data:** the doctor's verbatim-backup invariant means backups are AS sensitive as the original. The `.doctor/` directory inherits the project's compliance scope — gitignored, mode 0700, encrypted at rest if the project requires it.
- **Audit log retention:** `actions.jsonl` and `scorecard_history.jsonl` are append-only, content-hashed, and timestamped. They satisfy most "operational change log" requirements.
- **Right to erasure (GDPR):** if a user must be erased from project state, the doctor's backups STILL contain that user's data. Compliance-mode runs (`--retention-days N`) auto-prune `.doctor/runs/` directories older than N days via `<tool> doctor gc --before <date>`. The `gc` command requires `--yes` and an explicit cutoff (Axiom 14: bounded blast radius).

---

## Audit checklist (per release)

Before tagging a doctor release, run:

- [ ] `scripts/validate-doctor.sh` exits 0 (no destructive shell, no out-of-chokepoint writes).
- [ ] Every fixture's round-trip respects `chmod 0600` on backups.
- [ ] `redact_secrets()` regex coverage tested on canonical token corpus (Stripe, AWS, GitHub, JWT, generic bearer).
- [ ] `<tool> doctor capabilities --json::write_scopes` is a subset of the project's documented data paths.
- [ ] Symlink-escape test: plant `<scope>/inner → /etc/passwd`; doctor's read OR mutate refuses.
- [ ] `actions.jsonl` poisoning test: plant a malicious `actions.jsonl` with out-of-scope path; `undo --strict` refuses.
- [ ] `.gitignore` includes `.doctor/` after the first `<tool> doctor` invocation on a fresh repo.
