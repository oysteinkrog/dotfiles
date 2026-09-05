# Language Profiles — Per-Language Fingerprint Patterns

Language-specific patterns for FINGERPRINT and VERIFY-ON-MAIN. The default heuristic in `triage-batch.sh` is good enough for Quick / Standard runs; language-specialist subagents use these profiles for Comprehensive runs.

---

## Rust

**Fingerprint patterns:**
- Functions: `^\+(\s*)(pub(\([^)]+\))? )?(unsafe )?(async )?(extern \"[^"]+\" )?fn (\w+)`
- Methods: `^\+(\s*)(pub(\([^)]+\))? )?(unsafe )?(async )?fn (\w+)\(&?(mut )?self`
- Types: `^\+(\s*)(pub(\([^)]+\))? )?(struct|enum|trait|union|type) (\w+)`
- Macros: `^\+(\s*)(pub )?macro_rules! (\w+)|^\+macro_rules! (\w+)`
- Tests: `#\[test\]` line followed by next `fn (\w+)` (multi-line pattern)
- Attribute macros: `^\+(\s*)#\[(\w+)`
- Constants: `^\+(\s*)(pub(\([^)]+\))? )?const (\w+)`

**Same-signature heuristic:**
- Compare param list character-by-character (ignoring whitespace)
- Compare return type (the `->` clause)
- Compare lifetimes only when both are explicit (`'a`, `'b`)
- Sample 3 functions per stash; if any disagree on signature shape, flip verdict

**Idiomatic-pattern checks (Expert mode):**
- Unwraps without justification → flag
- `.clone()` in hot paths → flag
- Missing `Result` in fallible operations → flag
- Lifetime annotations that could be elided → cosmetic; ignore in triage
- `unsafe` blocks → always surface to user, even on `superseded` verdict (unsafe code might have been backed out for safety reasons)

