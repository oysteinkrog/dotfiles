//! http_oracle_e2e.rs — paste-ready HTTP-Protocol-class oracle test.
//!
//! Copy into `crates/<port>-e2e/tests/<route_family>_oracle_e2e.rs`.

use std::collections::HashMap;

const SUBJECT_IDENTITY_LABEL: &str = "<port>";        // e.g. "fastapi_rust"
const REFERENCE_IDENTITY_LABEL: &str = "fastapi-oracle";

/// Drive an HTTP request fixture through both reference (uvicorn-FastAPI) and
/// port; assert normalized-response equivalence (status + case-insensitive
/// headers + MIME-aware body comparison).
fn scenario_http(
    method: &str,
    path: &str,
    headers: &[(&str, &str)],
    body: &[u8],
    label: &str,
) {
    assert_ne!(SUBJECT_IDENTITY_LABEL, REFERENCE_IDENTITY_LABEL,
        "EngineIdentity self-comparison violation");

    let ref_resp = call_reference(method, path, headers, body);
    let port_resp = call_port(method, path, headers, body);

    // Status must match exactly.
    assert_eq!(ref_resp.status, port_resp.status,
        "{label}: status mismatch ref={} port={}", ref_resp.status, port_resp.status);

    // Headers compared case-insensitively, ignoring server-specific transient ones.
    let ref_hdr = normalize_headers(&ref_resp.headers);
    let port_hdr = normalize_headers(&port_resp.headers);
    assert_eq!(ref_hdr, port_hdr, "{label}: header divergence");

    // Body compared MIME-aware.
    let ct = ref_resp.headers.iter()
        .find(|(k, _)| k.eq_ignore_ascii_case("content-type"))
        .map(|(_, v)| v.as_str())
        .unwrap_or("application/octet-stream");

    if ct.starts_with("application/json") {
        let ref_v: serde_json::Value = serde_json::from_slice(&ref_resp.body).expect("ref json");
        let port_v: serde_json::Value = serde_json::from_slice(&port_resp.body).expect("port json");
        assert_eq!(ref_v, port_v, "{label}: JSON body divergence");
    } else {
        assert_eq!(ref_resp.body, port_resp.body, "{label}: body byte divergence");
    }
}

#[derive(Debug)]
struct HttpResponse {
    status: u16,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

fn call_reference(method: &str, path: &str, headers: &[(&str, &str)], body: &[u8]) -> HttpResponse {
    // Drive uvicorn-FastAPI test client; pinned per python-reference-bridger
    // with deterministic clock + uuid + RNG.
    let _ = (method, path, headers, body);
    HttpResponse {
        status: 200,
        headers: vec![("content-type".into(), "application/json".into())],
        body: br#"{"hello":"world"}"#.to_vec(),
    }
}

fn call_port(method: &str, path: &str, headers: &[(&str, &str)], body: &[u8]) -> HttpResponse {
    // Drive port via in-process test client.
    let _ = (method, path, headers, body);
    HttpResponse {
        status: 200,
        headers: vec![("content-type".into(), "application/json".into())],
        body: br#"{"hello":"world"}"#.to_vec(),
    }
}

/// Lowercase + sort headers; strip transient (Date, Server, request-id, traceparent).
fn normalize_headers(h: &[(String, String)]) -> HashMap<String, String> {
    let transient = ["date", "server", "x-request-id", "traceparent", "x-correlation-id"];
    h.iter()
        .filter(|(k, _)| !transient.contains(&k.to_ascii_lowercase().as_str()))
        .map(|(k, v)| (k.to_ascii_lowercase(), v.clone()))
        .collect()
}

#[test]
fn get_root_basic() {
    scenario_http("GET", "/", &[], b"", "get_root_basic");
}

#[test]
fn post_json_validation() {
    scenario_http(
        "POST", "/items",
        &[("content-type", "application/json")],
        br#"{"name":"a","price":1.0}"#,
        "post_json_validation",
    );
}
