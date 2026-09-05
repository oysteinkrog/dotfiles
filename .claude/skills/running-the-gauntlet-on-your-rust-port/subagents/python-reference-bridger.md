# python-reference-bridger

> Phase 3 • For project classes whose reference is itself Python (Numerical / ML / HTTP-with-Python-ref / SQLModel / FastMCP). Builds the PyO3 in-process bridge with the reference imported into a sub-interpreter, with determinism flags pinned and per-call seeded RNG state captured.

## Inputs

- `<workspace>/phase0_project_class.json` (must be Numerical | ML | or a HTTP/Protocol-class with Python reference).
- `<workspace>/docs/contracts/<reference>_version_contract.toml`.

## Deliverables

- `crates/<port>-harness/src/python_bridge.rs` — the PyO3 bridge module.
- `crates/<port>-harness/src/determinism_flags.rs` — the per-class determinism contract enforcer.
- `crates/<port>-harness/src/seeded_rng.rs` — per-call seed capture + replay.
- `crates/<port>-harness/Cargo.toml` updated with `pyo3` + class-specific deps.
- `tests/python_bridge_smoke.rs` — smoke test that bridge imports the reference + executes one trivial op.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase3-python-bridge`
- **Reservations needed:** `tool://oracle-runner` (exclusive, TTL 1h).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

```
You are the python-reference-bridger. Your job is to wire the subject Rust port to
the Python reference via PyO3, with the reference imported into a sub-interpreter,
all determinism flags pinned, and per-call RNG state captured.

INPUTS:
- <workspace>/phase0_project_class.json
- <workspace>/docs/contracts/<reference>_version_contract.toml

PROJECT-CLASS GATE:
  class=$(jq -r .detected_class <workspace>/phase0_project_class.json)
  case "$class" in
    Numerical|ML|HTTPWithPythonRef|SQLModelClass|FastMCPClass) ;;
    *) echo "python-reference-bridger: not applicable for $class"; exit 0 ;;
  esac

STEPS:

1. Add PyO3 to <port>/crates/<port>-harness/Cargo.toml:
     [dependencies]
     pyo3 = { version = "0.23", features = ["auto-initialize"] }
     # Per-class extra:
     # Numerical: numpy = "0.23"
     # ML:        tch = "0.18" (or burn-tch), pyo3-asyncio = "..." if async
     # HTTP-Py:   reqwest, hyper

2. Write python_bridge.rs with:
   - A `PythonReference` struct holding `Py<PyModule>` for the imported reference.
   - `PythonReference::new()` calls `pyo3::Python::with_gil(|py| py.import("<reference>"))`.
   - `PythonReference::call(&self, op: &str, args: ...) -> Result<...>` dispatcher.
   - Per-class deserialization: numpy → ndarray; torch → Tensor; pandas → DataFrame; etc.

3. Write determinism_flags.rs — class-specific:
   - Numerical (numpy): assert numpy's `__version__` matches contract; pin BLAS threads via `OPENBLAS_NUM_THREADS=1`.
   - ML (torch): call `torch.use_deterministic_algorithms(True)`, `torch.backends.cudnn.deterministic=True`, `torch.backends.cudnn.benchmark=False`. Pin `CUBLAS_WORKSPACE_CONFIG=:4096:8`. Verify `torch.__version__`, `torch.cuda.is_available()`, `torch.cuda.get_device_name(0)`, `torch.backends.cudnn.version()`. Pin RNG via `torch.manual_seed(<S>)` + `numpy.random.seed(<S>)` + `random.seed(<S>)`.
   - JAX: call `jax.config.update('jax_enable_x64', True)`, `jax.config.update('jax_default_dtype_bits', '64')`. Pin RNG via `jax.random.PRNGKey(<S>)`.
   - HTTP-Py: deterministic clock via `freezegun.freeze_time(<T>)`; deterministic UUID via `uuid.UUID(int=<I>)`.
   - SQLModel: SQLAlchemy `pool_pre_ping=False`, deterministic UUID seed, deterministic timestamp.
   - FastMCP: deterministic JSON-RPC id sequence, deterministic clock.

4. Write seeded_rng.rs:
   - `SeedContract { fn derive_seed(corpus_entry_id: &str) -> u64 }`.
   - Per-call seed capture (write into the artifact id stack).
   - Replay verification (re-run with captured seed → same output).
   - NEVER `rand::random()`; NEVER `thread_rng()`.

5. Write tests/python_bridge_smoke.rs:
   - Test 1: import the reference; assert version matches contract.
   - Test 2: execute one trivial op (e.g., `numpy.array([1,2,3]).sum()` → 6).
   - Test 3: assert determinism — run the same op twice with the same seed; outputs byte-identical.
   - Test 4: EngineIdentity check — `subject_identity_label != reference_identity_label`.

6. Update phase3_oracle_wiring.md to record:
   - Python version detected
   - Reference version detected vs contract
   - Determinism flags applied
   - Smoke-test pass/fail

EXIT CRITERIA:
- All 5 source files written + smoke test passes locally.
- Determinism flags asserted in the smoke test (test 3).
- EngineIdentity check passes (test 4).

ESCALATION:
- Reference version mismatch → write certification_bundle/RELEASE_BLOCKED.md
  ("python reference version drift; re-run scope-decider Phase 2").
- Determinism flag fails to apply (e.g., torch determinism warns about unsupported op) →
  surface to FeatureUniverse builder as Excluded with rationale.
```

## Exit Criteria

- 5 source files written + smoke test green.
- Determinism flags asserted programmatically.
- EngineIdentity strict-distinct verified.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 3)
- [../references/patterns/05-SUBJECT-ORACLE-COMPARATOR.md](../references/patterns/05-SUBJECT-ORACLE-COMPARATOR.md)
- [../references/patterns/15-ENGINE-IDENTITY.md](../references/patterns/15-ENGINE-IDENTITY.md)
- [../references/taxonomy/PROJECT-CLASSES.md](../references/taxonomy/PROJECT-CLASSES.md) (Numerical / ML / HTTP rows)
- [../references/tooling/ORACLE-TOOLCHAIN.md](../references/tooling/ORACLE-TOOLCHAIN.md)
