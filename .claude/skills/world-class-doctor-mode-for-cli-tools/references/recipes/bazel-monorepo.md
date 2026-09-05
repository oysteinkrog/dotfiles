# Recipe: Bazel monorepo

**When to use.** The target uses Bazel as its build system: `WORKSPACE`, `WORKSPACE.bazel`, or `MODULE.bazel` (bzlmod) at the repo root, plus `BUILD.bazel` (or `BUILD`) files declaring targets per package. Multiple binaries are common (each `binary` rule in any `BUILD.bazel` is a candidate doctor surface).

**Examples we anticipate** (none in `/dp` yet): backends-of-microservices monorepos, ML training pipelines, Google-style codebases.

This recipe extends [monorepo-multi-cli.md](monorepo-multi-cli.md) with Bazel-specific details. The parent-doctor delegation pattern is the same; what differs is binary discovery, invocation, and test integration.

---

## Discovery

`scripts/discover-cli.sh` should detect Bazel when it sees:
- `WORKSPACE` or `WORKSPACE.bazel` (legacy)
- `MODULE.bazel` (bzlmod, current)

Binary candidates come from `BUILD.bazel` files. The canonical query:

```bash
bazel query 'kind("(.+)_binary rule", //...)' --output=label 2>/dev/null
```

Returns labels like `//cmd/server:server`, `//cli:my-cli`. Each label is a binary candidate. The doctor surface goes on whichever binary the user designates as canonical (typically the user-facing CLI).

For `discover-cli.sh` to handle Bazel, add a branch:

```bash
elif [ -f WORKSPACE ] || [ -f WORKSPACE.bazel ] || [ -f MODULE.bazel ]; then
    language="bazel"
    build_system="bazel"
    # Use `bazel query` to enumerate binary targets. Falls back gracefully if
    # bazel isn't installed (just sets language=bazel, binaries=[]).
    if command -v bazel >/dev/null 2>&1; then
        while IFS= read -r label; do
            [ -n "$label" ] && binaries+=("${label##*:}")
        done < <(bazel query 'kind(".*_binary rule", //...)' --output=label 2>/dev/null)
    fi
fi
```

(Implementing this is round-56 forward work; the recipe documents the pattern.)

---

## Where the parent doctor lives

A new package, conventionally `tools/doctor/`:

```
tools/
  doctor/
    BUILD.bazel
    doctor.go         # or doctor.rs, doctor.py — language follows the rest of the repo
    main.go
```

`tools/doctor/BUILD.bazel` declares:

```python
load("@rules_go//go:def.bzl", "go_binary", "go_library")

go_library(
    name = "doctor_lib",
    srcs = ["doctor.go"],
    importpath = "github.com/<org>/<repo>/tools/doctor",
    visibility = ["//visibility:public"],
)

go_binary(
    name = "doctor",
    embed = [":doctor_lib"],
    visibility = ["//visibility:public"],
)
```

Invocation:

```bash
bazel run //tools/doctor -- diagnose
bazel run //tools/doctor -- --fix
bazel run //tools/doctor -- capabilities --json
```

The `--` separates Bazel's own args from the doctor's args.

---

## Capabilities aggregation

The parent doctor's `capabilities --json` lists each sub-CLI as a `sub_doctors[]` entry per the [monorepo-multi-cli](monorepo-multi-cli.md) recipe. Each sub-CLI's invocation in Bazel is a label, not a binary path:

```jsonc
{
  "sub_doctors": [
    {
      "name": "server",
      "binary": "bazel run //cmd/server:server -- doctor",
      "version": "0.4.7"
    }
  ]
}
```

Note the full invocation string (including `bazel run` + label + `--` + args) — the parent doctor SHELL-INVOKES this when delegating, since each sub-CLI is built and run via Bazel.

---

## Test integration

Phase 5 safety harness (`run-safety-harness.sh`) uses `cargo test` / `pytest` / etc. depending on language. For Bazel:

```bash
bazel test //tools/doctor:doctor_test --test_output=errors
```

Bazel's hermetic test environment is ideal for fixture-based safety tests — no shared state between runs. Each `verify-*.sh` script should adapt to invoke the doctor via `bazel run`:

```bash
# In verify-undo.sh, when language=bazel:
bin_invocation=(bazel run //cmd/server:server --)
"${bin_invocation[@]}" doctor --fix --json
```

The parent doctor must NOT call `bazel build //...` at runtime (slow, side-effecting). It assumes Bazel has already built the targets in the user's workflow.

---

## Phase 8 integration (CI)

Bazel CI typically uses `bazel test //...` as the universal gate. Add a doctor-quick step:

```yaml
- run: bazel run //tools/doctor:doctor -- --quick --json
- run: bazel test //tools/doctor:doctor_test
```

Same exit-code-handling rules apply (catch 0|1 for the regression-check step).

---

## Known sharp edges

1. **Bazel's PATH is sandboxed.** When the parent doctor invokes `bazel run //sub:bin -- doctor`, the binary's PATH inside the sandbox is empty. If the sub-CLI's doctor uses `command -v jq` or similar, it will fail. Mitigation: declare runtime deps in `data = [...]` on the binary rule, OR run the doctor outside Bazel's sandbox (`bazel run` with `--enable_runfiles` in some configs).
2. **`bazel run` cold-start latency.** First invocation rebuilds; ~5-30s overhead. The `health` subcommand's < 200ms target is unreachable on cold start. Mitigation: have CI pre-warm with `bazel build //tools/doctor:doctor` before running `health`.
3. **Multi-language workspaces.** A Bazel monorepo can mix Go + Python + TypeScript. The skill currently assumes ONE language for `scaffold-doctor.sh`; for Bazel, the language follows the doctor's own implementation language, not the polyglot workspace.
4. **`MODULE.bazel` vs `WORKSPACE`.** Bzlmod is the current default; older repos use `WORKSPACE`. The discover branch should accept either.
5. **Visibility.** `tools/doctor:doctor` MUST have `visibility = ["//visibility:public"]` so the parent can be invoked from anywhere in the repo.

---

## Phase 4 implementer guidance

`scripts/scaffold-doctor.sh --language go` works as-is for the doctor module's source. Then HAND-WRITE `tools/doctor/BUILD.bazel` (no template currently). Future: a `--bazel-build` flag on scaffold-doctor.sh could emit the BUILD file too.
