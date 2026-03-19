---
name: py-ruff
description: |
  Run ruff (Astral's Python linter & formatter) on Python code. Use when writing,
  editing, or reviewing Python code for lint issues and formatting. Triggers on:
  writing Python files, "lint", "format python", "run ruff", or after editing .py files.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
---

# ruff — Python Linter & Formatter (Astral)

Extremely fast Python linter and formatter written in Rust. Replaces Flake8, Black,
isort, pyupgrade, pydocstyle, and autoflake.
**Repo:** https://github.com/astral-sh/ruff

## When to use

Run `ruff check` and `ruff format` after writing or editing Python code. Always
lint and format before considering a Python task complete.

## Installation

```bash
uv tool install ruff@latest       # preferred
# or: pip install ruff
# or: curl -LsSf https://astral.sh/ruff/install.sh | sh
```

## Key commands

```bash
# Linting
ruff check                        # lint current directory
ruff check --fix                  # auto-fix fixable issues
ruff check --select F401          # check specific rule
ruff check path/to/file.py        # check specific file

# Formatting
ruff format                       # format current directory
ruff format path/to/file.py       # format specific file

# Info
ruff rule F401                    # explain a rule
```

## Configuration

In `pyproject.toml`:
```toml
[tool.ruff]
line-length = 88
target-version = "py311"
src = ["src"]

[tool.ruff.lint]
select = ["E4", "E7", "E9", "F", "UP", "B", "I"]
ignore = ["E501"]
fixable = ["ALL"]

[tool.ruff.lint.per-file-ignores]
"__init__.py" = ["F401"]
"tests/**/*.py" = ["D100"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
docstring-code-format = true
```

## Key rule prefixes

| Prefix | Source | What it checks |
|--------|--------|----------------|
| F | Pyflakes | Unused imports/vars, undefined names |
| E/W | pycodestyle | Style violations |
| UP | pyupgrade | Modernize syntax |
| B | flake8-bugbear | Common bugs |
| I | isort | Import sorting |
| S | flake8-bandit | Security issues |
| RUF | Ruff-specific | Custom rules |

## Workflow

1. After writing/editing Python code, run `ruff check --fix` to lint and auto-fix
2. Run `ruff format` to format
3. Review any remaining issues that couldn't be auto-fixed
4. Suppress intentional violations with `# noqa: RULE` comments
