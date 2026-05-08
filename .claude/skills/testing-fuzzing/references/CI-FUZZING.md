# CI/CD Fuzzing Integration

> Run fuzzing in CI to catch regressions and continuously discover new bugs.

## Strategy: Two-Tier Fuzzing

| Tier | When | Duration | Purpose |
|------|------|----------|---------|
| **PR fuzzing** | Every pull request | 5-15 min | Catch regressions in changed code |
| **Continuous fuzzing** | Nightly on main | Hours-days | Deep exploration for new bugs |

## PR Fuzzing (Short Runs)

```yaml
# GitHub Actions: run fuzz regression corpus on every PR
name: Fuzz Regression
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@nightly
      - run: cargo install cargo-fuzz

      # Run each fuzz target against its committed corpus
      # This catches regressions — inputs that USED to not crash
      - name: Fuzz regression tests
        run: |
          for target in $(cargo fuzz list); do
            echo "=== $target ==="
            cargo fuzz run "$target" -- \
              -max_total_time=60 \
              -runs=10000 \
              2>&1 || { echo "CRASH in $target"; exit 1; }
          done
        timeout-minutes: 10

      # Upload any crash artifacts
      - name: Upload crash artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: fuzz-crashes
          path: fuzz/artifacts/
```

## Continuous Fuzzing (Long Runs)

```yaml
# Nightly: deep fuzzing with corpus persistence
name: Continuous Fuzz
on:
  schedule:
    - cron: '0 2 * * *'  # 2 AM daily
  workflow_dispatch:

jobs:
  fuzz:
    runs-on: ubuntu-latest
    timeout-minutes: 360  # 6 hours
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@nightly
      - run: cargo install cargo-fuzz

      # Restore cached corpus from previous runs
      - uses: actions/cache@v4
        with:
          path: fuzz/corpus/
          key: fuzz-corpus-${{ github.sha }}
          restore-keys: fuzz-corpus-

      - name: Run fuzzing
        run: |
          for target in $(cargo fuzz list); do
            cargo fuzz run "$target" -- \
              -max_total_time=3600 \
              -print_final_stats=1 \
              2>&1 | tee "fuzz-${target}.log"
          done

      # Minimize corpus after long run
      - name: Minimize corpus
        run: |
          for target in $(cargo fuzz list); do
            cargo fuzz cmin "$target" || true
          done

      # Save corpus for next run
      - uses: actions/cache/save@v4
        with:
          path: fuzz/corpus/
          key: fuzz-corpus-${{ github.sha }}

      - name: Upload crash artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: fuzz-crashes-nightly
          path: fuzz/artifacts/
```

## OSS-Fuzz Integration

For open-source projects, use Google's free continuous fuzzing:

```dockerfile
# oss-fuzz/Dockerfile
FROM gcr.io/oss-fuzz-base/base-builder-rust
RUN cargo install cargo-fuzz
COPY . $SRC/my_project
WORKDIR $SRC/my_project
COPY oss-fuzz/build.sh $SRC/build.sh
```

```bash
# oss-fuzz/build.sh
cd $SRC/my_project
cargo fuzz build
for target in $(cargo fuzz list); do
  cp fuzz/target/x86_64-unknown-linux-gnu/release/$target $OUT/
  cp -r fuzz/corpus/$target $OUT/${target}_seed_corpus || true
done
```

## Corpus Persistence Strategies

| Strategy | Pros | Cons |
|----------|------|------|
| Git (committed corpus) | Always available, versioned | Bloats repo |
| CI cache (`actions/cache`) | Fast, no repo bloat | Evicted after 7 days |
| Cloud storage (S3/R2) | Persistent, large | Setup overhead |
| OSS-Fuzz (managed) | Free, professional | Open-source only |

**Recommendation:** Commit a minimized seed corpus to git. Use CI cache for the evolving corpus. Periodically `cmin` and re-commit.

---

## OSS-Fuzz Full Configuration

### project.yaml

