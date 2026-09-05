# COOKBOOK.md — Recipes for Common Scenarios

Paste-ready end-to-end walkthroughs. Each recipe assumes the skill is installed and the user has run `check-skills.sh`. Recipe snippets resolve `$SKILL` from an existing value first, then try the Claude install path, then the Codex install path.

---

## Recipe 1 — "I want a full audit of my Rust project."

The default flow. Outputs a defensible audit + beads + harness.

```bash
PROJECT=/path/to/my-rust-project
AUDIT_DIR="$PROJECT/.unsafe-audit"
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

# 1. Bootstrap
mkdir -p "$AUDIT_DIR" && (cd "$AUDIT_DIR" && git init)
$SKILL/scripts/check-skills.sh "$AUDIT_DIR"
$SKILL/scripts/install-toolchain.sh --check "$AUDIT_DIR"
$SKILL/scripts/detect-mode.sh "$PROJECT"

# 2. Enumerate
$SKILL/scripts/enumerate-unsafe.sh "$PROJECT" "$AUDIT_DIR"
node $SKILL/scripts/generate-inventory.mjs "$AUDIT_DIR"

# 3. Invoke the skill via slash command (in Claude Code)
# /rust-unsafe-code-exorcist "$PROJECT" --mode audit-only

# OR drive programmatically:
# Spawn the orchestrator subagent per references/methodology/KICKOFF-PROMPTS.md.
```

Expected output: `$AUDIT_DIR/AUDIT_SUMMARY.md` after Phase 10 completes. Read first.

Time: ~30 min for a small lib (≤50 sites), 2–6h for medium workspace, half-day+ for polyrepo.

---

## Recipe 2 — "We had a CVE. Fix it. Then expand to a full audit."

`harden-incident` mode. RCA → fix → regression test → ship. THEN expand.

```bash
PROJECT=/path/to/my-rust-project
AUDIT_DIR="$PROJECT/.unsafe-audit-incident-2026-NNNN"
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

mkdir -p "$AUDIT_DIR" && (cd "$AUDIT_DIR" && git init)

# Capture incident metadata first
cat > "$AUDIT_DIR/incident-rca.md" <<'EOF'
# Incident RCA — CVE-2026-NNNN
- Severity: High
- Symptom: <one-line>
- Reporter: <name>
- Affected versions: <semver>
EOF

# Invoke the skill in harden-incident mode
# /rust-unsafe-code-exorcist "$PROJECT" --mode harden-incident --incident-id CVE-2026-NNNN
```

The skill then runs the 5-phase incident protocol ([INCIDENT-RESPONSE-PLAYBOOK.md](INCIDENT-RESPONSE-PLAYBOOK.md)): CONTAIN → RECONSTRUCT → ROOT-CAUSE → FIX-AND-REGRESS → EXPAND.

Time to fix: ~half-day to day. Expand phase: 2-6h.

---

## Recipe 3 — "Should we upgrade dep `tokio` from 1.39 to 1.40?"

Differential audit. Audit both versions; surface the deltas.

```bash
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
TOKIO_139=/tmp/tokio-1.39
TOKIO_140=/tmp/tokio-1.40
AUDIT_139="$TOKIO_139/.unsafe-audit"
AUDIT_140="$TOKIO_140/.unsafe-audit"
DELTA="$AUDIT_140/delta-from-1.39"

# Clone both versions to /tmp; audit artifacts stay inside each clone.
git clone https://github.com/tokio-rs/tokio "$TOKIO_139" && (cd "$TOKIO_139" && git -c advice.detachedHead=false switch --detach tokio-1.39.0)
git clone https://github.com/tokio-rs/tokio "$TOKIO_140" && (cd "$TOKIO_140" && git -c advice.detachedHead=false switch --detach tokio-1.40.0)

# Audit both (quick mode for speed)
# /rust-unsafe-code-exorcist "$TOKIO_139" --audit-dir "$AUDIT_139" --mode audit-only --quick
# /rust-unsafe-code-exorcist "$TOKIO_140" --audit-dir "$AUDIT_140" --mode audit-only --quick

# Diff
mkdir -p "$DELTA"
bash $SKILL/scripts/diff-audit-vs-baseline.sh \
  "$AUDIT_139" "$AUDIT_140" "$DELTA" \
  --label-a "tokio 1.39.0" --label-b "tokio 1.40.0"

# Read the recommendation
cat "$DELTA/diff-report.md" | head -30
```

Output: ADOPT / ADOPT-WITH-MITIGATION / DON'T-ADOPT with reasoning.

Time: ~10–30 min per version + ~1 min for diff.

---

## Recipe 4 — "Add a `safe-only` Cargo feature to my SIMD crate."

`dual-feature-migration` mode. Identify (B) sites; emit safe-only branches; benchmark.

