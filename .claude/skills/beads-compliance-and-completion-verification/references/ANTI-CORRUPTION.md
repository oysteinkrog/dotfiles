# ANTI-CORRUPTION.md — Detect Tampering With The Audit

<!-- TOC: Threat model | rubric_sha256 chain | git log integrity | manifest checksums | Signed commits | Detection script | What to do if compromised -->

> The audit dir is git-tracked, locally-stored, and may be human-editable. If an attacker (or an "overly helpful" agent) tampers with prior audit artifacts, future audits could produce false confidence. Anti-corruption defenses make tampering detectable.

---

## Threat model

| Threat | Damage |
|--------|--------|
| Adversary edits a prior pass's scorecard.md to inflate score | Trends.md shows fake improvement; convergence becomes meaningless |
| Adversary tunes rubric.md mid-pass to relax thresholds | False-closed flags disappear without real fixes |
| Agent (well-intentioned) edits passes/<UTC>/beads/<id>/show.json to fix a typo | Subsequent audits compare against modified history; deltas look weird |
| Adversary deletes prior pass dirs to "clean up" | History gone; convergence undefined |
| Adversary swaps the audit dir with a doctored one | Identity confusion |
| Compromised CI runs the audit with a modified scorer subagent | Systematic generosity bias |

The threat is rarely *malicious* — usually it's "I edited this to fix something" without realizing the audit dir's integrity matters. Either way, detection is the first defense.

---

## Defense layer 1 — `rubric_sha256` pinned in every manifest

Every pass's `manifest.json` records the SHA256 of `rubric.md` at pass time:

```json
{
  "pass_id": "2026-05-06T14-00-00Z",
  "rubric_sha256": "9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1908f7e6d5c4b3a2918f0e9d8c7b"
}
```

If `rubric.md` is later modified, `sha256sum rubric.md` won't match the recorded hash. `convergence-check.py` detects this:

```python
cur_rubric = rubric_sha(audit_dir)
prior_rubric_hash = json.loads((prior_pass / "manifest.json").read_text()).get("rubric_sha256")
if prior_rubric_hash and prior_rubric_hash != cur_rubric:
    out["rubric_changed_since_prior_pass"] = True
    out["rubric_changed_reason"] = "rubric.md SHA changed between passes"
```

The flag surfaces in `convergence.json` so anyone reading it knows the rubric drifted.

---

## Defense layer 2 — git log integrity

Every pass commits to the audit dir's git repo. Tampering with prior commits requires force-push, which is detectable:

```bash
# Check git log for force-pushes (rewrites) — reflog tells the story
git -C <audit-dir> reflog | grep 'reset\|force\|amend' | head -20

# Check that every commit message follows the standard format
git -C <audit-dir> log --format='%s' \
  | grep -v '^audit pass [0-9-]*T[0-9-]*Z:' | head
# If any commit has a non-standard message → human / agent edited the dir
```

Add to a periodic check (e.g., as part of bootstrap or tripwire):

```bash
# scripts/integrity-check.sh
LATEST_HASH=$(git -C <audit-dir> rev-parse HEAD)
echo "$LATEST_HASH" > <audit-dir>/.last_known_hash
# Next run:
if [ "$(cat <audit-dir>/.last_known_hash)" != "$(git -C <audit-dir> rev-parse HEAD~1)" ]; then
  echo "WARN: audit dir HEAD jumped beyond +1 commit since last check" >&2
fi
```

---

## Defense layer 3 — manifest content checksums

Each pass's manifest can record SHAs of every artifact in the pass:

```bash
# At end of pass, compute artifact-tree checksum
find passes/<UTC>/ -type f -not -path '*/raw/*' -exec sha256sum {} \; \
  | sort | sha256sum | awk '{print $1}'
```

This is added to `manifest.json#artifact_tree_sha256`. If a single scorecard is edited later, this checksum changes.

```bash
# Verify
RECORDED=$(jq -r .artifact_tree_sha256 passes/<UTC>/manifest.json)
ACTUAL=$(find passes/<UTC>/ -type f -not -path '*/raw/*' -exec sha256sum {} \; | sort | sha256sum | awk '{print $1}')
if [ "$RECORDED" != "$ACTUAL" ]; then
  echo "TAMPERING DETECTED: pass <UTC> artifacts changed since pass committed" >&2
fi
```

---

## Defense layer 4 — signed commits

For high-stakes audits (regulator-bound), sign every audit commit with a key only the audit infrastructure has:

```bash
# bootstrap signs commits
git -C <audit-dir> config commit.gpgsign true
git -C <audit-dir> config user.signingkey <audit-key-id>

# Verify
git -C <audit-dir> log --show-signature | head -20
# Every commit should show "Good signature from <audit-key-id>"
```

The audit key is stored in:
- A hardware HSM (gold standard).
- A CI-only env var (`AUDIT_GPG_KEY`).
- Per-developer GPG key on a yubikey (if humans run the audit).

If a commit is unsigned or signed with the wrong key, integrity-check rejects it.

---

## Defense layer 5 — append-only audit log

Beyond git history, maintain a separate append-only log of who did what:

```bash
# At every audit operation
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) ${USER:-agent} ${OPERATION} ${PASS_ID} ${ARGS}" \
  >> <audit-dir>/AUDIT_LOG.jsonl
```

The log is written but not edited — entries are append-only. If a human / agent removes lines from the log, the gaps are detectable by `wc -l` over time.

For extra paranoia: ship the log to an external append-only system (S3 with object lock, AWS CloudTrail equivalent).

