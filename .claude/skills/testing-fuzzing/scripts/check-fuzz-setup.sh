#!/usr/bin/env bash
# Check if a project is set up for fuzzing (polyglot: Rust, Go, Python, TS, C/C++, Java)
set -euo pipefail

echo "=== Fuzzing Setup Check ==="
echo ""

LANG_DETECTED=""
ISSUES=0
WARNINGS=0

ok() {
    echo "  OK   $*"
}

info() {
    echo "  INFO $*"
}

warn() {
    echo "  WARN $*"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    echo "  FAIL $*"
    ISSUES=$((ISSUES + 1))
}

require_core_cmds() {
    local missing=()
    local cmd
    for cmd in grep find wc df awk tr cat head; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "ERROR Missing required commands: ${missing[*]}"
        exit 1
    fi
}

require_core_cmds

count_children() {
    local dir="$1"
    find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l
}

count_recursive_matches() {
    local pattern="$1"
    shift
    { grep -r "$pattern" . "$@" 2>/dev/null || true; } | wc -l
}

count_recursive_files() {
    local pattern="$1"
    shift
    { grep -rl "$pattern" . "$@" 2>/dev/null || true; } | wc -l
}

# --- Detect Language ---

if [ -f "Cargo.toml" ]; then
    LANG_DETECTED="rust"
    echo "Language: Rust (Cargo.toml found)"
fi
if [ -f "go.mod" ]; then
    LANG_DETECTED="${LANG_DETECTED:+$LANG_DETECTED,}go"
    echo "Language: Go (go.mod found)"
