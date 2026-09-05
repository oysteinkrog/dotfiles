# Recipe — Installer / Provisioner CLI

Shape: a CLI whose primary job is to install other tools (or to provision a system). Examples: `acfs` (agentic-coding-flywheel-setup), `dsr` (Doodlestein Self-Releaser), fleet-provisioning installer CLIs, `installer-workmanship` outputs, `rustup`, `ggshield install`.

The doctor's role: verify the install integrity post-hoc, optionally re-install corrupted artifacts.

---

## The trust manifest

Every installer the doctor watches must publish a *trust manifest*: a list of what should be installed, where, with what checksum, and which signing key authorizes it. The manifest is bundled in the installer binary at build time:

```jsonc
// embedded as a resource (e.g., include_bytes! / //go:embed / package data)
{
  "schema_version": "1.0",
  "trust_anchor_pubkey_pem": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----",
  "artifacts": [
    {
      "id": "a-binary-acfs",
      "install_path": "$XDG_BIN/acfs",
      "sha256": "deadbeef...",
      "mode": "0755",
      "signature": "base64-signature-over-sha256",
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
    {
      "id": "a-systemd-service",
      "install_path": "$HOME/.config/systemd/user/acfs.service",
      "sha256": "...",
      "mode": "0644",
      "signature": "...",
      "purpose": "user-mode systemd unit"
    }
  ],
  "install_root_required": false,
  "supported_platforms": ["linux-x86_64", "linux-aarch64", "darwin-arm64"]
}
```

The doctor's `<tool> doctor verify-install` reads this manifest, checks every artifact's checksum and signature, and emits findings for each drift. It NEVER fetches keys from the network; the trust anchor is built-in.

---

## Failure-mode classes specific to installers

### `external_artifacts` subsystem

```
fm-external-artifacts-binary-checksum-mismatch
  detector: for each artifact, compute sha256(file at install_path);
            compare against manifest. If mismatch, P0.
  fixer: re-extract bundled artifact via mutate() with Op::WriteFile.
         Backup the existing (possibly tampered) file first.

fm-external-artifacts-binary-missing
  detector: artifact in manifest has no file at install_path. P1.
  fixer: install fresh via mutate(). Idempotent: if file exists with right
         hash, no-op.

fm-external-artifacts-permissions-too-permissive
  detector: stat install_path; mode > manifest.mode. P1.
  fixer: chmod via mutate() with Op::Chmod.

fm-external-artifacts-orphaned-extra-file
  detector: scan known install dirs; find files matching our naming pattern
            but NOT in the manifest. P2 (could be a leftover from an old
            version).
  fixer: refuse — could be the user's own customization. Manual remediation
         lists the orphans for review.

fm-external-artifacts-signature-invalid
  detector: signature fails verification against the bundled trust anchor.
            P0 (potential supply-chain compromise).
  fixer: refuse — DO NOT re-extract. Emit a HIGH-priority finding pointing
         to the supply-chain incident report. Per AGENTS.md, never delete;
         quarantine the suspect file via Op::Rename.
```

### `userland_state` subsystem (XDG dirs, shell rc files)

```
fm-userland-state-shell-rc-broken-source
  detector: scan ~/.bashrc / ~/.zshrc for `source "$HOME/.<tool>/init.sh"`
            references; if the referenced file doesn't exist, P1.
  fixer: depends — either re-create init.sh (if it should exist per manifest)
         or remove the source line (NOT auto, since it's user shell config).
         Default: refuse with manual remediation pointing at the offending
         file:line.

fm-userland-state-path-pollution
  detector: $PATH contains our install_path more than once, or contains
            multiple versions. P2.
  fixer: refuse — auto-rewriting shell rc files is too invasive. Manual
         remediation cites the offending lines and suggests the fix.
```

### `permissions` subsystem (cross-cutting)

```
fm-permissions-install-as-root-but-running-as-user
  detector: install_path is root-owned but the user can write there;
            the user is not root. P1 — likely sudo install side-effect.
  fixer: refuse — chown changes require sudo. Manual remediation.
```

---

## Surface additions

```text
<tool> doctor verify-install
    Walk the trust manifest. Verify checksums + signatures + permissions
    + presence. Read-only.

<tool> doctor verify-install --json
    Same, but as the standard --json shape.

<tool> doctor reinstall <artifact-id>
    Re-extract bundled artifact and replace the installed one.
    Routes through mutate() with backup. Idempotent.

<tool> doctor reinstall-all
    Reinstall every artifact whose checksum doesn't match.
    Equivalent to `verify-install` then `reinstall <id>` per finding.

<tool> doctor uninstall --dry-run
    Print the list of files that would be removed if uninstalled.
    UNINSTALL ITSELF IS NOT IMPLEMENTED HERE — per AGENTS.md no-delete,
    the doctor doesn't delete. Uninstallation is a separate command (the
    user's installer publishes its own uninstaller).
```

---

## The bundled-artifact discipline

The installer binary embeds *every* artifact it installs (using `include_bytes!` / `//go:embed` / package-data / resource files). Re-installation is always from-bundle; never network.

```rust
// Rust
const ACFS_BINARY: &[u8] = include_bytes!("../bundled/acfs");
const COMPLETION_BASH: &[u8] = include_bytes!("../bundled/completions/acfs.bash");
```

```go
// Go
//go:embed bundled/acfs
var acfsBinary []byte

//go:embed bundled/completions/acfs.bash
var completionBash []byte
```

```python
# Python
import importlib.resources as ires
acfs_binary = ires.files("acfs").joinpath("bundled/acfs").read_bytes()
```

The doctor's `mutate()` for an installer fixer:

```rust
fn fix_external_artifacts_binary_checksum_mismatch(
    repo: &Path, ctx: &MutateContext, artifact_id: &str,
) -> anyhow::Result<()> {
    let artifact = MANIFEST.lookup(artifact_id)?;
    let bundled = bundled_for(artifact_id)?;
    let install_path = expand_path(&artifact.install_path)?;
    let mode = u32::from_str_radix(&artifact.mode.trim_start_matches('0'), 8)?;
    mutate(ctx, &install_path, Op::WriteFile { content: bundled.to_vec(), mode })?;
    Ok(())
}
```

---

## Combining offline + online verification

By default, only the bundled signature is checked (offline; trust-on-first-install). With `--online --verify-online`:

1. Doctor fetches the *current* manifest from the release server.
2. Compares against the bundled manifest.
3. If newer, emits a finding suggesting the user upgrade.
4. Online manifest is signed by the same key; signature checked offline against the bundled trust anchor.

This catches "the user's installed version is N versions out of date" without trusting the release server's TLS endpoint blindly.

---

## Common pitfalls

- **Re-installing without backup.** The mutate() chokepoint enforces backup; trust the chokepoint.
- **Embedding the trust anchor in a separate file.** Don't — embed as bytes baked into the binary. A separate file can be tampered with; bytes in the binary cannot (without invalidating the binary's own signature, if it's signed).
- **Signature verification using a network call.** Never. The bundled trust anchor is the root of trust.
- **Reinstalling on EVERY checksum mismatch.** Sometimes the user has deliberately customized an installed config (e.g., a systemd unit). The detector classifies "is this our file with our hash?" but the fixer should refuse if there are signs of customization (e.g., timestamps newer than install). Add a "customization detection" predicate.
- **Touching files outside the trust manifest.** Forbidden by `write_scopes`. The doctor cannot install or reinstall anything not in the manifest.
- **Auto-rewriting shell rc files.** Shell rcs are user-owned configuration. Doctor detects, never auto-fixes. Manual remediation always.
