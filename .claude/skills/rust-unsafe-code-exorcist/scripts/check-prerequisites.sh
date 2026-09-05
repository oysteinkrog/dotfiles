#!/usr/bin/env bash
# check-prerequisites.sh — friendly per-tool availability check for the audit.
# Usage: ./check-prerequisites.sh
#
# Doesn't install anything. Just reports what's installed and what's missing,
# with copy-paste install commands for each missing tool.

set -uo pipefail   # NOT pipefail-strict; we want to keep going

OS="unknown"
case "$(uname -s)" in
  Linux)   OS="linux"   ;;
  Darwin)  OS="macos"   ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows-bash" ;;
esac

echo "=========================================="
echo "rust-unsafe-code-exorcist — prerequisites"
echo "=========================================="
echo "Detected OS: $OS"
echo
if [ "$OS" = "windows-bash" ]; then
  cat <<'EOF'
ℹ️  You're on Windows running bash (Git Bash / Cygwin / WSL).
   Some features (miri on FFI, cargo-fuzz) work better in WSL2.
   See references/methodology/PLATFORM-NOTES.md for details.

EOF
fi

# Counters
INSTALLED=0
MISSING=0
declare -a MISSING_REQUIRED=()
declare -a MISSING_RECOMMENDED=()
declare -a MISSING_OPTIONAL=()

# check(name, command-to-detect, tier, install-hint)
check() {
  local name="$1"
  local detect="$2"
  local tier="$3"          # required | recommended | optional
  local install="$4"

  if eval "$detect" >/dev/null 2>&1; then
    local version=""
    version=$(eval "$detect" 2>/dev/null | head -1 | tr -d '\r' | cut -c 1-60 || true)
    printf "  ✓  %-22s %s\n" "$name" "$version"
    INSTALLED=$((INSTALLED+1))
  else
    case "$tier" in
      required)
        printf "  ✗  %-22s (REQUIRED — install: %s)\n" "$name" "$install"
        MISSING_REQUIRED+=("$install")
        ;;
      recommended)
        printf "  ⚠  %-22s (recommended — install: %s)\n" "$name" "$install"
        MISSING_RECOMMENDED+=("$install")
        ;;
      optional)
        printf "  ·  %-22s (optional — install: %s)\n" "$name" "$install"
        MISSING_OPTIONAL+=("$install")
        ;;
    esac
    MISSING=$((MISSING+1))
  fi
}

echo "REQUIRED"
echo "--------"
check "rustc"          "rustc --version"          required "https://rustup.rs/"
check "cargo"          "cargo --version"          required "https://rustup.rs/"
check "git"            "git --version"            required "macOS: brew install git | Linux: apt install git | Windows: install Git for Windows"
check "bash"           "bash --version"           required "macOS/Linux: built-in | Windows: install Git Bash or WSL2"
check "jq"             "jq --version"             required "macOS: brew install jq | Linux: apt install jq | Windows: https://jqlang.github.io/jq/download/"
check "node"           "node -e 'console.log(process.version)'" required "macOS: brew install node | Linux: apt install nodejs | Windows: https://nodejs.org/"
check "python3"        "python3 --version"        required "macOS/Linux: usually pre-installed | Windows: https://python.org/"

echo
echo "RECOMMENDED (for the full audit harness)"
echo "----------------------------------------"
check "rustc +nightly" "rustc +nightly --version"           recommended "rustup toolchain install nightly"
check "cargo +nightly" "cargo +nightly --version"           recommended "rustup toolchain install nightly"
check "miri"           "cargo +nightly miri --version"      recommended "rustup +nightly component add miri rust-src && cargo +nightly miri setup"
check "ast-grep"       "ast-grep --version"                 recommended "cargo install ast-grep --locked"
check "cargo-expand"   "cargo expand --version"             recommended "cargo install cargo-expand --locked"
check "cargo-geiger"   "cargo +nightly geiger --version"    recommended "cargo +nightly install --locked cargo-geiger"

echo
echo "OPTIONAL (for deeper audits, incident response, formal verification)"
echo "--------------------------------------------------------------------"
check "cargo-careful"  "cargo +nightly careful --version"   optional "cargo +nightly install cargo-careful"
check "cargo-fuzz"     "cargo +nightly fuzz --version"      optional "cargo install cargo-fuzz --locked  (requires nightly)"
check "cargo-mutants"  "cargo mutants --version"            optional "cargo install --locked cargo-mutants"
check "flamegraph"     "flamegraph --version"               optional "cargo install flamegraph --locked"
check "hyperfine"      "hyperfine --version"                optional "cargo install --locked hyperfine"
check "gh (GitHub CLI)" "gh --version"                      optional "macOS: brew install gh | Linux: https://cli.github.com/"
check "kani"           "cargo kani --version"               optional "cargo install --locked kani-verifier && cargo kani setup"
check "br (beads)"     "br --version"                       optional "cargo install beads_rust  (for the issue tracker the audit emits)"
check "bv (beads viewer)" "bv --version"                    optional "cargo install beads_viewer"
check "shellcheck"     "shellcheck --version"               optional "macOS: brew install shellcheck | Linux: apt install shellcheck"

