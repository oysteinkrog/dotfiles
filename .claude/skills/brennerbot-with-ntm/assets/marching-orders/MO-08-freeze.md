# MO-08-freeze.md — RESUME.md + Checkpoint + Commit

**Phase:** 8
**Parameters:** `<PANE_N>`, `<SESSION_ID>`, `<WORKSPACE_PATH>`, `<SKILL_SCRIPTS>`

---

You are pane `<PANE_N>` (likely the operator pane or a synthesizer). Your job: produce `deliverables/RESUME.md`, save the ntm checkpoint, commit, push.

This phase is mostly mechanical. Don't add content; produce the freeze.

---

**Step 1 — Compute artifact hashes.**

```bash
# Portable sha256: GNU/Linux ships `sha256sum`; macOS/BSD ships `shasum -a 256`
# (matches the wrapper in dump-session-report.sh / resume-session.sh).
sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }

sha256 <WORKSPACE_PATH>/intake/question_of_record.md | awk '{print $1}'   > /tmp/qor.hash
sha256 <WORKSPACE_PATH>/corpus/corpus_index.md       | awk '{print $1}'   > /tmp/corpus.hash
sha256 <WORKSPACE_PATH>/distillations/disagreement_register.md | awk '{print $1}' > /tmp/disagreement.hash
# also: for each per-family distillation
for F in <WORKSPACE_PATH>/distillations/by_*.md; do
  sha256 "$F" | awk '{print $1}' > "/tmp/$(basename $F .md).hash"
done
```

**Step 2 — Find beads head SHA.**

```bash
cd <WORKSPACE_PATH>
git log -1 --format=%H -- .beads/    > /tmp/beads-head.sha
```

**Step 3 — Save ntm checkpoint.**

```bash
cd <WORKSPACE_PATH>
ntm checkpoint save <SESSION_ID> -m "Phase 8 freeze for <SESSION_ID>"
NTM_CHECKPOINT_ID=$(ntm checkpoint list <SESSION_ID> --json | jq -r '.checkpoints[-1].id')
mkdir -p .ntm/checkpoints
ARCHIVE_PATH=".ntm/checkpoints/${NTM_CHECKPOINT_ID}.tar.gz"
ntm checkpoint export <SESSION_ID> "$NTM_CHECKPOINT_ID" --output="$ARCHIVE_PATH"
```

**Step 4 — Run `dump-session-report.sh --emit-resume`.**

```bash
"<SKILL_SCRIPTS>/dump-session-report.sh" --emit-resume \
  --workspace=<WORKSPACE_PATH> \
  --session=<SESSION_ID> \
  --qor-hash=$(cat /tmp/qor.hash) \
  --corpus-hash=$(cat /tmp/corpus.hash) \
  --disagreement-hash=$(cat /tmp/disagreement.hash) \
  --beads-head=$(cat /tmp/beads-head.sha) \
  --checkpoint-archive="$ARCHIVE_PATH" \
  --checkpoint-id="$NTM_CHECKPOINT_ID" \
  > <WORKSPACE_PATH>/deliverables/RESUME.md.draft
```

**Step 5 — Verify draft.**

```bash
"<SKILL_SCRIPTS>/resume-session.sh" --dry-run --resume <WORKSPACE_PATH>/deliverables/RESUME.md.draft
```

If dry-run reports any field problem, fix the draft (probably you missed a hash or bead query).

**Step 6 — Add free-text fields to draft.**

The dump-script populates structural fields. You add narrative:

- `session_label:` — one-line label for human readers
- `next_loop_recommendation:`
  - `phase:` — which phase to re-enter (4 / 6 / 7 / 10 / none)
  - `duration_estimate_hours:` — float
  - `reason:` — why this phase next
- For each `open_threads[].next_action:` — fill in specific actions

**Step 7 — Promote draft to final.**

```bash
mv <WORKSPACE_PATH>/deliverables/RESUME.md.draft <WORKSPACE_PATH>/deliverables/RESUME.md
```

**Step 8 — Run final dry-run.**

```bash
"<SKILL_SCRIPTS>/resume-session.sh" --dry-run --resume <WORKSPACE_PATH>/deliverables/RESUME.md
```

Must exit 0. Otherwise loop on Step 6.

**Step 9 — Sync beads + commit.**

```bash
br sync --flush-only
cd <WORKSPACE_PATH>
git add intake/ corpus/ evidence/ distillations/ deliverables/ .brenner_workspace/ .beads/ .ntm/checkpoints/
git status   # verify nothing surprising
git commit -m "Phase 8: session frozen — RESUME.md ready for <SESSION_ID>"
```

**Step 10 — Push if remote configured.**

```bash
if git remote -v | grep -q origin; then
  git pull --rebase
  git push
  git status   # MUST show "up to date with origin"
fi
```

**Step 11 — Mark phase complete.**

```bash
echo "Phase 8 complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > <WORKSPACE_PATH>/.brenner_workspace/phase_8_complete.flag
```

**Step 12 — Post freeze summary.**

```
Subject: [<SESSION_ID>] Phase 8 freeze complete
Body:
  RESUME.md: <WORKSPACE_PATH>/deliverables/RESUME.md
  ntm checkpoint: $NTM_CHECKPOINT_ID  (archive: $ARCHIVE_PATH)
  Beads head: $(cat /tmp/beads-head.sha)
  Git: <commit-sha-just-pushed>
  Resume command:
    <SKILL_SCRIPTS>/resume-session.sh --resume <WORKSPACE_PATH>/deliverables/RESUME.md
```

---

**Anti-patterns to avoid:**

- ✗ Skipping the dry-run. RESUME.md that fails dry-run is worse than no RESUME.md.
- ✗ Committing without `br sync --flush-only`. Beads JSONL drift breaks resume.
- ✗ `git push --force` without explicit user approval (per AGENTS.md IRREVERSIBLE GIT rules).
- ✗ Filling `next_loop_recommendation:` as "we'll see" or empty. Required field; pick 4 / 6 / 7 / 10 / `none — converged`.
- ✗ Hand-editing RESUME.md to fix a hash mismatch. If hashes don't match, the underlying file changed; that's an integrity issue, not a hash-update issue.

**Ship-or-Surface SLA:** within 30 minutes, the freeze is complete OR you've surfaced a specific blocker (e.g., "ntm checkpoint export failed; trying alternate path").
