# Case Study: FastMCP Rust — `/dp/fastmcp_rust`

The cancel-correctness-and-four-valued-outcome class. MCP transcript fixtures + tool/resource schema snapshots exist; the formal harness, ledger, and math layer are all absent.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | HTTP-Protocol-class with protocol-versioning + JSON-RPC overlays ([PROJECT-CLASSES.md § HTTP-Protocol-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T3 — Workspace** (compile-time-codegen overlay for `#[tool]` macros effectively bumps to T4 for those features) |
| **Recommended mode** | `gauntlet-full` (first proper application) |
| **Reference pinning** | `docs/contracts/fastmcp_version_contract.toml` likely at `fastmcp-0.X.Y` + MCP spec version (e.g., 2024-11-05); preflight verifies both |
| **README claims summary** | Rust FastMCP-equivalent with JSON-RPC tool/resource/prompt surface, four-valued outcomes, cancellation budgets, capability negotiation. Recent activity (commits `adc0c99`, `a409638`, `d5c3e01`) shows dependency bumps + version bump to 0.3.1 — public release in motion. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ❌ | no formal harness vs MCP spec + Python FastMCP |
| Negative ledger | ❌ | absent |
| cass | ✅ | wired |
| Agent Mail | ⚠️ partial | |
| bv | ⚠️ partial | |
| Math layer (§75–76) | ❌ | absent |
| MT-scale harness | ❌ | absent |
| RaptorQ | ❌ | not applicable |
| MCP transcript fixtures | ✅ | exists |
| Tool/resource schema snapshots | ✅ | exists |
| Outcome classification tests | ✅ | exists |
| Cancellation scenarios | ✅ | exists |
| Macro expansion oracle | ❌ | `#[tool]` macro output not snapshotted |
| Schema generation caching | ⚠️ | exists; not gauntlet-tested |
| Capability security tests | ⚠️ | partial |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Tool-invocation latency measured ad-hoc. No aggregate.

**First 3 gaps:**
1. **No p99 tool invocation latency primary score** with explicit threshold.
2. **`jsonrpc_parse_time_ns` / `tool_dispatch_time_ns` not exposed** — per-phase attribution missing.
3. **Schema generation cost** invisible — per-tool schema generation cached or recomputed unclear.

### (b) Conformance — current state + first 3 gaps

**Current state.** MCP transcript fixtures + tool/resource schema snapshots + outcome classification + cancellation scenarios all exist. Format probably ad-hoc.

**First 3 gaps:**
1. **`#[tool]` macro generated schema** — schema for tool inputs/outputs must match per-version baseline; macro expansion changes break clients silently.
2. **Cancellation correctness** — `notifications/cancelled` mid-tool-invocation must abort cleanly; budget enforcement may be partial.
3. **Four-valued outcomes** — Success/Error/Cancelled/Timeout — explicit coverage per tool may be partial; e.g., timeout-path may inherit error-path code.

### (c) Surface — current state + first 3 gaps

**First 3 gaps:**
1. **MCP capability negotiation** — `roots/list`, `resources/subscribe`, `tools/list_changed` — per-capability `present|partial|missing|excluded` not formal.
2. **Transport layers** — `stdio` vs `http+sse` vs `streamable-http` — per-transport conformance.
3. **MCP server-initiated requests** — server-to-client `sampling/createMessage`, `roots/list` — typically partial.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/fastmcp_rust /dp/fastmcp_rust__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: fastmcp-0.X.Y + MCP spec 2024-11-05
# - oracle mode: subprocess Python FastMCP reference
# - perf weights: ToolDispatch=0.30, ResourceRead=0.20, Schema=0.10,
#   Cancellation=0.15, Capability=0.10, Streaming=0.10, Auth=0.05
# - failure terms: macro expansion changed, schema generation cache miss,
#   budget enforcement weakened, resource streaming regressed, error mapping broke,
#   capability negotiation drift, cancellation race, transport-specific corner

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/fastmcp_rust /dp/fastmcp_rust__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 72
```

Wall time T3 × `gauntlet-full`: **14–21 days.**

---

## 5. Expected Pillar Findings

### Performance
1. **JSON-RPC parser allocates per request** — pooled buffer opportunity.
2. **Tool dispatch table O(N) lookup** — radix tree opportunity.
3. **Schema serialization per `tools/list` call** — `OnceLock` cache opportunity (pattern 9).
4. **Cancellation check polling overhead** — per-step check expensive.
5. **Resource streaming chunk size suboptimal** — too-small chunks → syscall overhead; too-large → cancellation latency.
6. **SSE event framing allocates per event** — zero-copy opportunity.

### Conformance
1. **`#[tool]` macro omits `Optional[T] = None` parameter's null-vs-absent distinction.**
2. **Cancellation mid-streaming-response leaves SSE stream open** — must close cleanly.
3. **Budget enforcement** — `cancellation_budget_ms` not honored on long-running tool.
4. **Tool input schema `additionalProperties: false`** vs `true` differs between port and reference.
5. **`tools/list_changed` notification** — sent on tool registration; ordering with `initialized` matters.
6. **Capability negotiation** — `roots/list` returns different roots between port and reference.
7. **Server-initiated `sampling/createMessage`** semantics.
8. **`resources/subscribe` notification dedup** — re-subscribe behavior.
9. **JSON-RPC batch handling** — atomic vs partial-success.
10. **Error code mapping** — `-32601 Method not found` vs `-32602 Invalid params` for missing required field.

### Surface
1. **MCP transport coverage** — stdio + http+sse + streamable-http.
2. **OAuth resource server (per MCP spec 2025-03)** — authorization integration.
3. **Logging API** — typically partial.

---

## 6. Patterns to Apply First

1. **Full FrankenSQLite floor adapted.**
2. **MCP transcript fixtures Tier 1/2/3** — per tool/resource/prompt.
3. **Four-valued outcome explicit per tool** — Success/Error/Cancelled/Timeout coverage matrix.
4. **Cancellation budget enforcement** — `cancellation_budget_ms` honored mid-stream + mid-tool.
5. **Macro expansion oracle** — `cargo expand` snapshot per `#[tool]` invocation; compare to per-version baseline.
6. **Schema generation caching** — cache key includes MCP spec version + macro hash + tool body hash.

---

## 7. Estimated Rounds to Convergence

**10–14 rounds.** Cancellation correctness + four-valued outcomes are deep wells of bugs; transport variants (stdio + http+sse + streamable-http) compound.

---

## 8. Risk Register

1. **MCP spec churn** — spec versions change semantics; pin to specific spec date. *Mitigation:* contract pins; `migration` mode for spec bumps.
2. **Macro expansion churn** — `#[tool]` macro output sensitive to dependency-version updates. *Mitigation:* `cargo expand` snapshot in CI.
3. **Cancellation race** — between client `notifications/cancelled` and server's natural completion. *Mitigation:* race-condition fuzzing.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- Universal floor
- `mcp_protocol_compliance.json` — per-method pass rate
- `tool_schema_snapshot.json` — per-tool schema vs baseline
- `cancellation_budget_proof.json` — per-tool budget enforcement
- `four_valued_outcome_coverage.json` — per-tool outcome matrix
- `transport_compliance.json` — per-transport conformance

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FastMCP Rust](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § HTTP-Protocol-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/http-protocol-class.md](../first-bug-hunt/http-protocol-class.md)
- [case-studies/fastapi_rust.md](fastapi_rust.md) — sibling HTTP-class
