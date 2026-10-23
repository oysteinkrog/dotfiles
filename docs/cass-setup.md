# CASS Setup (coding_agent_session_search)

Setup for cass on native Linux. The older Windows + WSL1 layout is kept at the end as
history; it does not apply on Linux.
cass indexes coding-agent session logs (Claude Code, Codex, Gemini, Cursor, ...)
into a searchable archive (lexical + semantic). Upstream:
`Dicklesworthstone/coding_agent_session_search`.

## Native Linux (current)

- **Binary:** `/usr/bin/cass` (0.10.0 with CUDA embedding), the pacman package
  `cass-local`, built by the localbuilds recipe `cass` (`~/src/localbuilds/recipes/cass`)
  from the fork branch `local/v0.10.0-cuda` (commit 54ed6b4f, installed 2026-10-23).
  That is upstream v0.10.0 plus two ledger fixes and the CUDA embedding commits; the
  recipe README lists them. `~/.local/bin/cass` is a wrapper that sets
  `CASS_AUTO_REFRESH=0`; `~/.local/bin/cass-gpu` is a symlink to the same binary. Track
  release tags, not upstream `main`: for a new release, rebase the local commits onto the
  tag and run `localbuild bump cass <commit>`.
- **Data dir:** `~/.local/share/coding-agent-search` (`agent_search.db`, `index/`,
  `vector_index/`, `models/`, `raw-mirror/`). It was copied from the Windows data
  dir, so the archive keeps the old sessions. Their source paths point at the
  copied session files under `~/.claude/projects`, `~/.codex` and `~/.gemini`.
