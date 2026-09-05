# Case Study: FastAPI Rust — `/dp/fastapi_rust`

The OpenAPI-schema-drift-sensitive HTTP-Protocol-class. Compliance corpus exists (HTTP transcripts, validation-error JSON, OpenAPI golden files, route macro compile-fail tests) but no formal conformance harness, no ledger, no math layer.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | HTTP-Protocol-class ([PROJECT-CLASSES.md § HTTP-Protocol-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T3 — Workspace** |
| **Recommended mode** | `gauntlet-full` (first proper application) |
| **Reference pinning** | `docs/contracts/fastapi_version_contract.toml` likely at `fastapi-0.110.x` + `pydantic-2.x` + OpenAPI 3.1; preflight verifies all three versions match |
| **README claims summary** | Rust FastAPI-equivalent with Pydantic-v2-compatible validation + OpenAPI 3.1 schema generation. Recent activity (commits `bbbb388`, `53e1137`, `85fd035`) shows infra-level fixes (getrandom bump, macOS socket blocking-mode fix) — core HTTP correctness in active maintenance. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ❌ | no formal harness vs FastAPI/Pydantic/OpenAPI behavior |
| Negative ledger | ❌ | absent |
| cass | ✅ | wired |
| Agent Mail | ⚠️ partial | |
| bv | ⚠️ partial | |
| Math layer (§75–76) | ❌ | absent |
| MT-scale harness | ❌ | absent |
| RaptorQ | ❌ | not applicable |
| HTTP transcript Tier 1/2 | ⚠️ | transcripts exist; tier classification informal |
| OpenAPI schema diff | ⚠️ | golden files exist; diff not automated |
| Validation-error JSON | ⚠️ | golden files exist |
| Route macro compile-fail tests | ✅ | implemented |
| 5 request-lifecycle crash boundaries | ❌ | not enumerated |
| `RequestFaultMiddleware` | ❌ | absent |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Per-route benches exist informally. No aggregate. p99 latency not headlined.

**First 3 gaps:**
1. **No requests/sec p99 latency primary score** with explicit threshold across `JSON body sizes × middleware stacks × concurrency`.
2. **`route_match_time_ns` not exposed** — route matching cost is dominant for high-route-count apps.
3. **`middleware_traversal_time_ns` not exposed** — per-middleware-frame attribution missing.

### (b) Conformance — current state + first 3 gaps

**Current state.** Transcript fixtures exist; OpenAPI golden files exist; validation-error JSON exists.

**First 3 gaps:**
1. **OpenAPI schema diff not gated in CI** — schema can drift unnoticed; a `Field(...)` optionality change shows up in clients but not in port.
2. **Cookie SameSite handling** — `SameSite=Lax` vs `Strict` vs `None` plus `Secure` interaction subtle.
3. **Pydantic v2 validation-error message format** — error-message shape (loc, msg, type, input) must match exactly; recent Pydantic minors change shape.

### (c) Surface — current state + first 3 gaps

**Current state.** Per-endpoint enumeration informal.

**First 3 gaps:**
1. **Middleware ordering** — FastAPI executes middleware in registration order; port may differ.
2. **DI scope leakage** — `Depends()` scope (request vs session) — leakage between requests is a known class of bug.
3. **WebSocket surface** — typically partial/excluded.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/fastapi_rust /dp/fastapi_rust__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: fastapi-0.110.x + pydantic 2.x + OpenAPI 3.1
# - oracle mode: subprocess Python FastAPI server; deterministic TZ/clock/RNG
# - perf weights: Routing=0.20, Validation=0.15, SerDe=0.20, Middleware=0.10,
#   OpenAPI=0.10, DI=0.05, Streaming=0.10, ErrorMapping=0.10
# - failure terms: extractor fast path broke, parser zero-copy regressed,
#   validation cache invalidated wrong, DI lifetime changed, middleware order
#   observable, cookie samesite wrong, openapi schema drift, multipart boundary handling

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/fastapi_rust /dp/fastapi_rust__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 48
```

Wall time T3 × `gauntlet-full`: **10–21 days.**

---

## 5. Expected Pillar Findings

### Performance
1. **`route_match_time_ns` linear in route count** — radix tree opportunity.
2. **JSON serde double-allocation** — `serde_json::to_vec` then `Vec::into_bytes`.
3. **Middleware per-frame async-overhead** — `Pin<Box<dyn Future>>` cost.
4. **Validation regex compilation per request** — `OnceLock` opportunity (pattern 9).
5. **Multipart parser O(N²) on adversarial boundaries** — Boyer-Moore opportunity.
6. **Cookie parse allocates per cookie** — zero-copy parser opportunity.
7. **`Content-Length` body buffering** — streaming opportunity.
8. **WebSocket frame allocation per message** — pooled buffer opportunity.

### Conformance
1. **Multipart upload with `filename*` (RFC 5987)** encoding.
2. **JSON body `Content-Type: application/vnd.api+json`** negotiation.
3. **`SameSite=None; Secure` cookie** rejected on insecure connection (browser behavior; framework must mirror).
4. **Redirect after POST** — 303 See Other vs 307 Temporary Redirect.
5. **Cancellation mid-stream** — request body cleanup, response stream cleanup.
6. **OpenAPI schema sensitivity to `Optional[T] = None`** — `nullable: true` vs `default: null`.
7. **Validation error format drift** — Pydantic v2 minor bumps change message shape.
8. **DI scope leakage** — `Depends(get_db)` returning same DB connection across two concurrent requests.
9. **`request.body()` consumed twice** — body stream re-read.
10. **Trailer headers** (`Trailer: Content-MD5`) — typically excluded but counts as coverage debt.

### Surface
1. **Per-extractor enumeration** — `Body`, `Form`, `File`, `Cookie`, `Header`, `Query`, `Path` — completeness gaps.
2. **WebSocket support** — typically partial.
3. **HTTP/2 support** — typically partial.

---

## 6. Patterns to Apply First

1. **Full FrankenSQLite floor adapted for HTTP-Protocol-class.**
2. **HTTP transcript fixtures per route** — Tier 1 byte where deterministic, Tier 2 canonical for `Date`/`etag`, Tier 3 logical for streaming bodies.
3. **Validation-error JSON golden files** — Pydantic v2 shape pinned in contract.
4. **OpenAPI golden file diff** — generated OpenAPI schema must match per-version baseline; gate in CI.
5. **5 request-lifecycle crash boundaries** — `BeforeRequestParse`, `AfterHeaderParseBeforeBody`, `MidBodyRead`, `AfterBodyBeforeHandler`, `MidResponseWrite`, `MidCancellation` (+1).
6. **`RequestFaultMiddleware`** — connection drops mid-body, slow-loris, partial multipart.

---

## 7. Estimated Rounds to Convergence

**8–12 rounds.** HTTP protocol is well-specified; convergence is faster than numerical-class siblings.

---

## 8. Risk Register

1. **FastAPI minor-version churn** — error message shapes change. *Mitigation:* contract pins minor; `migration` mode for bumps.
2. **Async-runtime divergence** — Tokio vs async-std subtleties in cancellation semantics. *Mitigation:* pin Tokio version + `tokio-test` runtime in tests.
3. **macOS-specific socket behavior** (already seen, commit `85fd035`) — `accept()` returning non-blocking socket. *Mitigation:* per-platform compliance fixture corpus.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- Universal floor
- `openapi_schema_diff.json` — empty diff vs reference
- `http_transcript_compliance.json` — per-transcript Tier-1/2 result
- `cancellation_proof.json` — per-boundary cancellation observation
- `validation_error_shape.json` — per-error-class shape conformance

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FastAPI Rust](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § HTTP-Protocol-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/http-protocol-class.md](../first-bug-hunt/http-protocol-class.md)