```bash
PROJECT=/path/to/my-simd-crate
AUDIT_DIR="$PROJECT/.unsafe-audit-safe-only-migration"
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

mkdir -p "$AUDIT_DIR" && (cd "$AUDIT_DIR" && git init)

# /rust-unsafe-code-exorcist "$PROJECT" --mode dual-feature-migration --perf-budget 5%
```

The skill enumerates (B) sites, drafts safe-only branches (per [20-SIMD-AND-PERF.md](../patterns/20-SIMD-AND-PERF.md)), runs per-target benchmarks, and emits the CI matrix update.

Expected:
- New `[features] safe-only = []` in Cargo.toml.
- `#[cfg(feature = "safe-only")]` branches added per site.
- Bench results per target in `audit/plans/bench-site-NNNN/`.
- CI matrix entry in `audit/ci-matrix.yml`.

Time: 1-3h per crate depending on bench time.

---

## Recipe 5 — "Continuous mode: catch drift nightly."

After a baseline audit, enable the cron.

```bash
PROJECT=/path/to/my-rust-project
AUDIT_DIR="$PROJECT/.unsafe-audit"
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

# 1. Snapshot baseline (after baseline audit completed)
mkdir -p "$AUDIT_DIR/baseline"
cp -r "$AUDIT_DIR/unsafe-inventory.jsonl" \
      "$AUDIT_DIR/audit/classification" \
      "$AUDIT_DIR/phase1" \
      "$AUDIT_DIR/baseline/"
cp "$AUDIT_DIR/geiger-after.json" "$AUDIT_DIR/baseline/cargo-geiger.json" 2>/dev/null || true

# 2. Configure continuous mode
cp "$SKILL/assets/continuous-mode.toml.template" "$AUDIT_DIR/continuous-mode.toml"
${EDITOR:-vi} "$AUDIT_DIR/continuous-mode.toml"
# Edit thresholds, notifications channel, gates, budget.

# 3. Schedule via cron
crontab -l > /tmp/crontab.bak
(crontab -l 2>/dev/null; echo "0 6 * * * $SKILL/scripts/cron-drift-check.sh $AUDIT_DIR $PROJECT") | crontab -

# 4. Optional: GH Actions auditor for PR gates
cp "$SKILL/assets/gh-actions-auditor.yml.template" "$PROJECT/.github/workflows/soundness.yml"
(cd "$PROJECT" && git add .github/workflows/soundness.yml && git commit -m "ci: add soundness workflow")
```

Now: nightly cron checks drift; PR workflow gates. Read `$AUDIT_DIR/drift/<date>/summary.md` for daily snapshots.

---

## Recipe 6 — "Generate a public SECURITY.md."

After audit, expose the soundness posture to downstream users.

```bash
PROJECT=/path/to/my-rust-project
AUDIT_DIR="$PROJECT/.unsafe-audit"
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

# 1. Invoke the security-md-author subagent
# /rust-unsafe-code-exorcist "$AUDIT_DIR" --mode security-md-generate

# 2. Review the draft
${EDITOR:-vi} "$AUDIT_DIR/audit/changelog-drafts/SECURITY.md"

# 3. Copy to project
cp "$AUDIT_DIR/audit/changelog-drafts/SECURITY.md" "$PROJECT/SECURITY.md"

# 4. Add the README badge
cat <<'EOF' >> "$PROJECT/README.md"

[![Soundness audited](https://img.shields.io/badge/soundness-audited-brightgreen)](./SECURITY.md)
EOF

(cd "$PROJECT" && git add SECURITY.md README.md && git commit -m "docs: add SECURITY.md from audit")
```

Time: ~10 min.

---

## Recipe 7 — "Quantify and prioritize: which 5 sites should I fix this week?"

Risk-score + tactical fix order.

```bash
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
PROJECT=/path/to/my-rust-project
AUDIT_DIR="$PROJECT/.unsafe-audit"

# Compute risk scores
node $SKILL/scripts/compute-risk-score.mjs "$AUDIT_DIR"

# Read the summary (Pareto recommendation included)
cat "$AUDIT_DIR/audit/synthesis/risk-summary.md" | head -50
```

The output's `## Recommendation` line names the top-N covering 80% of risk. Address those first.

For deeper refinement (overrides per project policy), spawn the risk-scorer subagent:

```
# /rust-unsafe-code-exorcist "$AUDIT_DIR" --mode risk-refine
```

---

## Recipe 8 — "Mine the project's git history for past soundness decisions."

Soundness archeology. Surface tribal knowledge.

