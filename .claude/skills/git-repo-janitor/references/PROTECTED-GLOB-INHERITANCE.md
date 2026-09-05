# Protected Glob Inheritance

Each archetype's `protected_globs` list is built by inheriting from a base set, then layering archetype-specific overrides, then layering user-supplied additions. This reference codifies the inheritance rules so the agent can compute the final set deterministically.

---

## Inheritance hierarchy

```
base
 └── archetype (single-rust-crate / polyglot-monorepo / claude-skill-repo / nextjs-saas / ...)
       └── archetype-extensions (LFS, submodules, polyglot subtrees)
             └── user-supplied (from Phase 0 review)
                   └── final protected_globs
```

Higher levels override lower levels (additive only — globs are never removed by inheritance).

---

## Layer 1 — Base (always)

Every archetype inherits these:

```
README.md
README*
LICENSE
LICENSE*
COPYING
NOTICE
.gitignore
.gitattributes
.gitmodules
AGENTS.md
CLAUDE.md
GEMINI.md
.cursor/rules/**
.github/copilot-instructions.md
CHANGELOG.md
CHANGES.md
HISTORY.md
.editorconfig
.pre-commit-config.yaml
.lefthook.yml
.husky/**
```

These are universally protected. Removing or moving them would break repo norms.

---

## Layer 2 — Archetype-specific

### `single-rust-crate`

```
Cargo.toml
Cargo.lock
rust-toolchain.toml
rust-toolchain
build.rs
deny.toml
.ubsignore
.rchignore
.cargo/**
src/**
tests/**
benches/**
examples/**
```

### `polyglot-monorepo`

Inherits per-language layers (see below) for each detected language. Plus:

```
docker-compose.yml
docker-compose*.yml
compose.yaml
compose.*.yaml
Dockerfile
Dockerfile.*
.dockerignore
Makefile
GNUmakefile
justfile
.envrc
flake.nix
flake.lock
```

### `claude-skill-repo`

```
.claude/**
SKILL.md
references/**
subagents/**
assets/**
scripts/**
SELF-TEST.md
```

### `nextjs-saas`

```
package.json
package-lock.json
pnpm-lock.yaml
yarn.lock
bun.lockb
next.config.*
tailwind.config.*
postcss.config.*
tsconfig.json
tsconfig.base.json
tsconfig.*.json
playwright.config.*
middleware.ts
middleware.js
app/**
pages/**
components/**
lib/**
hooks/**
public/**
styles/**
prisma/**
supabase/**
drizzle/**
e2e/**
.env.example
.env.template
.env.sample
.env.test
vercel.json
.vercel/**
```

### `python-package`

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
conftest.py
```

### `go-cli`

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
```

### `mixed-rust-and-frontend`

Union of `single-rust-crate` and `nextjs-saas` (or generic web frontend).

### `unknown`

Falls back to base only. Phase 0 must ask the user to confirm before any work.

---

## Layer 3 — Archetype extensions

### LFS-tracked subtree

When `git lfs ls-files` returns non-empty, add:

```
.gitattributes  # already in base
*.bin   # if LFS-tracked
*.zip
*.tar.gz
*.dmg
*.iso
*.font  # if Webfonts in LFS
```

(Only the patterns matching actual LFS-tracked content; the skill detects them per-repo.)

### Submodule extension

When `.gitmodules` exists, add:

```
.gitmodules  # already in base
<submodule-path>/**  # union of all submodule paths
```

The submodule subtrees are out-of-scope for cleanup (handled by per-submodule skill instances).

### Polyglot extension (Rust + Python + Go in one repo)

Layer all language-specific protected lists. E.g., `polyglot-monorepo` with Rust + Python:

```
# from rust:
Cargo.toml, Cargo.lock, rust-toolchain.toml, build.rs, deny.toml, src/**, tests/**, benches/**

# from python:
pyproject.toml, requirements*.txt, src/**, tests/**

# union:
Cargo.toml, Cargo.lock, rust-toolchain.toml, build.rs, deny.toml,
pyproject.toml, requirements*.txt,
src/**, tests/**, benches/**
```

---

## Layer 4 — User-supplied (Phase 0 review)

After the auto-derived list, the user reviews and may add:

