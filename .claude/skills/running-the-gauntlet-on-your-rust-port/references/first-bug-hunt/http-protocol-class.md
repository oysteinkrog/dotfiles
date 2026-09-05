# First-Bug-Hunt Recipe: HTTP-Protocol-Class

These 10 bug classes surface in the first day on HTTP-Protocol-class ports (fastapi_rust, fastmcp_rust).

**Prerequisites:** subprocess reference (Python FastAPI/FastMCP); deterministic clock (`TZ=UTC`, mock clock); seeded RNG; HTTP transcript fixture corpus; OpenAPI golden files (for fastapi); MCP transcript fixtures (for fastmcp); normalized HTTP response `(status_code, normalized_headers, normalized_body)`.

Per item: **symptom** → **paste-ready repro** → **MismatchClassification expected** → **severity** → **fix pattern**.

---

## 1. Multipart upload edge cases

**Symptom.** `Content-Type: multipart/form-data; boundary=xyz` with adversarial boundary in body bytes — subject's parser may incorrectly split or fail; oracle handles per RFC 7578.

**Repro:**
```bash
./scripts/http-replay.sh \
  --request fixtures/multipart-adversarial-boundary.http \
  --reference http://localhost:18000 \
  --subject http://localhost:18001
```

Fixture (paste-ready):
```http
POST /upload HTTP/1.1
Host: localhost
Content-Type: multipart/form-data; boundary=xyz
Content-Length: 142

--xyz
Content-Disposition: form-data; name="file"; filename="test"

--xyz fake boundary in body--
--xyz--

```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **critical** — security (form-data injection).
**Fix pattern:** [pattern:30-DIFFERENTIAL-V2-ENVELOPE](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) with per-RFC-7578 corpus including: empty parts, missing closing boundary, body-contains-boundary, `filename*` (RFC 5987) encoding, nested multipart.

---

## 2. JSON body content-type negotiation

**Symptom.** Client sends `Content-Type: application/vnd.api+json` (JSON:API spec); subject expects `application/json` exactly and rejects; oracle accepts the `+json` suffix per RFC 6838.

**Repro:**
```bash
./scripts/http-replay.sh --request fixtures/vnd-api-json.http
```

Fixture:
```http
POST /api/v1/posts HTTP/1.1
Host: localhost
Content-Type: application/vnd.api+json
Content-Length: 24

{"data":{"type":"post"}}
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **medium** — non-canonical clients break.
**Fix pattern:** content-type parser accepts `*+json`, `*+xml`, `*+yaml` suffixes per RFC 6838.

---

## 3. Cookie SameSite handling

**Symptom.** `Set-Cookie: foo=bar; SameSite=None; Secure` over HTTP (not HTTPS) — browser silently drops; framework must mirror this. Subject may set the cookie anyway.

**Repro:**
```bash
./scripts/http-replay.sh --request fixtures/samesite-none-over-http.http
# inspect response Set-Cookie header
```

Fixture:
```http
GET /set-cookie HTTP/1.1
Host: localhost
Connection: keep-alive
```

Expected (over plain HTTP) response should NOT contain `Set-Cookie: foo=bar; SameSite=None; Secure` (browser-spec).

**MismatchClassification:** `TrueDivergence`.
**Severity:** **medium-high** — auth flows break in cross-site scenarios.
**Fix pattern:** explicit Cookie test corpus per `SameSite ∈ {Strict, Lax, None}` × `Secure ∈ {true, false}` × `HTTPS ∈ {true, false}`.

---

## 4. Redirect after POST

**Symptom.** `POST /resource` returns `302 Found` with `Location: /other`. Per HTTP/1.1 RFC, client should follow with GET (303 See Other) but historically many follow with POST (307 Temporary Redirect). Subject's response status differs from oracle.

**Repro:**
```bash
./scripts/http-replay.sh --request fixtures/post-redirect-302.http
./scripts/http-replay.sh --request fixtures/post-redirect-303.http
./scripts/http-replay.sh --request fixtures/post-redirect-307.http
```

**MismatchClassification:** `TrueDivergence { description: "redirect status differs" }`.
**Severity:** **high** — client-server contract.
**Fix pattern:** explicit per-redirect-status corpus; document framework default in contract.

---

## 5. Cancellation mid-stream cleanup

**Symptom.** Client cancels mid-response-stream (closes connection); subject's handler doesn't release resources (DB cursor, file handle).

**Repro:**
```bash
./scripts/http-cancel-oracle.sh \
  --endpoint /stream-data \
  --cancel-after-ms 100 \
  --inspect-resources db-cursor,file-handle
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **critical** — resource leak under load.
**Fix pattern:** 5 request-lifecycle crash boundaries + cancellation: `MidCancellation` boundary with per-handler resource-cleanup assertion.