**Verify-on-main path scoping:**
- For functions: `git grep -F "fn $name" $primary -- 'src/**/*.rs' 'tests/**/*.rs'`
- For types: `git grep -F "$type_name" $primary -- 'src/**/*.rs'` (also matches uses, not just definition; that's fine — supersession means the symbol is around)

**Typical files:** `src/**/*.rs`, `tests/**/*.rs`, `benches/**/*.rs`, `examples/**/*.rs`, `build.rs`

---

## TypeScript / JavaScript

**Fingerprint patterns:**
- Functions: `^\+(\s*)(export )?(async )?function( \*)? (\w+)`
- Arrow exports: `^\+(\s*)(export )?(const|let|var) (\w+)\s*=\s*(async )?\([^)]*\)\s*=>`
- Methods: `^\+(\s*)(public |private |protected |static |async )*(\w+)\([^)]*\)\s*(:|{)`
- Types: `^\+(\s*)(export )?(class|interface|type|enum) (\w+)`
- Tests (Jest/Vitest): `^\+(\s*)(it|test|describe|beforeEach|afterEach)\(['"]([^'"]+)`
- Tests (Mocha): same patterns
- React components: `^\+(\s*)(export )?(default )?function ([A-Z]\w+)\(` (capitalized = component convention)
- React hooks: `^\+(\s*)(export )?const use[A-Z]\w+ =`

**Same-signature heuristic:**
- Compare param count + types (when annotated)
- Compare return type annotation
- Compare default values
- For TS, prefer ast-grep when available

**Idiomatic-pattern checks:**
- Missing `await` on a function returning Promise → flag
- `any` types where specific types could be inferred → cosmetic; ignore in triage
- Missing error handling on `fetch` / external calls → flag
- React hooks called conditionally → flag (rules-of-hooks violation)
- `useEffect` with missing deps → flag

**Typical files:** `src/**/*.{ts,tsx,js,jsx,mjs}`, `tests/**/*.{ts,tsx}`, `app/**/*.{ts,tsx}`, `pages/**/*.{ts,tsx}`

---

## Python

**Fingerprint patterns:**
- Functions: `^\+(\s*)(async )?def (\w+)`
- Classes: `^\+(\s*)class (\w+)`
- Decorators: `^\+(\s*)@(\w+(\.\w+)*)`
- Tests: `^\+(\s*)def (test_\w+)|^\+(\s*)class (Test\w+)`
- Tests (pytest fixtures): `^\+(\s*)@pytest\.fixture`
- Type aliases: `^\+(\s*)(\w+)\s*:\s*(TypeAlias|type)\s*=`

**Same-signature heuristic:**
- Compare param list (positional + kwargs + defaults)
- Compare return annotation
- Compare decorators (e.g., `@property` adds semantic difference)

**Idiomatic-pattern checks:**
- Mutable default arguments (`def foo(x=[])`) → flag
- `except:` (bare except) → flag
- `print` statements (vs. logger) → cosmetic; ignore in triage unless project's lint enforces
- Missing type hints on public APIs → cosmetic
- Async function not awaited → flag

**Typical files:** `**/*.py`, `tests/**/*.py`, `src/**/*.py`

---

## Go

**Fingerprint patterns:**
- Functions: `^\+func (\w+)|^\+func \([^)]+\) (\w+)`
- Types: `^\+type (\w+) (struct|interface|=)`
- Constants: `^\+const (\w+)|^\+const \(`
- Tests: `^\+func (Test\w+)|^\+func (Benchmark\w+)|^\+func (Example\w+)`

**Same-signature heuristic:**
- Compare param + return list (Go has explicit `(returnType, error)` etc.)
- Compare receiver type (`func (s *Server) Foo()` vs. `func Foo()`)
- Method sets matter for interface satisfaction

**Idiomatic-pattern checks:**
- Ignored errors (`_, err := ...; err = nil`) → flag
- `panic` instead of error return → flag
- Goroutines without context cancellation → flag

**Typical files:** `**/*.go`, `cmd/**/*.go`, `pkg/**/*.go`, `internal/**/*.go`

---

## Java

**Fingerprint patterns:**
- Methods: `^\+(\s*)(public |private |protected |static |final |abstract |synchronized )*\w+ (\w+)\(`
- Classes: `^\+(\s*)(public |abstract |final )*class (\w+)`
- Interfaces: `^\+(\s*)(public )?interface (\w+)`
- Enums: `^\+(\s*)(public )?enum (\w+)`
- Annotations: `^\+@(\w+)`

**Same-signature heuristic:**
- Param types + return type + thrown exceptions (`throws X, Y`)
- Generic type parameters (`<T extends ...>`)

**Typical files:** `src/main/java/**/*.java`, `src/test/java/**/*.java`

---

## Ruby

**Fingerprint patterns:**
- Methods: `^\+(\s*)def (\w+)`
- Classes: `^\+(\s*)class (\w+)`
- Modules: `^\+(\s*)module (\w+)`
- Tests (RSpec): `^\+(\s*)(describe|context|it|before|after) (['"][^'"]+)`
- Tests (Minitest): `^\+(\s*)def (test_\w+)`

**Same-signature heuristic:**
- Ruby's dynamic dispatch makes signature comparison weaker; rely more on test name presence

**Typical files:** `lib/**/*.rb`, `app/**/*.rb`, `spec/**/*.rb`, `test/**/*.rb`

---

## C / C++

**Fingerprint patterns:**
- Functions: `^\+(\s*)([\w:*&]+\s+)+(\w+)\([^)]*\)\s*(const)?(noexcept)?\s*(\{|;)`
- Structs/classes: `^\+(\s*)(struct|class|union) (\w+)`
- Templates: `^\+(\s*)template\s*<` (multi-line awareness needed)
- Macros: `^\+#define (\w+)`
- Tests (Google Test): `^\+TEST(_F)?\((\w+),\s*(\w+)\)`

**Same-signature heuristic:**
- Param types + return + qualifiers (`const`, `noexcept`, `override`)
- For C++: namespace context matters (`namespace foo { ... }`)

**Typical files:** `src/**/*.{c,cc,cpp,cxx,h,hh,hpp}`, `include/**/*.h`, `tests/**/*.{cc,cpp}`

---

## Kotlin

**Fingerprint patterns:**
- Functions: `^\+(\s*)(public |private |protected |internal |suspend |inline |operator )*fun (\w+)`
- Classes: `^\+(\s*)(public |private |internal |abstract |open |sealed |data )*class (\w+)`
- Objects: `^\+(\s*)(public |private |internal )?object (\w+)`
- Tests (JUnit/Spek): `^\+(\s*)@Test\s*\n\s*fun (\w+)|^\+(\s*)(describe|it)\(['"]`

---

## Swift

**Fingerprint patterns:**
- Functions: `^\+(\s*)(public |private |internal |fileprivate |open |static |class |final )*(@\w+ )*func (\w+)`
- Classes/structs: `^\+(\s*)(public |internal |open |final )*(class|struct|enum|protocol|extension) (\w+)`
- Tests: `^\+(\s*)func (test\w+)\(`

---

## Shell (bash/zsh/posix)

**Fingerprint patterns:**
- Functions: `^\+(\s*)(\w+)\s*\(\)\s*\{|^\+function (\w+)`
- Variables (top-level): `^\+([A-Z_]+)=` (uppercase convention)
- Tests (Bats): `^\+@test "([^"]+)"`

**Caveats:**
- Shell is hard to fingerprint reliably (lots of overloading via `function` keyword vs. POSIX form)
- Don't trust supersession verdicts on pure-shell stashes; surface to user

---

## SQL

**Fingerprint patterns:**
- DDL: `^\+(\s*)CREATE (TABLE|INDEX|VIEW|FUNCTION|PROCEDURE|TRIGGER) (\w+)`
- Migrations: filename matters more than diff content

**Caveats:**
- SQL "supersession" is hard: a CREATE TABLE statement isn't superseded by a similar statement on main (could be a divergent migration)
- Default to surfacing to user for SQL-only stashes

---

## YAML / TOML / JSON / config

**Fingerprint patterns:**
- Top-level keys
- Nested keys with values

**Default verdict:**
- Lockfiles (`Cargo.lock`, `package-lock.json`, `pnpm-lock.yaml`, `Gemfile.lock`, `poetry.lock`) → garbage (regenerate from manifest)
- Config files where the diff is meaningful → surface to user; rarely auto-classifiable

---

## Markdown / docs

**Fingerprint patterns:**
- Headings: `^\+#{1,6} (.+)`
- Code-block languages: `^\+\`\`\`(\w+)`

**Default verdict:**
- Doc-only stashes are usually `superseded` (the doc landed) or `garbage` (the doc was never finished)
- For doc-only stashes that are clearly novel, prefer the `documentation-website-for-software-project` skill for proper integration, not direct apply

---

## Polyglot Detection

If a stash touches files in multiple languages, the worker:
1. Fingerprints each file separately using its language profile
2. Computes per-file confidence; aggregates via min (the weakest fingerprint sets the row's confidence)
3. Classifies based on aggregate

For Comprehensive mode, polyglot stashes get a language-specialist subagent per language touched.

---

## Adding a New Language Profile

1. Add a section to this file with: fingerprint patterns, same-signature heuristic, idiomatic checks, typical files
2. Update `triage-batch.sh` if the language is common enough to warrant a built-in profile (vs. specialist subagent)
3. Add a `language-specialist-<lang>.md` subagent if the language has unique patterns
4. Add a worked example showing the language's typical stash classifications
