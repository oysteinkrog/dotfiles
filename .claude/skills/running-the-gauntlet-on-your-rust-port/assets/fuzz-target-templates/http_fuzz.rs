//! http_fuzz.rs — paste-ready HTTP-Protocol-class differential-fuzz target.
//!
//! Copy into `fuzz/fuzz_targets/fuzz_http_oracle.rs` after running
//!   `cargo +nightly fuzz init`
//!   `cargo +nightly fuzz add fuzz_http_oracle`
//!
//! fuzz/Cargo.toml dependencies:
//!   libfuzzer-sys = "0.4"
//!   arbitrary     = { version = "1", features = ["derive"] }
//!   serde_json    = "1"
//!   <your-port>   = { path = "../" }
//!
//! Reference framework: uvicorn-FastAPI running in a subprocess with a
//! deterministic clock and seeded RNG (per ORACLE-TOOLCHAIN §8).
//!
//! Pairs with: assets/integration-test-templates/http_oracle_e2e.rs.

#![no_main]

use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;

// ===== Structure-aware input — narrow to valid HttpRequest =====
//
// Bounded path components, bounded header count, bounded body size so the
// fuzzer doesn't OOM the in-process reference. The path vocabulary is small
// so route precedence + dispatch is actually exercised.

#[derive(Arbitrary, Debug, Clone)]
pub struct HttpRequest {
    pub method: Method,
    pub path: PathSpec,
    pub headers: Vec<HeaderPair>,
    pub body: Body,
}

#[derive(Arbitrary, Debug, Clone, Copy)]
pub enum Method { Get, Post, Put, Delete, Patch, Head, Options }

impl Method {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Get => "GET", Self::Post => "POST", Self::Put => "PUT",
            Self::Delete => "DELETE", Self::Patch => "PATCH",
            Self::Head => "HEAD", Self::Options => "OPTIONS",
        }
    }
}

#[derive(Arbitrary, Debug, Clone)]
pub struct PathSpec {
    /// Bounded path index — selects from a fixed pool registered on both
    /// sides at harness setup; ensures route-level coverage.
    pub route_idx: u8,
    pub query: Option<String>,
}

impl PathSpec {
    fn render(&self) -> String {
        const POOL: &[&str] = &[
            "/",
            "/health",
            "/items",
            "/items/123",
            "/users/me",
            "/admin/echo",
            "/v1/resource/abc",
            "/v1/resource/abc/nested",
        ];
        let base = POOL[(self.route_idx as usize) % POOL.len()];
        match &self.query {
            Some(q) => format!("{}?{}", base, sanitize_query(q)),
            None    => base.to_string(),
        }
    }
}

fn sanitize_query(q: &str) -> String {
    q.chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '=' || *c == '&' || *c == '_')
        .take(64)
        .collect()
}

#[derive(Arbitrary, Debug, Clone)]
pub struct HeaderPair {
    pub name: HeaderName,
    pub value: String,
}

#[derive(Arbitrary, Debug, Clone, Copy)]
pub enum HeaderName { ContentType, Accept, Authorization, UserAgent, XCustom, IfMatch }

impl HeaderName {
    fn as_str(&self) -> &'static str {
        match self {
            Self::ContentType => "Content-Type",
            Self::Accept => "Accept",
            Self::Authorization => "Authorization",
            Self::UserAgent => "User-Agent",
            Self::XCustom => "X-Custom-Header",
            Self::IfMatch => "If-Match",
        }
    }
}

#[derive(Arbitrary, Debug, Clone)]
pub enum Body { Empty, Json(String), Text(String), Bytes(Vec<u8>) }

impl Body {
    fn bytes(&self) -> Vec<u8> {
        match self {
            Self::Empty       => Vec::new(),
            Self::Json(s)     => s.as_bytes().iter().take(512).copied().collect(),
            Self::Text(s)     => s.as_bytes().iter().take(512).copied().collect(),
            Self::Bytes(b)    => b.iter().take(512).copied().collect(),
        }
    }
    fn content_type(&self) -> Option<&'static str> {
        match self {
            Self::Empty       => None,
            Self::Json(_)     => Some("application/json"),
            Self::Text(_)     => Some("text/plain"),
            Self::Bytes(_)    => Some("application/octet-stream"),
        }
    }
}

