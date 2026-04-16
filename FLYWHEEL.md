# Agentic Flywheel

Cross-session procedural memory for AI coding agents. Agents learn from past sessions,
rules are extracted and served in context, and the system improves over time.

## Architecture

```
Agent session → cass indexes → cm reflects → playbook rules
                                                    ↓
                               cm context ← Ollama embeddings (semantic ranking)
                                    ↓
                              Agent gets relevant rules → works better → ...
```

| Component | Binary | Purpose |
|-----------|--------|---------|
| **cass** | Windows `.exe` via WSL wrapper | Index + search 14K+ session logs (Tantivy full-text) |
| **cm** | Linux ELF (forked, rebuilt) | Procedural memory: extract, serve, score playbook rules |
| **ms** | Windows `.exe` via WSL wrapper | Mine sessions for reusable skills |
| **Ollama** | Windows native | GPU-accelerated embeddings for semantic search |
| **trauma_guard** | Python hook | Block dangerous command patterns before execution |

### Why Windows binaries for cass/ms

WSL1 kernel (4.4.0) doesn't support the mmap operations Tantivy needs. Both cass and
ms use Tantivy internally. The Linux binaries crash with `EINVAL (os error 22)`.
Running the Windows `.exe` via WSL interop (`exec /path/to/tool.exe "$@"`) avoids this.

### Why cm is forked

The upstream cm binary (`~/.local/bin/cm`) uses `@xenova/transformers` for embeddings,
which requires ONNX native libraries that don't work on WSL1. Our fork replaces this
with an Ollama HTTP backend — embeddings are computed GPU-side via Ollama's `/api/embed`.

Fork: `oysteinkrog/cass_memory_system` branch `feat/ollama-embedding-backend`.
Source: `/c/work/cass_memory_system/`. Rebuild: `cd /c/work/cass_memory_system && bun run build:current && cp dist/cass-memory ~/.local/bin/cm`

## Install (new machine)

### 1. Prerequisites

```bash
# Ollama (Windows — install via https://ollama.com, then pull embedding model)
ollama pull nomic-embed-text

# Bun (for building cm from source)
curl -fsSL https://bun.sh/install | bash
```

### 2. Install cass (session search)

```bash
# Download Windows binary (v0.1.64 — v0.2.x has Limbo/FrankenSQLite bugs)
curl -fsSL -o /tmp/cass-win.zip \
  "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v0.1.64/cass-windows-amd64.zip"
python3 -c "import zipfile; zipfile.ZipFile('/tmp/cass-win.zip').extractall('/tmp/cass-win')"
mkdir -p ~/bin  # Windows-side bin (e.g., /c/Users/$USER/bin)
cp /tmp/cass-win/cass.exe ~/bin/cass.exe
chmod +x ~/bin/cass.exe
```

Create WSL wrapper at `~/.local/bin/cass`:

```bash
#!/usr/bin/env bash
CASS_EXE="/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n')/bin/cass.exe"
CASS_DATA="C:\\Users\\$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n')\\AppData\\Roaming\\cass-old"
HAS_DATADIR=false; HAS_SUBCOMMAND=false
for arg in "$@"; do
  [[ "$arg" == "--data-dir" ]] && HAS_DATADIR=true
  [[ "$arg" != -* && "$HAS_SUBCOMMAND" == "false" ]] && HAS_SUBCOMMAND=true
done
if [[ "$HAS_DATADIR" == "false" && "$HAS_SUBCOMMAND" == "true" ]]; then
  exec "$CASS_EXE" "$@" --data-dir "$CASS_DATA"
else
  exec "$CASS_EXE" "$@"
fi
```

```bash
chmod +x ~/.local/bin/cass
```

### 3. Fix .claude symlink for Windows visibility

WSL1 Linux symlinks are invisible to Windows executables. Replace with a junction:

```bash
# Remove Linux symlink
rm ~/.claude
# Create Windows junction (cass.exe needs to see .claude/projects/)
cmd.exe /c "mklink /J C:\Users\%USERNAME%\.claude C:\Users\%USERNAME%\.dotfiles\.claude"
```

### 4. Build and install cm (procedural memory)

```bash
git clone https://github.com/oysteinkrog/cass_memory_system.git /c/work/cass_memory_system
cd /c/work/cass_memory_system
git checkout feat/ollama-embedding-backend
npm install
bun run build:current
cp dist/cass-memory ~/.local/bin/cm
chmod +x ~/.local/bin/cm
```

### 5. Install ms (meta_skill)

```bash
curl -fsSL -o /tmp/ms-win.zip \
  "https://github.com/Dicklesworthstone/meta_skill/releases/download/v0.1.0/ms-0.1.0-x86_64-pc-windows-msvc.zip"
python3 -c "import zipfile; zipfile.ZipFile('/tmp/ms-win.zip').extractall('/tmp/ms-win')"
cp /tmp/ms-win/ms.exe ~/bin/ms.exe
chmod +x ~/bin/ms.exe
```

Create WSL wrapper at `~/.local/bin/ms`:

