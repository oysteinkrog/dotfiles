# CASS Setup (coding_agent_session_search)

Complete setup for cass on a Windows + WSL1 machine. cass indexes coding-agent
session logs (Claude Code, Codex, Cursor, ...) into a searchable archive
(lexical + semantic). Upstream: `Dicklesworthstone/coding_agent_session_search`.

## Architecture on this setup

- **cass.exe runs on the Windows side** (`C:\Users\<user>\bin\cass.exe`).
  WSL1 cannot run it natively (Tantivy needs mmap semantics WSL1 lacks).
- **WSL wrapper** `~/.local/bin/cass` (tracked in dotfiles) execs the Windows
  binary so `cass` works from WSL shells and agents.
- **Data dir**: `%APPDATA%\coding-agent-search\coding-agent-search\data\`
  (canonical DB `agent_search.db` on frankensqlite + lexical index + vector index
  + raw-mirror evidence store).
- **Maintenance loop**: Windows Task Scheduler task `CASS-Maintenance` fires every
  30 min → `wscript.exe cass-maintenance.vbs` (hidden window) → `wsl.exe bash
  ~/.local/bin/cass-maintenance.sh` → `cass index --semantic` + `cm reflect`.
  Both scripts are tracked in dotfiles (`.local/bin/`).

## Fresh-machine install

1. Install binary: download `cass-windows-amd64.zip` from the latest GitHub
   release, verify `.sha256`, unpack to `C:\Users\<user>\bin\cass.exe`.
2. Install the wrapper + maintenance scripts: canonical copies live in dotfiles
   at `.local/bin/{cass,cass-maintenance.sh,cass-maintenance.vbs}` — **copy** them
   to `~/.local/bin/` (do NOT symlink: the .vbs is read by Windows wscript.exe,
   which can't follow WSL-created symlinks). Adjust `CASS_EXE` in the wrapper if
   the Windows username differs.
3. Semantic model (one-time, ~90 MB from HuggingFace):
   `echo y | cass models install` then `cass models verify`.
4. First index: `cass index --full` (then `cass status --json` → healthy).
5. Register the scheduled task (from an elevated-enough Windows shell):
   `schtasks /Create /TN CASS-Maintenance /XML <exported-task.xml>` or recreate:
   trigger = daily 07:00 repeating every 30 min, action =
   `wscript.exe //B //Nologo C:\Users\<user>\.local\bin\cass-maintenance.vbs`,
   `MultipleInstancesPolicy=IgnoreNew`, execution limit 8 h.

## THE critical gotcha: WSLENV

WSL env vars do **not** reach Windows exes unless named in `WSLENV`
(share-list, colon-separated). Both the wrapper and cass-maintenance.sh handle
this for the vars below; any **new** env knob you want cass.exe to see must be
appended to `WSLENV` the same way, or exported from the Windows side.

| Var | Purpose |
|---|---|
| `FSQLITE_PAGE_BUFFER_MAX=1048576` | frankensqlite page-buffer ceiling (~4 GB) — prevents pool-OOM on large index runs |
| `CASS_SEMANTIC_GPU=1` | opt-in DirectML GPU embedding (see below) |

## GPU-accelerated semantic embedding (DirectML)

Custom build, branch `gpu-embedding` at `/c/work/cass-gpu`
(fork: `oysteinkrog/coding_agent_session_search`; 2 commits on upstream main).
Measured on RTX 5070 Ti: **634 chunks/s GPU vs 49 CPU (12.8x)**; CPU/GPU
embedding parity exact (cosine 1.000000, vectors L2-normalized).

- Opt-in: `CASS_SEMANTIC_GPU=1` (+ optional `CASS_SEMANTIC_GPU_DEVICE=<id>`).
  Fail-open: GPU init failure logs a warning and falls back to CPU — indexing
  never breaks. CPU remains default without the var.
- No runtime deps: onnxruntime statically linked, `DirectML.dll` ships with
  Windows (any DX12 GPU works, not just NVIDIA).
- Build (native Windows cargo, ~35 min):
  `powershell.exe -Command "cd C:\work\cass-gpu; cargo build --release"` →
  `target\x86_64-pc-windows-msvc\release\cass.exe`.
- The GPU build needs `onnx/model.onnx` in the model dir (`cass models install`
  adds it; stock ≤0.6.23 used `model.safetensors` instead).
- **Version-string caveat**: builds from main report `cass 0.6.0` (upstream
  doesn't bump the Cargo version between releases). Don't let `cass upgrade`
  overwrite a custom binary; back up as `cass.exe.<ver>.bak` before swapping.
- **Vector-provenance rule**: embeddings must all come from one runtime. When
  switching between a safetensors-based binary (≤0.6.23) and an ONNX-based one,
  wipe `<data>\vector_index\` before re-embedding — the resume checkpoint keys
  on tier+embedder_id+db_fingerprint only and would silently mix vector sets.
  Re-embed: `CASS_SEMANTIC_GPU=1 cass models backfill --tier quality
  --embedder fastembed --batch-conversations 1000 --json` in a loop until
  status `published` (checkpointed, resumable). Full archive (~1.3M chunks)
  ≈ 45–90 min on GPU vs ~8.5 h CPU.

## Known failure modes (hard-won, 2026-08)

- **Duplicate `fts_messages` row in sqlite_master** (frankensqlite
  `CREATE VIRTUAL TABLE IF NOT EXISTS` bug) → DB reports "malformed", every
  index run fails, maintenance task loops heavy rebuilds forever. Fix: salvage
  with official sqlite.org sqlite3 (`.recover` needs its `sqlite_dbpage`; Ubuntu
  build lacks it), drop `fts_messages*` schema rows first (FTS is derived and
  rebuilt by cass), verify row counts, swap file back. Full story:
  `~/.claude/projects/-c-users-oystein/memory/project_cass_recovery_2026-08.md`.
- **Stale frankensqlite sidecars after replacing the DB file**
  (`agent_search.db-fsqlite-ns-use`/`-ns-gate`): bound to the old file's
  identity → "unable to open database file". Move sidecars away together with
  the old DB (and always move `-wal`/`-shm` with their DB, never mix).
- **Stall watchdog false abort (exit 70)**: `cass index` progress counter stays
  0 during staged shard-build/preparing phases; long rebuilds can be killed as
  "stalled". Upstream bug; retry or run attended with memory headroom.
- **Semantic exit 9 "fastembed unavailable"**: model dir missing/incomplete →
  `echo y | cass models install`.

## Health checks

```sh
cass health            # <50 ms, exit 0/1
cass status --json     # index freshness, quarantine count, recommended action
cass doctor --check --json   # bounded read-only truth surface
tail ~/.local/share/cass-maintenance.log   # scheduled-run history
```
