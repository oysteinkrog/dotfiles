# Syn Walkers

Rust source programs that walk a project's AST via `syn` to catch predicates
that ast-grep can't express (dataflow, lifetime tracking, comment density,
SAFETY-doc coverage).

## Layout

```
syn-walkers/
├── Cargo.toml         # helper crate manifest
├── Cargo.lock         # pinned helper dependencies for reproducible local builds
├── README.md          # this file
└── src/
    ├── lib.rs         # shared helpers (file walker, comment extractor)
    └── bin/
        ├── safety_doc_coverage.rs   # every `unsafe fn` has `# Safety` doc?
        ├── aliasing.rs              # shared-to-mutable pointer hazards
        ├── validity.rs              # zeroing / initialization validity hazards
        ├── transmute_pairs.rs       # extract (Src, Dst) for every transmute
        ├── data_races.rs            # unsafe Send/Sync impl review candidates
        ├── pin.rs                   # Pin::new_unchecked + move-hazard hints
        └── escape.rs                # raw pointer escapes borrow scope
```

## Build & run

```bash
cd scripts/syn-walkers
cargo build --release
target/release/safety_doc_coverage "$SOURCE"
target/release/aliasing "$SOURCE"
# … etc
```

Each walker prints `file:line: <diagnostic>` to stdout and a JSON summary to
stderr.

## Author guidance

When you discover a UB shape that needs cross-function reasoning (e.g., "this
raw pointer is constructed in `fn a` and used in `fn b` after the originator
returned"), write a walker rather than an ast-grep rule.

Helpers in `src/lib.rs`:
- `walk_files(dir) -> impl Iterator<Item=(PathBuf, syn::File)>` — yields each
  parsed `.rs` file under the provided source directory, skipping generated
  dependency/build directories such as `target/` and `node_modules/`
- `find_safety_comment(file, span) -> Option<String>` — extracts the
  preceding `// SAFETY:` comment, if any
- `is_zero_valid_typename(ty) -> bool` — judges simple primitive type names
  that admit an all-zero value

## Walker expectations

The bundled walkers are real heuristic sweeps, not proof engines. Treat a hit
as a candidate that must be confirmed with a reproducer, Miri/sanitizers/loom,
or a project-specific invariant argument before filing it as UB. When a project
needs deeper interprocedural reasoning, extend the nearest walker in place and
record the added predicate in the audit artifacts.
