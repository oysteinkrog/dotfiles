# Repo Archetypes

Each archetype has a known shape: which root-level files are expected, which destination dirs are conventional, what `protected_globs` should default to. The Phase 1 project-profiler subagent classifies the repo into one of these (or `unknown`, which prompts user confirmation).

Most archetypes were observed during the Apr-27 multi-repo cleanup; their per-archetype patterns are derived from real cleanups.

---

## `single-rust-crate`

A single Rust binary or library. `Cargo.toml` + `src/` + `tests/` at root.

| Aspect | Value |
|--------|-------|
| **Identifier** | `Cargo.toml` at root with no `[workspace]` section, OR with one `[[bin]]` and no `[workspace]` |
| **Test command** | `cargo test --workspace` (or `cargo test` if not a workspace member) |
| **Typecheck** | `cargo check --workspace` |
| **Lint** | `cargo clippy --workspace -- -D warnings` |
| **Build** | `cargo build --workspace --release` |
| **Format** | `cargo fmt` |

**Protected globs (defaults):**
```
Cargo.toml
Cargo.lock
rust-toolchain.toml
rust-toolchain
build.rs
deny.toml
.ubsignore
.rchignore
src/**
tests/**
benches/**
examples/**
.cargo/
README.md
LICENSE*
AGENTS.md
CHANGELOG.md
```

**Conventional destinations:**
- `docs/planning/` — long-form planning markdown
- `docs/operations/` — runbooks, recovery docs
- `docs/reference/` — architecture summaries, search-pattern indexes
- `docs/progress/` — per-bead progress reports
- `scripts/` — deploy / verify / build helpers (not in `src/bin/`)
- `tools/` — auxiliary tools that aren't part of the main crate

