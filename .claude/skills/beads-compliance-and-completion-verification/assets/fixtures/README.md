# Audit Fixture Library

Synthetic test projects used to regression-test the audit infrastructure
itself. When you change the rubric, add a new theater pattern, or upgrade a
subagent prompt, run `scripts/regression-test.sh` to verify the audit still
produces the right verdicts on these known cases.

## Layout

```
assets/fixtures/
├── README.md                # this file
├── known-good/
│   ├── seed.sh              # bash script that creates a real .beads/ + impl
│   └── EXPECTED.md          # asserts what the audit should say
├── theater-only/
│   ├── seed.sh              # creates a closed bead with stub implementation
│   └── EXPECTED.md          # asserts the audit flags it as false-closed
└── …                        # add more fixtures via scripts/regenerate-fixture.sh
```

## Running the suite

```bash
# All fixtures:
scripts/regression-test.sh

# One fixture:
scripts/regression-test.sh --only known-good

# Keep tmp dirs after success (default: keep only on failure):
scripts/regression-test.sh --keep-tmp
```

## How a fixture works

1. **`seed.sh`** runs in a fresh tmp dir. It must:
   - `git init -q`
   - `br init` (or set up `.beads/` with a SQLite db some other way)
   - Create at least one bead via `br create` and (usually) close it via `br close`
   - Create matching implementation files in the project tree (or NOT,
     depending on the fixture's intent)

2. **`EXPECTED.md`** must contain a `## Assertions` section. Each bullet is
   a check `compare-to-expected.py` will verify. Supported assertion verbs:

   ```
   total_beads: N
   closed_count: N
   false_closed_count: N
   false_closed_includes: <bead-id>
   false_closed_excludes: <bead-id>
   score_min_for: <bead-id> >= N
   score_max_for: <bead-id> <= N
   verdict_band_for: <bead-id> == "<band-name-substring>"
   contains_text: "..."
   ```

3. **regression-test.sh** runs each fixture's seed.sh in `/tmp/audit-fixture-<name>-<unix>/`,
   audits with `run-pass.sh --policy report-only`, and runs `compare-to-expected.py`
   against the fixture's EXPECTED.md. Tmp dirs are removed on success, kept
   on failure for inspection.

## Adding a new fixture

```bash
# 1. Create the directory:
mkdir -p assets/fixtures/<descriptive-name>
# 2. Author seed.sh (write the bead-creation + impl-file commands).
# 3. Run regenerate-fixture.sh to capture the audit's actual output as EXPECTED.md:
scripts/regenerate-fixture.sh <descriptive-name>
# 4. Hand-verify EXPECTED.md is what the audit *should* say. Edit if needed.
# 5. Commit seed.sh + EXPECTED.md.
```

## Why fixtures matter

The audit is itself code. Code needs tests. Without fixtures, a rubric tweak
that quietly breaks scoring on `closed-but-stubbed` beads would ship
silently. With fixtures, the change either passes the suite (good) or fails
on the `theater-only` fixture (caught before merge).
