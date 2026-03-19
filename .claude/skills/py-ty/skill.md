---
name: py-ty
description: |
  Run ty (Astral's Python type checker) on Python code. Use when writing, editing,
  or reviewing Python code to catch type errors. Triggers on: writing Python files,
  "type check", "run ty", "check types", or after editing .py files.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
---

# ty — Python Type Checker (Astral)

Fast Python type checker written in Rust. 10-100x faster than mypy/Pyright.
**Repo:** https://github.com/astral-sh/ty

## When to use

Run `ty check` after writing or editing Python code. Always type-check before
considering a Python task complete.

## Installation

```bash
uv tool install ty@latest        # preferred
# or: pip install ty
# or: curl -LsSf https://astral.sh/ty/install.sh | sh
```

## Key commands

```bash
ty check                          # check current directory
ty check src/                     # check specific path
ty check --python-version 3.11    # target Python version
ty check --watch                  # incremental watch mode
ty check --output-format concise  # shorter output
ty check --error-on-warning       # strict mode
```

## Configuration

In `pyproject.toml`:
```toml
[tool.ty]
python-version = "3.11"

[tool.ty.rules]
# severity: "error", "warn", "ignore"
division-by-zero = "warn"
index-out-of-bounds = "error"
```

Or in `ty.toml`:
```toml
[rules]
empty-body = "error"
```

## Workflow

1. After writing/editing Python code, run `ty check` on the affected files
2. Fix any type errors found
3. Re-run until clean
4. If a rule is intentionally violated, suppress with `# type: ignore[rule-name]`

## Output formats

`full` (default), `concise`, `github`, `gitlab`, `junit`