fi
if [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
    LANG_DETECTED="${LANG_DETECTED:+$LANG_DETECTED,}python"
    echo "Language: Python"
fi
if [ -f "package.json" ] || [ -f "bun.lock" ]; then
    LANG_DETECTED="${LANG_DETECTED:+$LANG_DETECTED,}typescript"
    echo "Language: TypeScript/JavaScript (package.json found)"
fi
if [ -f "CMakeLists.txt" ] || [ -f "Makefile" ] || find . -maxdepth 3 \( -name '*.c' -o -name '*.cpp' -o -name '*.cc' \) -print -quit 2>/dev/null | grep -q .; then
    LANG_DETECTED="${LANG_DETECTED:+$LANG_DETECTED,}cpp"
    echo "Language: C/C++"
fi
if [ -f "build.gradle" ] || [ -f "pom.xml" ] || [ -f "build.gradle.kts" ]; then
    LANG_DETECTED="${LANG_DETECTED:+$LANG_DETECTED,}java"
    echo "Language: Java/JVM"
fi

if [ -z "$LANG_DETECTED" ]; then
    echo "ERROR No recognized project files found. Cannot determine language."
    exit 1
fi

echo ""

# --- Rust Checks ---

if echo "$LANG_DETECTED" | grep -q "rust"; then
    echo "=== Rust Fuzzing ==="

    if ! command -v rustup >/dev/null 2>&1; then
        fail "rustup not installed (needed to verify nightly fuzzing toolchain)"
    elif rustup run nightly rustc --version >/dev/null 2>&1; then
        ok "nightly toolchain: $(rustup run nightly rustc --version 2>/dev/null)"
    else
        fail "nightly toolchain not installed (run: rustup install nightly)"
    fi

    if command -v cargo-fuzz >/dev/null 2>&1; then
        ok "cargo-fuzz installed"
    else
        fail "cargo-fuzz not installed (run: cargo install cargo-fuzz)"
    fi

    if [ -d "fuzz" ]; then
        targets=$(find fuzz/fuzz_targets -maxdepth 1 -type f -name '*.rs' 2>/dev/null | wc -l)
        ok "fuzz/ directory exists ($targets targets)"
    else
        warn "fuzz/ directory not found (run: cargo fuzz init)"
    fi

    if [ -d "fuzz/corpus" ]; then
        corpus_dirs=$(find fuzz/corpus -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        ok "fuzz/corpus/ exists ($corpus_dirs target corpora)"
    else
        warn "fuzz/corpus/ not found (create seed corpus)"
    fi

    if [ -d "fuzz/dicts" ] || ls fuzz/*.dict >/dev/null 2>&1; then
        ok "dictionaries found"
    else
        warn "no dictionaries found (consider adding format-specific tokens)"
    fi

    # Check for fuzz deps leaking into production
    if command -v cargo >/dev/null 2>&1; then
        leak=$(cargo tree --no-dev 2>/dev/null | grep -cE 'arbitrary|libfuzzer|bolero' || true)
        if [ "$leak" -gt 0 ]; then
            fail "fuzz dependencies found in production build ($leak packages). Use feature flags!"
        else
            ok "no fuzz deps in production build"
        fi
    fi

    if [ -d "fuzz/fuzz_targets" ]; then
        echo ""
        echo "  Fuzz Targets:"
        shopt -s nullglob
        for target in fuzz/fuzz_targets/*.rs; do
            name=$(basename "$target" .rs)
            corpus_count=0
            if [ -d "fuzz/corpus/$name" ]; then
                corpus_count=$(count_children "fuzz/corpus/$name")
            fi
            has_guard=$(grep -c 'if.*len.*>.*return\|if.*len().*>' "$target" 2>/dev/null || true)
            has_guard="${has_guard:-0}"
            guard_status="NO GUARD"
            [ "$has_guard" -gt 0 ] && guard_status="guarded"
            echo "    $name (corpus: $corpus_count inputs, $guard_status)"
        done
        shopt -u nullglob
    fi
    echo ""
fi

# --- Go Checks ---

if echo "$LANG_DETECTED" | grep -q "go"; then
    echo "=== Go Fuzzing ==="

    if ! command -v go >/dev/null 2>&1; then
        fail "go not installed (need >= 1.18 for native fuzzing)"
    else
        go_version="$(go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+' | head -1 || true)"
        go_numeric="${go_version#go}"
        go_minor="${go_numeric#*.}"
        if [ -n "$go_version" ] && [ -n "$go_minor" ] && [ "$go_minor" -ge 18 ]; then
            ok "Go version: $go_version (native fuzzing supported)"
        elif [ -n "$go_version" ]; then
            fail "Go version $go_version too old (need >= 1.18 for native fuzzing)"
        else
            fail "Could not determine Go version"
        fi
    fi

    fuzz_funcs=$(count_recursive_matches 'func Fuzz' --include='*_test.go')
    info "$fuzz_funcs Fuzz* functions found in test files"

    testdata_dirs=$(find . -path '*/testdata/fuzz/*' -type d 2>/dev/null | wc -l)
    if [ "$testdata_dirs" -gt 0 ]; then
        ok "testdata/fuzz/ directories found ($testdata_dirs)"
    else
        warn "no testdata/fuzz/ directories found"
    fi
    echo ""
fi

# --- Python Checks ---

if echo "$LANG_DETECTED" | grep -q "python"; then
    echo "=== Python Fuzzing ==="

    if ! command -v python3 >/dev/null 2>&1; then
        fail "python3 not installed"
    elif python3 -c "import atheris" 2>/dev/null; then
        ok "atheris installed"
    else
        warn "atheris not installed (run: pip install atheris)"
    fi

    if command -v python3 >/dev/null 2>&1 && python3 -c "import hypothesis" 2>/dev/null; then
        ok "hypothesis installed"
    else
        warn "hypothesis not installed (run: pip install hypothesis)"
    fi

    fuzz_files=$(find . -name '*fuzz*' -name '*.py' 2>/dev/null | wc -l)
    info "$fuzz_files fuzz-related Python files found"

    test_one_input=$(count_recursive_matches 'def TestOneInput' --include='*.py')
    info "$test_one_input Atheris TestOneInput functions found"
    echo ""
fi

# --- TypeScript/JavaScript Checks ---

if echo "$LANG_DETECTED" | grep -q "typescript"; then
    echo "=== TypeScript/JavaScript Fuzzing ==="

    if [ -f "bun.lock" ]; then
        info "bun.lock detected (bun runtime)"
    fi

    if [ -f "package.json" ]; then
        if grep -q '"fast-check"' package.json 2>/dev/null; then
            ok "fast-check found in dependencies"
        else
            warn "fast-check not found (run: npm install --save-dev fast-check)"
        fi

        if grep -q '"@jazzer.js/core"' package.json 2>/dev/null; then
            ok "@jazzer.js/core found in dependencies"
        else
            info "@jazzer.js/core not installed (optional, for coverage-guided fuzzing)"
        fi
    fi

    fc_tests=$(count_recursive_matches 'fc\.assert\|fc\.property\|fc\.check' --include='*.ts' --include='*.js')
    info "$fc_tests fast-check assertions found"
    echo ""
fi

# --- C/C++ Checks ---

if echo "$LANG_DETECTED" | grep -q "cpp"; then
    echo "=== C/C++ Fuzzing ==="

    if clang --version >/dev/null 2>&1; then
        ok "clang installed: $(clang --version 2>/dev/null | head -1)"
        # Test fuzzer sanitizer support
        if echo "int LLVMFuzzerTestOneInput(const unsigned char*d,unsigned long s){return 0;}" | \
           clang -x c -fsanitize=fuzzer,address - -o /dev/null 2>/dev/null; then
            ok "-fsanitize=fuzzer,address supported"
        else
            fail "clang does not support -fsanitize=fuzzer"
        fi
    else
        fail "clang not installed"
    fi

    if command -v afl-fuzz >/dev/null 2>&1; then
        ok "AFL++ installed: $(afl-fuzz --version 2>/dev/null | head -1)"
    else
        info "AFL++ not installed (optional)"
    fi

    fuzz_targets=$(count_recursive_files 'LLVMFuzzerTestOneInput' --include='*.c' --include='*.cpp')
    info "$fuzz_targets LLVMFuzzerTestOneInput targets found"
    echo ""
fi

# --- Java Checks ---

if echo "$LANG_DETECTED" | grep -q "java"; then
    echo "=== Java/JVM Fuzzing ==="

    if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
        if grep -q 'jazzer' build.gradle build.gradle.kts 2>/dev/null; then
            ok "Jazzer found in Gradle dependencies"
        else
            warn "Jazzer not found in Gradle dependencies"
        fi
    fi

    if [ -f "pom.xml" ]; then
        if grep -q 'jazzer' pom.xml 2>/dev/null; then
            ok "Jazzer found in Maven dependencies"
        else
            warn "Jazzer not found in Maven dependencies"
        fi
    fi

    fuzz_tests=$(count_recursive_matches '@FuzzTest\|@Fuzz' --include='*.java' --include='*.kt')
    info "$fuzz_tests @FuzzTest/@Fuzz annotations found"
    echo ""
fi

# --- Universal Checks ---

echo "=== Universal Checks ==="

# Disk space
avail_gb=$(df -BG . 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || true)
if [ -z "$avail_gb" ]; then
    warn "Could not determine available disk space"
elif [ "$avail_gb" -lt 10 ]; then
    warn "Only ${avail_gb}GB disk space available. Long fuzzing campaigns need 50GB+."
else
    ok "${avail_gb}GB disk space available"
fi

# llvm-cov for coverage analysis
if command -v llvm-cov >/dev/null 2>&1; then
    ok "llvm-cov installed (coverage analysis available)"
else
    info "llvm-cov not installed (optional, for coverage reports)"
fi

# llvm-profdata
if command -v llvm-profdata >/dev/null 2>&1; then
    ok "llvm-profdata installed"
else
    info "llvm-profdata not installed (needed for coverage reports)"
fi

# Core dump pattern (required for AFL++)
if [ -f /proc/sys/kernel/core_pattern ]; then
    core_pat=$(cat /proc/sys/kernel/core_pattern)
    if [ "$core_pat" = "core" ]; then
        ok "core_pattern is 'core' (AFL++ compatible)"
    else
        warn "core_pattern is '$core_pat'. AFL++ needs 'core'. Run: echo core | sudo tee /proc/sys/kernel/core_pattern"
    fi
fi

# CPU governor (performance recommended for fuzzing)
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    if [ "$governor" = "performance" ]; then
        ok "CPU governor: performance"
    else
        warn "CPU governor: $governor (use 'performance' for consistent exec/s)"
    fi
fi

echo ""
echo "=== Summary ==="
if [ "$ISSUES" -eq 0 ]; then
    if [ "$WARNINGS" -eq 0 ]; then
        echo "  All checks passed. Ready to fuzz!"
    else
        echo "  No blocking issues found, but $WARNINGS warning(s) need review."
    fi
else
    echo "  $ISSUES issue(s) found. Fix them before fuzzing."
fi

echo ""
echo "=== Quick Commands ==="
if echo "$LANG_DETECTED" | grep -q "rust"; then
    echo "  Rust:   cargo fuzz list / cargo fuzz run TARGET / cargo fuzz cmin TARGET"
fi
if echo "$LANG_DETECTED" | grep -q "go"; then
    echo "  Go:     go test -fuzz=FuzzTarget -fuzztime=60s"
fi
if echo "$LANG_DETECTED" | grep -q "python"; then
    echo "  Python: python fuzz_target.py corpus/"
fi
if echo "$LANG_DETECTED" | grep -q "cpp"; then
    echo "  C/C++:  ./fuzz_target -max_total_time=60 corpus/"
fi
if echo "$LANG_DETECTED" | grep -q "java"; then
    echo "  Java:   ./gradlew test --tests '*FuzzTest*'"
fi

if [ "$ISSUES" -gt 0 ]; then
    exit 1
fi
