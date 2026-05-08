# Canvas & List Preservation (Sidecar Pattern)

Slack canvases and lists are native Slack artifacts with no Mattermost equivalent. This reference covers how to extract and preserve them during migration.

## What Slack Exports

### Canvases
- Exported as **HTML** files
- Current version included
- Version history available when all-conversations export is approved (Business+/Enterprise)
- Canvases are rich documents with embedded content, formatting, and embedded objects

### Lists
- Exported as **JSON** files
- Current version included
- Version history available with all-conversations export
- Lists are structured data (think spreadsheet-like tables within Slack)

## The Problem

Mattermost's bulk importer has no native object types for canvases or lists. The importer documentation explicitly states that additional post types beyond the standard set are not supported. If you ignore canvases and lists, their content is silently lost during migration.

## The Sidecar Pattern

Instead of trying to force canvases/lists into Mattermost objects, preserve them as **files attached to posts in archive channels**. This makes them searchable, browsable, and accessible without pretending they're native objects.

### Architecture

```
Slack Export ZIP
├── canvases/
│   ├── canvas_F0ABC.html
│   └── canvas_F0DEF.html
└── lists/
    ├── list_L0ABC.json
    └── list_L0DEF.json

           ↓ (extraction + injection)

Mattermost JSONL (appended)
├── channel: slack-canvases-archive (private)
├── channel: slack-lists-archive (private)
├── post: "Canvas: Project Roadmap Q1" + attached canvas_F0ABC.html
├── post: "Canvas: Onboarding Guide" + attached canvas_F0DEF.html
├── post: "List: Bug Tracker" + attached list_L0ABC.json
└── post: "List: OKR Tracker" + attached list_L0DEF.json
```

### Implementation Steps

#### Step 1: Extract Canvas and List Files
```bash
# Find canvas files in the export
unzip -l slack_export.zip | grep -i canvas

# Find list files
unzip -l slack_export.zip | grep -i list

# Extract to working directory
unzip -j slack_export.zip '*.html' -d workdir/canvases/ 2>/dev/null || true
unzip -j slack_export.zip '*.json' -d workdir/lists/ 2>/dev/null || true
```

The exact paths depend on the Slack export format version. Canvas HTML files may be embedded within channel folders or in a top-level directory.

#### Step 2: Create Archive Channels in JSONL
```bash
# Append archive channel definitions
cat >> mattermost_import.jsonl << 'EOF'
{"type":"channel","channel":{"team":"myteam","name":"slack-canvases-archive","display_name":"Slack Canvases Archive","type":"P","header":"Archived Slack canvases from migration","purpose":"Read-only archive of Slack canvases"}}
{"type":"channel","channel":{"team":"myteam","name":"slack-lists-archive","display_name":"Slack Lists Archive","type":"P","header":"Archived Slack lists from migration","purpose":"Read-only archive of Slack lists"}}
{"type":"channel","channel":{"team":"myteam","name":"slack-export-admin","display_name":"Slack Export Admin","type":"P","header":"Migration audit artifacts","purpose":"Integration logs, audit CSVs, and other admin data from Slack export"}}
EOF
```

#### Step 3: Copy Files into Import Package
```bash
mkdir -p data/bulk-export-attachments/canvases/
mkdir -p data/bulk-export-attachments/lists/
mkdir -p data/bulk-export-attachments/admin/

cp workdir/canvases/*.html data/bulk-export-attachments/canvases/
cp workdir/lists/*.json data/bulk-export-attachments/lists/

# Also preserve admin artifacts
cp workdir/integration_logs.json data/bulk-export-attachments/admin/ 2>/dev/null || true
cp workdir/channel_audit.csv data/bulk-export-attachments/admin/ 2>/dev/null || true
```

#### Step 4: Generate Posts with Attachments
```python
#!/usr/bin/env python3
"""Generate JSONL posts for canvas/list archives."""
import json, os, time, glob

team = "myteam"
admin_user = "admin"  # Must be a user that exists in the JSONL
base_ts = int(time.time() * 1000)  # Current time in ms

posts = []

# Canvases
for i, path in enumerate(sorted(glob.glob("data/bulk-export-attachments/canvases/*.html"))):
    filename = os.path.basename(path)
    name = filename.replace('.html', '').replace('_', ' ').title()
    posts.append({
        "type": "post",
        "post": {
            "team": team,
            "channel": "slack-canvases-archive",
            "user": admin_user,
            "message": f"**Slack Canvas:** {name}\n\nThis canvas was preserved from the Slack workspace migration.",
            "create_at": base_ts + i,
            "attachments": [{"path": path}]
        }
    })

# Lists
for i, path in enumerate(sorted(glob.glob("data/bulk-export-attachments/lists/*.json"))):
    filename = os.path.basename(path)
    name = filename.replace('.json', '').replace('_', ' ').title()
    posts.append({
        "type": "post",
        "post": {
            "team": team,
            "channel": "slack-lists-archive",
            "user": admin_user,
            "message": f"**Slack List:** {name}\n\nThis list was preserved from the Slack workspace migration.",
            "create_at": base_ts + 1000 + i,
            "attachments": [{"path": path}]
        }
    })

# Admin artifacts
for i, path in enumerate(sorted(glob.glob("data/bulk-export-attachments/admin/*"))):
    filename = os.path.basename(path)
    posts.append({
        "type": "post",
        "post": {
            "team": team,
            "channel": "slack-export-admin",
            "user": admin_user,
            "message": f"**Migration Artifact:** `{filename}`",
            "create_at": base_ts + 2000 + i,
            "attachments": [{"path": path}]
        }
    })

# Append to JSONL
with open("mattermost_import.jsonl", "a") as f:
    for post in posts:
        f.write(json.dumps(post) + "\n")

print(f"Added {len(posts)} archive posts to JSONL")
```

## What Else to Preserve

Beyond canvases and lists, these Slack artifacts should be archived:

| Artifact | Where to Find | Archive Channel |
|----------|--------------|-----------------|
| `integration_logs.json` | Top-level in export ZIP | `slack-export-admin` |
| Channel audit CSV | Separate download from Slack admin | `slack-export-admin` |
| `content_flags.json` | Top-level in export ZIP (if present) | `slack-export-admin` |
| Workflow definitions | Not in standard export | Document manually |
| Slack Connect metadata | Per-channel in export | `slack-export-admin` |

## Converting Canvas HTML for Readability

Canvas HTML from Slack is self-contained but may reference Slack-hosted assets. For long-term preservation:

```bash
# Inline any external CSS/images (optional)
for html in data/bulk-export-attachments/canvases/*.html; do
  # Simple check: are there external references?
  grep -c 'https://.*slack' "$html" && echo "WARNING: $html has external Slack references"
done
```

External references will break after Slack workspace is decommissioned. Consider using a tool like `monolith` to inline all assets if long-term offline access matters.

## Converting List JSON for Readability

Slack list JSON can be converted to CSV or markdown for easier viewing in Mattermost:

```python
import json, csv, io

with open("list_data.json") as f:
    data = json.load(f)

# Extract headers and rows (schema varies by list type)
if "columns" in data and "rows" in data:
    headers = [col.get("name", f"col_{i}") for i, col in enumerate(data["columns"])]
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(headers)
    for row in data["rows"]:
        writer.writerow([row.get(h, "") for h in headers])

    with open("list_data.csv", "w") as f:
        f.write(output.getvalue())
```

Attach both the original JSON and the derived CSV/markdown to the archive post for maximum utility.
