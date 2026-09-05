#!/usr/bin/env bash
# Shared project-path + workspace + bundle resolution for the
# git-worktree-branch-rationalization skill.

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

# WORKSPACE override (env var) supersedes the in-repo default. Default is
# .worktree_branch_rationalization_workspace/ inside the repo root.
resolve_workspace() {
  local project_abs="${1:?missing project root}"
  if [[ -n "${WORKSPACE:-}" ]]; then
    printf '%s\n' "$WORKSPACE"
    return 0
  fi
  printf '%s/.worktree_branch_rationalization_workspace\n' "$project_abs"
}

# Slugify a branch name so it can sit safely inside a directory or ref path.
# Replaces every char that isn't [A-Za-z0-9._-] with '_'. Caller is responsible
# for length capping if needed.
slugify_branch() {
  local raw="${1:?missing input}"
  local safe hash
  safe=$(printf '%s' "$raw" | tr -c 'A-Za-z0-9._-' '_')
  safe="${safe:0:80}"
  [[ -z "$safe" ]] && safe=branch

  if command -v sha1sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$raw" | sha1sum | awk '{print substr($1, 1, 12)}')
  elif command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$raw" | shasum -a 1 | awk '{print substr($1, 1, 12)}')
  else
    hash=$(printf '%s' "$raw" | cksum | awk '{printf "%08x%04x", $1, $2 % 65536}')
  fi

  printf '%s-%s\n' "$safe" "$hash"
}

# Sanitize an absolute filesystem path into a directory-name fragment.
# Used to map worktree paths into <bundle>/worktrees/<sanitized>/.
sanitize_path() {
  local raw="${1:?missing input}"
  local label hash

  if command -v sha1sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$raw" | sha1sum | awk '{print substr($1, 1, 12)}')
  elif command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$raw" | shasum -a 1 | awk '{print substr($1, 1, 12)}')
  else
    hash=$(printf '%s' "$raw" | cksum | awk '{printf "%08x%04x", $1, $2 % 65536}')
  fi

  # Strip the leading slash for readability, collapse path separators, and cap
  # the visible prefix so the hash keeps the directory name unique but short.
  label="${raw#/}"
  label=$(printf '%s' "$label" | sed 's@/@__@g' | tr -c 'A-Za-z0-9._-' '_')
  label="${label:0:120}"
  [[ -z "$label" ]] && label=path
  printf '%s-%s\n' "$label" "$hash"
}

# Split a single TSV row into named variables while preserving empty fields.
# Bash treats tabs in IFS as whitespace, so plain `IFS=$'\t' read ...` collapses
# adjacent tabs and corrupts column alignment.
tsv_read() {
  local row="${1-}"
  shift
  row=${row//$'\t'/$'\037'}
  local IFS=$'\037'
  read -r "$@" <<< "$row"
}

# Emit a NUL-delimited manifest for untracked files:
#   type<TAB>content-hash<TAB>relative-path<NUL>
#
# `git status --porcelain` only proves untracked path names, not bytes. Phase 10
# removals need byte-level equality so a same-path untracked edit after bundling
# cannot be lost behind a stale tarball.
emit_untracked_content_manifest() {
  local root="${1:?missing root}" list="${2:?missing untracked list}"
  local rel abs hash target target_hash

  while IFS= read -r -d '' rel; do
    [[ -z "$rel" ]] && continue
    case "$rel" in
      ""|/*|..|../*|*/..|*/../*)
        printf 'unsafe\t-\t%s\0' "$rel"
        continue
        ;;
    esac

    abs="$root/$rel"
    if [[ -L "$abs" ]]; then
      target=$(readlink "$abs" 2>/dev/null || true)
      target_hash=$(printf '%s' "$target" | sha256sum | awk '{print $1}')
      printf 'symlink\t%s\t%s\0' "$target_hash" "$rel"
    elif [[ -f "$abs" ]]; then
      hash=$(sha256sum "$abs" 2>/dev/null | awk '{print $1}')
      if [[ -n "$hash" ]]; then
        printf 'file\t%s\t%s\0' "$hash" "$rel"
      else
        printf 'unreadable\t-\t%s\0' "$rel"
      fi
    elif [[ -d "$abs" ]]; then
      printf 'dir\t-\t%s\0' "$rel"
    else
      printf 'missing\t-\t%s\0' "$rel"
    fi
  done < "$list"
}

write_untracked_content_manifest() {
  local root="${1:?missing root}" list="${2:?missing untracked list}" out="${3:?missing output}"
  emit_untracked_content_manifest "$root" "$list" > "$out"
}

untracked_content_manifest_hash_for_root() {
  local root="${1:?missing root}" list="${2:?missing untracked list}"
  emit_untracked_content_manifest "$root" "$list" | sha256sum | awk '{print $1}'
}

# Emit one shell string as a JSON string literal. Prefer Python's full encoder
# when available; the shell fallback covers the characters these helpers
# normally handle in paths, branch names, and tool versions.
json_string() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1]))
PY
    return 0
  fi

  local s="${1-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

# Encode a value for use as a single URL path segment. GitHub branch names often
# contain '/', which must be encoded when calling the branch-protection endpoint.
url_path_segment() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY'
import sys
from urllib.parse import quote

print(quote(sys.argv[1], safe=""))
PY
    return 0
  fi

  local s="${1-}"
  s=${s//%/%25}
  s=${s//\//%2F}
  s=${s// /%20}
  s=${s//#/%23}
  s=${s//\?/%3F}
  printf '%s' "$s"
}

# Prove an object bundle is not just syntactically listable, but actually
# fetchable into a fresh object database. `git bundle verify` and `list-heads`
# can pass on some truncated packs; a real fetch is the recovery operation.
bundle_fetch_roundtrip() {
  local pack="${1:?missing bundle pack}"
  local backup_ns="${2:-refs/branch-rationalization-backup}"
  local parent="${3:-${TMPDIR:-/tmp}}"
  local verify_git

  mkdir -p "$parent" || return 1
  verify_git=$(mktemp -d "$parent/.bundle_fetch_verify_XXXXXX") || return 1
  git init --bare --quiet "$verify_git" >/dev/null 2>&1 || return 1
  git --git-dir="$verify_git" fetch --quiet "$pack" "+$backup_ns/*:$backup_ns/*" >/dev/null 2>&1
}
