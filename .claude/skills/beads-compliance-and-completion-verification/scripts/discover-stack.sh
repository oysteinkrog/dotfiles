#!/usr/bin/env bash
# discover-stack.sh — Detect the project's primary language(s) and build/test
# stack so per-language defaults from references/PROJECT-TYPES.md can be applied
# automatically. Emits a machine-readable JSON profile to stdout (or to the
# audit dir if --write is passed).
#
# Usage:
#   discover-stack.sh <project-path> [--write <audit-dir>]
#
# Output (stdout):
#   { "primary": "rust", "languages": [...], "build": {...}, "test": {...},
#     "coverage": {...}, "fuzz": {...}, "ci": [...], "monorepo": bool, ... }
#
# Detection is a probe-stack: we look at known files in priority order and
# stop when a confident signal is found. Tools we cannot probe (binary version
# checks) get null in the JSON, never a fake value — Phase 4 must be honest
# about what it actually exercised.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path required}"
[ -d "$PROJECT" ] || { echo "ERROR: $PROJECT is not a directory" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"

WRITE_DIR=""
if [ "${2:-}" = "--write" ]; then
  WRITE_DIR="${3:?--write requires a destination dir}"
  [ -d "$WRITE_DIR" ] || mkdir -p "$WRITE_DIR"
fi

# ---- helpers -----------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }
exists() { [ -e "$PROJECT/$1" ]; }
glob_count() { find "$PROJECT" -maxdepth 4 -name "$1" 2>/dev/null | head -50 | wc -l; }

vers_or_null() {
  # Run a command, capture first line, json-encode. Empty/missing → null.
  local out=""
  if out="$("$@" 2>/dev/null | head -1)"; then
    if [ -n "$out" ]; then
      printf '%s' "$out" | jq -Rs .
      return
    fi
  fi
  printf 'null'
}

# ---- language detection ------------------------------------------------------
LANGS=()
exists "Cargo.toml" && LANGS+=("rust")
exists "package.json" && LANGS+=("typescript")
{ exists "pyproject.toml" || exists "setup.py" || exists "requirements.txt"; } && LANGS+=("python")
exists "go.mod" && LANGS+=("go")
exists "Gemfile" && LANGS+=("ruby")
exists "pom.xml" || exists "build.gradle" || exists "build.gradle.kts" && LANGS+=("java")
exists "mix.exs" && LANGS+=("elixir")
exists "Project.toml" && LANGS+=("julia")
exists "composer.json" && LANGS+=("php")

# Pick PRIMARY by source file count.
PRIMARY="unknown"
MAX=0
for L in "${LANGS[@]}"; do
  case "$L" in
    rust)      C=$(glob_count "*.rs") ;;
    typescript) C=$(($(glob_count "*.ts") + $(glob_count "*.tsx"))) ;;
    python)    C=$(glob_count "*.py") ;;
    go)        C=$(glob_count "*.go") ;;
    ruby)      C=$(glob_count "*.rb") ;;
    java)      C=$(glob_count "*.java") ;;
    elixir)    C=$(glob_count "*.ex") ;;
    julia)     C=$(glob_count "*.jl") ;;
    php)       C=$(glob_count "*.php") ;;
    *)         C=0 ;;
  esac
  if [ "$C" -gt "$MAX" ]; then PRIMARY="$L"; MAX="$C"; fi
done
[ "$PRIMARY" = "unknown" ] && [ "${#LANGS[@]}" -gt 0 ] && PRIMARY="${LANGS[0]}"

# ---- monorepo detection ------------------------------------------------------
MONOREPO=false
if exists "Cargo.toml" && grep -q '\[workspace\]' "$PROJECT/Cargo.toml" 2>/dev/null; then MONOREPO=true; fi
if exists "package.json" && grep -q '"workspaces"' "$PROJECT/package.json" 2>/dev/null; then MONOREPO=true; fi
if exists "pnpm-workspace.yaml" || exists "lerna.json" || exists "turbo.json" || exists "nx.json"; then MONOREPO=true; fi

# ---- per-language stack maps -------------------------------------------------
build_cmd=null; test_cmd=null; coverage_cmd=null; fuzz_cmd=null; bench_cmd=null
test_file_glob=null; e2e_cmd=null; lint_cmd=null

