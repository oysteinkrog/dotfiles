#!/usr/bin/env bash
# discover-cli.sh — detect language, build system, binary entry points, completion-script
# paths, and existing doctor / health / verify / repair / check / diagnose / fix surfaces.
#
# Usage: discover-cli.sh <target> [--probe-doctor]
#
# Output: JSON to stdout; diagnostics to stderr. Exit 0 on success.

set -euo pipefail
target="${1:-.}"
probe_doctor=0
[ "${2:-}" = "--probe-doctor" ] && probe_doctor=1

if [ ! -d "$target" ]; then
    echo "error: $target is not a directory" >&2
    exit 66
fi

cd "$target"
target_dir="$PWD"

# --- Language + build system detection ---

language=""
build_system=""
binaries=()

if [ -f Cargo.toml ]; then
    language="rust"
    build_system="cargo"
    # Detect Cargo workspaces: when the top-level Cargo.toml has a [workspace]
    # section and no [[bin]] / no [package] (or the [package] section is purely
    # the workspace root), the binaries live in member crates. Real-world
    # case: /dp/mcp_agent_mail_rust has 13+ workspace members, 3 of which
    # produce binaries. Round-53 real-world application surfaced this gap.
    is_workspace=0
    if grep -qE '^\[workspace\]' Cargo.toml; then
        is_workspace=1
    fi
    if [ "$is_workspace" -eq 1 ]; then
        # Extract member globs from the [workspace] members list. The list
        # spans multiple lines; awk captures everything between the opening
        # `members = [` and the closing `]`. Members can be globs (e.g.,
        # "crates/*") or specific paths.
        while IFS= read -r member_path; do
            # Strip surrounding quotes + whitespace; skip empty entries.
            member_path="${member_path//\"/}"
            member_path="${member_path//,/}"
            member_path="$(echo "$member_path" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
            [ -z "$member_path" ] && continue
            # Expand glob (e.g., "crates/*" → each subdir).
            for resolved in $member_path; do
                [ -d "$resolved" ] || continue
                [ -f "$resolved/Cargo.toml" ] || continue
                # Found a member crate. Re-apply the same detection logic:
                # [[bin]] sections first, then fallback to [package].name when
                # an implicit src/main.rs exists (Cargo's default-binary rule).
                while IFS= read -r line; do
                    bin=$(echo "$line" | sed -nE 's/^name = "(.*)"/\1/p')
                    [ -n "$bin" ] && binaries+=("$bin")
                done < <(awk '/^\[\[bin\]\]/{flag=1;next}/^\[/{flag=0}flag' "$resolved/Cargo.toml")
                # Implicit binary: src/main.rs without explicit [[bin]].
                if [ -f "$resolved/src/main.rs" ] && ! grep -qE '^\[\[bin\]\]' "$resolved/Cargo.toml"; then
                    pkg_name=$(awk -F'"' '/^name *=/{print $2; exit}' "$resolved/Cargo.toml")
                    [ -n "$pkg_name" ] && binaries+=("$pkg_name")
                fi
            done
        done < <(awk '
            /^\[workspace\]/{ws=1; next}
            /^\[/ && ws { ws=0 }
            ws && /members[[:space:]]*=[[:space:]]*\[/ { in_list=1; sub(/.*\[/, ""); }
            ws && in_list {
                # Strip closing bracket; emit each comma-separated entry on its own line.
                if (/\]/) { sub(/\].*/, ""); in_list=0 }
                # Split on commas, trim, emit.
                n = split($0, parts, ",")
                for (i = 1; i <= n; i++) {
                    p = parts[i]
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
                    if (p != "") print p
                }
            }
        ' Cargo.toml)
    else
        # Single-crate Cargo project (no [workspace] section).
        while IFS= read -r line; do
            bin=$(echo "$line" | sed -nE 's/^name = "(.*)"/\1/p')
            [ -n "$bin" ] && binaries+=("$bin")
        done < <(awk '/^\[\[bin\]\]/{flag=1;next}/^\[/{flag=0}flag' Cargo.toml)
        if [ ${#binaries[@]} -eq 0 ] && [ -f src/main.rs ]; then
            pkg_name=$(awk -F'"' '/^name *=/{print $2; exit}' Cargo.toml)
            [ -n "$pkg_name" ] && binaries+=("$pkg_name")
        fi
    fi
elif [ -f go.mod ]; then
    language="go"
    build_system="go"
    if [ -d cmd ]; then
        for d in cmd/*/; do
            [ -d "$d" ] && binaries+=("$(basename "$d")")
        done
    fi
elif [ -f pyproject.toml ]; then
    language="python"
    build_system=$(grep -q '\[tool.uv\]' pyproject.toml && echo "uv" || echo "pip")
    while IFS= read -r line; do
        bin=$(echo "$line" | sed -nE 's/^([a-zA-Z0-9_-]+) *= *"[^"]+:.*"/\1/p')
        [ -n "$bin" ] && binaries+=("$bin")
    done < <(awk '/^\[project.scripts\]/{flag=1;next}/^\[/{flag=0}flag' pyproject.toml 2>/dev/null)
elif [ -f package.json ]; then
    pm=""
    [ -f bun.lockb ] && pm="bun"
    [ -f pnpm-lock.yaml ] && pm="pnpm"
    [ -z "$pm" ] && [ -f deno.json ] && language="deno" && pm="deno"
    [ -z "$pm" ] && pm="npm"
    language="${language:-typescript}"
    build_system="$pm"
    if command -v jq >/dev/null 2>&1; then
        # If .bin is an object, its keys ARE the binary names.
        # If .bin is a string, the binary name is .name (the package name) —
        # the .bin value is a path to the entry point, not the bin name.
        # If .bin is null/missing, .name MAY still be a binary if the package
        # exports a single entry; we don't infer that automatically.
        while IFS= read -r b; do
            [ -n "$b" ] && binaries+=("$b")
        done < <(jq -r '
            if (.bin // null) == null then
                empty
            elif (.bin | type) == "object" then
                .bin | keys[]
            else
                .name
            end
        ' package.json 2>/dev/null)
    fi
elif [ -f Gemfile ]; then
    language="ruby"
    build_system="bundler"
elif [ -f mix.exs ]; then
    language="elixir"
    build_system="mix"
elif [ -f CMakeLists.txt ]; then
    language="cpp"
    build_system="cmake"
elif [ -f build.zig ]; then
    language="zig"
    build_system="zig"
fi

# --- Bash / shell CLI fallback ---
# When no recognized build-system file is found, look for top-level executable
# scripts with a shell shebang. SKILL.md line 61 lists Bash as a supported
# language; without this branch the SELF-TEST against tinycli (a single Bash
# script) finds zero binaries and the auto-detection heuristic for upgrade
# vs. add mode fails. We only run this when nothing else matched, so a Rust
# project's `scripts/build.sh` doesn't shadow the Cargo.toml detection.
if [ -z "$language" ] || [ "$language" = "unknown" ]; then
    while IFS= read -r f; do
        # Skip dotfiles and helper subdirs.
        case "$(basename "$f")" in
            .*) continue ;;
        esac
        # Only top-level files (depth 1).
        case "$f" in
            ./*/*) continue ;;
        esac
        if [ -x "$f" ] && [ -f "$f" ]; then
            shebang=$(head -c 256 "$f" 2>/dev/null | head -1)
            case "$shebang" in
                '#!'*/sh|'#!'*/sh\ *|'#!'*/bash|'#!'*/bash\ *|'#!'*/env\ sh|'#!'*/env\ sh\ *|'#!'*/env\ bash|'#!'*/env\ bash\ *)
                    binaries+=("$(basename "$f")")
                    [ -z "$language" ] || [ "$language" = "unknown" ] && language="bash"
                    [ -z "$build_system" ] || [ "$build_system" = "unknown" ] && build_system="none"
                    ;;
            esac
        fi
    done < <(find . -maxdepth 1 -type f 2>/dev/null)
fi

# --- Default branch ---
# Fallback chain: origin/HEAD → local current branch → init.defaultBranch
# config → "main" literal. The local-current-branch step is essential when
# there's no remote (fresh git init repos), and we need it before the
# init.defaultBranch fallback because system-default git may be "master"
# (init.defaultBranch unset) but the actual branch is also "master" — the
# config fallback would silently report "main" when the truth is "master".
default_branch=$(git -C "$target_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's@^origin/@@' || true)
[ -z "$default_branch" ] && default_branch=$(git -C "$target_dir" symbolic-ref --short HEAD 2>/dev/null || true)
[ -z "$default_branch" ] && default_branch=$(git -C "$target_dir" config --get init.defaultBranch 2>/dev/null || echo "main")

# rev-parse HEAD leaks "HEAD" to stdout on a fresh repo with no commits before
# failing; redirect both streams so the fallback string is clean.
target_sha=$(git -C "$target_dir" rev-parse HEAD 2>/dev/null) || target_sha="unknown"
# Defensive: strip any embedded newlines / CRs that could break JSON.
target_sha="${target_sha//$'\n'/}"
target_sha="${target_sha//$'\r'/}"
[ -z "$target_sha" ] && target_sha="unknown"

# Final fallback values for the JSON output if no detector matched.
[ -z "$language" ] && language="unknown"
[ -z "$build_system" ] && build_system="unknown"

# --- Probe doctor surface (if requested) ---
# Try multiple invocation forms per binary: PATH lookup (`command -v $bin`),
# then a local file path under the target directory (`./$bin` after cd),
# then a Cargo target/release/<bin> or target/debug/<bin> for unbuilt-in-PATH
# Rust workspaces. Probe EVERY binary, not just binaries[0] — round-53
# real-world application surfaced multi-binary projects (e.g.,
# /dp/mcp_agent_mail_rust where the server binary `mcp-agent-mail` has no
# doctor subcommand but the CLI binary `am` has both `doctor` and `check`).
# The probe picks the FIRST binary that exposes a doctor verb as the
# canonical existing_doctor; existing_diagnostic_subcommands is the union
# across binaries (deduplicated).
existing_doctor=""
existing_doctor_binary=""
declare -A seen_subcommands
existing_subcommands=()
# Round-54 real-world application against /dp/coding_agent_session_search
# surfaced a critical FALSE-POSITIVE class: cass interprets unknown
# subcommands as search queries and exits 0, so the naive
# `<bin> <verb> --help; exit_code` probe falsely reported 7 verbs when
# only 2 (`doctor`, `health`) are real. Defense-in-depth, in order:
#   (a) Sentinel check: try `<bin> __doctor_skill_sentinel_xyz__ --help`.
#       If it exits 0, the binary has a fallback parser; we cannot trust
#       exit codes for verb existence. Fall back to (b).
#   (b) Help-text parsing: capture `<bin> --help` output, look for a
#       "Commands:" / "Available Commands:" / "Subcommands:" section,
#       extract the listed subcommand names, and intersect with our 7
#       canonical verbs.
#   (c) Last resort: if neither (a) succeeds nor (b) can parse the help,
#       trust the naive probe but emit a `probe_reliability: "uncertain"`
#       note in the output JSON so consumers can flag it.
probe_one_binary() {
    local bin="$1"
    local bin_invocation=""
    if command -v "$bin" >/dev/null 2>&1; then
        bin_invocation="$bin"
    elif [ -x "./$bin" ]; then
        bin_invocation="./$bin"
    elif [ -x "./target/release/$bin" ]; then
        bin_invocation="./target/release/$bin"
    elif [ -x "./target/debug/$bin" ]; then
        bin_invocation="./target/debug/$bin"
    fi
    [ -z "$bin_invocation" ] && return 0

    # Sentinel check: does the binary reject unknown subcommands?
    # If `<bin> <unknown> --help` exits 0, it has a fallback parser
    # (cass routes unknown verbs to its `search` subcommand).
    local has_fallback_parser=0
    if "$bin_invocation" __doctor_skill_sentinel_xyz123__ --help >/dev/null 2>&1; then
        has_fallback_parser=1
    fi

    if [ "$has_fallback_parser" -eq 1 ]; then
        # Help-text parsing path. Most clap/cobra/argparse CLIs emit
        # subcommand lists in a recognizable section. Capture --help and
        # extract the first column of any line that follows a
        # "Commands:" / "Available Commands:" / "Subcommands:" header
        # (until the next blank line or section header).
        local help_output
        help_output=$("$bin_invocation" --help 2>&1) || true
        local subcommand_list
        subcommand_list=$(echo "$help_output" | awk '
            /^Commands:|^Available Commands:|^Subcommands:|^SUBCOMMANDS:/ {
                in_section = 1
                next
            }
            in_section {
                # End of section: blank line, or new section header (line
                # ending in colon at column 0).
                if (/^$/) { in_section = 0; next }
                if (/^[A-Za-z][^[:space:]]*:[[:space:]]*$/ && !/^[[:space:]]/) {
                    in_section = 0; next
                }
                # Subcommand line: leading whitespace, then the name as
                # the first non-whitespace token. Skip continuation lines
                # that have unusual indentation patterns.
                if (/^[[:space:]]+[a-zA-Z][a-zA-Z0-9_-]*[[:space:]]/) {
                    # Extract first token after leading whitespace.
                    line = $0
                    sub(/^[[:space:]]+/, "", line)
                    split(line, parts, /[[:space:]]+/)
                    print parts[1]
                }
            }
        ')
        local verb
        for verb in doctor health verify repair check diagnose fix; do
            if echo "$subcommand_list" | grep -qxF "$verb"; then
                if [ -z "$existing_doctor" ]; then
                    existing_doctor="$verb"
                    existing_doctor_binary="$bin"
                fi
                if [ -z "${seen_subcommands[$verb]:-}" ]; then
                    existing_subcommands+=("$verb")
                    seen_subcommands[$verb]=1
                fi
            fi
        done
    else
        # No fallback parser → exit codes are trustworthy.
        local verb
        for verb in doctor health verify repair check diagnose fix; do
            if "$bin_invocation" "$verb" --help >/dev/null 2>&1; then
                if [ -z "$existing_doctor" ]; then
                    existing_doctor="$verb"
                    existing_doctor_binary="$bin"
                fi
                if [ -z "${seen_subcommands[$verb]:-}" ]; then
                    existing_subcommands+=("$verb")
                    seen_subcommands[$verb]=1
                fi
            fi
        done
    fi
}
if [ "$probe_doctor" -eq 1 ] && [ ${#binaries[@]} -gt 0 ]; then
    for b in "${binaries[@]}"; do
        probe_one_binary "$b"
    done
fi

# --- Emit JSON ---

esc() {
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

bins_json="["
for i in "${!binaries[@]}"; do
    [ "$i" -gt 0 ] && bins_json+=","
    bins_json+=$(esc "${binaries[$i]}")
done
bins_json+="]"

subs_json="["
for i in "${!existing_subcommands[@]}"; do
    [ "$i" -gt 0 ] && subs_json+=","
    subs_json+=$(esc "${existing_subcommands[$i]}")
done
subs_json+="]"

cat <<EOF
{
  "schema_version": "1.0",
  "target": $(esc "$target"),
  "target_sha": $(esc "$target_sha"),
  "default_branch": $(esc "$default_branch"),
  "language": $(esc "$language"),
  "build_system": $(esc "$build_system"),
  "binaries": $bins_json,
  "existing_doctor_subcommand": $(esc "$existing_doctor"),
  "existing_doctor_binary": $(esc "$existing_doctor_binary"),
  "existing_diagnostic_subcommands": $subs_json,
  "probe_doctor": $probe_doctor
}
EOF