```bash
PROJECT=/path/to/my-rust-project
AUDIT_DIR="$PROJECT/.unsafe-audit"
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

bash $SKILL/scripts/git-history-soundness-mine.sh "$PROJECT" "$AUDIT_DIR"

# The archeologist subagent then reads $AUDIT_DIR/audit/archeology/ and produces:
# - per-site birth.md
# - refactor-wins.md catalog
# - rejected-refactors.md catalog
# - pattern-signatures.md (high-confidence patterns; rejected patterns)
# - tribal-knowledge.md
```

Output: feeds Phase 4 classifier (pattern signatures) + Phase 5 planner (don't propose rejected patterns).

Time: ~15-30 min depending on history depth.

---

## Recipe 9 — "Pre-release soundness gate before `cargo publish`."

`pre-release-soundness-gate` mode. Strictest possible.

```bash
PROJECT=/path/to/my-rust-crate
AUDIT_DIR="$PROJECT/.unsafe-audit-pre-release-v2.0.0"
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

mkdir -p "$AUDIT_DIR" && (cd "$AUDIT_DIR" && git init)

# /rust-unsafe-code-exorcist "$PROJECT" --mode pre-release-soundness-gate --version v2.0.0
```

Acceptance criteria (per [OPERATING-MODES.md](OPERATING-MODES.md)):
- Every (A) has hardened SAFETY + clippy lint.
- Every (B) ships safe-only feature.
- `cargo +nightly geiger` delta ≤ 0 vs prior version.
- CI matrix green on default AND `safe-only`.
- Reviewer confidence ≥ Medium.

Time: half-day to day for a real release.

---

## Recipe 10 — "Find UB the audit might have missed (inverse audit)."

Fuzz from pub API toward unsafe.

```bash
PROJECT=/path/to/my-rust-project
AUDIT_DIR="$PROJECT/.unsafe-audit"
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

# Inverse audit subagent generates fuzz targets per pub fn
# /rust-unsafe-code-exorcist "$AUDIT_DIR" --mode inverse-audit --top-n 20

# Then run the generated targets (manually or via CI)
cd "$PROJECT"
for target in $(cargo fuzz list); do
  cargo +nightly fuzz run "$target" -- -max_total_time=300
done

# Triage findings
cat "$AUDIT_DIR/audit/inverse-findings.md"
```

Findings cross-reference with forward inventory; either confirm classifications, surface missed sites, or break (A) claims.

Time: depends heavily on fuzz budget; from 1h (smoke) to days (sustained).

---

## Recipe 11 — "Audit a workspace; verify cross-crate contracts."

Workspace-aware audit.

```bash
PROJECT=/path/to/my-workspace   # has Cargo.toml with [workspace]
AUDIT_DIR="$PROJECT/.unsafe-audit"
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

# /rust-unsafe-code-exorcist "$PROJECT" --mode audit-only --workspace
```

The skill detects the workspace + invokes the synthesizer with cross-crate-soundness emphasis. Cross-crate contracts (CCC-NNN) land in `audit/synthesis/cross-crate-contracts.md`.

Then verify the contracts:

```
# /rust-unsafe-code-exorcist "$AUDIT_DIR" --mode contract-verify
```

Output: `audit/synthesis/cross-crate-contracts-verification.md` listing each contract's status (PASS / DRIFT / FAIL).

---

## Recipe 11.5 — "Audit a project I don't have locally — give me a GitHub URL."

You have only a URL. The skill clones, sets up the audit dir inside the cloned project, and starts the audit. The same flow handles HTTPS URLs, SSH-form URLs, and a specific ref / subdirectory.

```bash
URL="https://github.com/owner/repo"        # or git@github.com:owner/repo.git
REF=""                                     # branch / tag / sha; empty = default branch
SUBDIR=""                                  # path within repo if it's a monorepo; empty = repo root
SHALLOW=0                                  # 1 = --depth 50 (faster, less history for archeology)
CLONE_ROOT="/tmp"                          # change to ~/audits if /tmp is tmpfs / small
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

BASENAME=$(basename "${URL%.git}")
CLONE_DIR="$CLONE_ROOT/$BASENAME"

# If a clone directory of the same name exists, use a timestamped clone target.
# Audit artifacts still go inside that clone's project tree.
if [ -e "$CLONE_DIR" ]; then
  CLONE_DIR="$CLONE_ROOT/${BASENAME}-$(date -u +%Y%m%dT%H%M%SZ)"
fi

# Clone
CLONE_ARGS=()
if [ "$SHALLOW" = "1" ]; then CLONE_ARGS+=("--depth" "50"); fi
git clone "${CLONE_ARGS[@]}" "$URL" "$CLONE_DIR"

# Check out a specific ref if requested
if [ -n "$REF" ]; then
  (cd "$CLONE_DIR" && git fetch --tags origin "$REF" && git -c advice.detachedHead=false switch --detach "$REF")
fi

# Anchor on a subdir if monorepo
PROJECT="$CLONE_DIR"
if [ -n "$SUBDIR" ]; then PROJECT="$CLONE_DIR/$SUBDIR"; fi

# Audit dir inside the project; existing source files stay read-only
AUDIT_DIR="$PROJECT/.unsafe-audit"
mkdir -p "$AUDIT_DIR" && (cd "$AUDIT_DIR" && git init)

# Standard intake
"$SKILL/scripts/check-prerequisites.sh"
"$SKILL/scripts/check-skills.sh" "$AUDIT_DIR"
"$SKILL/scripts/install-toolchain.sh" --check "$AUDIT_DIR"
"$SKILL/scripts/detect-mode.sh" "$PROJECT"

# Enumerate, then proceed via slash command:
"$SKILL/scripts/enumerate-unsafe.sh" "$PROJECT" "$AUDIT_DIR"
node "$SKILL/scripts/generate-inventory.mjs" "$AUDIT_DIR"
# /rust-unsafe-code-exorcist "$PROJECT" --audit-dir "$AUDIT_DIR" --mode audit-only
```

Notes:
- Existing source files in the clone are treated as read-only until Phase 8.5 authorizes a refactor pass. The in-project audit dir is the only thing that gets `git commit`s during the audit.
- For SSH-form URLs (`git@github.com:owner/repo.git`) auth flows through `ssh-agent`. If unauthenticated, the `git clone` step fails; fix with `ssh-add` or `gh auth login` before retrying.
- If the repo is private and you've already authenticated `gh`, use `gh repo clone owner/repo "$CLONE_DIR"` instead of `git clone`.
- `--shallow` loses history depth Phase 0.5's soundness archeology can use; if mining git history matters, omit `--shallow`.
- A monorepo with multiple Rust crates: either run the audit once per crate (parallel, each crate gets its own `.unsafe-audit` dir) or pass `--workspace` if there's a top-level `[workspace]` Cargo.toml.

Time to first inventory: ~30 sec for the clone + 1–2 min for enumerate. Full audit time depends on project size (see Recipe 1).

---

## Recipe 12 — "I'm starting from a freshly-installed skill. What's the simplest first move?"

Smoke test on a tiny crate.

```bash
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

# Create the toy from SELF-TEST.md
mkdir -p /tmp/exorcist-smoke && cd /tmp/exorcist-smoke
cat > Cargo.toml <<'EOF'
[package]
name = "exorcist-smoke"
version = "0.1.0"
edition = "2021"
EOF
mkdir src
cat > src/lib.rs <<'EOF'
pub fn from_be_unsafe(b: [u8; 4]) -> u32 {
    unsafe { std::mem::transmute::<[u8; 4], u32>(b) }.to_be()
}
pub fn first_byte_unchecked(s: &[u8]) -> u8 {
    unsafe { *s.get_unchecked(0) }
}
unsafe impl Send for MyHandle {}
pub struct MyHandle {
    inner: *const u8,
}
EOF

# Run the skill's plumbing
AUDIT_DIR=/tmp/exorcist-smoke/.unsafe-audit
mkdir -p "$AUDIT_DIR"
$SKILL/scripts/check-skills.sh "$AUDIT_DIR"
$SKILL/scripts/enumerate-unsafe.sh /tmp/exorcist-smoke "$AUDIT_DIR"
node $SKILL/scripts/generate-inventory.mjs "$AUDIT_DIR"

# Should produce 3+ inventory rows
wc -l "$AUDIT_DIR/unsafe-inventory.jsonl"

# Then invoke the orchestrator for the full audit
# /rust-unsafe-code-exorcist /tmp/exorcist-smoke
```

Time: ~5 min plumbing test; ~20 min full audit on the toy.

---

## Cross-recipe combos

The recipes compose. Common combinations:

- **Recipe 1 + 5 + 6**: full audit → continuous mode → SECURITY.md. The complete onboarding flow.
- **Recipe 1 + 8**: full audit + archeology mining. Best for projects with rich history.
- **Recipe 2 + 9**: incident response then pre-release gate before re-publishing.
- **Recipe 3 + 4**: differential audit (current vs proposed dep upgrade) + dual-feature migration to absorb the upgrade safely.
- **Recipe 7 + 11**: risk-score + workspace contracts. Best for monorepos.

---

## When to deviate from these recipes

- **Time-constrained.** Use `--quick` (skips Phase 5 detailed planning + Phase 7 fresh-eyes).
- **Project too small to fan out.** Manual single-agent run; pass `--tier solo`.
- **Stable toolchain only (no nightly).** `--toolchain-profile stable-only`. Loses miri + careful coverage; documents the gap.
- **Privacy-sensitive.** `--no-cass --no-archeology`. Skip the history mining; the audit only sees current source.

The recipes are starting points. Adjust per project.
