# Recipe: Nix flake project

**When to use.** Target ships a `flake.nix` at the repo root, declaring `packages.<system>.<name>` for each binary. May also have `flake.lock`, `devShells`, and `apps`. Common in NixOS / nixpkgs-adjacent ecosystems.

This recipe parallels [bazel-monorepo.md](bazel-monorepo.md) but for Nix flakes. Key differences: hermetic builds via `nix run`, packages are pure (no PATH dependencies), and the doctor-binary lives in `packages.<system>.doctor` rather than as a build target.

---

## Discovery

`scripts/discover-cli.sh` should detect Nix flakes when it sees:
- `flake.nix` at the repo root
- (optionally) `flake.lock` confirming it's a real flake project, not just a `flake.nix` template

Binary candidates come from the flake's outputs:

```bash
nix flake show --json 2>/dev/null \
    | jq -r '.packages | to_entries[] | .value | to_entries[] | .key' \
    | sort -u
```

This yields the names registered under `packages.<system>` (e.g., `packages.x86_64-linux.my-cli`). Each is a binary candidate.

For `discover-cli.sh` to handle Nix, add a branch:

<!-- noverify -->
```bash
elif [ -f flake.nix ]; then
    language="nix"
    build_system="nix"
    if command -v nix >/dev/null 2>&1; then
        # Use `nix flake show` to enumerate packages. This requires
        # `experimental-features = nix-command flakes` in the user's nix config.
        while IFS= read -r pkg; do
            [ -n "$pkg" ] && binaries+=("$pkg")
        done < <(nix flake show --json 2>/dev/null \
            | jq -r '.packages | to_entries[] | .value | to_entries[] | .key' \
            | sort -u 2>/dev/null)
    fi
fi
```

(Implementing this is round-56 forward work; the recipe documents the pattern.)

---

## Where the doctor lives

The doctor is a regular flake package. Whichever language the project uses (Rust, Go, Python, etc.), build the doctor crate and expose it as `packages.<system>.doctor` in `flake.nix`:

```nix
{
  outputs = { self, nixpkgs, ... }: {
    packages.x86_64-linux.doctor = nixpkgs.legacyPackages.x86_64-linux.callPackage ./tools/doctor { };
    apps.x86_64-linux.doctor = {
      type = "app";
      program = "${self.packages.x86_64-linux.doctor}/bin/doctor";
    };
  };
}
```

Invocation:

```bash
nix run .#doctor                     # `apps.<system>.doctor` form
nix run .#doctor -- --fix
nix run .#doctor -- capabilities --json
nix run .#doctor -- --quick --json   # for pre-commit
```

`nix run` builds (if needed) and executes the binary. First-run latency depends on cache hit.

---

## Capabilities aggregation

For multi-binary flakes (server + CLI + test-runner), each binary may have its own doctor. The parent's `capabilities --json::sub_doctors[]` declares each:

```jsonc
{
  "sub_doctors": [
    {
      "name": "server",
      "binary": "nix run .#server -- doctor",
      "version": "0.4.7"
    },
    {
      "name": "cli",
      "binary": "nix run .#cli -- doctor",
      "version": "0.4.7"
    }
  ]
}
```

Per [monorepo-multi-cli.md](monorepo-multi-cli.md) the parent shell-invokes each sub-doctor; for Nix, that means `nix run .#<bin> -- doctor`.

---

## Hermeticity considerations

Nix builds are hermetic — the doctor binary has its own pinned dependency tree. This matters for the doctor's own behavior:

1. **`<tool> doctor health`** runs in a Nix-built binary; it cannot probe the user's `$PATH` to find related CLIs. If the doctor needs to invoke `git` or `jq`, declare them as `buildInputs`.
2. **The `target_sha` in `phase0_cli.json`** comes from `git rev-parse HEAD` — works fine inside a `nix develop` shell as long as `git` is in `devShells.<system>.<name>.buildInputs`.
3. **Pure mode (`nix run --pure`)** strips most env vars. The doctor's env-var-controlled flags (`NO_COLOR`, `<TOOL>_DOCTOR_LOG_LEVEL`) won't propagate. Document this in `capabilities --json::env_vars` with a note that `--pure` excludes them.

---

## DevShell integration

A `devShells.<system>.default` can provide the doctor on PATH for interactive use:

```nix
devShells.x86_64-linux.default = pkgs.mkShell {
  buildInputs = [ self.packages.x86_64-linux.doctor pkgs.jq pkgs.git ];
};
```

Then inside `nix develop`, `doctor --fix` works directly without `nix run`.

---

## Phase 8 integration (CI)

Nix CI typically uses `nix flake check` as the universal gate. Add a doctor step:

```yaml
- uses: cachix/install-nix-action@v25
- run: nix flake check
- run: nix run .#doctor -- --quick --json
- run: |
    rc=0
    nix run .#doctor -- --json > /tmp/run.json || rc=$?
    case "$rc" in 0|1) ;; *) exit "$rc";; esac
    # ... regression check via jq, per integration-wirer canonical
```

---

## Known sharp edges

1. **Cold-build latency.** `nix run .#doctor` from a clean store takes 30s-5min depending on dependency tree. Pre-warm in CI with `nix build .#doctor` before invoking `health`.
2. **`nix run` cannot pass-through stderr cleanly in some shells.** If the doctor's progress output is critical, prefer `nix develop -c doctor --fix` over `nix run`.
3. **Lock-file drift.** `flake.lock` updates are atomic; if the CI doctor builds against a different lock than the developer, conformance harness can flag the divergence.
4. **`flake.nix` with no doctor package.** `discover-cli.sh` correctly returns the package list; if `doctor` isn't there, mode = `add` and Phase 4 implementer adds the package definition + the source module.
5. **Bzlmod-style `inputs.nixpkgs.url`.** When pinning via flake inputs, the doctor binary's runtime deps are pinned too — meaning the doctor's `health` always exhibits the SAME version of `git`, `jq`, etc. Useful for reproducibility; less useful when the user expects PATH-based version matching with their dev env.

---

## Phase 4 implementer guidance

`scripts/scaffold-doctor.sh --language rust` (or go/python/typescript) emits the doctor module's source. Then HAND-WRITE the flake addition (`packages.<system>.doctor` and `apps.<system>.doctor`); no template currently. Future: a `--flake` flag on scaffold-doctor.sh could emit the flake.nix snippet.
