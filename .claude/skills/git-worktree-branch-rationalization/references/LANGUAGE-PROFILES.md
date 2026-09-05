# Language Profiles — Per-Language Fingerprint Patterns for Phase 5 Triage

Language-specific patterns for [`✦ FINGERPRINT`](OPERATOR-LIBRARY.md) and [`◐ VERIFY-ON-CANONICAL`](OPERATOR-LIBRARY.md). The default heuristic in `scripts/triage-batch.sh` is good enough for Quick / Standard runs; language-specialist subagents use these profiles for Comprehensive and Council modes.

Adapted from [git-stash-janitor's LANGUAGE-PROFILES.md](../../git-stash-janitor/references/LANGUAGE-PROFILES.md). The fingerprint patterns are largely identical — the language hasn't changed between stashes and branches — but the *unit of fingerprint* is different: a stash gives you one diff against a known parent; a branch gives you `git diff <merge-base>..<branch>`, which can span many commits and many files. Per-file fingerprinting is more important here because a branch may legitimately introduce a symbol in commit 3, then refactor it in commit 7; the merge-base diff shows only the net effect.

> **Why:** [SKILL.md "Operator Library"](../SKILL.md#operator-library--the-cognitive-moves) — `✦ FINGERPRINT` is the load-bearing first step of every triage row. Language-correct extraction is the difference between a real verdict and a guessed verdict.

---

## How fingerprint extraction works at the branch level

For each non-protected branch B (and each dirty worktree W's combined diff):

1. Compute `merge_base = git merge-base <canonical> <B>`.
2. Run `git diff <merge_base> <B> --name-only` → list of touched files.
3. For each touched file, dispatch on its extension to a language profile below.
4. The profile yields five outputs per file: introduced functions, introduced types, introduced tests, introduced fixtures, file paths (always present).
5. Aggregate per-file outputs into the branch's overall fingerprint.

Per-language regex snippets below assume the input is the *output of `git diff`* — lines beginning with `+` indicate additions; the regex anchors on `^\+` to capture only what the branch added. Removals (`^-` lines) are not part of the fingerprint but are inputs to the same-signature heuristic.

For Comprehensive runs that have `ast-grep` available, prefer the ast-grep patterns (more accurate for multi-line constructs like generic types and lambda bodies).

The 8-scenario synthetic SELF-TEST repo at [SELF-TEST.md](../SELF-TEST.md) exercises every profile below; concrete examples are drawn from there.

---

## Rust

**Typical files:** `src/**/*.rs`, `tests/**/*.rs`, `benches/**/*.rs`, `examples/**/*.rs`, `build.rs`. Fixtures: `tests/fixtures/`, `tests/data/`, `tests/snapshots/` (insta), `*.snap`.

**Fingerprint patterns:**

| Construct | Regex | ast-grep pattern |
|-----------|-------|------------------|
| Functions | `^\+(\s*)(pub(\([^)]+\))? )?(unsafe )?(async )?(extern "[^"]+" )?fn (\w+)` | `fn $NAME($$$ARGS) $$$BODY` |
| Methods | `^\+(\s*)(pub(\([^)]+\))? )?(unsafe )?(async )?fn (\w+)\(&?(mut )?self` | `impl $TY { fn $NAME(&self, $$$) $$$ }` |
| Types | `^\+(\s*)(pub(\([^)]+\))? )?(struct\|enum\|trait\|union\|type) (\w+)` | `struct $NAME { $$$ }` etc. |
| Modules | `^\+(\s*)(pub(\([^)]+\))? )?mod (\w+)` | `mod $NAME { $$$ }` |
| Macros | `^\+(\s*)(pub )?macro_rules! (\w+)` | `macro_rules! $NAME { $$$ }` |
| Tests | `#\[test\]` line followed by next `fn (\w+)` (multi-line; capture pair) | `#[test] fn $NAME() $$$` |
| Test gating | `^\+\s*#\[cfg\(test\)\]` (signals a test module is being added/extended) | — |
| Constants | `^\+(\s*)(pub(\([^)]+\))? )?const (\w+)` | `const $NAME: $TY = $VAL;` |
| Attribute use | `^\+(\s*)#\[(\w+)` | `#[$ATTR]` |

**Same-signature heuristic** (used to validate `superseded` per [Axiom 16](../SKILL.md#the-rationalization-kernel-universal-axioms)):
- Compare the parameter list character-by-character (ignoring whitespace).
- Compare the return type (the `->` clause, including `-> Result<T, E>` shapes).
- Compare lifetimes only when both sides have explicit ones (`'a`, `'b`).
- Sample 3 introduced functions per branch; if any disagree on signature shape, flip the verdict to `divergent-refactor` (per Axiom 16) and surface to the user.

**Idiomatic-pattern checks (Comprehensive/Council mode):**
- `unwrap()` / `expect()` without justification → flag (the branch may have been *removing* defensive `?`s; that's a regression candidate).
- `.clone()` in hot paths → flag for performance review.
- Missing `Result` in fallible operations → flag.
- `unsafe` blocks → always surface to user, even on `superseded` verdict (unsafe code may have been backed out for safety reasons; harmonization may need to preserve it differently).
- `#[cfg(test)]` modules introduced — these always classify as `test` intent in the harmonization plan.

**Verify-on-canonical path scoping:**

```bash
# For functions
git grep -F "fn $name" "$canonical" -- 'src/**/*.rs' 'tests/**/*.rs'

# For types (matches uses + definition; that's fine — supersession means symbol is around)
git grep -F "$type_name" "$canonical" -- 'src/**/*.rs'

# For tests (test names rarely collide; if they do, the branch is likely a test reorganization)
git grep -F "fn $test_name" "$canonical" -- 'tests/**/*.rs' 'src/**/*.rs'
```

**Concrete example (from SELF-TEST scenario 3 — `feature/length-cap`):**

The branch's diff against canonical introduces:
```rust
+ pub fn cap_payload_length(buf: &[u8]) -> Result<&[u8], MysqlError> {
+     if buf.len() > MAX_PAYLOAD { return Err(MysqlError::PayloadTooLarge); }
+     Ok(buf)
+ }
+ #[cfg(test)]
+ mod tests {
+     #[test]
+     fn test_cap_payload_length_overflow() { ... }
+ }
```

Fingerprint extraction yields:
- functions: `cap_payload_length`
- tests: `test_cap_payload_length_overflow`
- types: (none introduced; `MysqlError` is from canonical)
- file paths: `src/mysql/protocol.rs`, `src/mysql/protocol.rs::tests`

VERIFY-ON-CANONICAL: `git grep -F "fn cap_payload_length" master -- 'src/**/*.rs'` returns empty → fingerprint absent → branch is novel-and-accretive (subject to apply-check).

---

## TypeScript / JavaScript

**Typical files:** `src/**/*.{ts,tsx,js,jsx,mjs,cjs}`, `tests/**/*.{ts,tsx,js}`, `app/**/*.{ts,tsx}`, `pages/**/*.{ts,tsx}`. Fixtures: `__fixtures__/`, `__mocks__/`, `__snapshots__/`, `*.snap`, `cypress/fixtures/`, `playwright/fixtures/`.

**Fingerprint patterns:**

| Construct | Regex |
|-----------|-------|
| Functions (declared) | `^\+(\s*)(export )?(async )?function( \*)? (\w+)` |
| Functions (arrow exports) | `^\+(\s*)(export )?(const\|let\|var) (\w+)\s*=\s*(async )?\([^)]*\)\s*=>` |
| Methods | `^\+(\s*)(public \|private \|protected \|static \|async )*(\w+)\([^)]*\)\s*(:\|{)` |
| Types | `^\+(\s*)(export )?(class\|interface\|type\|enum) (\w+)` |
| Tests (Jest/Vitest) | `^\+(\s*)(it\|test\|describe\|beforeEach\|afterEach)\(['"]([^'"]+)` |
| Tests (Mocha) | (same patterns) |
| Tests (Playwright) | `^\+(\s*)(test\|test\.describe)\(['"]([^'"]+)` |
| React components | `^\+(\s*)(export )?(default )?function ([A-Z]\w+)\(` (capitalized = component convention) |
| React hooks | `^\+(\s*)(export )?const use[A-Z]\w+ =` |
| Type aliases | `^\+(\s*)(export )?type (\w+)\s*=` |

**Same-signature heuristic:**
- Compare param count + types (when annotated).
- Compare return type annotation.
- Compare default values + optional parameter markers (`?`).
- For TS, prefer ast-grep when available: `function $NAME($$$ARGS): $RET { $$$ }`.

**Idiomatic-pattern checks:**
- Missing `await` on a function returning Promise → flag.
- `any` types introduced where specific types could be inferred → cosmetic; ignore in triage unless project's `tsconfig.json` has `strict: true` AND `noImplicitAny: true`.
- Missing error handling on `fetch` / external calls → flag.
- React hooks called conditionally → flag (rules-of-hooks violation; harmonization synthesis must not preserve this).
- `useEffect` with missing deps → flag.
- New `console.log` in non-test code → flag (often left over from agent debug sessions; usually `garbage` intent at the hunk level).

**Concrete example (SELF-TEST scenario 5 — `feature/redact-secrets`):**

```typescript
+ export function redactSecrets(msg: string): string {
+   return msg.replace(/sk_live_\w+/g, '[REDACTED]');
+ }
+ describe('redactSecrets', () => {
+   it('redacts Stripe live keys', () => { ... });
+ });
```

Fingerprint:
- functions: `redactSecrets`
- tests (descriptions): `'redactSecrets > redacts Stripe live keys'`
- file paths: `src/util/logger.ts`, `tests/util/logger.test.ts`

---

## Python

**Typical files:** `**/*.py`, `tests/**/*.py`, `src/**/*.py`. Fixtures: `tests/fixtures/`, `tests/data/`, `conftest.py` (pytest fixture definitions).

**Fingerprint patterns:**

| Construct | Regex |
|-----------|-------|
| Functions | `^\+(\s*)(async )?def (\w+)` |
| Classes | `^\+(\s*)class (\w+)` |
| Decorators | `^\+(\s*)@(\w+(\.\w+)*)` |
| Tests | `^\+(\s*)def (test_\w+)` or `^\+(\s*)class (Test\w+)` |
| pytest fixtures | `^\+(\s*)@pytest\.fixture` followed by next `def (\w+)` |
| Type aliases | `^\+(\s*)(\w+)\s*:\s*(TypeAlias\|type)\s*=` |

**Same-signature heuristic:**
- Compare param list (positional + kwargs + defaults).
- Compare return annotation (`-> ReturnType`).
- Compare decorators (e.g., `@property` adds semantic difference).
- Async-ness matters (`async def` vs `def`).

**Idiomatic-pattern checks:**
- Mutable default arguments (`def foo(x=[])`) → flag (always a bug latent or actual).
- `except:` (bare except) → flag.
- `print` statements in non-CLI code → flag if project uses logging.
- Missing type hints on public APIs → cosmetic unless project has `mypy --strict`.
- Async function not awaited at call sites → flag.

**Verify-on-canonical specifics:**

The `conftest.py` files matter — pytest fixtures defined in `tests/conftest.py` are visible to all sibling tests. A branch that adds a fixture to `conftest.py` is making a wider semantic change than a branch that adds the fixture inline. Treat `conftest.py` modifications as `fixture` intent in the harmonization plan.

**Concrete example (SELF-TEST scenario 4 — `agent-cleanup-pass-3`):**

```python
+ def redact_secrets(msg: str) -> str:
+     return re.sub(r'sk_live_\w+', '[REDACTED]', msg)
+
+ @pytest.fixture
+ def stripe_test_keys():
+     return ['sk_live_abc', 'sk_test_def']
```

Fingerprint:
- functions: `redact_secrets`
- fixtures: `stripe_test_keys`
- file paths: `src/util/logger.py`, `tests/conftest.py`

---

## Go

**Typical files:** `**/*.go`, `cmd/**/*.go`, `pkg/**/*.go`, `internal/**/*.go`. Test files: `*_test.go` (Go's convention is the test lives next to the file under test). Fixtures: `testdata/` (Go's standard).

**Fingerprint patterns:**

| Construct | Regex |
|-----------|-------|
| Functions | `^\+func (\w+)` or `^\+func \([^)]+\) (\w+)` |
| Types | `^\+type (\w+) (struct\|interface\|=)` |
| Constants | `^\+const (\w+)` or `^\+const \(` |
| Tests | `^\+func (Test\w+)` |
| Benchmarks | `^\+func (Benchmark\w+)` |
| Examples | `^\+func (Example\w+)` |

**Same-signature heuristic:**
- Compare param + return list (Go has explicit `(returnType, error)` etc.).
- Compare receiver type (`func (s *Server) Foo()` vs `func Foo()`).
- Method sets matter for interface satisfaction; if a branch changes a receiver from value to pointer, that's a refactor intent.

**Idiomatic-pattern checks:**
- Ignored errors (`_, err := ...; err = nil`) → flag.
- `panic` instead of error return → flag.
- Goroutines without context cancellation → flag.
- Test files without `t.Parallel()` when other sibling tests have it → cosmetic.

**Concrete example:**

```go
+ func capPayloadLength(buf []byte) ([]byte, error) {
+     if len(buf) > MaxPayload {
+         return nil, ErrPayloadTooLarge
+     }
+     return buf, nil
+ }
+ func TestCapPayloadLength_Overflow(t *testing.T) { ... }
```

Fingerprint:
- functions: `capPayloadLength`, `TestCapPayloadLength_Overflow`
- types: (none introduced; `ErrPayloadTooLarge` is from canonical)
- file paths: `mysql/protocol.go`, `mysql/protocol_test.go`

---

## Bash / Shell

**Typical files:** `**/*.sh`, `**/*.bash`, `**/*.zsh`, `bin/*` (often shell), `scripts/*`. Test files: Bats (`*.bats`), shellspec (`spec/*.sh`).

**Fingerprint patterns:**

| Construct | Regex |
|-----------|-------|
| Functions (POSIX form) | `^\+(\s*)(\w+)\s*\(\)\s*\{` |
| Functions (function keyword) | `^\+function (\w+)` |
| Variables (top-level) | `^\+([A-Z_]+)=` (uppercase convention) |
| Tests (Bats) | `^\+@test "([^"]+)"` |
| Command-substitution captures | `^\+(\w+)=\$\(([^)]+)\)` (the captured command is part of the fingerprint) |

**Caveats:**
- Shell is hard to fingerprint reliably (lots of overloading via `function` keyword vs POSIX form, alias re-binding, sourced files).
- Don't trust supersession verdicts on pure-shell branches; surface to user.
- A function defined in a script the branch sources (`source lib/foo.sh`) doesn't appear in the branch's diff but does affect the script's behavior — the harmonization plan must consider sourced-file dependencies.

**Concrete example (SELF-TEST scenario 7 — bash CLI tool):**

```bash
+ check_disk_space() {
+   local needed_mb="$1"
+   local available_mb
+   available_mb=$(df -m / | awk 'NR==2 {print $4}')
+   [[ "$available_mb" -ge "$needed_mb" ]]
+ }
```

Fingerprint:
- functions: `check_disk_space`
- variables: (local-scoped; not part of top-level fingerprint)
- file paths: `bin/cleanup.sh`

---

## C / C++

**Typical files:** `src/**/*.{c,cc,cpp,cxx,h,hh,hpp}`, `include/**/*.h`, `tests/**/*.{cc,cpp}`. Fixtures: `tests/fixtures/`, `tests/data/`.

**Fingerprint patterns:**

| Construct | Regex |
|-----------|-------|
| Functions | `^\+(\s*)([\w:*&]+\s+)+(\w+)\([^)]*\)\s*(const)?(noexcept)?\s*(\{|;)` |
| Structs / classes | `^\+(\s*)(struct\|class\|union) (\w+)` |
| Templates | `^\+(\s*)template\s*<` (multi-line awareness needed) |
| Macros | `^\+#define (\w+)` |
| Tests (Google Test) | `^\+TEST(_F)?\((\w+),\s*(\w+)\)` |
| Tests (Catch2) | `^\+TEST_CASE\("([^"]+)"\)` |

**Same-signature heuristic:**
- Param types + return + qualifiers (`const`, `noexcept`, `override`, `final`).
- For C++: namespace context matters (`namespace foo { ... }`); a function `foo::bar()` and `baz::bar()` are different.
- Templates: parameter pack equivalence is hard; surface to user when the only difference is a template parameter.

**Idiomatic-pattern checks:**
- Raw `new` / `delete` without RAII → flag.
- `printf`-family without bounds-checking → flag.
- Missing `const` on getters → cosmetic.
- New `#include` of a banned-header (project-specific list) → flag.

**Concrete example:**

```cpp
+ namespace mysql {
+ Result<std::span<const std::byte>> cap_payload_length(std::span<const std::byte> buf) {
+   if (buf.size() > MAX_PAYLOAD) return ErrPayloadTooLarge;
+   return buf;
+ }
+ }
+ TEST(MysqlProtocol, CapPayloadLengthOverflow) { ... }
```

Fingerprint:
- functions: `mysql::cap_payload_length` (namespace-qualified)
- tests: `MysqlProtocol::CapPayloadLengthOverflow` (TEST-fixture-qualified)
- file paths: `src/mysql/protocol.cpp`, `tests/mysql_protocol_test.cpp`

---

## Java

**Typical files:** `src/main/java/**/*.java`, `src/test/java/**/*.java`. Fixtures: `src/test/resources/`.

**Fingerprint patterns:**

| Construct | Regex |
|-----------|-------|
| Methods | `^\+(\s*)(public \|private \|protected \|static \|final \|abstract \|synchronized )*\w+ (\w+)\(` |
| Classes | `^\+(\s*)(public \|abstract \|final )*class (\w+)` |
| Interfaces | `^\+(\s*)(public )?interface (\w+)` |
| Enums | `^\+(\s*)(public )?enum (\w+)` |
| Annotations (use) | `^\+\s*@(\w+)` |
| Tests (JUnit 4/5) | `@Test` followed by next method declaration |

**Same-signature heuristic:**
- Param types + return type + thrown exceptions (`throws X, Y` is part of the signature).
- Generic type parameters (`<T extends ...>`).
- Annotations on the method (`@Override`, `@Deprecated`) matter.

**Concrete example:**

```java
+ @Test
+ public void testCapPayloadLengthOverflow() throws MysqlException { ... }
+
+ public byte[] capPayloadLength(byte[] buf) throws MysqlException { ... }
```

Fingerprint:
- methods: `capPayloadLength`, `testCapPayloadLengthOverflow`
- file paths: `src/main/java/com/example/mysql/Protocol.java`, `src/test/java/com/example/mysql/ProtocolTest.java`

---

## SQL

**Typical files:** `migrations/*.sql`, `db/schema/*.sql`, `*.sql`.

**Fingerprint patterns:**

| Construct | Regex |
|-----------|-------|
| DDL (creation) | `^\+(\s*)CREATE (TABLE\|INDEX\|VIEW\|FUNCTION\|PROCEDURE\|TRIGGER\|MATERIALIZED VIEW) (\w+)` |
| DDL (alteration) | `^\+(\s*)ALTER TABLE (\w+) (ADD\|DROP\|RENAME)` |
| DML in migrations | `^\+(\s*)(INSERT\|UPDATE\|DELETE) (INTO )?(\w+)` |

**Caveats:**
- SQL "supersession" is hard: a `CREATE TABLE` statement isn't superseded by a similar statement on canonical (could be a divergent migration with different defaults, different constraints, different indexes).
- Default to surfacing to user for SQL-only branches.
- Migration filename matters more than diff content. A branch whose only diff is `migrations/20260507_add_user_email.sql` should be triaged as `novel-but-stale` if canonical's migrations now include `20260601_add_user_contact.sql` that supersedes it; surface to user.

**Concrete example:**

```sql
+ CREATE TABLE webhook_events (
+   id UUID PRIMARY KEY,
+   provider TEXT NOT NULL,
+   payload JSONB NOT NULL,
+   received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
+ );
+ CREATE INDEX idx_webhook_events_provider ON webhook_events(provider);
```

Fingerprint:
- DDL creations: `webhook_events` (table), `idx_webhook_events_provider` (index)
- file paths: `migrations/20260507_add_webhook_events.sql`

---

## Markdown / Documentation

**Typical files:** `**/*.md`, `**/*.mdx`, `docs/**/*`, `README.md`, `AGENTS.md`, `CHANGELOG.md`.

**Fingerprint patterns:**

| Construct | Regex |
|-----------|-------|
| Headings (introduced) | `^\+#{1,6} (.+)` |
| Code-block languages | `^\+\`\`\`(\w+)` |
| Internal links | `^\+.*\[([^\]]+)\]\(([^)]+\.md[^)]*)\)` |

**Default verdict:**
- Doc-only branches are usually `superseded` (the doc landed via PR with a different branch name) or `garbage` (the doc was never finished).
- Heading-level changes only (`# Foo` → `## Foo`) usually classify as `superseded` — the canonical version is the authoritative IA.
- For doc-only branches that introduce genuinely novel content, prefer the [`documentation-website-for-software-project`](../../documentation-website-for-software-project/SKILL.md) skill for proper integration, not direct apply.

**Caveats:**
- README diffs are often *re-ordered* rather than *added* — a branch that adds an "Installation" section may have been superseded by canonical's "Getting Started" section that says the same thing differently. Don't classify as novel-and-accretive without checking content equivalence, not just heading-name.

---

## Config — YAML / TOML / JSON

**Typical files:** `*.yaml`, `*.yml`, `*.toml`, `*.json`, `Cargo.toml`, `pyproject.toml`, `package.json`, `.github/workflows/*.yml`, `.gitlab-ci.yml`.

**Fingerprint patterns:**

| Construct | Pattern |
|-----------|---------|
| Top-level keys | `^\+(\w[\w-]*):` (YAML/TOML at column 0) |
| Nested keys with values | per-line key extraction; value-equality is the meaningful comparison |

**Default verdict:**
- Lockfiles (`Cargo.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `Gemfile.lock`, `poetry.lock`, `go.sum`) → almost always `garbage` (regenerate from manifest after merging the manifest changes).
- Manifest files (`Cargo.toml`, `package.json`, `pyproject.toml`, `go.mod`) — surface to user; rarely auto-classifiable. A new dependency entry could be novel-and-accretive (the dep is genuinely needed) or could be a forgotten experiment.
- CI workflow files (`.github/workflows/*.yml`) — surface to user; CI changes deserve human review.

**Concrete example — `garbage` lockfile churn:**

```diff
- "version": "1.2.3",
+ "version": "1.2.4",
- "integrity": "sha512-abc...",
+ "integrity": "sha512-def...",
```

That's lockfile-update-only, no manifest changes. Fingerprint is empty (no symbols introduced); name often matches `dependabot/*` or `renovate/*` (auto-protected per [Mozilla EX-4](EXEMPLARS.md#ex-4--mozillas-branch-protection--dependabot-conventions)). When a branch isn't auto-protected and its only diff is lockfile churn, default to `garbage`.

---

## Polyglot Detection

If a branch touches files in multiple languages, the worker:

1. Fingerprints each file separately using its language profile.
2. Computes per-file confidence; aggregates via min (the weakest fingerprint sets the row's confidence).
3. Classifies based on aggregate.

For Comprehensive mode, polyglot branches get a language-specialist subagent per language touched.

**Common polyglot patterns:**

- Rust/TS monorepo (Cargo workspace + Next.js) — branch may add a Rust API endpoint AND its TS client. Treat as one logical unit; the harmonization plan groups them.
- Python/SQL — branch may add an ORM model AND its migration. Migrations are harder to harmonize (see SQL caveats); surface to user.
- Bash/Rust — installer scripts paired with a Rust CLI; the bash side is usually `superseded` if the Rust side is.

---

## Adding a New Language Profile

1. Add a section to this file with: typical files, fingerprint patterns table, same-signature heuristic, idiomatic-pattern checks, a concrete example.
2. Update `scripts/triage-batch.sh` if the language is common enough to warrant a built-in profile (vs. specialist subagent).
3. Add a `subagents/language-specialist-<lang>.md` if the language has unique patterns.
4. Add a SELF-TEST scenario exercising the language so the profile gets regression coverage.

When in doubt about a language not listed here, the default heuristic (regex on `^\+(?:fn|def|function|class|struct|interface|type|impl|trait|enum) (\w+)`) covers ~80% of cases. Surface lower-confidence matches to the user.