```yaml
homepage: "https://github.com/myorg/myproject"
language: c++          # c, c++, go, rust, python, java, swift
primary_contact: "maintainer@example.com"
auto_ccs:
  - "security-team@example.com"
main_repo: "https://github.com/myorg/myproject.git"
sanitizers:
  - address
  - memory
  - undefined
architectures:
  - x86_64
fuzzing_engines:
  - libfuzzer
  - afl
  - honggfuzz
```

### Dockerfile

```dockerfile
FROM gcr.io/oss-fuzz-base/base-builder-rust  # or base-builder, base-builder-go, etc.
RUN apt-get update && apt-get install -y cmake pkg-config
COPY . $SRC/myproject
WORKDIR $SRC/myproject
COPY oss-fuzz/build.sh $SRC/build.sh
```

### build.sh

```bash
#!/bin/bash -eu
cd $SRC/myproject

# Rust
cargo fuzz build
for target in $(cargo fuzz list); do
    cp fuzz/target/x86_64-unknown-linux-gnu/release/$target $OUT/
    [[ -d fuzz/corpus/$target ]] && cp -r fuzz/corpus/$target $OUT/${target}_seed_corpus
    [[ -f fuzz/dicts/$target.dict ]] && cp fuzz/dicts/$target.dict $OUT/${target}.dict
done

# C/C++
# compile_fuzzer myproject fuzz_parser fuzz/fuzz_parser.c -I include/
```

### Local Testing with infra/helper.py

```bash
# Clone OSS-Fuzz repo
git clone https://github.com/google/oss-fuzz.git
cd oss-fuzz

# Build fuzz targets locally
python3 infra/helper.py build_fuzzers myproject /path/to/local/checkout

# Run a specific fuzz target
python3 infra/helper.py run_fuzzer myproject my_fuzz_target

# Check that build works
python3 infra/helper.py check_build myproject
```

---

## ClusterFuzzLite (Self-Hosted)

For **private repos** that can't use OSS-Fuzz.

### GitHub Actions

```yaml
name: ClusterFuzzLite
on:
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 2 * * *'

jobs:
  pr-fuzzing:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google/clusterfuzzlite/actions/build_fuzzers@v1
        with:
          language: c++
          sanitizer: address
      - uses: google/clusterfuzzlite/actions/run_fuzzers@v1
        with:
          fuzz-seconds: 300
          mode: code-change

  continuous-fuzzing:
    if: github.event_name == 'schedule'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google/clusterfuzzlite/actions/build_fuzzers@v1
        with:
          language: c++
          sanitizer: address
      - uses: google/clusterfuzzlite/actions/run_fuzzers@v1
        with:
          fuzz-seconds: 3600
          mode: batch
      - uses: google/clusterfuzzlite/actions/run_fuzzers@v1
        with:
          mode: prune
```

### .clusterfuzzlite/Dockerfile

```dockerfile
FROM gcr.io/oss-fuzz-base/base-builder
COPY . $SRC/myproject
COPY .clusterfuzzlite/build.sh $SRC/build.sh
```

---

## Go CI Fuzzing

```yaml
name: Go Fuzz
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - uses: actions/cache@v4
        with:
          path: testdata/fuzz/
          key: go-fuzz-${{ github.sha }}
          restore-keys: go-fuzz-
      - name: Fuzz
        run: |
          for pkg in $(go list ./...); do
            funcs=$(go test -list 'Fuzz.*' "$pkg" 2>/dev/null | grep '^Fuzz' || true)
            for fn in $funcs; do
              go test "$pkg" -fuzz="$fn" -fuzztime=30s -race 2>&1 || exit 1
            done
          done
```

## Python CI Fuzzing

```yaml
name: Python Fuzz
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install atheris hypothesis pytest
      - name: Hypothesis property tests
        run: pytest tests/ -k "fuzz or property or hypothesis" -x
      - name: Atheris regression
        run: |
          for target in fuzz_targets/*.py; do
            [ -f "$target" ] || continue
            timeout 60 python "$target" corpus/ 2>&1 || exit 1
          done
```

## Java CI Fuzzing

```yaml
name: Java Fuzz
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { java-version: '21', distribution: 'temurin' }
      - name: Jazzer fuzz tests
        run: ./gradlew test --tests "*FuzzTest*" --info
        timeout-minutes: 10
```