**Common smells:**
- `target/` accidentally tracked (rare; usually `.gitignore`'d)
- `*.rs.bk` (rustfmt backup files)
- ELF binaries at root (e.g., `bv_profile`, `bv_test`, `optzst`)
- Dev SQLite DBs at root (e.g., `storage.sqlite3`)
- `findings.jsonl`, `ubs_*.jsonl` (tool outputs)
- `nohup.out`

---

## `polyglot-monorepo`

Multiple language ecosystems sharing a tree. Often a `crates/` Rust workspace + a `packages/` JS workspace + a top-level `package.json`. The frankensqlite-style.

| Aspect | Value |
|--------|-------|
| **Identifier** | `Cargo.toml` AND `package.json` AND `pyproject.toml` (any 2+) at root, OR multiple lang-specific subdirs (`crates/`, `packages/`, `apps/`, `services/`) |
| **Test command** | Multi-step (each language's command); the profiler enumerates them |
| **Build command** | Often a `Makefile` or `package.json` `build` script that orchestrates sub-builds |

**Protected globs (defaults):**
```
Cargo.toml
Cargo.lock
package.json
package-lock.json
pnpm-lock.yaml
yarn.lock
bun.lockb
pyproject.toml
uv.lock
poetry.lock
go.mod
go.sum
Makefile
Dockerfile
docker-compose.yml
compose.yaml
.dockerignore
deny.toml
rust-toolchain.toml
tsconfig.base.json
playwright.config.ts
.cargo/
crates/**
packages/**
apps/**
services/**
tools/**
docs/**
README.md
LICENSE*
AGENTS.md
```

**Conventional destinations:**
- `docs/planning/`
- `docs/contracts/` — TOML contract specs (frankensqlite pattern; but check: are they referenced by hardcoded paths? then DEFER the move)
- `docs/progress/`
- `docs/operations/`
- `docs/reference/`
- `scripts/` (or `scripts/<area>/`)
- `e2e/` — top-level E2E test orchestration scripts

**Common smells (from frankensqlite Apr-27):**
- 16 long-form `*PLAN*.md`, `*ARCHITECTURE*.md`, `*SPEC*.md` at root
- 27 `progress_bd-*.md` per-bead reports
- 8 `*_viz.py` visualization pipeline scripts
- 3 `deploy*.sh` Cloudflare Pages deploy scripts
- TOML contracts at root with hardcoded paths in 20+ Rust files (the cat C deferral case)
- Per-LLM PLAN cluster (`__GPT.md`, `__OPUS.md`, `__GEMINI.md`)

---

## `claude-skill-repo`

A repo whose primary content is `.claude/skills/<name>/SKILL.md` files. Either a private skill collection or the canonical skill registry.

| Aspect | Value |
|--------|-------|
| **Identifier** | `.claude/skills/` directory exists with multiple skill subdirs (each containing `SKILL.md`) |
| **Test command** | Often a `scripts/check-skills.sh` validator |
| **Build command** | Often `scripts/build_skill_pack.sh` or similar |

**Protected globs (defaults):**
```
.claude/**
README.md
LICENSE*
AGENTS.md
.gitignore
.gitattributes
package.json  (if a Next.js companion site)
pnpm-lock.yaml  (etc.)
docs/**
data/**          (if the skill-pack registry has data files)
src/**
public/**
```

**Conventional destinations:**
- `docs/planning/`
- `docs/internal/` — internal/agent-only docs
- `scripts/`

**Common smells:**
- `.skill-loop-progress.md` from skill iterations leaking
- `MODES_OF_REASONING_REPORT_AND_ANALYSIS_OF_PROJECT.md` and similar skill-output markdown
- Per-skill `BENCHMARK_*.md` clusters
- ad-hoc `extract_*.py`, `analyze_*.py` scratch scripts

---

## `nextjs-saas`

Next.js 13+ App Router app, often with Supabase / Drizzle / Stripe.

| Aspect | Value |
|--------|-------|
| **Identifier** | `next.config.js` or `next.config.ts` or `next.config.mjs` at root, AND `app/` directory |
| **Test command** | `pnpm test` or `bun test` (E2E often `pnpm playwright test`) |
| **Typecheck** | `pnpm tsc --noEmit` or `bun tsc --noEmit` |
| **Build** | `pnpm build` or `bun run build` |

**Protected globs (defaults):**
```
package.json
package-lock.json
pnpm-lock.yaml
bun.lockb
next.config.*
tailwind.config.*
postcss.config.*
tsconfig.json
playwright.config.*
middleware.ts
app/**
pages/**
components/**
lib/**
public/**
styles/**
prisma/**
supabase/**
drizzle/**
e2e/**
.env.example
.env.template
vercel.json
README.md
LICENSE*
AGENTS.md
```

**Conventional destinations:**
- `docs/`
- `docs/architecture/`
- `docs/launch/`
- `scripts/`

**Common smells:**
- `nohup.out` from local dev runs
- `.next/` (usually `.gitignore`'d, but sometimes leaks)
- `*.log` from middleware
- Stray Stripe webhook test outputs
- `*.snap.new` from Playwright

---

## `python-package`

Single Python package. `pyproject.toml` + `src/<package>/` or top-level `<package>/`.

| Aspect | Value |
|--------|-------|
| **Identifier** | `pyproject.toml` at root, no `Cargo.toml`, no top-level `package.json` (or only as a frontend companion) |
| **Test command** | `pytest` or `python -m pytest` |
| **Typecheck** | `mypy <package>` or `pyright` |
| **Lint** | `ruff check` or `flake8` or `pylint` |

**Protected globs (defaults):**
```
pyproject.toml
setup.cfg
setup.py
requirements*.txt
Pipfile
Pipfile.lock
poetry.lock
uv.lock
hatch.toml
MANIFEST.in
.python-version
src/**
tests/**
docs/**
README.md
LICENSE*
AGENTS.md
CHANGELOG.md
```

**Common smells:**
- `__pycache__/` (usually ignored)
- `.coverage`, `htmlcov/`
- `nohup.out`
- ad-hoc `extract_*.py`, `fix_*.py`, `migrate_*.py` at root
- `dist/`, `build/`, `*.egg-info/` (when not ignored)

---

## `go-cli`

Go-language CLI tool. `go.mod` + `cmd/<name>/` or single-package root.

| Aspect | Value |
|--------|-------|
| **Identifier** | `go.mod` at root |
| **Test command** | `go test ./...` |
| **Typecheck** | `go vet ./...` |
| **Lint** | `golangci-lint run` |
| **Build** | `go build ./...` or `make build` |

**Protected globs (defaults):**
```
go.mod
go.sum
Makefile
.golangci.yml
.goreleaser.yaml
cmd/**
internal/**
pkg/**
docs/**
tests/**
README.md
LICENSE*
AGENTS.md
```

**Common smells (from beads_viewer + ntm Apr-27):**
- ELF binaries at root (`bv_profile`, `bv_test`)
- `coverage_report.txt`
- `.golangci.bck.yml` (backup file)
- `*.patch` blobs
- Per-LLM PLAN cluster

---

## `pypi-publishable-cli`

Python package designed to be installed via pip + run as CLI.

Same as `python-package` plus:

**Protected globs (additional):**
```
install.sh
install.ps1
*.spec  (when using PyInstaller)
.npmrc.example
```

---

## `mixed-rust-and-frontend`

Rust backend + JS/TS frontend in the same repo.

| Aspect | Value |
|--------|-------|
| **Identifier** | `Cargo.toml` at root AND a `frontend/`, `web/`, or `client/` subdir with `package.json` |

**Protected globs:** union of `single-rust-crate` + `nextjs-saas` (or generic `web/`).

**Common smells:** dual lint configs that disagree, stale `.next/` if frontend is deployed separately.

---

## `unknown`

Default when no archetype matches. The Phase 1 profiler asks the user to confirm or override.

In `unknown` mode, the protected_globs default to:

```
README.md
LICENSE*
AGENTS.md
CHANGELOG.md
.gitignore
.gitattributes
.gitmodules
```

— the smallest universal set. Everything else needs explicit confirmation.

---

## Archetype-shaped destinations cheat-sheet

| Archetype | docs/ | docs/planning/ | docs/progress/ | scripts/ | tools/ | tests/ |
|-----------|-------|----------------|----------------|----------|--------|--------|
| single-rust-crate | conventional | conventional | rare | conventional | rare | always |
| polyglot-monorepo | always | always | conventional | always | conventional | per-subtree |
| claude-skill-repo | always | always | rare | always | rare | rare |
| nextjs-saas | conventional | conventional | rare | conventional | rare | `e2e/` more common |
| python-package | always | conventional | rare | conventional | rare | always |
| go-cli | conventional | conventional | rare | conventional | rare | conventional |

---

## Detecting the archetype (Phase 1 logic)

```python
# Pseudocode
def detect_archetype(repo_root):
    files = top_level_files(repo_root)

    has_cargo = "Cargo.toml" in files
    has_pkg_json = "package.json" in files
    has_pyproject = "pyproject.toml" in files
    has_go_mod = "go.mod" in files
    has_skills = exists(repo_root / ".claude" / "skills")
    has_next_config = any(f.startswith("next.config.") for f in files)

    if has_skills:
        return "claude-skill-repo"
    if sum([has_cargo, has_pkg_json, has_pyproject, has_go_mod]) >= 2:
        return "polyglot-monorepo"
    if has_next_config:
        return "nextjs-saas"
    if has_cargo:
        cargo = read_toml(repo_root / "Cargo.toml")
        if "workspace" in cargo and "members" in cargo["workspace"]:
            # Workspace; could still be single-language
            if has_pkg_json:
                return "polyglot-monorepo"
            return "single-rust-crate"  # workspace is one Rust archetype
        return "single-rust-crate"
    if has_pyproject:
        return "python-package"  # may upgrade to pypi-publishable-cli on closer look
    if has_go_mod:
        return "go-cli"
    return "unknown"
```

The detection is deliberately conservative. The user always sees the detected archetype at Phase 0 and can override.
