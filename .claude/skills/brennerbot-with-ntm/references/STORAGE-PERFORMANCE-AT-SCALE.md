# STORAGE-PERFORMANCE-AT-SCALE.md — File Locking, Incremental Indexing, Compound IDs

<!-- TOC: Why storage performance matters | Incremental index updates | Cross-process file locking | Compound + simple ID formats | Optimized deletion (fast vs slow path) | At-scale storage patterns | Anti-patterns | Cross-references -->

A single brennerbot session creates dozens of files (artifacts, evidence, beads, intervention logs). 10 sessions/week × 52 weeks = 500+ session histories. Without storage performance discipline, querying across sessions becomes O(N) on a growing N — and the operator's CLI feels slower with each session.

Brennerbot's storage layer implements **incremental indexing**, **cross-process file locking**, **compound + simple ID formats**, and **fast-path deletion**. These optimizations make at-scale operation viable.

Mined from `/dp/brenner_bot/README.md § Storage Performance Optimizations`.

---

## Why storage performance matters

Three failures of naive storage:

1. **Full rebuild on every save** — re-scan every per-session file and rebuild the index; cost grows with session × entry count
2. **Race conditions** — concurrent writes corrupt files; lost updates
3. **Slow lookups** — every ID lookup scans all session files

Three benefits of optimized storage:

1. **Incremental updates** — read+filter+rewrite a single index file (O(N) where N = total entries), instead of re-scanning every per-session file (O(S × K) where S = sessions, K = entries-per-session)
2. **Concurrency-safe** — file locking prevents concurrent-write corruption
3. **Fast lookups** — compound IDs encode session ID, enabling direct per-session file access

---

## Incremental index updates

The cross-session index is rebuilt **per-session**, not globally:

```typescript
async updateIndexForSessionUnlocked(sessionId: string, items: T[]): Promise<void> {
  // 1. Read existing index
  const index = await this.loadIndex();

  // 2. Filter out entries for THIS session only
  const otherEntries = index.entries.filter(e => e.sessionId !== sessionId);

  // 3. Create new entries from current items
  const newEntries = items.map(item => this.toIndexEntry(item));

  // 4. Merge (other sessions unchanged + this session refreshed) and write
  index.entries = [...otherEntries, ...newEntries];
  await this.writeIndex(index);
}
```

Per `/dp/brenner_bot/CHANGELOG.md` v0.3.0:
> Incremental index updates: O(1) updates vs O(n) full rebuilds for session saves