## Converting Crashes to Issues

```bash
# When CI finds a crash, auto-create a GitHub issue
- name: Create issue for crash
  if: failure()
  uses: actions/github-script@v7
  with:
    script: |
      const fs = require('fs');
      const crashes = fs.readdirSync('fuzz/artifacts/').filter(f => f.startsWith('crash-'));
      if (crashes.length === 0) return;
      await github.rest.issues.create({
        owner: context.repo.owner,
        repo: context.repo.repo,
        title: `Fuzz: ${crashes.length} crash(es) found`,
        body: `Crashes found:\n${crashes.map(c => '- ' + c).join('\n')}\n\nDownload artifacts from the workflow run.`,
        labels: ['bug', 'fuzzing'],
      });
```

---

## C/C++ Standalone CI Workflow

A complete GitHub Actions workflow for libFuzzer C/C++ targets with ASan+UBSan, corpus caching, and crash artifact upload.

```yaml
name: Fuzz C/C++ (libFuzzer)
on:
  pull_request:
  workflow_dispatch:

jobs:
  fuzz:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - name: Install LLVM/Clang
        run: |
          sudo apt-get update
          sudo apt-get install -y clang-17 llvm-17

      - uses: actions/cache@v4
        with:
          path: corpus/
          key: fuzz-corpus-cpp-${{ github.sha }}
          restore-keys: fuzz-corpus-cpp-

      - name: Build fuzz targets with ASan + UBSan
        run: |
          for src in fuzz_targets/*.c fuzz_targets/*.cpp; do
            [ -f "$src" ] || continue
            base=$(basename "$src" | sed 's/\.[^.]*$//')
            clang-17 -g -O1 -fno-omit-frame-pointer \
              -fsanitize=fuzzer,address,undefined \
              -I include/ "$src" src/*.c -o "build_fuzz_${base}"
          done
        env:
          CC: clang-17
          CXX: clang++-17

      - name: Run fuzz targets
        run: |
          mkdir -p corpus artifacts
          for target in build_fuzz_*; do
            name=${target#build_fuzz_}
            mkdir -p "corpus/$name"
            echo "=== Fuzzing $name ==="
            ./"$target" "corpus/$name" \
              -max_total_time=120 \
              -print_final_stats=1 \
              -artifact_prefix="artifacts/${name}-" \
              2>&1 || { echo "CRASH in $name"; exit 1; }
          done

      - name: Upload crash artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: fuzz-crashes-cpp
          path: artifacts/

      - uses: actions/cache/save@v4
        if: always()
        with:
          path: corpus/
          key: fuzz-corpus-cpp-${{ github.sha }}
```

---

## TypeScript CI Workflow

A complete GitHub Actions workflow for fast-check + Jazzer.js with numRuns configuration and corpus management.

```yaml
name: Fuzz TypeScript
on:
  pull_request:
  workflow_dispatch:
    inputs:
      num_runs:
        description: 'Number of fast-check runs per property'
        default: '100000'

jobs:
  fuzz:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '22' }

      - run: npm ci

      - uses: actions/cache@v4
        with:
          path: .fast-check-corpus/
          key: fuzz-corpus-ts-${{ github.sha }}
          restore-keys: fuzz-corpus-ts-

      - name: Run fast-check property tests
        run: |
          npx vitest run --reporter=verbose tests/fuzz/
        env:
          FAST_CHECK_NUM_RUNS: ${{ github.event.inputs.num_runs || '100000' }}

      - name: Run Jazzer.js targets
        run: |
          mkdir -p .jazzer-corpus .jazzer-artifacts
          for target in fuzz_targets/*.js fuzz_targets/*.ts; do
            [ -f "$target" ] || continue
            npx jazzer "$target" .jazzer-corpus/ \
              -- -max_total_time=120 \
              -artifact_prefix=.jazzer-artifacts/ \
              2>&1 || { echo "CRASH in $target"; exit 1; }
          done
        continue-on-error: false

      - name: Upload crash artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: fuzz-crashes-ts
          path: .jazzer-artifacts/

      - uses: actions/cache/save@v4
        if: always()
        with:
          path: |
            .fast-check-corpus/
            .jazzer-corpus/
          key: fuzz-corpus-ts-${{ github.sha }}
```