echo
echo "=========================================="
echo "Summary: $INSTALLED installed, $MISSING missing"
echo "=========================================="

if [ ${#MISSING_REQUIRED[@]} -gt 0 ]; then
  echo
  echo "❌ Missing REQUIRED tools. The audit can't run without these:"
  for cmd in "${MISSING_REQUIRED[@]}"; do
    echo "   $cmd"
  done
fi

if [ ${#MISSING_RECOMMENDED[@]} -gt 0 ]; then
  echo
  echo "⚠️  Missing RECOMMENDED tools. The audit will run in a reduced form:"
  for cmd in "${MISSING_RECOMMENDED[@]}"; do
    echo "   $cmd"
  done
  echo
  echo "   Without miri: no UB detection (the audit's primary soundness check)."
  echo "   Without ast-grep: enumeration falls back to ripgrep IF installed, then to grep (less precise)."
  echo "   Without cargo-expand: macro-generated unsafe (zerocopy-derive, pin-project-lite, …) stays invisible."
  echo "   Without cargo-geiger: no unsafe-count baseline / drift tracking."
fi

if [ ${#MISSING_OPTIONAL[@]} -gt 0 ]; then
  echo
  echo "ℹ️  Missing OPTIONAL tools. Each unlocks a specific feature:"
  for cmd in "${MISSING_OPTIONAL[@]}"; do
    echo "   $cmd"
  done
fi

# Per-mode capability check. Each mode needs SPECIFIC tools; the bucket-counts
# alone are misleading (e.g., triage needs ast-grep but ast-grep is recommended-tier).
has() { command -v "$1" >/dev/null 2>&1; }
has_cargo_subcmd() { cargo "$1" --version >/dev/null 2>&1; }
has_nightly_cargo_subcmd() { cargo +nightly "$1" --version >/dev/null 2>&1; }

HAVE_AST_GREP=$(has ast-grep && echo yes || echo no)
HAVE_RG=$(has rg && echo yes || echo no)
HAVE_MIRI=$(has_nightly_cargo_subcmd miri && echo yes || echo no)
HAVE_EXPAND=$(has_cargo_subcmd expand && echo yes || echo no)
HAVE_GEIGER=$(has_nightly_cargo_subcmd geiger && echo yes || echo no)
HAVE_CAREFUL=$(has_nightly_cargo_subcmd careful && echo yes || echo no)
HAVE_FUZZ=$(has_nightly_cargo_subcmd fuzz && echo yes || echo no)
HAVE_MUTANTS=$(has_cargo_subcmd mutants && echo yes || echo no)
HAVE_KANI=$(has_cargo_subcmd kani && echo yes || echo no)

# An enumerator exists if EITHER ast-grep OR rg is installed (rg is fallback).
HAVE_ENUMERATOR=no
if [ "$HAVE_AST_GREP" = "yes" ] || [ "$HAVE_RG" = "yes" ]; then HAVE_ENUMERATOR=yes; fi

mark() { [ "$1" = "yes" ] && echo "✓" || echo "✗"; }
warn() { [ "$1" = "yes" ] && echo "✓" || echo "⚠"; }

echo
echo "Modes you can run RIGHT NOW with what you have installed:"
if [ ${#MISSING_REQUIRED[@]} -gt 0 ]; then
  echo "  ✗ Nothing (install required tools first)"
else
  # forbid-soundness mode: project already has #![forbid(unsafe_code)] or a Cargo
  # lint table forbid. miri/loom/fuzz/mutants have NOTHING to verify because
  # there's no in-tree unsafe; this mode is achievable with just enumerator +
  # expand (and optionally geiger for dep-side baseline).
  if [ "$HAVE_ENUMERATOR" = "yes" ] && [ "$HAVE_EXPAND" = "yes" ]; then
    extra=""
    [ "$HAVE_GEIGER" = "no" ] && extra=" (dep-soundness numbers degraded without cargo-geiger)"
    echo "  ✓ forbid-soundness${extra}"
    echo "      For projects with #![forbid(unsafe_code)] or [lints.rust] unsafe_code = \"forbid\"."
    echo "      No miri / fuzz / mutants needed — nothing in-tree to verify."
  else
    missing=""
    [ "$HAVE_ENUMERATOR" = "no" ] && missing="ast-grep or rg, "
    [ "$HAVE_EXPAND"     = "no" ] && missing="${missing}cargo-expand, "
    echo "  ⚠ forbid-soundness — needs: ${missing%, }"
  fi

  # triage: needs an enumerator + jq + node (all-required for the basic flow)
  printf "  %s triage (60-second enumeration + risk-score)" "$(mark "$HAVE_ENUMERATOR")"
  [ "$HAVE_ENUMERATOR" = "no" ] && printf "  [needs ast-grep OR rg]"
  [ "$HAVE_AST_GREP" = "no" ] && [ "$HAVE_RG" = "yes" ] && printf "  [running on ripgrep fallback — less precise]"
  echo

  # audit-only --quick: enumerator + cargo-expand (for macro-generated unsafe)
  if [ "$HAVE_ENUMERATOR" = "yes" ] && [ "$HAVE_EXPAND" = "yes" ]; then
    echo "  ✓ audit-only --quick (skips Phase 5 detail + Phase 7 harness)"
  else
    missing=""
    [ "$HAVE_ENUMERATOR" = "no" ] && missing="ast-grep or rg, "
    [ "$HAVE_EXPAND"     = "no" ] && missing="${missing}cargo-expand, "
    echo "  ⚠ audit-only --quick (degraded; missing: ${missing%, })"
  fi

  # audit-only (full): + miri + geiger
  # CAVEAT: for projects with zero in-tree unsafe, miri has nothing to verify;
  # the prereq is documented as the tool set for the GENERAL full audit.
  if [ "$HAVE_ENUMERATOR" = "yes" ] && [ "$HAVE_EXPAND" = "yes" ] && \
     [ "$HAVE_MIRI"       = "yes" ] && [ "$HAVE_GEIGER" = "yes" ]; then
    echo "  ✓ audit-only (full)"
  else
    missing=""
    [ "$HAVE_MIRI"       = "no" ] && missing="miri, "
    [ "$HAVE_GEIGER"     = "no" ] && missing="${missing}cargo-geiger, "
    [ "$HAVE_EXPAND"     = "no" ] && missing="${missing}cargo-expand, "
    [ "$HAVE_ENUMERATOR" = "no" ] && missing="${missing}ast-grep/rg, "
    echo "  ✗ audit-only (full) — needs: ${missing%, }"
    echo "    (note: if your project has zero in-tree unsafe, run 'forbid-soundness' instead — miri/fuzz/mutants would have nothing to verify)"
  fi

  # audit-and-refactor: + fuzz + mutants
  if [ "$HAVE_ENUMERATOR" = "yes" ] && [ "$HAVE_EXPAND" = "yes" ] && \
     [ "$HAVE_MIRI"       = "yes" ] && [ "$HAVE_GEIGER" = "yes" ] && \
     [ "$HAVE_FUZZ"       = "yes" ] && [ "$HAVE_MUTANTS" = "yes" ]; then
    echo "  ✓ audit-and-refactor + harden-incident"
  else
    echo "  ✗ audit-and-refactor + harden-incident — needs full audit-only + cargo-fuzz + cargo-mutants"
  fi

  # pre-release-soundness-gate: + careful + (optionally kani)
  if [ "$HAVE_CAREFUL" = "yes" ] && [ "$HAVE_MIRI" = "yes" ] && \
     [ "$HAVE_FUZZ"    = "yes" ] && [ "$HAVE_MUTANTS" = "yes" ]; then
    extra=""
    [ "$HAVE_KANI"   = "no" ] && extra=" (no kani — formal verification skipped)"
    echo "  ✓ pre-release-soundness-gate${extra}"
  else
    echo "  ✗ pre-release-soundness-gate — needs miri + careful + fuzz + mutants (kani optional)"
  fi
fi

echo
echo "Next steps:"
echo "  1. Install any required-or-recommended tools above."
echo "  2. Re-run this script to verify."
echo "  3. Try the toy project from README.md § 'Try it on a toy project first'."
echo "  4. Then run on your real project."
echo
echo "See references/methodology/PREREQUISITES.md for the full per-OS install guide."
echo "See references/methodology/PLATFORM-NOTES.md for OS-specific quirks."
echo

# Exit code: 0 if no required missing, 1 if required missing
[ ${#MISSING_REQUIRED[@]} -eq 0 ]
