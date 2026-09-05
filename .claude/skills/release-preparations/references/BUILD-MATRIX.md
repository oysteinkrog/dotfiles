# Cross-Platform Build Matrix

## Build Hosts

| Host | Alias | Platform | Architecture | Connection | Toolchain |
|------|-------|----------|--------------|------------|-----------|
| trj | local | Linux | x86_64 | local | nightly rust, gcc |
| mmini | mac | macOS | aarch64 (ARM) | SSH via Tailscale | nightly rust |
| wlap | win | Windows | x86_64 | SSH via Tailscale | nightly rust, MSVC |

## Target Triples

| Platform | Target Triple | Binary Suffix | Archive Format |
|----------|--------------|---------------|----------------|
| Linux x86_64 | x86_64-unknown-linux-gnu | (none) | .tar.gz |
| Linux x86_64 musl | x86_64-unknown-linux-musl | (none) | .tar.gz |
| Linux aarch64 | aarch64-unknown-linux-gnu | (none) | .tar.gz |
| macOS ARM | aarch64-apple-darwin | (none) | .tar.gz |
| macOS Intel | x86_64-apple-darwin | (none) | .tar.gz |
| Windows x86_64 | x86_64-pc-windows-msvc | .exe | .zip |

## Asset Naming Convention

```
<tool>-v<version>-<target-triple>.<archive-ext>
```

Examples:
```
ntm-v1.5.2-x86_64-unknown-linux-gnu.tar.gz
ntm-v1.5.2-aarch64-apple-darwin.tar.gz
ntm-v1.5.2-x86_64-pc-windows-msvc.zip
```

## Build Commands by Host

### trj (Linux, local)

```bash
# Standard build
cargo build --release
strip target/release/<binary>

# Musl static build (if cross is installed)
cross build --release --target x86_64-unknown-linux-musl

# Package
tar czf <tool>-v<ver>-x86_64-unknown-linux-gnu.tar.gz -C target/release <binary>
```

### mmini (macOS, SSH)

```bash
# Sync code first
ssh mmini "cd /path/to/project && git pull"

# Build
ssh mmini "cd /path/to/project && cargo build --release"

# Copy artifact back
scp mmini:/path/to/project/target/release/<binary> ./artifacts/

# Package
tar czf <tool>-v<ver>-aarch64-apple-darwin.tar.gz -C artifacts <binary>
```

### wlap (Windows, SSH)

```bash
# Sync and build
ssh wlap "cd /path/to/project && git pull && cargo build --release"

# Copy artifact
scp wlap:/path/to/project/target/release/<binary>.exe ./artifacts/

# Package (zip)
cd artifacts && zip <tool>-v<ver>-x86_64-pc-windows-msvc.zip <binary>.exe
```

## Path Dependency Handling

Many workspace projects use `/dp/` or `/data/projects/` path dependencies. These don't resolve on remote hosts unless:

1. The dependency repos are synced to the remote host
2. The paths match (or are remapped)

### macOS Path Remapping

macOS uses `/Users/jemanuel/dp/` instead of `/data/projects/`. Options:
- Synthetic firmlink via `/etc/synthetic.conf` (requires reboot)
- Rsync the deps and sed-remap Cargo.toml paths
- Build locally if path deps exist

### When Path Deps Block Remote Builds

If `Cargo.toml` has `path = "/dp/..."` dependencies:

1. Check if the dep exists on the remote: `ssh host 'ls /dp/dep_name'`
2. If not, sync it: `rsync -az /dp/dep_name/ host:/dp/dep_name/`
3. If paths differ, build locally with dsr instead

## dsr Build Orchestration

```bash
# Single platform
dsr build <tool> --version <ver> --target x86_64-unknown-linux-gnu

# All platforms
dsr build <tool> --version <ver>

# Check what got built
ls ~/.local/state/dsr/artifacts/<tool>/<ver>/
```

## rch Remote Compilation

```bash
# Use rch for heavy compilation (offloads to fastest available worker)
rch exec -- cargo build --release

# Check which worker was used
rch status --workers --jobs
```

## Checksum Generation

```bash
# Generate SHA256SUMS for all artifacts
cd artifacts/
sha256sum *.tar.gz *.zip > SHA256SUMS.txt

# Verify
sha256sum -c SHA256SUMS.txt
```
