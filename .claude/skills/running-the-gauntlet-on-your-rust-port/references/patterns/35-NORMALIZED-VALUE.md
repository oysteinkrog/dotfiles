# Pattern 35 — NORMALIZED VALUE (render-to-canonical-string comparator)

## What

A pure function, `normalize_value(value: &str) -> String`, that produces a bytewise-canonical rendering of any single value — NULL, integer, float (NaN/Inf normalized), text, blob — so that two engines that semantically agree produce byte-identical strings, and two engines that semantically disagree produce different strings. The atomic building block of the [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md) row labeled "string render of rows". Operationalizes [K-7](../methodology/KERNEL.md#k-7).

## Why

> "Two engines 'agreeing' requires a comparator whose output is bytewise identical for semantically equal inputs." — [methodology/KERNEL.md § K-7](../methodology/KERNEL.md#k-7)

A test that compares `Display::display(value)` against `Debug::display(value)` fails for `f64::NAN` (both print `NaN` differently across libc), for sub-normal floats (Rust prints `1.0e-300`, Python prints `1e-300`), for negative zero (`-0.0` vs `0.0`), for empty vs NULL string. The canonical rendering forces every difference to be either truly semantic or truly the comparator's fault — no third bucket of "ambient formatting differences".

## Where in FrankenSQLite

- `crates/fsqlite-e2e/src/oracle.rs` lines 284–310 — the `normalize_value` function (MINING-2 §1)
- `crates/fsqlite-e2e/tests/null_semantics_oracle_e2e.rs` — the 30-line `scenario()` template that consumes it

## Verbatim shape — `normalize_value`

From MINING-2 §1 (`oracle.rs` 284–310), verbatim:

```rust
pub fn normalize_value(value: &str) -> String {
    let trimmed = value.trim();
    if let Ok(f) = trimmed.parse::<f64>() {
        if f.is_nan() { return "NaN".to_string(); }
        if f.is_infinite() {
            return if f.is_sign_positive() { "Inf".to_string() } else { "-Inf".to_string() };
        }
        return format!("{f:.15}");
    }
    if trimmed.is_empty() || trimmed.eq_ignore_ascii_case("null") {
        return "NULL".to_string();
    }
    trimmed.to_string()
}
```

### Rendering conventions (verbatim from MINING-2 §1)

> "String rendering uniform: `Vec<Vec<String>>` with NULL capitalized, integers base-10, floats via `Display`, text in single quotes, blob as `X'<hex>'`."

| Value kind | Canonical rendering |
|---|---|
| NULL | `NULL` (uppercase, exact) |
| Integer | base-10, no thousands separators, leading `-` if negative |
| Float (finite) | `format!("{f:.15}")` — 15 fractional digits, fixed-point notation |
| Float NaN | `NaN` (mixed case, exact) |
| Float +Inf | `Inf` |
| Float -Inf | `-Inf` |
| Float -0.0 | `-0.000000000000000` (sign preserved via `{f:.15}`) |
| Text | single-quoted; embedded single-quotes doubled (`'O''Brien'`) |
| Blob | `X'<hex>'` (uppercase X, lowercase hex; example: `X'deadbeef'`) |
| Empty string | `''` (distinct from NULL!) |
| Trimmed whitespace | trimmed BEFORE comparison; embedded whitespace preserved |

### The 30-line `scenario()` template that consumes it

```rust
let mut mismatches = Vec::new();
for q in queries {
    match (frank_rows(&f, q), sqlite_rows(&r, q)) {
        (Ok(a), Ok(b)) if a == b   => { /* PASS */ },
        (Ok(a), Ok(b))             => mismatches.push(format!("MISMATCH: {q}\n  frank: {a:?}\n  csql:  {b:?}")),
        (Err(e), Ok(b))            => mismatches.push(format!("FRANK_ERR: {q}\n  frank: ERROR({e})\n  csql:  {b:?}")),
        (Ok(a), Err(e))            => mismatches.push(format!("CSQL_ERR: {q}\n  frank: {a:?}\n  csql: ERROR({e})")),
        (Err(_), Err(_))           => { /* both ERROR — agreement (K-8) */ },
    }
}
```

Where `frank_rows` and `sqlite_rows` return `Vec<Vec<String>>` with each cell already `normalize_value`'d.

## Per-class instantiation

### SQL: `normalize_value` (above) — `Vec<Vec<String>>` per row

### RESP: `render_resp_value()` over 14 RESP3 types

```rust
pub enum RespValue {
    SimpleString(String),
    Error { kind: String, message: String },
    Integer(i64),
    BulkString(Option<Vec<u8>>),  // None = NULL bulk
    Array(Option<Vec<RespValue>>), // None = NULL array
    // RESP3:
    Null,
    Boolean(bool),
    Double(f64),
    BigNumber(String),
    BulkError { kind: String, message: String },
    VerbatimString { encoding: [u8;3], text: String },
    Map(BTreeMap<RespValue, RespValue>),  // BTreeMap → canonical key order
    Set(BTreeSet<RespValue>),             // BTreeSet → canonical element order
    Attribute { attrs: BTreeMap<RespValue, RespValue>, value: Box<RespValue> },
    Push(Vec<RespValue>),
}

pub fn render_resp_value(v: &RespValue) -> String {
    match v {
        RespValue::Null => "NULL".to_string(),
        RespValue::Boolean(true) => "true".to_string(),
        RespValue::Boolean(false) => "false".to_string(),
        RespValue::Integer(n) => n.to_string(),
        RespValue::Double(f) if f.is_nan() => "NaN".to_string(),
        RespValue::Double(f) => format!("{f:.15}"),
        RespValue::SimpleString(s) | RespValue::VerbatimString { text: s, .. } => format!("'{}'", s.replace('\'', "''")),
        RespValue::BulkString(Some(b)) => format!("X'{}'", hex::encode(b)),
        RespValue::BulkString(None) => "NULL".to_string(),
        RespValue::Array(Some(a)) => format!("[{}]", a.iter().map(render_resp_value).collect::<Vec<_>>().join(",")),
        RespValue::Array(None) => "NULL".to_string(),
        RespValue::Map(m) => format!("{{{}}}", m.iter().map(|(k,v)| format!("{}:{}", render_resp_value(k), render_resp_value(v))).collect::<Vec<_>>().join(",")),
        RespValue::Set(s) => format!("#{{{}}}", s.iter().map(render_resp_value).collect::<Vec<_>>().join(",")),
        RespValue::Error { kind, message } | RespValue::BulkError { kind, message } => format!("ERR({kind}): {message}"),
        RespValue::BigNumber(s) => s.clone(),
        RespValue::Attribute { value, .. } => render_resp_value(value),  // attrs are out-of-band
        RespValue::Push(items) => format!(">{}", items.iter().map(render_resp_value).collect::<Vec<_>>().join(",")),
    }
}
```

### Numerical / ML: `render_tensor_spec()` over `(shape, dtype, device, requires_grad, data_hash)`

```rust
pub struct TensorSpec {
    pub shape: Vec<usize>,
    pub dtype: String,            // "float32", "int64", "bool", etc.
    pub device: String,           // "cpu", "cuda:0"
    pub requires_grad: bool,
    pub data_hash: String,        // BLAKE3 of bytes, *after* ULP-tolerant canonicalization
}

pub fn render_tensor_spec(t: &TensorSpec) -> String {
    format!(
        "tensor(shape={:?}, dtype={}, device={}, requires_grad={}, data_hash={})",
        t.shape, t.dtype, t.device, t.requires_grad, t.data_hash
    )
}
```

For per-op ULP tolerance, `data_hash` is computed *after* the values are bucketed to ULP-bins (e.g., `(x - min) / ulp_step` rounded to integer, then BLAKE3'd). Bucket size is per-op (4 ULP f32 matmul, 2 ULP elementwise default).

### HTTP: `render_http_response()` over `(status, headers, body)`

```rust
pub fn render_http_response(r: &HttpResponse) -> String {
    let mut s = format!("HTTP/1.1 {}\r\n", r.status);
    let mut hdrs: Vec<(String,String)> = r.headers.iter().map(|(k,v)| (k.to_ascii_lowercase(), v.clone())).collect();
    hdrs.sort();
    for (k,v) in &hdrs { s.push_str(&format!("{k}: {v}\r\n")); }
    s.push_str("\r\n");
    let body = match r.content_type.as_str() {
        "application/json" => canonical_json(&r.body),
        _ => format!("X'{}'", hex::encode(&r.body)),
    };
    s.push_str(&body);
    s
}
```

## Composition

- [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md) — the Comparator row of every gate uses this function.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — `CanonicalizationRules.float_tolerance` parameterizes the float branch.
- [pattern:40-METAMORPHIC-TRANSFORMS](40-METAMORPHIC-TRANSFORMS.md) — `MismatchClassification::FloatingPointDifference { max_epsilon_str }` carries the ULP that bypasses strict equality.
- [pattern:50-THREE-TIER-EQUIVALENCE](50-THREE-TIER-EQUIVALENCE.md) — Tier 2 canonical is the tier defined *by* this function; Tier 1 byte is stricter, Tier 3 logical is looser.

## Pitfalls

- **Using `f64::to_string()` instead of `format!("{f:.15}")`.** The default `to_string` is round-trippable but not fixed-width; `1.0_f64.to_string()` is `"1"`, but `format!("{:.15}", 1.0_f64)` is `"1.000000000000000"`. Mixing them across engines produces false mismatches.
- **Trimming embedded whitespace.** `value.trim()` is only for the outer rendering; if the SQL value is `"  hello  "`, the canonical form is `'  hello  '` with single quotes preserving the spaces. The trim is for the *outer* string before parsing as numeric.
- **NULL vs empty string conflated.** `''` and `NULL` are different values in SQL. The function correctly distinguishes them (`trimmed.is_empty()` is NULL only after the "null" case-insensitive check; an actually-empty literal is rendered as `''` upstream).
- **Locale-sensitive float formatting.** `{:.15}` uses POSIX `.`; if the harness ever runs under `LC_NUMERIC=de_DE.UTF-8`, comma-decimals leak in. Force `LC_ALL=C` in test runners.
- **`NaN` printed by libc vs Rust.** Some libc prints `nan` (lowercase), Rust prints `NaN`. The canonical form is `NaN` (per the function above); a comparator that takes the libc string verbatim fails.
- **Blob hex case.** `X'DEADBEEF'` vs `X'deadbeef'`. The canonical form is lowercase hex with uppercase `X` prefix. Pick one and stick.
- **Tensor data_hash computed pre-ULP-bucketing.** If two engines produce `1.000001` vs `1.000002` and the per-op ULP tolerance is `2e-7`, they should agree. If the hash is computed on raw bytes, they disagree. Bucket FIRST, hash SECOND.
- **RESP Map rendered with insertion order instead of sorted-by-key.** RESP3 Maps have no canonical order in the protocol; the comparator must sort by key (`BTreeMap` in the type system enforces this).
- **HTTP header order preserved.** HTTP/1.1 headers are case-insensitive AND order-agnostic per RFC. Render with case-folded keys and sorted order.
