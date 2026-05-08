# Alternative Migration Targets

While this skill focuses on Mattermost, the Slack export and enrichment pipeline produces data that can target other platforms. If Mattermost isn't the right fit, these alternatives share the same Phase 1 extraction.

## Decision Matrix

| Criterion | Mattermost | Zulip | Rocket.Chat | Element (Matrix) |
|-----------|-----------|-------|-------------|-----------------|
| Slack-like UX | Very similar | Different (topics) | Very similar | Different |
| Import tooling maturity | Good (mmetl + mmctl) | Excellent (built-in) | Good (admin UI) | Complex (bridges) |
| Open source | Team Ed: yes, Ent: partial | 100% open source | Partial | 100% open source |
| Self-hosting difficulty | Medium | Medium | Easy (Docker) | Hard |
| Best for | Slack replacement | Knowledge management | Quick lift-and-shift | Federation/sovereignty |
| 1000-user fit | Needs Enterprise | Yes (free) | Yes (free) | Yes (but complex) |

## Zulip: Best Open-Source Story

### Why Consider
- 100% open source, no enterprise-gated features
- Topic-based threading (channels + topics, not just channels)
- Most polished Slack import tooling
- Imports: org name/logo, messages, attachments, emoji reactions, users, channels, custom emoji

### Import Process
```bash
# 1. Install Zulip on Linux
# 2. Create a Slack Bot App with scopes: emoji:read, users:read, users:read.email, team:read
# 3. Copy the xoxb- token

cd /home/zulip/deployments/current
./scripts/stop-server
./manage.py convert_slack_data /tmp/slack_export.zip \
  --token xoxb-your-bot-token \
  --output /tmp/converted_slack_data
./manage.py import '' /tmp/converted_slack_data
./scripts/start-server
```

### Key Differences from Mattermost
- Uses `xoxb-` (Bot Token) instead of `xoxp-` (User Token)
- Conversion and import are a single step (no separate mmetl)
- Import creates a **new** organization; cannot import into existing
- Handles emoji and users via Slack API during conversion (needs `team:read` scope)

### Same Phase 1 Extraction
The official Slack export ZIP is the input for both. Enrichment with slack-advanced-exporter works the same way. The only difference is the transform step.

## Rocket.Chat: Easiest Migration

### Why Consider
- Most Slack-like experience
- Import is done through the admin UI (no CLI tools)
- Docker Compose deployment is straightforward
- Built-in Slack importer

### Import Process
1. Deploy Rocket.Chat via Docker Compose
2. Go to **Manage > Workspace > Import**
3. Click **Import New File**
4. Choose **Slack** as import type
5. Upload the Slack export ZIP (or point to file path on server)
6. Select which users/channels/messages to import
7. Click **Start Importing**

### Caveats
- Keep import files under ~15 MB (split by date range if larger)
- If Slack hides email addresses, they'll be missing from the import
- No equivalent of mmetl for transform -- Rocket.Chat handles it internally

### Same Phase 1 Extraction
Same Slack export ZIP input. Enrichment less critical because Rocket.Chat's importer handles some of it internally.

## Element/Matrix: Protocol Sovereignty

### Why Consider
- Federated protocol (can communicate across organizations)
- Bridges to IRC, Slack, Telegram, Gitter
- No single point of failure
- Full encryption (end-to-end)

### Import Complexity
Matrix migration from Slack is the most complex option:
- No built-in Slack importer
- Must use third-party migration tools or custom scripts
- Message format conversion is non-trivial
- Bridges can maintain real-time Slack connectivity during transition

### When to Choose
Only if your top priority is:
- Protocol-level sovereignty and federation
- Bridging multiple chat platforms
- Decentralized architecture
- End-to-end encryption as a core requirement

## Recommendation Summary

| If you want... | Choose |
|----------------|--------|
| Closest Slack replacement | Mattermost or Rocket.Chat |
| Best open-source story | Zulip |
| Easiest migration | Rocket.Chat (UI import) |
| Best async knowledge management | Zulip (topics model) |
| Most powerful self-hosting with future scale | Mattermost |
| Federation and protocol sovereignty | Element/Matrix |
| Cheapest total cost of ownership | Any self-hosted option vs Slack |

## Shared Phase 1 Work

Regardless of target platform, Phase 1 extraction produces artifacts useful for all:

| Artifact | Mattermost | Zulip | Rocket.Chat | Matrix |
|----------|:-:|:-:|:-:|:-:|
| Official Slack export ZIP | yes | yes | yes | yes |
| Enriched export (emails + files) | yes | partial (uses API) | yes | yes |
| Custom emoji directory | yes | yes (during convert) | yes | yes |
| Channel audit CSV | yes | yes | yes | yes |
| Canvas/list sidecars | yes | manual | manual | manual |

The extraction pipeline is platform-agnostic. Only the transform step differs.