---

## 6. OpenAPI schema sensitivity to optional fields

**Symptom.** Pydantic `Optional[str] = None` generates `{"type": "string", "nullable": true}` in OpenAPI 3.0; `{"anyOf": [{"type": "string"}, {"type": "null"}]}` in OpenAPI 3.1. Subject may generate one when contract requires the other.

**Repro:**
```bash
./scripts/openapi-schema-diff.sh <target> <workspace> \
  --reference-schema <workspace>/fixtures/reference_openapi.json \
  --endpoint "/components/schemas/User/properties/email"
```

**MismatchClassification:** `TrueDivergence { description: "openapi schema drift" }`.
**Severity:** **medium-high** — clients generated from OpenAPI break.
**Fix pattern:** OpenAPI version pinned in contract (`openapi-3.1` or `3.0`); per-schema golden; CI-gated diff.

---

## 7. Validation error message format drift

**Symptom.** Pydantic v2 error shape: `[{"type": "missing", "loc": ("body", "x"), "msg": "Field required", "input": {...}, "url": "..."}]`. Pydantic v2.5+ added `url`; v2.4 did not. Subject pinned to v2.4 shape; reference at v2.5.

**Repro:**
```bash
./scripts/http-replay.sh --request fixtures/missing-required-field.http
# inspect 422 response body
```

Fixture:
```http
POST /create HTTP/1.1
Host: localhost
Content-Type: application/json
Content-Length: 2

{}
```

**MismatchClassification:** `TrueDivergence { description: "validation error shape" }`.
**Severity:** **medium** — clients parsing error shape break.
**Fix pattern:** validation-error JSON golden per Pydantic version; CI-gated diff.

---

## 8. Dependency-injection scope leakage between requests

**Symptom.** `Depends(get_db)` should return a NEW connection per request (request-scoped). Subject's DI may cache and return the same connection across two concurrent requests; transaction state leaks.

**Repro:**
```bash
./scripts/http-concurrent-oracle.sh \
  --endpoint /transaction-test \
  --requests 100 \
  --concurrency 10 \
  --assert-isolation
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **critical** — transaction isolation broken.
**Fix pattern:** DI scope explicit in contract (`request | session | application`); per-scope test corpus.

---

## 9. MCP `#[tool]` macro omits null-vs-absent distinction (fastmcp only)

**Symptom.** Tool with `Optional[str] = None` parameter generates schema:
```json
{"type": "object", "properties": {"x": {"type": "string"}}, "required": []}
```
But should generate (per MCP spec):
```json
{"type": "object", "properties": {"x": {"type": ["string", "null"]}}, "required": []}
```
Client validates input `{"x": null}` against subject's schema → rejected. Against reference → accepted.

**Repro:**
```bash
./scripts/mcp-tool-schema-oracle.sh \
  --tool fixtures/tools/optional_string_tool.rs \
  --inspect-schema
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **high** — clients break.
**Fix pattern:** `#[tool]` macro generates explicit `["T", "null"]` for `Option<T>`; macro expansion oracle snapshot.

---

## 10. MCP cancellation budget mid-tool

**Symptom.** Long-running tool invocation; client sends `notifications/cancelled`. Subject's `cancellation_budget_ms` not honored — tool runs to completion; oracle aborts within budget.

**Repro:**
```bash
./scripts/mcp-cancel-oracle.sh \
  --tool fixtures/tools/slow_tool.rs \
  --cancel-after-ms 100 \
  --budget-ms 500 \
  --max-overrun-ms 50
```

**MismatchClassification:** `TrueDivergence { description: "cancellation budget violated" }`.
**Severity:** **high** — production reliability.
**Fix pattern:** explicit cancellation budget enforcement per-tool; `cancellation_check_time_ns` counter; per-tool budget golden.

---

## Empirical first-day stats

- **3–5 of 10 in first hour** (multipart, content-type negotiation, cookie SameSite, redirect-after-POST, validation error shape)
- **6–8 in first day** (cancellation cleanup, OpenAPI diff, DI scope)
- **All 10 by round 3** (MCP-specific items deepest; require macro snapshot + cancellation budget infrastructure)

Items 5 (cancellation cleanup) and 10 (MCP cancellation budget) are the deepest — they require concurrent workloads + explicit resource-tracking infrastructure.

---

## Cross-references

- [PROJECT-CLASSES.md § HTTP-Protocol-Class](../taxonomy/PROJECT-CLASSES.md)
- [case-studies/fastapi_rust.md](../case-studies/fastapi_rust.md)
- [case-studies/fastmcp_rust.md](../case-studies/fastmcp_rust.md)
- [patterns/30-DIFFERENTIAL-V2-ENVELOPE.md](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md)
