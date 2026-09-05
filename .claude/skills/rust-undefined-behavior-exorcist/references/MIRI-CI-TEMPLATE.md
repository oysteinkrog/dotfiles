# Miri CI Template — Exact YAML, Mined From The Corpus

Anchor: cass Q-701 — the verbatim GitHub Actions YAML from frankensearch.

The user has historically run Miri in CI as a **non-blocking** signal job — `continue-on-error: true`, `-Zmiri-disable-isolation`, `cargo miri test --lib`. This file documents that pattern + how the skill extends it to the full matrix from Phase 3.

---

## The corpus baseline (frankensearch Q-701)

```yaml
# Miri for undefined behavior detection (optional, can be slow)
miri:
  name: Miri
  runs-on: ubuntu-latest
  timeout-minutes: 60
  steps:
    - uses: actions/checkout@v4
    - uses: dtolnay/rust-toolchain@nightly
      with: { components: miri }
    - uses: Swatinem/rust-cache@v2
      with: { key: miri }
    - name: Setup Miri
      run: cargo miri setup
    - name: Run Miri tests
      run: cargo miri test --lib
      continue-on-error: true
      env: { MIRIFLAGS: -Zmiri-disable-isolation }
```

Key choices:
- **`continue-on-error: true`** — Miri findings are signal, not gates. The CI passes if Miri reports UB; humans review the log.
- **`-Zmiri-disable-isolation`** — Allows Miri to use system time, system RNG, environment variables. Necessary for many integration tests; trades a tiny bit of soundness fidelity for runnability.
- **`cargo miri test --lib`** — Runs the library tests only, not integration tests. Integration tests often need FFI which Miri can't run.
- **60-minute timeout** — Miri is 5-100× slower than native; 60 min covers most projects.
- **`Swatinem/rust-cache@v2`** — Critical. Without caching, Miri's setup phase alone is 5+ minutes.

---

## Extension: the full MIRIFLAGS matrix

The skill (per [TOOLING.md §The MIRIFLAGS matrix](TOOLING.md#the-miriflags-matrix-run-all-four)) runs four configurations. CI extension:

```yaml
miri-matrix:
  name: Miri (${{ matrix.config }})
  runs-on: ubuntu-latest
  timeout-minutes: 90
  strategy:
    fail-fast: false
    matrix:
      config:
        - { name: default,            flags: "" }
        - { name: tree_borrows,       flags: "-Zmiri-tree-borrows" }
        - { name: strict_provenance,  flags: "-Zmiri-strict-provenance" }
        - { name: symbolic_alignment, flags: "-Zmiri-symbolic-alignment-check" }
  steps:
    - uses: actions/checkout@v4
    - uses: dtolnay/rust-toolchain@nightly
      with: { components: miri }
    - uses: Swatinem/rust-cache@v2
      with: { key: "miri-${{ matrix.config.name }}" }
    - name: Setup Miri
      run: cargo miri setup
    - name: Run Miri tests
      run: cargo miri test --lib
      continue-on-error: true
      env:
        MIRIFLAGS: "${{ matrix.config.flags }} -Zmiri-disable-isolation"
    - name: Upload Miri log
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: miri-${{ matrix.config.name }}-log
        path: ./*.log
```

Notes:
- **`fail-fast: false`** — one failing config shouldn't cancel the others; collect all signal.
- **Per-config cache key** — each `MIRIFLAGS` config builds to a separate target dir; caches don't share.
- **Artifact upload** — preserves logs for post-PR triage even though the job passes (continue-on-error).

---

## Extension: gating Miri on changed paths only

For large workspaces, full Miri matrix on every PR is expensive. Gate to changed paths:

```yaml
miri-quick:
  if: github.event_name == 'pull_request'
  steps:
    - uses: actions/checkout@v4
      with: { fetch-depth: 0 }
    - name: Detect changed crates
      id: changed
      run: |
        crates=$(git diff --name-only origin/main...HEAD \
                 | grep '^crates/' | awk -F/ '{print $2}' | sort -u)
        echo "crates=$crates" >> $GITHUB_OUTPUT
    - name: Miri on changed crates only
      run: |
        for crate in ${{ steps.changed.outputs.crates }}; do
          cargo miri test -p "$crate" --lib || true
        done
```

The full matrix only runs nightly (`schedule: cron: '0 0 * * *'`).

---

## Extension: blocking gates after audit lands

Once Phase 9 ladders close and the project is "UB-clean", upgrade the Miri job to blocking:

```yaml
miri-default:
  # was continue-on-error: true; after audit, gate hard
  steps:
    - run: cargo miri test --lib
      env: { MIRIFLAGS: -Zmiri-disable-isolation }
```

Drop `continue-on-error`. Now Miri findings block PR merge. This is what the `UB_RUNBOOK.md` recommends for projects post-audit.

---

## Extension: sanitizers + Miri together

Sanitizers complement Miri (Miri can't run FFI; sanitizers can). Add a separate job:

```yaml
sanitizers:
  strategy:
    fail-fast: false
    matrix:
      sanitizer: [address, thread, leak]
  runs-on: ubuntu-latest
  timeout-minutes: 30
  steps:
    - uses: actions/checkout@v4
    - uses: dtolnay/rust-toolchain@nightly
      with: { components: rust-src }
    - uses: Swatinem/rust-cache@v2
      with: { key: "san-${{ matrix.sanitizer }}" }
    - name: Run under sanitizer
      run: |
        export RUSTFLAGS="-Zsanitizer=${{ matrix.sanitizer }}"
        if [[ "${{ matrix.sanitizer }}" == "thread" ]]; then
          cargo test --target x86_64-unknown-linux-gnu -- --test-threads=1
        else
          cargo test --target x86_64-unknown-linux-gnu
        fi
```

---

## Honest-gap callout

Per cass deep mining round 2, the user has **not historically run** loom / shuttle / Kani / cargo-fuzz / TSan in their local sessions. The Miri-CI pattern above is real; the loom/shuttle/Kani/etc. extensions in the skill are **upgrade-path** recommendations, not codified existing practice.

If you're adopting the skill on a project that doesn't yet have these in CI:
1. Start with the corpus baseline (frankensearch-style non-blocking Miri).
2. Add the MIRIFLAGS matrix.
3. After Phase 9 closes, drop `continue-on-error` for the default config.
4. Add sanitizers only after stage 3 is stable.
5. Add loom / shuttle / Kani lanes incrementally, prioritized by where Phase 3 dynamic sweep found the most UB.

Don't try to add all six lanes in one review unit — too much CI volume to manage, too easy to flake.

---

## Cross-references

- cass Q-701 — verbatim source
- [TOOLING.md](TOOLING.md) — full tool matrix
- [LIFECYCLE.md](LIFECYCLE.md) — when to flip non-blocking to blocking
- [PHASES.md §Phase 12](PHASES.md#phase-12-final-artifacts) — where this lands in UB_RUNBOOK.md
