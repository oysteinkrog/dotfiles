//! sql_oracle_e2e.rs — paste-ready 30-line scenario template for SQL-class
//! per-behavior-class oracle tests.
//!
//! Copy this file into `crates/<port>-e2e/tests/<behavior_class>_oracle_e2e.rs`
//! (e.g., `null_semantics_oracle_e2e.rs`, `group_by_oracle_e2e.rs`) and fill in
//! the per-behavior-class `STMTS` setup + `QUERIES` list. The `scenario()` body
//! is the verbatim 30-line template from references/patterns/05-SUBJECT-ORACLE-COMPARATOR.md.

use fsqlite as port;       // alias for your port crate
use rusqlite as reference; // pinned via libsqlite3-sys to the contract version

const SUBJECT_IDENTITY_LABEL: &str = "<port>";        // e.g. "frankensqlite"
const REFERENCE_IDENTITY_LABEL: &str = "csqlite-oracle";

/// The 30-line scenario template (verbatim from pattern:05-SUBJECT-ORACLE-COMPARATOR).
///
/// - Setup: panic if engines DISAGREE on success/error.
/// - Queries: collect MATCH / MISMATCH / FRANK_ERR / CSQL_ERR / BOTH_ERR.
/// - Both-error = agreement REGARDLESS of message.
/// - One-error-one-OK = hard failure.
fn scenario(stmts: &[&str], queries: &[&str], label: &str) {
    // Engine-identity guard (pattern:15-ENGINE-IDENTITY).
    assert_ne!(SUBJECT_IDENTITY_LABEL, REFERENCE_IDENTITY_LABEL,
        "EngineIdentity self-comparison violation");

    let f = port::Connection::open(":memory:").expect("open port");
    let r = reference::Connection::open_in_memory().expect("open reference");

    // 1. Setup statements: panic if engines DISAGREE on whether the statement succeeded.
    for s in stmts {
        let fe = port_execute(&f, s);
        let re = r.execute_batch(s);
        match (&fe, &re) {
            (Ok(_), Ok(())) | (Err(_), Err(_)) => {} // agreement
            (Ok(_), Err(e)) => panic!("{label}: port OK, reference ERROR({e}) on: {s}"),
            (Err(e), Ok(())) => panic!("{label}: port ERROR({e}), reference OK on: {s}"),
        }
    }

    // 2. Queries: classify each as MATCH / MISMATCH / FRANK_ERR / CSQL_ERR / BOTH_ERR.
    let mut mismatches = Vec::new();
    for q in queries {
        match (port_rows(&f, q), reference_rows(&r, q)) {
            (Ok(a), Ok(b)) if a == b => {}, // PASS
            (Ok(a), Ok(b)) => mismatches.push(format!("MISMATCH: {q}\n  port: {a:?}\n  ref:  {b:?}")),
            (Err(e), Ok(b)) => mismatches.push(format!("PORT_ERR: {q}\n  port: ERROR({e})\n  ref:  {b:?}")),
            (Ok(a), Err(e)) => mismatches.push(format!("REF_ERR: {q}\n  port: {a:?}\n  ref:  ERROR({e})")),
            (Err(_), Err(_)) => {} // both ERROR = agreement (pattern:K-8)
        }
    }

    assert!(mismatches.is_empty(), "{label}: {} mismatch(es)\n{}",
        mismatches.len(), mismatches.join("\n"));
}

// ===== Adapter helpers — port-specific shims =====

fn port_execute(c: &port::Connection, s: &str) -> Result<(), String> {
    c.execute_batch(s).map_err(|e| e.to_string())
}

fn port_rows(c: &port::Connection, q: &str) -> Result<Vec<Vec<String>>, String> {
    let mut stmt = c.prepare(q).map_err(|e| e.to_string())?;
    let col_count = stmt.column_count();
    let mut rows = Vec::new();
    let mut rows_iter = stmt.query([]).map_err(|e| e.to_string())?;
    while let Some(row) = rows_iter.next().map_err(|e| e.to_string())? {
        let r: Vec<String> = (0..col_count)
            .map(|i| normalize_value(&row.get_value(i).unwrap_or_default()))
            .collect();
        rows.push(r);
    }
    Ok(rows)
}

fn reference_rows(c: &reference::Connection, q: &str) -> Result<Vec<Vec<String>>, String> {
    // Same shape using rusqlite — render every cell to NormalizedValue's canonical string.
    let mut stmt = c.prepare(q).map_err(|e| e.to_string())?;
    let col_count = stmt.column_count();
    let rows = stmt
        .query_map([], |row| {
            let r: Vec<String> = (0..col_count)
                .map(|i| {
                    let v: reference::types::Value = row.get(i).unwrap_or(reference::types::Value::Null);
                    normalize_reference_value(&v)
                })
                .collect();
            Ok(r)
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

/// Normalize per pattern:35-NORMALIZED-VALUE.
fn normalize_value(s: &str) -> String {
    let t = s.trim();
    if let Ok(f) = t.parse::<f64>() {
        if f.is_nan() { return "NaN".into(); }
        if f.is_infinite() {
            return if f.is_sign_positive() { "Inf".into() } else { "-Inf".into() };
        }
        return format!("{f:.15}");
    }
    if t.is_empty() || t.eq_ignore_ascii_case("null") { return "NULL".into(); }
    t.into()
}

fn normalize_reference_value(v: &reference::types::Value) -> String {
    use reference::types::Value;
    match v {
        Value::Null => "NULL".into(),
        Value::Integer(i) => i.to_string(),
        Value::Real(f) => {
            if f.is_nan() { "NaN".into() }
            else if f.is_infinite() {
                if f.is_sign_positive() { "Inf".into() } else { "-Inf".into() }
            } else { format!("{f:.15}") }
        }
        Value::Text(s) => format!("'{s}'"),
        Value::Blob(b) => format!("X'{}'", hex::encode(b)),
    }
}

// ===== Per-behavior-class TESTS — fill these in =====

#[test]
fn null_semantics_basic() {
    scenario(
        &[
            "CREATE TABLE t(x INTEGER, y TEXT);",
            "INSERT INTO t VALUES (1, 'a'), (NULL, 'b'), (3, NULL);",
        ],
        &[
            "SELECT x FROM t WHERE x = NULL;",        // three-valued logic
            "SELECT x FROM t WHERE x IS NULL;",
            "SELECT COUNT(x), COUNT(*) FROM t;",      // NULL not counted
            "SELECT x + 1 FROM t ORDER BY rowid;",    // NULL propagation
            "SELECT y FROM t WHERE y NOT IN ('a');",  // NULL in NOT IN edge case
        ],
        "null_semantics_basic",
    );
}

// Add one test per behavior-class sub-area: GROUP BY, JOIN, RECURSIVE CTE, etc.