```yaml
# user-supplied additions for this run
- path/to/intentional-test-fixture.db
- assets/branding/**
- spec_evolution_v1.sqlite3   # frankensqlite-specific intentional commit
- third_party_vendored/**
```

**Users can ADD but cannot REMOVE archetype-derived protected globs.** If the user wants to "unprotect" something (treat `Cargo.toml` as a candidate), they must override per-row at Phase 5, not through the protected_globs mechanism.

---

## Computation order

```python
def compute_protected_globs(archetype, lfs_present, submodule_paths, user_supplied):
    globs = set(LAYER_1_BASE)

    if archetype == "polyglot-monorepo":
        for lang in detected_languages:
            globs |= LAYER_2_BY_ARCHETYPE[lang]
    else:
        globs |= LAYER_2_BY_ARCHETYPE[archetype]

    if lfs_present:
        globs |= compute_lfs_extension()

    if submodule_paths:
        globs |= compute_submodule_extension(submodule_paths)

    globs |= set(user_supplied)

    return sorted(globs)
```

The result is written to `project_profile.json`'s `protected_globs` field.

---

## Verification

For each protected glob in the final set, the skill verifies it actually matches at least one tracked file:

```bash
for glob in $protected_globs:
    matching=$(git ls-files "$glob" | head -1)
    if [[ -z "$matching" ]] AND [[ "$glob" not in BASE_PATTERNS ]]:
        echo "WARN: protected glob '$glob' matches zero tracked files; remove?"
```

Globs that don't match anything are surfaced for user review (they may be aspirational or stale).

---

## How protected globs interact with verdicts

A file matching a protected glob:

- Verdict is forced to `protected` regardless of smell tags.
- Confidence is 1.0.
- Phase 4 triage workers SKIP these files entirely.
- Phase 5 plan does not include them in any category.

This is the strongest verdict in the rubric. The user cannot override it without removing the glob first.

---

## Worked example: skill-repo + LFS extension

A claude-skill-repo with LFS-tracked illustration `.png`s in `assets/`:

**Layer 1 (base):**
```
README.md, README*, LICENSE*, AGENTS.md, .gitignore, .gitattributes, ...
```

**Layer 2 (claude-skill-repo):**
```
.claude/**, SKILL.md, references/**, subagents/**, assets/**, scripts/**, SELF-TEST.md
```

**Layer 3 (LFS extension):**
```
*.png  # because LFS-tracks them
*.webp
```

**Layer 4 (user-supplied):**
```
data/**  # user adds because their skill ships sample data
```

**Final union (protected_globs):**
```
README.md, README*, LICENSE*, AGENTS.md, .gitignore, .gitattributes, .gitmodules,
CHANGELOG.md, CHANGES.md, .editorconfig, .pre-commit-config.yaml, .lefthook.yml,
.cursor/rules/**, .github/copilot-instructions.md,
.claude/**, SKILL.md, references/**, subagents/**, assets/**, scripts/**, SELF-TEST.md,
*.png, *.webp,
data/**
```

These globs are NEVER triaged. A `*.png` in `assets/` is implicitly protected by both archetype and LFS extension layers.

---

## Why explicit inheritance matters

**Without inheritance:**
- Each archetype's protected_globs is a copy-paste of the base + archetype-specific
- Updating the base requires updating every archetype
- Polyglot monorepos can't combine archetypes cleanly
- LFS interaction is bolted on per-archetype

**With inheritance:**
- Base updates propagate automatically
- Polyglot is the union of language layers
- LFS extension is a single rule applied conditionally
- User-supplied is explicit and transparent
- The final set is auditable: "this glob is protected because of which layer?"

This pattern mirrors `wills-and-estate-planning-skill`'s state-by-state verification matrix and `saas-billing-patterns-for-stripe-and-paypal`'s conditional bundle activation.

---

## When the inheritance is wrong

If the auto-derived protected_globs over-protects (a file the user wants to triage is matched), the user adjusts:

- Phase 0: user removes the glob from the proposed list (allowed only for user-supplied additions, NOT for archetype-derived)
- Phase 5: user overrides the verdict per-row ("actually, treat this `.gitkeep` as `delete-and-gitignore`")

If the auto-derived list under-protects (a critical file shows up as a candidate), the user adds to user-supplied at Phase 0.

The first kind of error is more common (user wants to delete a `.gitkeep` they no longer need); the second kind is rare in practice.