- **Indexing:** the systemd user timer `cass-maintenance.timer` runs
  `cass-maintenance.service` once a day at 04:00 (plus up to 15 minutes of random
  delay, and at the next boot if the machine was off). A normal run takes about
  1 hour, capped at 4 hours. cass skips a file when its source ledger entry
  (size, mtime, inode, ctime) still matches the file. Upstream cass also compares
  the device number, and btrfs gives `/home` a new device number at some boots
  (36 to 54 on 2026-10-07). After such a boot about 60,000 unchanged transcripts
  looked changed and every run timed out at 4 hours. The local build ignores the
  device number since 2026-10-10 (reported upstream as issue #536). Do not
  set `CASS_EXCLUDE_PATHS`: it turns the ledger skip off for every source, so every
  run parses the whole corpus again. The service runs
  `~/.local/bin/cass-maintenance.sh`: a capped `cass index` (4 hours), then
  `cm reflect` on new Claude sessions. Before that, `cass-memcheck` (ExecCondition)
  needs MemAvailable >= 20 GiB and SwapFree >= 12 GiB. If not, it retries every
  5 minutes for up to 2 hours, logging each wait to the journal, then skips the
  run. `TimeoutStartSec` is 6h10min: 2 h wait + 4 h index cap + slack. `install.sh`
  links the script and both units, and the `services` step enables the timer.
  Linger must be on (`loginctl enable-linger`) so the timer runs without a login.
- **Log:** `~/.local/share/cass-maintenance.log`, and
  `journalctl --user -u cass-maintenance`.
- **Nightly index on hold (2026-10-23).** `cass-maintenance.timer` is stopped. With
  the caps in the unit (MemoryHigh 6G, MemoryMax 14G, MemorySwapMax 2G) both 0.9.0 and
  0.10.0 fill the 2 GiB swap cap during startup, before indexing anything. The 0.10.0 test
  (11:48 to 11:52, samples in `/var/tmp/claude/cass-mem/sampler-v010.tsv`) held about
  4.5 GiB of anon memory (2.5 GiB resident plus 2.0 GiB swapped), 3.0 GiB of page cache
  (1.6 GiB of it mapped database and index files) and 0.7 GiB of kernel memory. The first
  0.10.0 index also rebuilds the whole lexical index once (schema v22). Start the timer
  again only after a capped run passes: `systemctl --user start cass-maintenance.timer`.
- **Rollback copy of the data dir.** `/var/tmp/claude/cass-data-pre-v010` is a reflink
  copy taken before 0.10.0 first touched the data (2026-10-23 11:36). To go back to the
  0.9.0 build, check out the old recipe pin, `localbuild install cass`, and restore this
  copy.

Check that it works:

```sh
systemctl --user list-timers cass-maintenance.timer   # next and last run
cass status --json | jq '{healthy, fresh: .index.fresh, last: .index.last_indexed_at}'
tail ~/.local/share/cass-maintenance.log
```

Set it up on a new Linux machine: run `setup/bootstrap.sh tools links services`,
copy the data dir and the session folders from the old machine, then run
`systemctl --user start cass-maintenance.service` once.

## Semantic search and GPU embedding

Semantic search needs a vector index. None works yet on Linux: the August index came
from the Windows GPU build, and cass rejects it ("incompatible vector index ... rebuild
semantic vectors"). `--mode semantic` and `--mode hybrid` fall back to lexical.

The installed build embeds with the RTX 5070 Ti through CUDA (model all-MiniLM-L6-v2,
quality tier `minilm-384`). At start it compares GPU and CPU output for 9 fixed texts
and uses the GPU only if they agree within 1e-4. `CASS_EMBED_DEVICE=cpu` turns the GPU
off without a reinstall.

Rules:

- **Never run `cass index --semantic`.** It holds the whole text of each conversation in
  memory, and some transcripts are over 600 MB. The `harness-rules-guard` hook blocks it,
  also as `cass-gpu index --semantic`.
- Embed only with `cass models backfill --tier quality --embedder minilm`, in a capped
  unit in `builds.slice`, never during working hours on the real data dir.
- The model folder must hold only the current bundle. The August folder has an extra
  `onnx/` subfolder from the Windows build, and 0.10.0 refuses it ("unregistered file
  collides with an expected semantic role"). Fix: move
  `models/all-MiniLM-L6-v2` aside and run `cass models install -y`.

### GPU test, 2026-10-23

Run on a reflink copy of the data dir (`/var/tmp/claude/cass-embed-test`) in a transient
unit: builds.slice, MemoryHigh 6G, MemoryMax 10G, MemorySwapMax 1G, CPUQuota 800%.
Scripts and samples: `/var/tmp/claude/cass-embed-run/`.

| Measure | Result |
|---|---|
| First batch, 3,000 conversations, 235,529 chunks | 115 s: 32 s selection, 82 s embedding |
| GPU embedding rate | 2,911 chunks/s steady |
| Memory | process RSS 1.4 GiB, unit peak 2.0 GiB, unit swap at most 81 MiB |
| GPU memory | 2.46 GiB before, 5.80 GiB peak (+3.3 GiB) |
| Second and later batches | blocked: about 13 h per batch, see below |

**Resume does not work on 0.10.0.** Once a checkpoint exists, each later
`models backfill` call first re-reads every conversation from id 0
(`reconcile_backfill_from_storage` in `src/indexer/semantic/engine.rs`). Measured: 1.41
conversations/s on one CPU core, which is about 13 h for the 67,117 conversations, per
batch. The GPU waits the whole time. So a nightly, resumable embed job is not possible on
this release. Upstream `main` has reworked this path since v0.10.0 (#525 fixes, a replay
cache); I have not tested it. A single first batch over the whole corpus would avoid the
re-read, but its memory use is not measured.

Projection: the corpus is about 5.3 million chunks (guess from 78.5 chunks per
conversation in the first 3,000), which is about 30 minutes of GPU time. The real limit
is the re-read above.

A draft `cass-embed.service`, timer and script are in
`/var/tmp/claude/cass-mem/cass-embed-draft/`. They are not installed.

## Windows history (does not apply on Linux)

The Windows + WSL1 setup ran until 2026-09-28. The split-binary rule, the DirectML
build and the vector-provenance rule below were about two different Windows binaries.
On Linux there is one binary, and cass now checks the vector space itself.

### Windows + WSL1 layout (before 2026-09-28)

- **cass.exe runs on the Windows side** (`C:\Users\<user>\bin\cass.exe`).
  WSL1 cannot run it natively (Tantivy needs mmap semantics WSL1 lacks).
- **WSL wrapper** `~/.local/bin/cass` (tracked in dotfiles) execs the Windows
  binary so `cass` works from WSL shells and agents.
- **Data dir**: `%APPDATA%\coding-agent-search\coding-agent-search\data\`
  (canonical DB `agent_search.db` on frankensqlite + lexical index + vector index
  + raw-mirror evidence store).
- **Maintenance loop**: Windows Task Scheduler task `CASS-Maintenance` fires every
  30 min → `wscript.exe cass-maintenance.vbs` (hidden window) → `wsl.exe bash
  ~/.local/bin/cass-maintenance.sh` → `cass index` (lexical, 0.6.23) +
  `cass-gpu models backfill` (GPU semantic) + `cm reflect`.
  Both scripts are tracked in dotfiles (`.local/bin/`).

### Fresh-machine install

1. Install binary: download `cass-windows-amd64.zip` from the latest GitHub
   release, verify `.sha256`, unpack to `C:\Users\<user>\bin\cass.exe`.
2. Install the wrapper + maintenance scripts: canonical copies live in dotfiles
   at `.local/bin/{cass,cass-maintenance.sh,cass-maintenance.vbs}`. **Copy** them
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

### THE critical gotcha: WSLENV

WSL env vars do **not** reach Windows exes unless named in `WSLENV`
(share-list, colon-separated). Both the wrapper and cass-maintenance.sh handle
this for the vars below; any **new** env knob you want cass.exe to see must be
appended to `WSLENV` the same way, or exported from the Windows side.

| Var | Purpose |
|---|---|
| `FSQLITE_PAGE_BUFFER_MAX=1048576` | frankensqlite page-buffer ceiling (~4 GB), prevents pool-OOM on large index runs |
| `CASS_SEMANTIC_GPU=1` | opt-in DirectML GPU embedding (see below) |

### Split-binary layout (REQUIRED as of 2026-08-09)

Two binaries, strict division of labour:

| Binary | Version | Runs | Never runs |
|---|---|---|---|
| `C:\Users\<user>\bin\cass.exe` | stock **0.6.23** | `cass index` (lexical incremental), lexical search, status/health | `--semantic` anything (safetensors embedder would mix vector provenance; its identity guard also refuses the ONNX index at query time) |
| `C:\Users\<user>\bin\cass-gpu.exe` | gpu-embedding branch (reports 0.6.0) | `models backfill` (bounded, checkpointed GPU embedding); `search --mode semantic` | `cass index` (see regression below) |

WSL wrappers: `~/.local/bin/cass` → cass.exe, `~/.local/bin/cass-gpu` →
cass-gpu.exe (both tracked in dotfiles).

Measured latencies (2026-08-09, warm-ish): lexical search 4 s on 0.6.23 vs
56 s on the main-branch build (main is slow across the board on this
dataset, not just at indexing); semantic search ~4 min via cass-gpu (vector
index load over drvfs dominates). So interactive/lexical traffic stays on
0.6.23 and semantic queries are an explicit `cass-gpu search --mode
semantic` when the 4-minute cost is worth it.

**Why split:** the main-branch build (post-0.6.23) has an incremental
`cass index` memory regression: 30+ GB private bytes and a stall at ~2
conversations processed, reproduced twice (2026-08-07 and 2026-08-09) under
different system load; 0.6.23 incrementals use ~300 MB. `models backfill` on
the same main-branch build is unaffected (bounded batches, checkpointed), so
the GPU build handles only embedding. cass-maintenance.sh encodes this:
step 1 `cass index` (0.6.23), step 1b `cass-gpu models backfill --tier
{quality,fast}` loop until published.

Query-time note: 0.6.23 REFUSES semantic queries over the ONNX-built index
("Embedding space identity is unverifiable": its identity guard cannot
authenticate vectors produced by the newer build; the guard was reworked
upstream after 0.6.23, so there is no local override). Semantic queries must
go through `cass-gpu`. A stale `models/all-MiniLM-L6-v2.downloading` staging
dir (leftover from a failed download) additionally pins the model lifecycle
in "acquiring" and blocks semantic search on any binary. If `cass models
status --json` says `state: acquiring` with 0 bytes present while the model
files verify, remove the empty staging dir.

### GPU-accelerated semantic embedding (DirectML)

Custom build, branch `gpu-embedding` at `~/work/cass-gpu`
(fork: `oysteinkrog/coding_agent_session_search`; 2 commits on upstream main).
Measured on RTX 5070 Ti: **634 chunks/s GPU vs 49 CPU (12.8x)**; CPU/GPU
embedding parity exact (cosine 1.000000, vectors L2-normalized).

- Opt-in: `CASS_SEMANTIC_GPU=1` (+ optional `CASS_SEMANTIC_GPU_DEVICE=<id>`).
  Fail-open: GPU init failure logs a warning and falls back to CPU, so indexing
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
  wipe `<data>\vector_index\` before re-embedding: the resume checkpoint keys
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
- **Main-branch incremental `cass index` memory regression** (2026-08): 30+ GB
  private bytes, stall at ~2 conversations, system commit pressure; watchdog
  diagnostics fire but the process can linger for a long time holding
  `index-run.lock` (later runs fail exit 7). Reproduced twice; 0.6.23 is fine.
  This is why the Windows split-binary layout existed. It does not apply on Linux.
- **Flaky process-exit detection**: `tasklist.exe /FI` can transiently return
  nothing under load, which looks like "process gone". Only trust an explicit
  "No tasks are running" answer, and require several consecutive ones.

## Health checks

```sh
cass health            # <50 ms, exit 0/1
cass status --json     # index freshness, quarantine count, recommended action
cass doctor --check --json   # bounded read-only truth surface
tail ~/.local/share/cass-maintenance.log   # scheduled-run history
```
