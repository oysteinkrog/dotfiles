#!/usr/bin/env bash
# Detect primary branch, archetype, build/test/lint commands, protected globs.
# Writes JSON to stdout (Phase 1 subagent will write to project_profile.json).
set -euo pipefail

project="${1:?usage: discover-project.sh <project-path>}"
cd "$project"

# Primary branch
primary=""
if remote_head=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
    primary="${remote_head##*/}"
fi
if [[ -z "$primary" ]]; then
    primary=$(git config init.defaultBranch 2>/dev/null || echo "")
fi
if [[ -z "$primary" ]]; then
    for candidate in main master develop trunk default; do
        if git show-ref --verify --quiet "refs/heads/$candidate"; then
            primary="$candidate"
            break
        fi
    done
fi
[[ -z "$primary" ]] && primary="main"

# Archetype detection
archetype="unknown"
has_cargo=$([[ -f Cargo.toml ]] && echo "true" || echo "false")
has_pkg_json=$([[ -f package.json ]] && echo "true" || echo "false")
has_pyproject=$([[ -f pyproject.toml ]] && echo "true" || echo "false")
has_go_mod=$([[ -f go.mod ]] && echo "true" || echo "false")
has_skills=$([[ -d .claude/skills ]] && echo "true" || echo "false")
has_next_config=$(ls next.config.* 2>/dev/null | head -1 || true)

count_ecosystem=0
[[ "$has_cargo" == "true" ]] && count_ecosystem=$((count_ecosystem + 1))
[[ "$has_pkg_json" == "true" ]] && count_ecosystem=$((count_ecosystem + 1))
[[ "$has_pyproject" == "true" ]] && count_ecosystem=$((count_ecosystem + 1))
[[ "$has_go_mod" == "true" ]] && count_ecosystem=$((count_ecosystem + 1))

if [[ "$has_skills" == "true" ]]; then
    archetype="claude-skill-repo"
elif [[ "$count_ecosystem" -ge 2 ]]; then
    archetype="polyglot-monorepo"
elif [[ -n "$has_next_config" ]]; then
    archetype="nextjs-saas"
elif [[ "$has_cargo" == "true" ]]; then
    archetype="single-rust-crate"
elif [[ "$has_pyproject" == "true" ]]; then
    archetype="python-package"
elif [[ "$has_go_mod" == "true" ]]; then
    archetype="go-cli"
fi

# Test/typecheck/lint/build commands by archetype
test_cmd=""
typecheck_cmd=""
lint_cmd=""
build_cmd=""
formatter=""

case "$archetype" in
    single-rust-crate|polyglot-monorepo)
        if [[ -f Cargo.toml ]]; then
            test_cmd="cargo test --workspace"
            typecheck_cmd="cargo check --workspace"
            lint_cmd="cargo clippy --workspace -- -D warnings"
            build_cmd="cargo build --workspace --release"
            formatter="cargo fmt"
        fi
        ;;
    nextjs-saas)
        if [[ -f package.json ]]; then
            if [[ -f bun.lockb ]]; then
                test_cmd="bun test"
                typecheck_cmd="bun tsc --noEmit"
                build_cmd="bun run build"
            elif [[ -f pnpm-lock.yaml ]]; then
                test_cmd="pnpm test"
                typecheck_cmd="pnpm tsc --noEmit"
                build_cmd="pnpm build"
            else
                test_cmd="npm test"
                typecheck_cmd="npx tsc --noEmit"
                build_cmd="npm run build"
            fi
            lint_cmd="eslint ."
            formatter="prettier --check ."
        fi
        ;;
    python-package)
        test_cmd="pytest"
        typecheck_cmd="mypy ."
        lint_cmd="ruff check"
        build_cmd="python -m build"
        formatter="ruff format"
        ;;
    go-cli)
        test_cmd="go test ./..."
        typecheck_cmd="go vet ./..."
        lint_cmd="golangci-lint run"
        build_cmd="go build ./..."
        formatter="gofmt"
        ;;
    claude-skill-repo)
        test_cmd="bash scripts/check-skills.sh ."
        ;;
esac

# CI gates
ci_gates=""
[[ -f .ubsignore ]] && ci_gates+="ubs,"
command -v dcg >/dev/null 2>&1 && ci_gates+="dcg,"
[[ -f .pre-commit-config.yaml ]] && ci_gates+="pre-commit,"
[[ -f .lefthook.yml ]] && ci_gates+="lefthook,"
[[ -f .githooks/pre-commit ]] && ci_gates+="githooks,"
ci_gates="${ci_gates%,}"

# Existing destination dirs
existing_dirs=""
for d in docs docs/planning docs/progress docs/reference docs/operations docs/audits docs/contracts docs/policies docs/architecture docs/launch docs/internal scripts scripts/visualization tools tests/fixtures e2e; do
    [[ -d "$d" ]] && existing_dirs+="\"$d\","
done
existing_dirs="${existing_dirs%,}"
[[ -z "$existing_dirs" ]] && existing_dirs=""

# Branch synonyms
synonyms=""
for syn in master develop release; do
    [[ "$syn" == "$primary" ]] && continue
    if git show-ref --verify --quiet "refs/heads/$syn" || git show-ref --verify --quiet "refs/remotes/origin/$syn"; then
        synonyms+="\"$syn\","
    fi
done
synonyms="${synonyms%,}"
[[ -z "$synonyms" ]] && synonyms=""

# Protected globs (archetype-specific defaults)
protected='"README.md","LICENSE*","AGENTS.md","CHANGELOG.md",".gitignore",".gitattributes",".gitmodules"'
case "$archetype" in
    single-rust-crate|polyglot-monorepo)
        protected+=',"Cargo.toml","Cargo.lock","rust-toolchain.toml","build.rs","deny.toml",".ubsignore","src/**","tests/**","benches/**"'
        ;;
    nextjs-saas)
        protected+=',"package.json","package-lock.json","pnpm-lock.yaml","next.config.*","tailwind.config.*","tsconfig.json","app/**","public/**","middleware.ts"'
        ;;
    python-package)
        protected+=',"pyproject.toml","setup.cfg","setup.py","src/**","tests/**","poetry.lock","uv.lock"'
        ;;
    go-cli)
        protected+=',"go.mod","go.sum","Makefile","cmd/**","internal/**","pkg/**"'
        ;;
    claude-skill-repo)
        protected+=',".claude/**","SKILL.md"'
        ;;
esac

# Output JSON
cat <<EOF
{
  "primary_branch": "$primary",
  "archetype": "$archetype",
  "test_command": "$test_cmd",
  "typecheck_command": "$typecheck_cmd",
  "lint_command": "$lint_cmd",
  "build_command": "$build_cmd",
  "formatter": "$formatter",
  "ci_gates": [${ci_gates:+\"${ci_gates//,/\",\"}\"}],
  "existing_dest_dirs": [${existing_dirs}],
  "branch_synonyms": [${synonyms}],
  "protected_globs": [$protected]
}
EOF