---

## Detection script

`scripts/integrity-check.sh` (sketch):

```bash
#!/usr/bin/env bash
# integrity-check.sh — verify audit dir hasn't been tampered with.
set -euo pipefail
AUDIT_DIR="${1:?audit dir}"

ISSUES=()

# 1. rubric_sha256 still matches rubric.md
RUBRIC_RECORDED=$(jq -r .rubric_sha256 "$AUDIT_DIR/manifest.json" 2>/dev/null)
RUBRIC_ACTUAL=$(sha256sum "$AUDIT_DIR/rubric.md" 2>/dev/null | awk '{print $1}')
if [ "$RUBRIC_RECORDED" != "$RUBRIC_ACTUAL" ]; then
  ISSUES+=("rubric.md SHA mismatch: recorded=$RUBRIC_RECORDED actual=$RUBRIC_ACTUAL")
fi

# 2. Git log: every commit follows audit-pass format
NON_STANDARD=$(git -C "$AUDIT_DIR" log --format='%s' \
  | grep -v -E '^(audit pass|audit: remediation|sync|init)' | head -5)
[ -n "$NON_STANDARD" ] && ISSUES+=("Non-standard commit messages: $NON_STANDARD")

# 3. Per-pass artifact_tree_sha256 matches
for pass_dir in "$AUDIT_DIR"/passes/*/; do
  RECORDED=$(jq -r '.artifact_tree_sha256 // empty' "$pass_dir/manifest.json")
  [ -z "$RECORDED" ] && continue   # older passes may not have it
  ACTUAL=$(find "$pass_dir" -type f -not -path '*/raw/*' -exec sha256sum {} \; \
           | sort | sha256sum | awk '{print $1}')
  if [ "$RECORDED" != "$ACTUAL" ]; then
    ISSUES+=("Pass $(basename "$pass_dir") artifact tree SHA mismatch")
  fi
done

# 4. Audit log has no gaps (NN entries continuous)
if [ -f "$AUDIT_DIR/AUDIT_LOG.jsonl" ]; then
  LOG_LINES=$(wc -l < "$AUDIT_DIR/AUDIT_LOG.jsonl")
  EXPECTED=$(ls -1 "$AUDIT_DIR/passes/" | wc -l)
  # Each pass produces ~10 log lines minimum
  [ "$LOG_LINES" -lt $((EXPECTED * 5)) ] && ISSUES+=("AUDIT_LOG suspiciously short: $LOG_LINES lines for $EXPECTED passes")
fi

if [ "${#ISSUES[@]}" -gt 0 ]; then
  echo "TAMPERING SUSPECTED:" >&2
  printf '  - %s\n' "${ISSUES[@]}" >&2
  exit 1
fi

echo "Integrity check: PASS"
```

Run periodically (cron / tripwire). If it fails, follow "What to do if compromised" below.

---

## What to do if tampering is detected

1. **Don't immediately re-run the audit.** Fresh runs may overwrite tamper signals.
2. **Snapshot the audit dir** to a forensic location (`cp -r <audit-dir> <audit-dir>.forensic.<UTC>`).
3. **Identify the scope.** Which artifacts changed? Use `git log --all --oneline` and `git diff` against last-known-good HEAD.
4. **Roll back** to the last commit that passes integrity check.
5. **Investigate.** Audit log + reflog tell who/what/when.
6. **Remediate the source.** If a human / agent introduced the tampering, address the access path.
7. **Re-run the next pass** from the rolled-back state. Convergence will be off by one pass; the next-next pass is the new baseline.

If tampering can't be ruled out and forensic recovery isn't conclusive: **abandon the audit dir** and re-bootstrap. The new audit dir starts at Pass 1 again. This is expensive but trustworthy.

---

## Operational hardening

For high-trust environments:

| Practice | Effect |
|----------|--------|
| Audit dir on a write-once filesystem (S3 object lock) | Tampering physically impossible |
| Audit dir behind an MCP server with role-based access | Auditable access trail |
| Audit infrastructure as a separate non-root user | Limits write surface |
| `chattr +a AUDIT_LOG.jsonl` (Linux append-only attribute) | OS-level append-only enforcement |
| Sign audit commits with HSM | Even if filesystem is rooted, signatures detect post-hoc edits |
| Mirror audit dir to a remote read-only replica | Tamper-detection across two sources |

---

## Red-team exercise

Periodically (annually for high-stakes), red-team the audit:

1. Have a privileged user / agent make a subtle edit to a prior pass's scorecard.
2. Verify the integrity-check detects it.
3. Verify no automated alert was suppressed.
4. Verify the rollback procedure works.

If any step fails, harden that layer.

---

## Anti-patterns

- Trusting `git log` alone (force-push erases history).
- Trusting integrity-check output without verifying its own integrity (the integrity-check script itself can be tampered with).
- Storing rubric_sha256 in a file inside the audit dir (the same place an attacker would tamper).
- Append-only logs that aren't actually append-only (no chattr, no S3 lock).
- One-pass paranoia: if you don't run integrity-check periodically, the defenses are theatrical.

---

## Cost-benefit

For most projects, layers 1-2 (rubric SHA + git log integrity) are sufficient. They cost essentially nothing.

Layers 3-5 (artifact tree checksums, signed commits, append-only log) are valuable for:
- Compliance / regulatory audits (SOC2 evidence trail).
- Multi-team projects where humans edit the audit dir.
- Audit dirs hosted in shared cloud storage.

For tripwire-mode-only single-machine setups, layer 1 is enough.