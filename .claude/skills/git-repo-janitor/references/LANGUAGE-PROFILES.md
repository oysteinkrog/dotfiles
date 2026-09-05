# Language Profiles — Per-Language Junk Patterns

Each language ecosystem has characteristic junk that accumulates at the repo root. This reference catalogues them for the smell rules.

---

## Rust

**Common junk:**
- `target/` (usually `.gitignore`'d, sometimes leaks)
- `*.rs.bk` (rustfmt backup files)
- ELF binaries at root: `<binary-name>`, `<binary-name>_test` from `cargo build` outputs being moved/copied accidentally
- `.cargo/config.toml` overrides at repo root that should be local
- `perf.data`, `perf.data.old` (perf profiling outputs)
- `*.profraw`, `*.profdata` (coverage)
- `cov_*.out`, `lcov.info`, `tarpaulin-report.html`
- `criterion/` (benchmark output)
- `flamegraph.svg`, `flame*.svg`

**Path constants pattern (for reference rewrites):**
```rust
const SPEC_REL_PATH: &str = "X.md";
const X_PATH: &str = "X.md";
let path = workspace_root().join("X.md");
```
The skill's REFERENCE-GREP catches all three forms.

**Build command:** `cargo build --workspace`
**Test command:** `cargo test --workspace`
**Typecheck:** `cargo check --workspace`
**Lint:** `cargo clippy --workspace -- -D warnings`

---

## Python

**Common junk:**
- `__pycache__/` (usually ignored)
- `*.pyc`, `*.pyo`, `*.egg-info/`
- `dist/`, `build/`, `.tox/`, `.nox/`
- `.coverage`, `.coverage.*`, `htmlcov/`
- `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/`
- `.venv/`, `venv/`, `env/`
- `*.so` (compiled extensions; usually built artifacts)
- `nohup.out` from local dev runs
- Stray scratch scripts: `extract_*.py`, `analyze_*.py`, `migrate_*.py`, `fix_*.py`, `check_*.py`, `find_*.py`
- Jupyter checkpoints: `.ipynb_checkpoints/`

**Path constants pattern:**
```python
SPEC_PATH = "X.md"
SPEC_PATH = pathlib.Path("X.md")
SPEC_PATH = os.path.join(repo_root, "X.md")
```
plus markdown link forms in docstrings: `# See X.md for details`.

**Build:** `pip install .` or `pyproject-build` or `python -m build`
**Test:** `pytest` or `python -m pytest`
**Typecheck:** `mypy <package>` or `pyright`
**Lint:** `ruff check` or `flake8`

---

## Go

**Common junk:**
- `/<binary-name>` (the build output landing at repo root from `go build`)
- `<binary-name>_test` (also a typical build output)
- `*.test` (test binaries from `go test -c`)
- `*.out` (`go test -coverprofile=coverage.out` outputs)
- `coverage.txt`, `coverage_report.txt`
- `vendor/` (when used; usually intentional)
- `.golangci.yml.bck`, `.golangci.bck.yml` (backup config files — common drift)
- `*.patch` from `git format-patch` work

**Path constants pattern:**
```go
const PalettePath = "command_palette.md"
const SpecPath = "X.md"
filepath.Join(projectDir, "X.md")
os.WriteFile("X.md", ...)
```

**Build:** `go build ./...`
**Test:** `go test ./...`
**Typecheck:** `go vet ./...`
**Lint:** `golangci-lint run`

---

## TypeScript / JavaScript / Node

**Common junk:**
- `node_modules/` (usually ignored)
- `dist/`, `build/`, `.next/`, `.turbo/`, `out/`
- `*.tsbuildinfo`
- `coverage/`, `*.lcov`
- `.eslintcache`, `.parcel-cache/`
- `*.log` from local dev runs
- `*.snap.new`, `*.snap.tmp` (test snapshot drift)
- `jest_*.log`
- `npm-debug.log*`, `yarn-debug.log*`, `yarn-error.log*`
- Stray `.npmrc` (potential secret if has `_authToken`)
- `package-lock.json` AND `yarn.lock` AND `pnpm-lock.yaml` all present (only one should be tracked, depending on pkg manager)

**Path constants pattern:**
```typescript
const SPEC_PATH = 'X.md';
import path from 'path';
path.join(__dirname, 'X.md');
fs.readFileSync('X.md');
```
plus JSX/TSX `import` paths and Next.js `next/og` ImageResponse references.

**Build:** `npm run build` or `pnpm build` or `bun run build`
**Test:** `npm test` or `pnpm test` or `bun test` (or `pnpm playwright test` for E2E)
**Typecheck:** `tsc --noEmit` or `pnpm tsc --noEmit` or `bun tsc --noEmit`
**Lint:** `eslint .` or `pnpm lint`

---

## Cross-language

**Always-junk (regardless of language):**
- `nohup.out`, `*.out` (when matching nohup-format)
- `.DS_Store`, `Thumbs.db`, `Desktop.ini`
- `*.bak`, `*~`, `*.swp`, `*.swo`, `*.orig`, `*.rej`
- `*.bck.*`, `.<file>.bck` (backup variants)
- `*.patch` matching mailbox-format-patch first line
- ELF/PE/Mach-O binaries at non-`bin/` paths

**Always-protected:**
- `README.md`, `LICENSE*`, `CHANGELOG.md`
- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
- `.gitignore`, `.gitattributes`, `.gitmodules`
- `.editorconfig`

---

## Shell / Bash

**Common junk:**
- Top-level `*.sh` files that aren't installer / build / verify entrypoints
- Scratch `fix_*.sh`, `script_to_*.sh`, `migrate_*.sh`
- `temp_*.sh`, `test_*.sh` (when not under `tests/`)
- `nohup.out`

**Reference patterns:**
```bash
SPEC_PATH="X.md"
spec_path="X.md"
source ./scripts/X.sh
```

---

## Docker / Deployment

**Common junk:**
- `Dockerfile.bak`, `Dockerfile.old`
- `docker-compose.override.yml` (when actually local-only)
- `.docker/` (when accidentally tracked)
- `*.tar`, `*.tar.gz` from container saves
- `kustomize.yaml.tmp`

---

## Per-archetype: notable smell adjustments

| Archetype | Extra smells | Extra protected |
|-----------|--------------|-----------------|
| `single-rust-crate` | `target/`, `*.rs.bk`, `criterion/` | `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml`, `build.rs` |
| `polyglot-monorepo` | mix of all language smells | `Cargo.toml`, `package.json`, `pyproject.toml`, `go.mod` (whichever apply) |
| `claude-skill-repo` | `.skill-loop-progress.md`, intermediate `.md` from skill outputs | `.claude/skills/**`, `SKILL.md` files |
| `nextjs-saas` | `.next/`, `.turbo/`, `*.tsbuildinfo` | `next.config.*`, `tailwind.config.*`, `app/**`, `public/**`, `.env.example`, `vercel.json` |
| `python-package` | `__pycache__/`, `.coverage`, `.pytest_cache/` | `pyproject.toml`, `setup.cfg`, `src/<package>/**` |
| `go-cli` | `*.test`, `*.out`, `<binary-name>` at root | `go.mod`, `go.sum`, `cmd/**`, `internal/**` |

The Phase 1 archetype detection seeds the right combinations.
