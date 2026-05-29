# Doctor & Disaster Recovery

Diagnostics, repair, backup, and restore for Agent Mail.

---

## Quick Health Check

```bash
curl http://127.0.0.1:8765/health
# → {"status": "healthy"}
```

---

## Doctor Commands

### Run Diagnostics

```bash
# Basic check
am doctor check

# Verbose with details
am doctor check --verbose

# JSON output for automation
am doctor check --json

# Check specific project
am doctor check /abs/path/project
```

**Checks performed:**
- Stale file reservations (expired TTL)
- Database integrity
- Orphaned records
- FTS index sync
- Git archive consistency

### Preview Repairs (Dry Run)

```bash
am doctor repair --dry-run
```

Shows what would be fixed without making changes.

### Apply Repairs

```bash
# Interactive (prompts for confirmation)
am doctor repair

# Auto-confirm (creates backup first)
am doctor repair --yes

# With custom backup directory
am doctor repair --yes --backup-dir /tmp/backups
```

---

## Backup & Restore

### Create Backup

```bash
# With label
am archive save --label nightly

# Default label (timestamp)
am archive save
```

### List Backups

```bash
am doctor backups

# JSON format
am doctor backups --json
```

### Restore from Backup

```bash
# Preview what would be restored
am doctor restore /path/to/backup.zip --dry-run

# Perform restore
am doctor restore /path/to/backup.zip --yes
```

---

## Static Mailbox Export

Export mailbox for auditors, stakeholders, or archives.

### Interactive Wizard (Recommended)

```bash
am share wizard
```

Guides you through export options, signing, encryption, and deployment.

### Manual Export

```bash
# Basic export
am share export --output ./bundle

# With cryptographic signing
am share export \
  --output ./bundle \
  --signing-key ./keys/signing.key

# With age encryption
am share export \
  --output ./bundle \
  --age-recipient age1abc...xyz

# Scrub sensitive content
am share export \
  --output ./bundle \
  --scrub-preset strict  # or 'standard'
```

### Preview Exported Bundle

```bash
am share preview ./bundle --port 9000 --open-browser
```

### Verify Bundle Integrity

```bash
am share verify ./bundle
```

### Refresh Existing Bundle

```bash
am share update ./bundle
```

### Decrypt Age-Encrypted Bundle

```bash
am share decrypt bundle.zip.age --identity ~/.age/key.txt
```

---

## Dangerous Operations

### Full Reset (Destructive!)

```bash
# Prompts for archive first
am clear-and-reset-everything

# Skip prompts (automation)
am clear-and-reset-everything --force --no-archive
```

**WARNING:** Deletes SQLite database and all storage contents.

---

## File Reservation Management

### List Reservations

```bash
# All reservations
am file_reservations list /abs/path/project

# Active only
am file_reservations list /abs/path/project --active-only

# Active with limit
am file_reservations active /abs/path/project --limit 10
```

### Expiring Soon

```bash
# Reservations expiring within 30 minutes
am file_reservations soon /abs/path/project --minutes 30
```

---

## ACK Management

### Pending Acknowledgments

```bash
am acks pending /abs/path/project GreenCastle --limit 10
```

### Overdue ACKs

```bash
am acks overdue /abs/path/project GreenCastle --ttl-minutes 60
```

### Remind About Old ACKs

```bash
am acks remind /abs/path/project GreenCastle --min-age-minutes 30
```

---

## Common Issues

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Stale reservations accumulating | Agent crashed without releasing | `doctor repair --yes` |
| FTS search returns wrong results | Index out of sync | `doctor repair --yes` |
| "database is locked" | Concurrent access issue | Restart server, retry |
| Corrupted git archive | Interrupted write | Restore from backup |
| Server won't start | Port conflict | `config set-port 9000` |
