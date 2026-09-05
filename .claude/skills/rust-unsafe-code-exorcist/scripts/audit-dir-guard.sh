#!/usr/bin/env bash
# Shared containment guard for rust-unsafe-code-exorcist scripts.
#
# The audit artifact directory must be inside the Rust project being audited.
# Scripts source this file before writing phase artifacts so a direct invocation
# cannot silently recreate the old sibling-directory layout.

audit_realpath() {
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

audit_project_root_from_dir() {
  local audit_abs="$1"
  local marker="$audit_abs/phase1/project-root.txt"
  if [ -f "$marker" ]; then
    local recorded
    recorded="$(sed -n '1p' "$marker")"
    if [ -n "$recorded" ]; then
      audit_realpath "$recorded"
      return
    fi
  fi

  local cur
  cur="$(dirname "$audit_abs")"
  while [ "$cur" != "/" ]; do
    if [ -f "$cur/Cargo.toml" ]; then
      audit_realpath "$cur"
      return
    fi
    cur="$(dirname "$cur")"
  done

  echo "error: cannot infer audited project root from audit dir" >&2
  echo "       audit dir: $audit_abs" >&2
  echo "       pass an audit dir inside the Rust project, such as <project>/.unsafe-audit" >&2
  return 2
}

audit_require_under_project() {
  local audit_abs
  local project_abs
  audit_abs="$(audit_realpath "$1")"
  project_abs="$(audit_realpath "$2")"

  if [ "$audit_abs" = "$project_abs" ]; then
    echo "error: audit dir must be a child directory inside the project, not the project root" >&2
    echo "       project:   $project_abs" >&2
    echo "       audit dir: $audit_abs" >&2
    return 2
  fi

  case "$audit_abs/" in
    "$project_abs"/*)
      printf '%s\n' "$audit_abs"
      ;;
    *)
      echo "error: audit dir must live inside the project being audited" >&2
      echo "       project:   $project_abs" >&2
      echo "       audit dir: $audit_abs" >&2
      echo "       do not create a sibling audit directory" >&2
      return 2
      ;;
  esac
}
