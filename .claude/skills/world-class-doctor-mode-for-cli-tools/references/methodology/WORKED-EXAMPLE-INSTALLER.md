# Worked Example — Applying the Skill to `acfs` (installer-pattern)

Third worked example, covering Pattern 5 (installer / provisioner) and Pattern 11 (installer-bootstrap chain). `acfs` (agentic-coding-flywheel-setup) is the example. Same bones as the other worked examples; the failure-mode space is what differs.

---

## Intake

```
Target: /dp/agentic_coding_flywheel_setup/
Binaries: acfs (the installer CLI)
Mode: add (no existing acfs doctor)
Operating location: worktree (worktree at sibling, branch doctor-mode-pass-1)
Patterns: 5 (installer), 11 (installer-bootstrap chain)
Triangulation: multi-model
CASS: deep
Online: offline-only (the installer's signature verification uses bundled
  trust anchor; vendor probes are opt-in via --online --verify-online)
Must-not-touch: tests/unit/test_doctor_fix.sh (pre-existing test file)
```

The project has a pre-existing `scripts/lib/doctor_fix_spec.md` from the `installer-workmanship` skill. That's our absorb-playbook target combined with `add`.

---

## Phase 0 — Bootstrap

CASS mining for "acfs" yields:
- 8 SYMPTOM (incl. "broken shell rc", "completion missing", "binary not in PATH")
- 6 MANUAL_FIX (the canonical "edit ~/.zshrc; reinstall completions; verify SHA")
- 4 INCIDENT (a couple of supply-chain near-misses)

The pre-existing `doctor_fix_spec.md` lists 12 named recovery scenarios. These BECOME the FM enumeration starting point.

---

## Phase 1 — Failure-Mode Inventory

Subsystems specific to this pattern:

- `external_artifacts` — installed binaries, completion scripts, man pages, systemd units.
- `userland_state` — shell rc files, XDG dirs.
- `permissions` — file modes, ownership.
- `secrets` — bundled trust anchor, signing keys.
- `signatures` — file integrity vs. manifest.

FMs (16 total):

```
fm-external-artifacts-binary-checksum-mismatch    P0   (supply-chain risk)
fm-external-artifacts-binary-missing               P1
fm-external-artifacts-completion-script-stale      P3
fm-external-artifacts-man-page-out-of-date         P3
fm-external-artifacts-systemd-unit-malformed       P1
fm-external-artifacts-orphaned-extra-file          P2
fm-external-artifacts-signature-invalid            P0   (supply-chain attack signal)
fm-userland-state-shell-rc-broken-source           P1
fm-userland-state-path-pollution                   P2
fm-userland-state-xdg-config-missing               P3
fm-permissions-binary-not-executable               P1
fm-permissions-config-too-permissive               P1
fm-permissions-install-as-root-running-as-user     P2
fm-secrets-trust-anchor-tampered                   P0   (supply-chain attack)
fm-secrets-credentials-stale                       P1
fm-installer-bootstrap-chain-broken                P1
```

The two P0 supply-chain FMs are the highest-priority because they detect malicious modifications.

---

## Phase 2 — Repair Specs

The trust manifest pattern (per [recipes/installer.md](../recipes/installer.md)) is central. The bundled manifest:

```jsonc
{
  "schema_version": "1.0",
  "trust_anchor_pubkey_pem": "-----BEGIN PUBLIC KEY-----\n...",
  "artifacts": [
    {
      "id": "a-binary-acfs",
      "install_path": "$XDG_BIN/acfs",
      "sha256": "deadbeef...",
      "mode": "0755",
      "signature": "base64-...",
      "purpose": "primary CLI"
    },
    {
      "id": "a-completion-acfs-bash",
      "install_path": "$XDG_DATA/bash-completion/completions/acfs",
      "sha256": "...",
      "mode": "0644",
      "signature": "...",
      "purpose": "bash completion"
    },
    ...
  ]
}
```

Sample spec for the headline P0:

```markdown
# RS-fm-external-artifacts-signature-invalid

severity: P0
currently_auto_detected: no
currently_auto_fixed: no (REFUSE; potential supply-chain)

## Detector (pure)
fn detect_signature_invalid(repo):
    for artifact in MANIFEST.artifacts:
        path = expand($XDG_BIN/acfs)
        if not path.exists(): continue
        bytes = read(path)
        sig_ok = verify_signature(bytes, artifact.signature, MANIFEST.trust_anchor_pubkey_pem)
        if not sig_ok:
            return Finding {
                id: "fm-external-artifacts-signature-invalid",
                severity: P0,
                evidence: {
                    artifact_id: artifact.id,
                    expected_sha256: artifact.sha256,
                    actual_sha256: sha256(bytes),
                    install_path: path,
                },
                remediation: {
                    command_or_instruction: "DO NOT REINSTALL. Investigate as a potential supply-chain attack. Quarantine via `<tool> doctor quarantine fm-external-artifacts-signature-invalid`",
                    auto_fixable: false,
                },
            }

## Fixer
REFUSE. The doctor will not auto-reinstall when the signature is invalid; that
could mask an attack. Manual quarantine via Op::Rename to a separate
quarantine directory; user investigates.

## Inverse
N/A (no mutation; only quarantine via mutate).

## Idempotence proof sketch
Pure read; signature verification is deterministic.

## Fixture spec
tests/doctor_fixtures/fm-external-artifacts-signature-invalid/:
- corrupt.sh: install acfs, then plant a corrupted binary at the install_path with WRONG sha
- assert.sh: assert exit 4; assert finding.evidence cites the install_path; assert binary is in quarantine
```

---

## Phase 3 — Synthesis

