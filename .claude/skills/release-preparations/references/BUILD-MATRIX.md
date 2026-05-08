# Cross-Platform Build Matrix

## Build Hosts

Template for a typical three-host setup. Adapt hostnames and connection details to your environment.

| Host Alias | Platform | Architecture | Connection | Toolchain |
|------------|----------|--------------|------------|-----------|
| linux-host | Linux | x86_64 | local | nightly rust, gcc |
| mac-host | macOS | aarch64 (ARM) | SSH | nightly rust |
| win-host | Windows | x86_64 | SSH | nightly rust, MSVC |

> You may only have one or two of these. The matrix works with any subset.

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
mytool-v1.5.2-x86_64-unknown-linux-gnu.tar.gz
mytool-v1.5.2-aarch64-apple-darwin.tar.gz
mytool-v1.5.2-x86_64-pc-windows-msvc.zip
```

## Build Commands by Host

### linux-host (Linux, local)

```bash
# Standard build
cargo build --release
strip target/release/<binary>

# Musl static build (if cross is installed)
cross build --release --target x86_64-unknown-linux-musl

# Package
tar czf <tool>-v<ver>-x86_64-unknown-linux-gnu.tar.gz -C target/release <binary>
```

### mac-host (macOS, SSH)

```bash
# Sync code first
ssh mac-host "cd ~/projects/<project> && git pull"

# Build
ssh mac-host "cd ~/projects/<project> && cargo build --release"

# Copy artifact back
scp mac-host:~/projects/<project>/target/release/<binary> ./artifacts/

# Package
tar czf <tool>-v<ver>-aarch64-apple-darwin.tar.gz -C artifacts <binary>
```

### win-host (Windows, SSH)

```bash
# Sync and build
ssh win-host "cd ~/projects/<project> && git pull && cargo build --release"

# Copy artifact
scp win-host:~/projects/<project>/target/release/<binary>.exe ./artifacts/

# Package (zip)
cd artifacts && zip <tool>-v<ver>-x86_64-pc-windows-msvc.zip <binary>.exe
```

## Path Dependency Handling

Many workspace projects use absolute path dependencies in `Cargo.toml`. These don't resolve on remote hosts unless:

1. The dependency repos are synced to the remote host
2. The paths match (or are remapped)

### macOS Path Remapping

macOS home directories differ from Linux (e.g., `/Users/<you>/projects/` vs `/home/<you>/projects/`). Options:
- Symlink to create a matching path on the remote host
- Synthetic firmlink via `/etc/synthetic.conf` (macOS-specific, requires reboot)
- Rsync the deps and sed-remap `Cargo.toml` paths
- Build locally if path deps exist

### When Path Deps Block Remote Builds

If `Cargo.toml` has absolute `path = "/path/to/..."` dependencies:

1. Check if the dep exists on the remote: `ssh <host> 'ls /path/to/dep_name'`
2. If not, sync it: `rsync -az /path/to/dep_name/ <host>:/path/to/dep_name/`
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