// ===== Differential driver =====
//
// Both reference (uvicorn-FastAPI) and port handle the same request; any
// normalized-response divergence (status + case-insensitive headers + MIME-
// aware body) is a bug.

fuzz_target!(|req: HttpRequest| {
    let path = req.path.render();
    let body = req.body.bytes();

    let mut headers: Vec<(String, String)> = req.headers.iter()
        .take(8)
        .map(|h| (h.name.as_str().to_string(), sanitize_header_value(&h.value)))
        .collect();
    if let Some(ct) = req.body.content_type() {
        // Only set if caller didn't.
        if !headers.iter().any(|(n, _)| n.eq_ignore_ascii_case("content-type")) {
            headers.push(("Content-Type".to_string(), ct.to_string()));
        }
    }

    let sub_resp  = call_subject(req.method.as_str(), &path, &headers, &body);
    let ref_resp  = call_reference(req.method.as_str(), &path, &headers, &body);

    // EngineIdentity (asserted at harness setup).

    // 1. Status — exact match.
    if sub_resp.status != ref_resp.status {
        panic!("DIFFERENTIAL DIVERGENCE: status sub={} ref={}", sub_resp.status, ref_resp.status);
    }

    // 2. Headers — case-insensitive name, value-exact, ignoring server-emitted
    //    transient headers (Date, Server, ETag-on-content) — those are not
    //    behavior-defining.
    let sub_norm = normalize_headers(&sub_resp.headers);
    let ref_norm = normalize_headers(&ref_resp.headers);
    if sub_norm != ref_norm {
        panic!("DIFFERENTIAL DIVERGENCE: headers\n  subject: {sub_norm:?}\n  reference: {ref_norm:?}");
    }

    // 3. Body — MIME-aware. JSON gets re-parsed for canonical key ordering;
    //    text gets string-compared; bytes get byte-compared.
    let ct = sub_resp.headers.iter()
        .find(|(k, _)| k.eq_ignore_ascii_case("content-type"))
        .map(|(_, v)| v.to_lowercase())
        .unwrap_or_default();
    if ct.starts_with("application/json") {
        let sub_v: serde_json::Value = serde_json::from_slice(&sub_resp.body).unwrap_or(serde_json::Value::Null);
        let ref_v: serde_json::Value = serde_json::from_slice(&ref_resp.body).unwrap_or(serde_json::Value::Null);
        if sub_v != ref_v {
            panic!("DIFFERENTIAL DIVERGENCE: JSON body\n  subject: {sub_v}\n  reference: {ref_v}");
        }
    } else if sub_resp.body != ref_resp.body {
        panic!(
            "DIFFERENTIAL DIVERGENCE: body bytes ({} vs {})",
            sub_resp.body.len(), ref_resp.body.len()
        );
    }
});

fn sanitize_header_value(v: &str) -> String {
    v.chars().filter(|c| !c.is_control()).take(128).collect()
}

#[derive(Debug)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

fn normalize_headers(h: &[(String, String)]) -> std::collections::BTreeMap<String, String> {
    const TRANSIENT: &[&str] = &["date", "server", "x-request-id", "x-trace-id"];
    h.iter()
        .filter(|(k, _)| !TRANSIENT.contains(&k.to_lowercase().as_str()))
        .map(|(k, v)| (k.to_lowercase(), v.clone()))
        .collect()
}

fn call_subject(_method: &str, _path: &str, _headers: &[(String, String)], _body: &[u8]) -> HttpResponse {
    // Stub. Replace with port's test client (e.g., `port::TestClient::new(app).request(...)`).
    HttpResponse { status: 200, headers: vec![("Content-Type".into(), "application/json".into())], body: b"{}".to_vec() }
}

fn call_reference(_method: &str, _path: &str, _headers: &[(String, String)], _body: &[u8]) -> HttpResponse {
    // Stub. Replace with uvicorn-FastAPI subprocess client driven over Unix socket.
    HttpResponse { status: 200, headers: vec![("Content-Type".into(), "application/json".into())], body: b"{}".to_vec() }
}