---

## Nightly Continuous Fuzzing (Go)

A nightly schedule workflow for Go that runs for 1 hour with corpus caching.

```yaml
name: Nightly Fuzz (Go)
on:
  schedule:
    - cron: '0 3 * * *'  # 3 AM UTC daily
  workflow_dispatch:

jobs:
  fuzz:
    runs-on: ubuntu-latest
    timeout-minutes: 90
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }

      - uses: actions/cache@v4
        with:
          path: |
            testdata/fuzz/
            ~/.cache/go-build/fuzz/
          key: go-fuzz-nightly-${{ github.sha }}
          restore-keys: go-fuzz-nightly-

      - name: Discover and run fuzz targets (1 hour each)
        run: |
          failed=0
          for pkg in $(go list ./...); do
            funcs=$(go test -list 'Fuzz.*' "$pkg" 2>/dev/null | grep '^Fuzz' || true)
            for fn in $funcs; do
              echo "=== $pkg / $fn ==="
              go test "$pkg" -fuzz="^${fn}$" -fuzztime=1h -race \
                -parallel=4 2>&1 | tee "fuzz-${fn}.log" || failed=1
            done
          done
          [ $failed -eq 0 ] || exit 1

      - name: Collect crash files
        if: failure()
        run: |
          mkdir -p fuzz-crashes
          find testdata/fuzz/ -name 'crash-*' -exec cp {} fuzz-crashes/ \; 2>/dev/null || true

      - name: Upload crash artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: go-fuzz-crashes-nightly
          path: fuzz-crashes/

      - uses: actions/cache/save@v4
        if: always()
        with:
          path: |
            testdata/fuzz/
            ~/.cache/go-build/fuzz/
          key: go-fuzz-nightly-${{ github.sha }}
```

---

## Nightly Continuous Fuzzing (Python)

A nightly schedule workflow for Atheris + Hypothesis with corpus persistence.

```yaml
name: Nightly Fuzz (Python)
on:
  schedule:
    - cron: '0 4 * * *'  # 4 AM UTC daily
  workflow_dispatch:

jobs:
  fuzz:
    runs-on: ubuntu-latest
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }

      - run: pip install atheris hypothesis pytest

      - uses: actions/cache@v4
        with:
          path: |
            corpus/
            .hypothesis/
          key: py-fuzz-nightly-${{ github.sha }}
          restore-keys: py-fuzz-nightly-

      - name: Run Hypothesis property tests (extended)
        run: |
          pytest tests/ -k "fuzz or property or hypothesis" -x \
            --hypothesis-seed=0 \
            -o "hypothesis_settings=max_examples=500000"
        env:
          HYPOTHESIS_DATABASE_BACKEND: directory

      - name: Run Atheris targets (1 hour each)
        run: |
          mkdir -p corpus artifacts
          for target in fuzz_targets/*.py; do
            [ -f "$target" ] || continue
            name=$(basename "$target" .py)
            mkdir -p "corpus/$name"
            echo "=== Atheris: $name ==="
            timeout 3600 python "$target" "corpus/$name" \
              -artifact_prefix="artifacts/${name}-" \
              -print_final_stats=1 \
              2>&1 | tee "atheris-${name}.log" || {
                echo "CRASH or timeout in $name"
                # timeout exit code 124 is OK (ran full duration)
                [ $? -eq 124 ] || exit 1
              }
          done

      - name: Upload crash artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: py-fuzz-crashes-nightly
          path: artifacts/

      - uses: actions/cache/save@v4
        if: always()
        with:
          path: |
            corpus/
            .hypothesis/
          key: py-fuzz-nightly-${{ github.sha }}
```

---

## Multi-Language Monorepo

A matrix strategy workflow that detects which languages have fuzz targets and runs appropriate fuzzing for each.

