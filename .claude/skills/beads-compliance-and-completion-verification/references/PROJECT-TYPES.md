# PROJECT-TYPES.md — Per-Language / Per-Framework Defaults

<!-- TOC: Rust workspace | TypeScript / Next.js | Python | Go | Polyglot / monorepo | discover-stack.sh | Project hints in rubric.md -->

The verification commands in `compliance-verifier.md` are language-agnostic. This file provides the **concrete defaults** per language so the auditor doesn't have to invent commands for every project.

> **Detection.** `scripts/discover-stack.sh` (analogous to the saas-billing skill's discover-stack) inspects the project root and emits `phase0_stack.json` with the detected language, runner, build tool, and CI host. Most defaults flow from that detection.

---

## Rust workspace

### Detection signals

- `Cargo.toml` at root (workspace OR single crate).
- `rust-toolchain.toml` for pinned toolchain.
- `cargo` available in PATH.

### Default commands

| Test type | Command |
|-----------|---------|
| Unit / integration | `cargo test --workspace -- --nocapture <test_name>` |
| Build | `cargo build --workspace --release` |
| Lint | `cargo clippy --workspace --all-targets -- -D warnings` |
| Fuzz | `cargo +nightly fuzz run <target> -- -max_total_time=<secs>` |
| Bench | `cargo bench --workspace --bench <bench_name>` |
| Coverage | `cargo llvm-cov --workspace --json --summary-only` |
| Property | `cargo test --workspace -- --test-threads=1 <prop_test_name>` (proptest harness) |
| Conformance | per project — typically a `tests/conformance/` runner; check `Cargo.toml#dev-dependencies` |
| Golden | `cargo insta test` then `cargo insta review` (insta crate) OR `git diff` over `tests/snapshots/` |
| E2E | per project — typically a `tests/e2e/` runner OR `scripts/e2e_test.sh` (audit beads_rust convention) |

### Coverage scoping (cargo-llvm-cov)

```bash
cargo llvm-cov --workspace --json > raw/coverage.json
# Filter to only the bead's files:
jq --arg bead_files "$(jq -r '.checks[].citations[].path' evidence.json | sort -u | tr '\n' ',')" \
   '.data[0].files | map(select(.filename as $f | $bead_files | contains($f)))' \
   raw/coverage.json > raw/coverage_bead_only.json
```

### Common Rust-specific theater patterns

- `unimplemented!()` in trait impls (very common).
- `todo!()` macros.
- `#[ignore]` on tests added "for later".
- `#[cfg(test)]` mock implementations of traits that override prod behavior.
- `unsafe { std::mem::zeroed() }` returning a default for a missing impl.

### Project hint: AGENTS.md conventions

Many Rust projects in this fleet (beads_rust, dcg, frankensqlite) have AGENTS.md with conventions like "Always run UBS before commit". The compliance-verifier should respect these — running `ubs <changed-files>` after the test suite as an additional Phase 4 check.

---

## TypeScript / Next.js

### Detection signals

- `package.json` with `"next"` dep OR `tsconfig.json`.
- `pnpm` / `bun` / `npm` lockfile.

### Default commands

| Test type | Command |
|-----------|---------|
| Unit | `bunx vitest run <test-path>` (or `npx`) |
| Integration | `bunx vitest run --pool=forks <integration-pattern>` |
| E2E | `bunx playwright test <test-name>` |
| Build | `bunx next build` |
| Lint | `bunx eslint . --max-warnings=0` |
| Type-check | `bunx tsc --noEmit` |
| Coverage | `bunx vitest run --coverage` |
| Golden (snapshot) | `bunx jest --ci` OR `bunx vitest run --no-update` for snapshot diffs |
| Conformance | per project — typically Pact / Hurl / Dredd against an OpenAPI spec |
| Fuzz | `bunx jazzer.js fuzz <target>` (for jazzer.js setups; otherwise rare in TS) |

### Coverage scoping (vitest + c8)

```bash
bunx vitest run --coverage --coverage.reporter=json
# Filter to bead's files via the v8 coverage JSON
jq --slurpfile evidence evidence.json '
  .[] | select(.url as $u | $evidence[0].checks
    | map(.citations[].path) | flatten | any($u | endswith("/" + .)))
' coverage/coverage-final.json > raw/coverage_bead_only.json
```

### Common TS-specific theater patterns

- `// @ts-ignore` over a real type error.
- `as any` casts hiding contract violations.
- `jest.mock(...)` of the very service under test.
- `it.todo(...)` instead of an actual test.
- API route returning `NextResponse.json({ error: 'Not Implemented' }, { status: 501 })`.
- Server actions that `'use server'` but the implementation is a no-op.
- Drizzle/Prisma migrations that run forward but have no `down`.

### Next.js-specific checks

- For features touching App Router: confirm the route file exists at the expected `app/<path>/page.tsx`.
- For server actions: confirm `'use server'` is at file top.
- For middleware changes: confirm `middleware.ts` exports `config.matcher`.
- For RSC components: confirm no `'use client'` was accidentally added (perf regression).

---

## Python

### Detection signals

- `pyproject.toml` OR `setup.py` OR `requirements.txt`.
- `pytest.ini` / `conftest.py` for pytest.

### Default commands

| Test type | Command |
|-----------|---------|
| Unit | `pytest <test-path> -v` |
| Integration | `pytest tests/integration/ -v --no-header` |
| E2E | `pytest tests/e2e/ -v` (or project-specific runner) |
| Build | `python -m build` (PEP 517) |
| Lint | `ruff check .` |
| Type-check | `mypy <package>` |
| Coverage | `pytest --cov=<package> --cov-report=json` |
| Property | `pytest --hypothesis-show-statistics tests/property/` |
| Fuzz | `python -m atheris <fuzz_target>` OR `python -m pythonfuzz <target>` |
| Golden | `pytest --snapshot-update` then diff (syrupy) |

### Common Python-specific theater patterns

- `def foo(): pass` (legitimate in protocols, theater elsewhere).
- `raise NotImplementedError` in concrete classes.
- `# type: ignore` over a real mypy error.
- `assert True` test bodies.
- `monkeypatch.setattr(module, 'real_func', lambda *a, **kw: None)` mocking the very function under test.
- Functions that always return `None` when they should return a value.

### Async-specific

- Missing `await` on coroutines (silent — function returns the coroutine object instead of the result).
- `asyncio.create_task(...)` without keeping a reference (task gets GC'd).

---

## Go

### Detection signals

- `go.mod` at root.
- `go` in PATH.

### Default commands

| Test type | Command |
|-----------|---------|
| Unit / integration | `go test ./<package>/... -run <TestName> -v` |
| Build | `go build ./...` |
| Lint | `go vet ./...` + `golangci-lint run` |
| Coverage | `go test -coverprofile=raw/cover.out ./<package>/... ; go tool cover -func raw/cover.out` |
| Fuzz | `go test -fuzz=<FuzzName> -fuzztime=<duration>` |
| Bench | `go test -bench=<BenchName> -benchmem` |
| Race | `go test -race ./...` |

### Common Go-specific theater patterns

- `if err != nil { return err }` without ever testing the error case.
- `// nolint:<rule>` over a real lint issue.
- `panic("unimplemented")` in concrete types.
- Empty `func (x *X) Foo() {}` interface implementations.
- Tests that only check `assert.NotNil(t, result)` without checking content.

---

## Polyglot / monorepo

For projects with multiple languages (e.g., a Rust core + TypeScript frontend), the compliance-verifier:
1. Detects each language present.
2. Runs the appropriate per-language commands.
3. Records per-language results in `compliance.json#per_language`.

```json
{
  "checks": [...],
  "per_language": {
    "rust": {"test_command": "cargo test", "exit_code": 0, "raw_path": "raw/cargo_test.stdout"},
    "typescript": {"test_command": "bun test", "exit_code": 0, "raw_path": "raw/bun_test.stdout"}
  }
}
```

A bead may be language-specific (its evidence files are all `.rs`); in that case only the Rust commands need to pass.

---

## Project-type detection script

`scripts/discover-stack.sh` outputs `phase0_stack.json`:

```json
{
  "primary_language": "rust",
  "all_languages": ["rust", "typescript"],
  "build_tools": {
    "rust": ["cargo"],
    "typescript": ["bun", "next"]
  },
  "test_runners": {
    "rust": ["cargo test"],
    "typescript": ["vitest", "playwright"]
  },
  "ci_host": "github-actions",
  "ci_workflows_dir": ".github/workflows",
  "agents_md_present": true,
  "beads_dir": ".beads",
  "rch_present": false,
  "ubs_present": true
}
```

The compliance-verifier reads this and selects the right command set per cited file.

---

## Project hints to capture in `rubric.md`

When auditing a new project, the onboarding pass should record project-specific hints in `rubric.md` so future passes are cheaper:

```yaml
# rubric.md frontmatter (excerpt)
project_hints:
  primary_language: rust
  test_command: "cargo test --workspace --no-fail-fast"
  build_command: "cargo build --workspace --release"
  fuzz_corpus_dir: "fuzz/corpus"
  golden_dir: "tests/snapshots"
  e2e_runner: "scripts/e2e_test.sh"
  bench_runner: "cargo bench --workspace"
  ubs_present: true
  rch_present: false
  agents_md_path: "AGENTS.md"
  noise_files:
    # Files the spec extractor / theater scanner should ignore as noise.
    - "rustc-ice-*.txt"
    - "core.*"
    - ".rch-target/**"
```
