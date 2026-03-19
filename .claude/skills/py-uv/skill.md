---
name: py-uv
description: |
  Manage Python projects with uv (Astral's package/project manager). Use when
  creating Python projects, adding dependencies, running scripts, or managing
  Python versions. Triggers on: "create python project", "add dependency",
  "uv init", "uv add", "run python", "install package", or Python project setup.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
---

# uv — Python Package & Project Manager (Astral)

Blazingly fast Python package and project manager written in Rust. Replaces pip,
pip-tools, pipx, poetry, pyenv, and virtualenv.
**Repo:** https://github.com/astral-sh/uv

## When to use

Use `uv` for ALL Python project management: creating projects, adding dependencies,
running scripts, managing Python versions, and installing tools.

## Installation

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh   # standalone
# or: pip install uv
# self-update: uv self update
```

## Key commands

### Project management
```bash
uv init my-project                # create new project
uv add requests fastapi           # add dependencies
uv add --dev pytest ruff ty       # add dev dependencies
uv remove requests                # remove dependency
uv sync                           # sync environment with lockfile
uv lock                           # generate/update lockfile
uv tree                           # show dependency tree
```

### Running code
```bash
uv run script.py                  # run in project environment
uv run --with requests script.py  # run with extra deps
uv run python                     # launch Python REPL
```

### Python version management
```bash
uv python install 3.12            # install Python version
uv python pin 3.12                # pin version (.python-version)
uv python list                    # list available versions
```

### Tool management
```bash
uv tool install ruff              # install CLI tool globally
uv tool upgrade --all             # upgrade all tools
uvx ruff check .                  # run tool ephemerally (no install)
uvx --from httpie http            # run from different package
```

### pip compatibility
```bash
uv pip install requests           # pip replacement
uv pip compile requirements.in    # pip-tools replacement
uv pip sync requirements.txt      # sync from requirements
uv venv                           # create virtualenv
```

### Publishing
```bash
uv build                          # build sdist/wheel
uv publish                        # upload to PyPI
```

## Configuration

In `pyproject.toml`:
```toml
[project]
name = "my-project"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = ["requests>=2.28"]

[tool.uv]
dev-dependencies = ["pytest>=7.0", "ruff", "ty"]

[tool.uv.workspace]
members = ["packages/*"]
```

## File artifacts

- `pyproject.toml` — project metadata and config
- `uv.lock` — universal lockfile (commit to VCS)
- `.venv/` — virtual environment (auto-created)
- `.python-version` — pinned Python version

## Inline script dependencies (PEP 723)

```python
# /// script
# dependencies = ["requests", "rich"]
# ///
import requests
```
Run with `uv run script.py` — deps installed automatically.

## Workflow

1. New projects: `uv init`, then `uv add` dependencies
2. Existing projects: `uv sync` to set up environment
3. Run code with `uv run` (never activate venvs manually)
4. Install dev tools with `uv add --dev ruff ty`