Synthesizer's dependency_graph notes:
- Trust anchor verification must precede any signature check (chain-of-trust).
- Binary checksum mismatch detection must run BEFORE binary missing (a tampered binary is more urgent than a missing one).
- Shell rc broken-source detector must run after path-pollution (path pollution might be the cause of broken sources).

Conflict matrix:
- `fm-permissions-install-as-root-running-as-user` and `fm-permissions-binary-not-executable` shouldn't co-execute auto-fix; the chmod may need elevated privileges.

Safety envelope (project-specific):
- Write scopes: `~/.local/bin/acfs`, `~/.config/acfs/`, `~/.local/share/bash-completion/completions/acfs`, `~/.config/systemd/user/acfs.service`.
- NEVER write to `/usr/`, `/etc/`, `/sbin/` (those are root-owned and out of scope).
- NEVER auto-rewrite `~/.zshrc` / `~/.bashrc` (user shell config).

---

## Phase 4 — Implementation

Bash-implemented (acfs is a bash CLI; per the discover-cli output). The `mutate.sh` chokepoint per [recipes/other-languages.md § Bash](../recipes/other-languages.md#bash):

```bash
# scripts/lib/mutate.sh
mutate() {
    local path="$1" op_kind="$2" content_path="${3:-}" mode="${4:-644}"
    local lock_path="${path}.doctor-lock"

    exec 9>"$lock_path"
    flock -n 9 || { echo '{"ok":false,"error":"lock_held"}'; return 1; }

    local before_hash="sha256:$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1 || echo)"
    ensure_in_scope "$path" || return 1

    local rel="${path#"$REPO_ROOT/"}"
    local backup="$RUN_DIR/backups/$rel"
    mkdir -p "$(dirname "$backup")"
    cp -a "$path" "$backup" 2>/dev/null || true
    cmp -s "$path" "$backup" 2>/dev/null || [ ! -e "$path" ] || return 1

    case "$op_kind" in
        WriteFile)
            local tmp; tmp=$(mktemp -p "$(dirname "$path")" .doctor.tmp.XXXXXX)
            cat "$content_path" > "$tmp"
            chmod "$mode" "$tmp"
            mv "$tmp" "$path"
            ;;
        Rename)
            local target="$3"
            mkdir -p "$(dirname "$target")"
            mv "$path" "$target"
            ;;
        Chmod)
            chmod "$3" "$path"
            ;;
    esac

    local after_hash="sha256:$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1)"

    exec 8>>"${ACTIONS_PATH}.lock"
    flock 8
    jq -nc --arg path "$rel" --arg op "$op_kind" \
        --arg before "$before_hash" --arg after "$after_hash" \
        --arg run_id "$RUN_ID" --arg fixer_id "$FIXER_ID" \
        '{path:$path,op:$op,before_hash:$before,after_hash:$after,run_id:$run_id,fixer_id:$fixer_id,ok:true}' \
        >> "$ACTIONS_PATH"
    sync
    flock -u 8

    echo "{\"ok\":true,\"before_hash\":\"$before_hash\",\"after_hash\":\"$after_hash\"}"
}
```

The doctor surface follows CLI-SURFACE.md verbatim. `acfs doctor verify-install` is the installer-specific subcommand.

---

## Phase 5 — Safety Harness

All five verifiers run for each of the ~8 mutating fixers (the rest are refuse-with-redirect for security reasons). Reversibility is straightforward (we backup before chmod, before reinstall, before completion-rewrite). Concurrency: the lock primitive uses `flock` on a sentinel file.

---

## Phase 6 — Scorecard

```
Aggregate score: 853
Per-FM medians (top 5):
  fm-external-artifacts-signature-invalid             900  (refuse-fix; clear evidence)
  fm-external-artifacts-binary-checksum-mismatch      890  (auto-reinstall from bundled)
  fm-external-artifacts-completion-script-stale       870
  fm-secrets-trust-anchor-tampered                    900  (refuse + escalate)
  fm-userland-state-shell-rc-broken-source            780  (refuse-fix; user must edit)
```

The doctor's value here is asymmetric: catching the supply-chain class is the highest-leverage outcome. The doctor's "score" doesn't reflect that asymmetry directly; the user's risk-tolerance does.

---

## Phase 7-10 differences

- **Phase 7 fresh-eyes** focuses on the signature verification path; multi-model triangulation runs against this code path specifically.
- **Phase 9 fixtures** include adversarial-fixture variants:
  - Plant a tampered binary with the right SHA but wrong signature (a forged-signature attempt).
  - Plant a tampered binary with wrong SHA AND right signature (claim from a malicious trust anchor; should fail signature against bundled).
- **Phase 10 cold-prober** specifically tests the supply-chain scenarios.

---

## What's different about installer doctors

- **Trust manifest is bundled at build time.** Not networked.
- **Signature verification is the high-stakes detector.** A false negative = supply-chain attack proceeds unnoticed.
- **Most fixers are reinstall-from-bundle.** The bundled artifact is the source of truth.
- **Some fixers are refuse-with-quarantine.** Suspicious binaries don't get auto-replaced — they're moved aside for forensic review.
- **The doctor has its own bootstrap concern.** What happens if the doctor binary itself is corrupted? See [recipes/installer.md § F.2](../recipes/installer.md).

---

## When to apply this exemplar

Use this template when:

- The CLI is primarily an installer (`acfs`, `dsr`, `rustup`, `nvm`, `pyenv`, `volta`).
- The CLI manages installed third-party tools (similar to `brew doctor` but more rigorous).
- Supply-chain integrity is in scope (most production-grade installers).

For a curl-pipe-bash one-liner installer that simply downloads + extracts, the surface is smaller — typically just Phase 1 (signature verify on download) and a tiny Phase 4 (the `<installer> doctor` reads the bundled manifest and verifies against installed bytes).
