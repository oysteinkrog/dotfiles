# HTTP-Protocol-class Adoption Checklist

For ports in the HTTP-Protocol class (fastapi_rust, fastmcp_rust).

## Phase 0 — Workspace
- [ ] `<workspace>/` git-init'd
- [ ] `docs/contracts/<ref>_version_contract.toml` pins (e.g., `fastapi=0.110.0`)
- [ ] `[reference.extras]`: `framework_version`, `middleware_stack_hash` (sha256 of canonical middleware ordering)

## Phase 3 — Oracle wiring
- [ ] Compliance fixture corpus + reference framework running in a test harness
- [ ] Deterministic clock (`freezegun.freeze_time(<T>)`)
- [ ] Deterministic UUID (`uuid.UUID(int=<I>)`)
- [ ] HTTP response normalized type: status + case-insensitive headers + body MIME-aware
- [ ] **OpenAPI schema diff as a `cargo test` invariant** (via `scripts/openapi-schema-diff.sh`)
- [ ] (FastMCP) **Cancel-correctness as a primary invariant** — cancelled requests don't leak resources, partial responses are clean
- [ ] EngineIdentity strict-distinct
- [ ] Oracle preflight: framework version + middleware stack hash + extractor registry + OpenAPI schema hash

## Phase 4 — Golden capture
- [ ] HTTP transcript fixtures per route
- [ ] Validation-error JSON corpus (every Pydantic validation error class for FastAPI)
- [ ] OpenAPI golden files (canonical-sorted-key + stripped of non-behavioral fields)
- [ ] Route macro compile-fail tests
- [ ] (FastMCP) MCP transcript fixtures + tool/resource schema snapshots

## Phase 5 — Performance
- [ ] HTTP request latency bench per route family
- [ ] Zero-copy parsing throughput axis
- [ ] JSON body size axis: 1KB, 100KB, 10MB
- [ ] Middleware stack depth axis
- [ ] Concurrent-request axis: 1, 10, 100, 1000 clients
- [ ] (FastMCP) Cancellation budget bench: cancel at 10ms, 100ms, 1s, mid-stream
- [ ] `release-perf` profile
- [ ] HotPath counters: `route_match_time_ns, handler_dispatch_time_ns, middleware_traversal_time_ns`

## Phase 6 — Conformance
- [ ] Oracle E2E per route + per extractor + per middleware + per validation-error class
- [ ] Differential V2 envelope with HTTP-response canonicalization
- [ ] Metamorphic transforms: route-permutation-equivalence (order of route registration doesn't matter), middleware-reorder-equivalence (where commutative), JSON-key-order-irrelevance
- [ ] RequestFaultMiddleware: connection drops mid-body, slow-loris client patterns, partial multipart uploads
- [ ] **5 request-lifecycle crash boundaries**: open / header / body-start / body-end / close + cancellation-mid-body
- [ ] Differential fuzz: `arbitrary` HttpRequest generator → both reference (Python uvicorn-FastAPI) and subject (Rust port)
- [ ] (FastMCP) Cancellation-correctness fuzz: random cancellation points; assert no resource leak
- [ ] E-processes: response-status-distribution-matches-reference, OpenAPI-schema-stable, request-cancellation-budget-respected
- [ ] Schema-diff regression test: every test run, regenerate OpenAPI and diff against committed golden

## Phase 7 — Surface
- [ ] FeatureUniverse covers every FastAPI feature: routing, extractors, validation, OpenAPI schema, middleware, DI scopes, dependency injection, response models, error handlers
- [ ] (FastMCP) FeatureUniverse covers: tools, resources, prompts, JSON-RPC method handlers, capability security, four-valued outcomes
- [ ] Per-extractor classification: `present | partial | missing | n/a | excluded`

## Phase 8 — Negative ledger
- [ ] AGENTS.md mandate with HTTP-class failure terms: `extractor fast paths, parser zero-copy changes, validation schema caching, DI lifetime changes, macro expansion changes, schema generation caching, budget enforcement, resource streaming, error mapping`

## HTTP-class extras
- [ ] **fastapi_rust**: OpenAPI schema diff as a `cargo test` invariant; Pydantic validation error compatibility
- [ ] **fastmcp_rust**: Cancellation-correctness primary invariant; JSON-RPC id sequence determinism; tool/resource schema snapshot stability
- [ ] Deterministic clock + RNG injection per request
- [ ] Middleware stack canonical-ordering hash committed
