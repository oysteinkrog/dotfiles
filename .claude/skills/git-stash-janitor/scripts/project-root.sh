#!/usr/bin/env bash
# Shared project-path normalization for stash-janitor scripts.

resolve_project_root() {
  local project="${1:?missing project path}"
  local input_abs
  local root

  if ! input_abs="$(cd "$project" && pwd)"; then
    return 1
  fi

  if ! root="$(git -C "$input_abs" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "ERROR: $input_abs is not a git work tree" >&2
    return 1
  fi

  printf '%s\n' "$root"
}