```bash
#!/usr/bin/env bash
exec "/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n')/bin/ms.exe" "$@"
```

```bash
chmod +x ~/.local/bin/ms
ms init --global
ms index
```

### 6. Initial index + reflect

```bash
# Index all session logs (takes ~45s for 14K sessions)
cass index --full

# Reflect on recent sessions to bootstrap playbook
for session in ~/.claude/projects/*/*.jsonl; do
  cm reflect --session "$session" --json 2>/dev/null || true
done

# Check result
cm playbook list | head -5
```

### 7. Add trauma patterns

```bash
cm trauma add "kill.*-9|pkill|killall" \
  --severity CRITICAL \
  --message "STOP: Verify you started this process before killing it."

cm trauma add "git add -A|git add \." \
  --severity CRITICAL \
  --message "STOP: Only stage specific files. Never use git add -A or git add ."

cm trauma add "git commit.*--no-verify" \
  --severity CRITICAL \
  --message "STOP: Do not bypass pre-commit hooks."
```

### 8. Install trauma guard hook

The guard script is at `~/.claude/hooks/trauma_guard.py` (ships with dotfiles).
It's wired into `settings.json` PreToolUse hooks — no manual step needed if
dotfiles are installed.

### 9. Schedule maintenance (Windows Task Scheduler)

```powershell
$action = New-ScheduledTaskAction `
  -Execute 'powershell.exe' `
  -Argument '-NoProfile -WindowStyle Hidden -Command "wsl.exe bash ~/.local/bin/cass-maintenance.sh"'

$trigger = New-ScheduledTaskTrigger -Daily -At '06:00' `
  | % { $_.Repetition = (New-ScheduledTaskTrigger -Once -At '06:00' `
        -RepetitionInterval (New-TimeSpan -Hours 6)).Repetition; $_ }

Register-ScheduledTask -TaskName 'CASS-Maintenance' `
  -Action $action -Trigger $trigger `
  -Description 'CASS: re-index sessions and reflect on recent work' `
  -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30))
```

## Config reference

### `~/.cass-memory/config.json`

| Setting | Value | Why |
|---------|-------|-----|
| `embeddingBackend` | `"ollama"` | Use local Ollama for embeddings (ONNX broken on WSL1) |
| `embeddingModel` | `"nomic-embed-text"` | 768-dim, fast, good quality |
| `ollamaBaseUrl` | `"http://localhost:11434"` | Default Ollama port |
| `semanticSearchEnabled` | `true` | Enable semantic dedup and ranking |
| `dedupSimilarityThreshold` | `0.7` | Tighter than default 0.85 |
| `maxBulletsInContext` | `20` | Keep context focused (default 50 is too many) |
| `sessionLookbackDays` | `14` | Wider than default 7 |
| `baseUrl` | `"https://***REMOVED-PROXY-DOMAIN***/v1"` | API proxy (if using ccflare) |
| `budget` | `$5/day, $50/month` | Controls LLM reflection cost |

### Hooks (in `settings.json`)

| Event | Hook | Purpose |
|-------|------|---------|
| Stop | `cm outcome success` | Record successful session for scoring |
| PostToolUseFailure | `cm outcome failure` | Record failures for scoring |
| PreToolUse[Bash] | `dcg` | Destructive command guard |
| PreToolUse[Bash] | `trauma_guard.py` | Block trauma patterns (kill, git add -A, --no-verify) |

## Daily operations

```bash
# Check playbook health
cm playbook list
cm top 10                    # best rules
cm stale                     # rules needing feedback

# Search sessions
cass search "authentication bug" --json

# Get context for a task
cm context "fix the build" --json --limit 5

# Manual reflection on a specific session
cm reflect --session ~/.claude/projects/<project>/<session>.jsonl --json

# Semantic dedup
cm similar "<rule text>" --threshold 0.8

# Re-index after many new sessions
cass index --full

# Run full maintenance
bash ~/.local/bin/cass-maintenance.sh
```

## Upstream repos

| Tool | Repo | Our fork |
|------|------|----------|
| cass | [Dicklesworthstone/coding_agent_session_search](https://github.com/Dicklesworthstone/coding_agent_session_search) | — (use v0.1.64 release binary) |
| cm | [Dicklesworthstone/cass_memory_system](https://github.com/Dicklesworthstone/cass_memory_system) | [oysteinkrog/cass_memory_system](https://github.com/oysteinkrog/cass_memory_system) `feat/ollama-embedding-backend` |
| ms | [Dicklesworthstone/meta_skill](https://github.com/Dicklesworthstone/meta_skill) | — (use v0.1.0 release binary) |

## Known limitations

- **cass v0.1.64** lacks `sessions` command (v0.2.x), so `cm onboard sample` returns empty
- **cass v0.2.2+** Windows binaries have FrankenSQLite/Limbo bugs (hang on reads)
- **Cross-agent learning** disabled — enable after playbook stabilizes
- **Ollama must be running** for semantic search — if it's down, cm falls back to keyword search
