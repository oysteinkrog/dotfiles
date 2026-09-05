# Recipe: Cargo + npm hybrid project

**When to use.** Target combines a Rust crate with a JavaScript/TypeScript frontend, both contributing to the same final binary. Common shapes:

- **Tauri app** — Rust backend with `src-tauri/Cargo.toml`, JS frontend with `package.json`, `tauri.conf.json` ties them together.
- **Wasm-pack project** — Rust crate compiled to WebAssembly, consumed by an npm package.
- **`napi-rs` / `neon` native module** — Rust crate exposed to Node via FFI; published to npm.
- **Embedded JS in Rust binary** — Rust crate uses `include_str!` to embed a built JS bundle; npm builds the bundle, Cargo builds the binary.

This recipe parallels [monorepo-multi-cli.md](monorepo-multi-cli.md). Differs in: a SINGLE binary is produced (not multiple sub-CLIs), but TWO build systems contribute, so two distinct stale/drift FM classes apply.

---

## Discovery

`scripts/discover-cli.sh` should detect the hybrid case when it sees BOTH:
- `Cargo.toml` (any layout)
- `package.json` (any layout, but typically at root or under `web/`, `frontend/`, `ui/`)

Heuristic: if both files exist, set `language="rust+typescript"` (or `rust+npm`), pick the Rust binary as canonical, but track the JS package's manifest.

```bash
# In discover-cli.sh, after the Cargo branch and BEFORE the elif chain to
# package.json, add a check for the hybrid case:
if [ -f Cargo.toml ] && [ -f package.json ]; then
    # Already detected as Rust above; augment the JSON with a `frontend`
    # field listing the npm bin (or null).
    # ... see implementation note below
fi
```

(Implementing as a `discover-cli.sh` branch is round-56 forward work.)

---

## Where the doctor lives

The doctor is a Rust binary. The JS layer is data, not a separate program. Phase 4 implementer scaffolds in Rust:

```bash
scripts/scaffold-doctor.sh --target . --tool <repo> --language rust
```

The doctor's detectors include BOTH Rust-side and JS-side FMs. Detection paths walk both `target/` (cargo build output) and `node_modules/` / `dist/` (npm/build output).

---

## Hybrid-specific failure modes

For `references/corpus/known-fms.jsonl` (round-56 candidates):

- **`fm-hybrid-frontend-bundle-stale`** — the embedded JS bundle (e.g., `src/embedded.rs` includes `dist/main.js`) is OLDER than the JS source. Detector: compare `dist/main.js` mtime vs `package.json` mtime AND vs each `src/**/*.{ts,tsx,js,jsx}` mtime. Fixer: NOT auto-fixable (rebuild via `npm run build` is the user's choice; emit `manual_remediations` entry).
- **`fm-hybrid-package-lock-divergence`** — `package-lock.json` (or `pnpm-lock.yaml` / `bun.lockb`) hasn't been updated after `package.json` change. Detector: parse both; check declared dep set ⊆ resolved dep set. Fixer: NOT auto-fixable (running `npm install` is the user's choice).
- **`fm-hybrid-cargo-npm-version-skew`** — Tauri's `Cargo.toml::version` and `package.json::version` should match (or follow a documented pattern). Detector: parse both; compare. Fixer: NOT auto-fixable (versioning is policy).
- **`fm-hybrid-node-modules-corruption`** — `node_modules/` has been partially deleted or contains broken symlinks (common after `git checkout` between branches with different deps). Detector: compare `package.json` deps against `node_modules/<pkg>/package.json` presence. Fixer: NOT auto-fixable (requires `npm install`).
- **`fm-hybrid-tsconfig-out-of-sync`** — `tsconfig.json` references files in `dist/` that don't exist (i.e., dist was wiped). Detector: parse tsconfig `references` array; check existence. Fixer: depends on whether the missing path is the doctor's data (auto-rebuild) or a sibling project (manual).

---

## Capabilities aggregation

Single binary = single capabilities document. Don't use `sub_doctors[]`. The capabilities lists hybrid-specific detectors alongside the standard Rust-side FMs.

---

## Phase 5 safety harness considerations

The fixture for an FM like `fm-hybrid-frontend-bundle-stale` requires creating the stale state — touch the JS source after a successful build. The fixture's `corrupt.sh` MUST NOT actually rebuild; it just munges mtimes:

```bash
# tests/doctor_fixtures/fm-hybrid-frontend-bundle-stale/corrupt.sh
#!/usr/bin/env bash
set -euo pipefail
sandbox="$1"
# Set up: pretend build was done, then source was touched.
mkdir -p "$sandbox/dist" "$sandbox/src"
touch -d '1 hour ago' "$sandbox/dist/main.js"
touch -d 'now' "$sandbox/src/main.ts"
# package.json mtime in the middle.
touch -d '30 minutes ago' "$sandbox/package.json"
```

The detector then walks mtimes and reports the staleness. The fixer is NOT auto-fixable (per AGENTS.md); the doctor emits a `manual_remediations` entry directing the user to run `npm run build`.

---

## Phase 8 integration

Pre-commit + CI hooks invoke the Rust doctor only — the doctor itself decides whether the JS-side FMs are present. No separate JS-side hook is needed.

```yaml
- uses: actions-rs/toolchain@v1
  with: { toolchain: stable }
- uses: actions/setup-node@v4
  with: { node-version: 20 }
- run: cargo build --release
- run: npm install
- run: npm run build
- run: ./target/release/<tool> doctor --quick --json
```

---

## Known sharp edges

1. **Build-order sensitivity.** Some hybrid projects need npm-built JS BEFORE cargo-built Rust (when Rust embeds the JS). Doctor detectors must understand this order; running before `npm run build` would falsely flag stale-bundle.
2. **Multiple package managers.** Project may use npm, pnpm, bun, OR yarn. Detector should accept any lockfile (`package-lock.json`, `pnpm-lock.yaml`, `bun.lockb`, `yarn.lock`).
3. **Cross-platform path differences.** Tauri's `src-tauri/target/` differs in content per OS. Doctor's detectors should be platform-aware.
4. **Wasm-pack output churn.** `wasm-pack build` regenerates files with new sha-suffixes; the doctor's hash-based comparison must be tolerant.

---

## Phase 4 implementer guidance

Default to Rust scaffolding via `scripts/scaffold-doctor.sh --target . --tool <name> --language rust`. Then hand-add the JS-side detectors in a sibling module (e.g., `src/doctor/frontend.rs`) that the main `doctor.rs` orchestrates. Tests for hybrid FMs need fixtures that simulate both build outputs.