(The CHANGELOG's "O(1)" describes the *increment operation* — the number of items added/removed for this session is bounded by session size, not by total session count. The single-index read+write itself is O(N) where N = total entries across all sessions; but it avoids the O(S × K) per-session-file scan that a full rebuild would do.)

The practical effect: for 500-session histories with ~20 entries each (~10K total), single-index update completes in ~10ms vs the multi-second rebuild it replaces.

### Fallback to full rebuild

If the index is missing or corrupt:

```typescript
async loadIndex(): Promise<Index> {
  try {
    return await readIndex();
  } catch {
    // Fall back: rebuild from scratch
    return await rebuildFullIndex();
  }
}
```

Recovery is automatic but slow (O(N) one-time). The fast path is the common case.

---

## Cross-process file locking

For filesystem operations across processes (CLI + web app + cron jobs), advisory file locks prevent concurrent modification:

```typescript
import { withFileLock } from "@/lib/storage/file-lock";

await withFileLock(baseDir, "hypotheses", async () => {
  // Safe to read-modify-write
  const data = await loadFile();
  data.items.push(newItem);
  await saveFile(data);
});
```

Lock implementation:
- **Atomic file operations** — `O_EXCL` flag for lock-file creation
- **TTL-based expiry** — locks auto-expire if process crashed; default 30s
- **Crash recovery** — stale locks detected by TTL; new process can take over

Per `/dp/brenner_bot/CHANGELOG.md` v0.3.0:
> Cross-Process File Locking: For filesystem operations, advisory file locks prevent concurrent modification

---

## Compound + simple ID formats

All storage modules support **two ID formats**:

| Format | Pattern | Example | Use Case |
|--------|---------|---------|----------|
| Compound | `{prefix}-{session}-{seq}` | `H-RS20251230-001` | Cross-session uniqueness; fast lookups |
| Simple | `{prefix}{n}` | `H1`, `T2` | Artifact-merge generation; quick references |

The compound format **embeds the session ID** in the ID itself. Per `/dp/brenner_bot/CHANGELOG.md` v0.3.0:
> Optimized ID lookups with normalized patterns supporting dots and simple H1/T1 formats

### Why both formats?

- **Compound** enables **fast lookups**: parse the session ID from the H-NNN, load only that session's file
- **Simple** is **artifact-friendly**: human-readable in artifact tables; less verbose

The parser supports both:

```typescript
function parseId(id: string): { sessionId?: string; seq: number } {
  // Compound: H-RS20251230-001
  const compound = id.match(/^[A-Z]+-(.+)-(\d+)$/);
  if (compound) {
    return { sessionId: compound[1], seq: parseInt(compound[2]) };
  }
  // Simple: H1, T2
  const simple = id.match(/^[A-Z]+(\d+)$/);
  if (simple) {
    return { seq: parseInt(simple[1]) };
  }
  throw new Error(`Invalid ID format: ${id}`);
}
```

Lookups try compound first (fast path); fall back to simple (slow path = scan all sessions).

---

## Optimized deletion (fast vs slow path)

```typescript
async deleteHypothesis(id: string): Promise<boolean> {
  // FAST PATH: extract session from compound ID
  const match = id.match(/^H-(.+)-\d+$/);
  if (match) {
    const sessionId = match[1];
    // Load ONLY the relevant session file (O(1) file lookup)
    const hypotheses = await this.loadSessionHypotheses(sessionId);
    // Filter out the deleted H; save
    return await this.saveSessionHypotheses(sessionId, hypotheses.filter(h => h.id !== id));
  }

  // SLOW PATH: scan all sessions (O(N))
  const hypothesis = await this.getHypothesisById(id);
  if (hypothesis) {
    return await this.deleteHypothesis(`H-${hypothesis.session_id}-${hypothesis.seq}`);  // re-call with compound
  }
  return false;
}
```

The fast path is **O(1)** — direct file access. The slow path is **O(N)** — scan all sessions. Compound IDs ensure most operations hit the fast path.

Per AGENTS.md no-deletion: brennerbot defers to user permission for deletion. The optimized deletion is for *the operations the user authorizes* — making them faster.

---

## At-scale storage patterns

For 500+ session histories (10/week × year):

| Optimization | Without (full rebuild) | With (incremental + compound) |
|--------------|------------------------|--------------------------------|
| Index update | re-scan 500 session files (O(S × K) ≈ 10000+ entry-reads) | single-index read+filter+write (O(N) ≈ 10000 entries; one file) |
| ID lookup (compound) | scan all 500 session files | direct file lookup by session ID parsed from compound ID |
| ID lookup (simple) | scan all 500 session files | scan all files (slow path; same cost) |
| Concurrent writes | corruption risk | safe (file locks) |
| Index recovery | manual | automatic (fallback rebuild) |

The dominant practical win is **eliminating the per-session-file scan**: file-system overhead drops from O(S) file-opens to O(1).

Per BRENNERBOT-AT-SCALE.md: at-scale operators use compound IDs by default; simple IDs for in-artifact references only.

### Performance characteristics

Per `/dp/brenner_bot/README.md § Performance Characteristics`:

- CLI startup: <50ms (Bun compiled binary)
- Test suite: 4500+ tests in <30 seconds (parallel execution; in-memory test servers)
- Artifact compilation: <50ms (parse + merge + lint + render)

These targets are maintained by the storage optimizations described here.

---

## Storage layer schema

Per `/dp/brenner_bot/README.md § Storage & Schema Architecture`:

```
artifacts/
├── <thread_id>/
│   ├── artifact.md              # the compiled artifact
│   ├── evidence.json            # evidence pack
│   ├── evidence.md              # evidence pack rendering
│   ├── interventions.jsonl      # operator intervention log
│   └── experiments/
│       └── <test_id>/
│           └── <timestamp>_<uuid>.json    # ExperimentResult records

.beads/
├── issues.jsonl                 # exported bead records (append-only)
├── interventions.jsonl          # cross-session intervention index
└── lock-*.json                  # file locks

session-records/
├── REC-<thread_id>-<timestamp>.json   # SessionRecord per session

metrics/
├── failure-mode-analytics-quarterly.json
├── pattern-detections.jsonl
└── operator-calibration-<operator-id>.md
```

The hierarchy is:
- **Per-session** content under `artifacts/<thread_id>/`
- **Cross-session** indexes under `.beads/`
- **Long-term** records under `session-records/`
- **Aggregates** under `metrics/`

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Use simple IDs as primary keys | Slow path on every lookup |
| Skip file locking for "quick" writes | Race condition under concurrent CLI + web access |
| Rebuild full index per save | O(N) when O(1) is achievable |
| Hardcode session ID in compound parsing | Use the canonical regex per ID format |
| Skip TTL on file locks | Crashed process holds lock forever; deadlock |
| Manually edit JSONL files | Per AGENTS.md no-script-based-changes; preserve structure |
| Mix compound + simple IDs in cross-session index | Inconsistency makes lookups unpredictable |
| Use single global lock for all storage | Contention; serializes all writes |

---

## Composition with brennerbot

Storage performance integrates with:

- **TAXONOMIES-COMPLETE-CATALOG.md**: ID prefix taxonomy
- **BEADS-SCHEMA.md**: bead schema
- **SESSION-REPLAY-AND-REPRODUCIBILITY.md**: SessionRecord storage
- **OPERATOR-INTERVENTION-RECORDING.md**: interventions.jsonl
- **EVIDENCE-PACK-PROTOCOL.md**: evidence.json + evidence.md
- **EXPERIMENT-CAPTURE-AND-RESULT-ENCODING.md**: experiments/<test_id>/
- **BRENNERBOT-AT-SCALE.md**: at-scale operational patterns
- **DESIGN-PRINCIPLES-CLI-FIRST.md**: deterministic merging requires storage discipline

---

## Cross-references

- [BEADS-SCHEMA.md](BEADS-SCHEMA.md) — bead-level schema
- [TAXONOMIES-COMPLETE-CATALOG.md](TAXONOMIES-COMPLETE-CATALOG.md) — ID prefixes
- [SESSION-REPLAY-AND-REPRODUCIBILITY.md](SESSION-REPLAY-AND-REPRODUCIBILITY.md) — SessionRecord storage
- [OPERATOR-INTERVENTION-RECORDING.md](OPERATOR-INTERVENTION-RECORDING.md) — interventions.jsonl
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — at-scale patterns
- [DESIGN-PRINCIPLES-CLI-FIRST.md](DESIGN-PRINCIPLES-CLI-FIRST.md) — deterministic merging
- /dp/brenner_bot/README.md § Storage & Schema Architecture — storage layout
- /dp/brenner_bot/README.md § Performance Characteristics — performance targets
- /dp/brenner_bot/README.md § Storage Performance Optimizations — implementation
- /dp/brenner_bot/CHANGELOG.md v0.3.0 — performance milestone
