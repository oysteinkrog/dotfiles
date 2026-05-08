# br Configuration

## Configuration Precedence (High to Low)

1. **CLI flags** (highest priority)
2. **Environment variables**
3. **Project config**: `.beads/config.yaml`
4. **User config**: `~/.config/beads/config.yaml`
5. **Defaults** (lowest priority)

---

## Example Config File

```yaml
# .beads/config.yaml

# Issue ID prefix (default: "bd")
issue-prefix: "myproject"

# Use a dedicated branch for syncing `.beads/issues.jsonl` if your team uses that workflow.
sync-branch: "beads-sync"

# Optional toggles (shown here because they are common in agent automation)
json: true
no-auto-import: false
no-auto-flush: false
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `BEADS_DB` | Override database path |
| `BEADS_JSONL` | Override JSONL path (requires `--allow-external-jsonl`) |
| `RUST_LOG` | Logging level (debug, info, warn, error) |

---

## Config Commands

```bash
br config list                         # Show all config
br config get issue-prefix             # Get specific value
br config set issue-prefix=myproject   # Set value
```

---

## Storage Paths

Default storage is in `.beads/` relative to project root:

```
.beads/
├── beads.db        # SQLite database (primary storage)
├── beads.db-shm    # SQLite shared memory (WAL mode)
├── beads.db-wal    # SQLite write-ahead log
├── issues.jsonl    # JSONL export (for git)
├── config.yaml     # Project configuration
└── metadata.json   # Workspace metadata
```