```yaml
name: Monorepo Fuzz
on:
  pull_request:
  schedule:
    - cron: '0 2 * * *'

jobs:
  detect:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.detect.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - id: detect
        run: |
          langs=()
          # Rust: Cargo.toml with cargo-fuzz
          [ -d fuzz/fuzz_targets ] && langs+=('{"lang":"rust","timeout":30}')
          # Go: any Fuzz* test functions
          grep -rq 'func Fuzz' --include='*_test.go' . 2>/dev/null && langs+=('{"lang":"go","timeout":20}')
          # C/C++: fuzz_targets/ directory with .c or .cpp
          ls fuzz_targets/*.c fuzz_targets/*.cpp 2>/dev/null | grep -q . && langs+=('{"lang":"cpp","timeout":20}')
          # Python: fuzz_targets/ with .py
          ls fuzz_targets/*.py 2>/dev/null | grep -q . && langs+=('{"lang":"python","timeout":15}')
          # TypeScript: tests/fuzz/ directory
          [ -d tests/fuzz ] && langs+=('{"lang":"typescript","timeout":15}')

          if [ ${#langs[@]} -eq 0 ]; then
            echo "matrix={\"include\":[]}" >> "$GITHUB_OUTPUT"
          else
            joined=$(IFS=,; echo "${langs[*]}")
            echo "matrix={\"include\":[${joined}]}" >> "$GITHUB_OUTPUT"
          fi

  fuzz:
    needs: detect
    if: ${{ fromJson(needs.detect.outputs.matrix).include[0] != null }}
    runs-on: ubuntu-latest
    timeout-minutes: ${{ fromJson(matrix.timeout) || 30 }}
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.detect.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/cache@v4
        with:
          path: |
            fuzz/corpus/
            testdata/fuzz/
            corpus/
            .fast-check-corpus/
          key: fuzz-${{ matrix.lang }}-${{ github.sha }}
          restore-keys: fuzz-${{ matrix.lang }}-

      # Rust
      - if: matrix.lang == 'rust'
        uses: dtolnay/rust-toolchain@nightly
      - if: matrix.lang == 'rust'
        run: |
          cargo install cargo-fuzz
          for target in $(cargo fuzz list); do
            cargo fuzz run "$target" -- -max_total_time=120 2>&1 || exit 1
          done

      # Go
      - if: matrix.lang == 'go'
        uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - if: matrix.lang == 'go'
        run: |
          for pkg in $(go list ./...); do
            funcs=$(go test -list 'Fuzz.*' "$pkg" 2>/dev/null | grep '^Fuzz' || true)
            for fn in $funcs; do
              go test "$pkg" -fuzz="^${fn}$" -fuzztime=60s -race 2>&1 || exit 1
            done
          done

      # C/C++
      - if: matrix.lang == 'cpp'
        run: sudo apt-get update && sudo apt-get install -y clang-17 llvm-17
      - if: matrix.lang == 'cpp'
        run: |
          for src in fuzz_targets/*.c fuzz_targets/*.cpp; do
            [ -f "$src" ] || continue
            base=$(basename "$src" | sed 's/\.[^.]*$//')
            clang-17 -g -O1 -fsanitize=fuzzer,address,undefined \
              -I include/ "$src" src/*.c -o "fuzz_${base}"
            ./fuzz_${base} corpus/${base}/ -max_total_time=60 2>&1 || exit 1
          done

      # Python
      - if: matrix.lang == 'python'
        uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - if: matrix.lang == 'python'
        run: |
          pip install atheris hypothesis pytest
          pytest tests/ -k "fuzz or property" -x
          for target in fuzz_targets/*.py; do
            [ -f "$target" ] || continue
            timeout 120 python "$target" corpus/ 2>&1 || exit 1
          done

      # TypeScript
      - if: matrix.lang == 'typescript'
        uses: actions/setup-node@v4
        with: { node-version: '22' }
      - if: matrix.lang == 'typescript'
        run: |
          npm ci
          npx vitest run tests/fuzz/

      - name: Upload crash artifacts
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: fuzz-crashes-${{ matrix.lang }}
          path: |
            fuzz/artifacts/
            artifacts/
            fuzz-crashes/
```