case "$PRIMARY" in
  rust)
    build_cmd='"cargo build --workspace"'
    test_cmd='"cargo test --workspace"'
    coverage_cmd='"cargo llvm-cov --workspace --json --output-path target/llvm-cov.json"'
    have cargo-fuzz && fuzz_cmd='"cargo +nightly fuzz run <target>"'
    bench_cmd='"cargo bench --workspace"'
    lint_cmd='"cargo clippy --workspace -- -D warnings"'
    test_file_glob='"**/tests/**/*.rs"'
    [ -d "$PROJECT/tests" ] && e2e_cmd='"cargo test --test \"*\""'
    ;;
  typescript)
    if exists "package.json"; then
      # Prefer scripts.test if defined.
      if jq -e '.scripts.test' "$PROJECT/package.json" >/dev/null 2>&1; then
        test_cmd='"npm test"'
      elif have vitest; then test_cmd='"vitest run"'
      elif have jest; then test_cmd='"jest"'
      fi
      jq -e '.scripts.build' "$PROJECT/package.json" >/dev/null 2>&1 && build_cmd='"npm run build"'
      jq -e '.scripts.coverage' "$PROJECT/package.json" >/dev/null 2>&1 && coverage_cmd='"npm run coverage"'
      jq -e '.scripts.lint' "$PROJECT/package.json" >/dev/null 2>&1 && lint_cmd='"npm run lint"'
      jq -e '.scripts["test:e2e"]' "$PROJECT/package.json" >/dev/null 2>&1 && e2e_cmd='"npm run test:e2e"'
    fi
    test_file_glob='"**/*.{test,spec}.{ts,tsx}"'
    ;;
  python)
    if exists "pyproject.toml"; then
      if grep -q 'pytest' "$PROJECT/pyproject.toml" 2>/dev/null; then test_cmd='"pytest"'; fi
      if grep -q 'hypothesis' "$PROJECT/pyproject.toml" 2>/dev/null; then fuzz_cmd='"pytest -m hypothesis"'; fi
    elif exists "setup.py" || exists "tox.ini"; then test_cmd='"pytest"'; fi
    coverage_cmd='"pytest --cov=. --cov-report=json"'
    lint_cmd='"ruff check ."'
    test_file_glob='"**/test_*.py"'
    ;;
  go)
    build_cmd='"go build ./..."'
    test_cmd='"go test ./..."'
    coverage_cmd='"go test -coverprofile=coverage.out ./..."'
    fuzz_cmd='"go test -fuzz=Fuzz -fuzztime=60s ./..."'
    bench_cmd='"go test -bench=. -benchmem ./..."'
    lint_cmd='"golangci-lint run ./..."'
    test_file_glob='"**/*_test.go"'
    ;;
  ruby)
    test_cmd='"bundle exec rspec"'; lint_cmd='"bundle exec rubocop"'; test_file_glob='"spec/**/*_spec.rb"'
    ;;
  java)
    if exists "pom.xml"; then build_cmd='"mvn package"'; test_cmd='"mvn test"';
    elif exists "build.gradle" || exists "build.gradle.kts"; then build_cmd='"./gradlew build"'; test_cmd='"./gradlew test"'; fi
    test_file_glob='"src/test/**/*.java"'
    ;;
  *)
    : # leave nulls
    ;;
esac

# ---- CI detection ------------------------------------------------------------
CI=()
[ -d "$PROJECT/.github/workflows" ] && [ -n "$(ls "$PROJECT/.github/workflows" 2>/dev/null)" ] && CI+=("github-actions")
exists ".gitlab-ci.yml" && CI+=("gitlab")
exists ".circleci/config.yml" && CI+=("circleci")
exists "azure-pipelines.yml" && CI+=("azure")
exists ".buildkite/pipeline.yml" && CI+=("buildkite")
exists ".woodpecker.yml" || exists ".woodpecker/pipeline.yml" && CI+=("woodpecker")

# ---- containerization --------------------------------------------------------
HAS_DOCKER=false; HAS_COMPOSE=false; HAS_NIX=false
exists "Dockerfile" && HAS_DOCKER=true
exists "docker-compose.yml" || exists "compose.yml" && HAS_COMPOSE=true
exists "flake.nix" || exists "shell.nix" && HAS_NIX=true

# ---- emit JSON ---------------------------------------------------------------
LANGS_JSON="$(printf '%s\n' "${LANGS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
CI_JSON="$(printf '%s\n' "${CI[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"

JSON=$(cat <<EOF
{
  "project_path": "$PROJECT",
  "primary": "$PRIMARY",
  "languages": $LANGS_JSON,
  "monorepo": $MONOREPO,
  "build": {"cmd": $build_cmd},
  "test": {"cmd": $test_cmd, "file_glob": $test_file_glob, "e2e_cmd": $e2e_cmd},
  "coverage": {"cmd": $coverage_cmd},
  "fuzz": {"cmd": $fuzz_cmd},
  "bench": {"cmd": $bench_cmd},
  "lint": {"cmd": $lint_cmd},
  "ci": $CI_JSON,
  "containers": {"docker": $HAS_DOCKER, "compose": $HAS_COMPOSE, "nix": $HAS_NIX},
  "tool_versions": {
    "cargo": $(vers_or_null cargo --version),
    "node":  $(vers_or_null node --version),
    "python":$(vers_or_null python3 --version),
    "go":    $(vers_or_null go version),
    "rg":    $(vers_or_null rg --version),
    "jq":    $(vers_or_null jq --version),
    "br":    $(vers_or_null br --version)
  },
  "discovered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)

if [ -n "$WRITE_DIR" ]; then
  printf '%s\n' "$JSON" | jq . > "$WRITE_DIR/stack.json"
  echo "Wrote $WRITE_DIR/stack.json (primary=$PRIMARY)" >&2
else
  printf '%s\n' "$JSON" | jq .
fi
