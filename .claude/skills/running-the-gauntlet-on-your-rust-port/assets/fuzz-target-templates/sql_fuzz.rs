//! sql_fuzz.rs — paste-ready SQL-class differential-fuzz target.
//!
//! Copy into `fuzz/fuzz_targets/fuzz_sql_oracle.rs` after running
//!   `cargo +nightly fuzz init`
//!   `cargo +nightly fuzz add fuzz_sql_oracle`
//!
//! fuzz/Cargo.toml dependencies:
//!   libfuzzer-sys = "0.4"
//!   arbitrary     = { version = "1", features = ["derive"] }
//!   rusqlite      = { version = "0.31", features = ["bundled"] }
//!   hex           = "0.4"
//!   <your-port>   = { path = "../" }
//!
//! Pairs with: the 30-line `scenario()` from
//! assets/integration-test-templates/sql_oracle_e2e.rs — every input drives
//! BOTH engines through the canonical comparator; any divergence is a bug.

#![no_main]

use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;

// ===== Structure-aware input — narrow to valid-by-construction SQL =====
//
// Per FUZZ-TOOLCHAIN.md §3.3: the art of structure-aware fuzz is making the
// input type as narrow as possible while still generating diverse inputs.
// We bound list lengths and pick from a small vocabulary so the fuzzer
// spends its energy on semantic edges, not syntactic noise.

#[derive(Arbitrary, Debug, Clone)]
pub struct DiffScript {
    /// CREATE TABLE / CREATE INDEX statements applied to both engines.
    pub setup: Vec<DDL>,
    /// SELECT / INSERT / UPDATE / DELETE queries run against both engines.
    pub queries: Vec<Stmt>,
}

#[derive(Arbitrary, Debug, Clone)]
pub enum DDL {
    CreateTable { name_idx: u8, col_count: u8 },
    CreateIndex { table_idx: u8, col_idx: u8 },
}

#[derive(Arbitrary, Debug, Clone)]
pub enum Stmt {
    Select { table_idx: u8, where_x: Option<i32> },
    Insert { table_idx: u8, row: Vec<Cell> },
    Update { table_idx: u8, col_idx: u8, new_val: Cell, where_x: Option<i32> },
    Delete { table_idx: u8, where_x: Option<i32> },
}

#[derive(Arbitrary, Debug, Clone)]
pub enum Cell {
    Null,
    Int(i32),
    Real(f64),
    Text(String),
}

// ===== Rendering — produce well-formed SQL =====
//
// Indices wrap into a small name pool so the same "table 0" stays the
// same statement across renderings.

fn table_name(i: u8) -> String { format!("t{}", i % 4) }
fn col_name(i: u8) -> String { format!("c{}", i % 4) }

fn render_cell(c: &Cell) -> String {
    match c {
        Cell::Null    => "NULL".into(),
        Cell::Int(i)  => i.to_string(),
        Cell::Real(f) if f.is_finite() => format!("{f}"),
        Cell::Real(_) => "0.0".into(), // skip NaN/Inf in literals; both engines reject
        Cell::Text(s) => format!("'{}'", s.replace('\'', "''").chars().take(16).collect::<String>()),
    }
}

fn render_ddl(d: &DDL) -> String {
    match d {
        DDL::CreateTable { name_idx, col_count } => {
            let cols: Vec<String> = (0..(col_count % 4).max(1))
                .map(|i| format!("{} INTEGER", col_name(i)))
                .collect();
            format!("CREATE TABLE IF NOT EXISTS {} ({});", table_name(*name_idx), cols.join(", "))
        }
        DDL::CreateIndex { table_idx, col_idx } => {
            format!("CREATE INDEX IF NOT EXISTS idx_{}_{} ON {}({});",
                table_idx % 4, col_idx % 4, table_name(*table_idx), col_name(*col_idx))
        }
    }
}

fn render_stmt(s: &Stmt) -> String {
    match s {
        Stmt::Select { table_idx, where_x } => match where_x {
            Some(v) => format!("SELECT * FROM {} WHERE c0 = {} ORDER BY c0;", table_name(*table_idx), v),
            None    => format!("SELECT * FROM {} ORDER BY c0;", table_name(*table_idx)),
        },
        Stmt::Insert { table_idx, row } => {
            let vals: Vec<String> = row.iter().take(4).map(render_cell).collect();
            if vals.is_empty() { return format!("INSERT INTO {} DEFAULT VALUES;", table_name(*table_idx)); }
            format!("INSERT INTO {} VALUES ({});", table_name(*table_idx), vals.join(", "))
        }
        Stmt::Update { table_idx, col_idx, new_val, where_x } => {
            let w = where_x.map(|v| format!(" WHERE c0 = {v}")).unwrap_or_default();
            format!("UPDATE {} SET {} = {}{};", table_name(*table_idx), col_name(*col_idx), render_cell(new_val), w)
        }
        Stmt::Delete { table_idx, where_x } => {
            let w = where_x.map(|v| format!(" WHERE c0 = {v}")).unwrap_or_default();
            format!("DELETE FROM {}{};", table_name(*table_idx), w)
        }
    }
}

// ===== Differential driver =====
//
// Verbatim shape from FUZZ-TOOLCHAIN §4 — both engines start from
// identical empty state; setup divergences are skipped (not interesting
// at this layer); query divergences PANIC so libfuzzer minimizes and
// saves the crash.

fuzz_target!(|script: DiffScript| {
    // Open both engines.
    // In real use replace these placeholders with the port's connection type.
    let subject = match rusqlite::Connection::open_in_memory() { Ok(c) => c, Err(_) => return };
    let reference = match rusqlite::Connection::open_in_memory() { Ok(c) => c, Err(_) => return };

    // EngineIdentity guard (pattern:15-ENGINE-IDENTITY): subject MUST NOT
    // be the reference. In a real port, this is a strict label compare
    // because both `Connection` types live in different crates.

    // 1. Setup: skip if engines DISAGREE (not interesting at this layer).
    for ddl in &script.setup {
        let s = render_ddl(ddl);
        let sub_ok = subject.execute_batch(&s).is_ok();
        let ref_ok = reference.execute_batch(&s).is_ok();
        if sub_ok != ref_ok { return; }
    }

    // 2. Queries: any divergence is a bug.
    for q in &script.queries {
        let s = render_stmt(q);
        let sub_result = collect_rows(&subject, &s);
        let ref_result = collect_rows(&reference, &s);
        match (sub_result, ref_result) {
            (Ok(a), Ok(b)) if a == b => continue,    // PASS
            (Err(_), Err(_))         => continue,    // both-error = agreement (K-8)
            (a, b) => {
                // PANIC: libfuzzer minimizes the input and saves the crash to
                // fuzz/artifacts/fuzz_sql_oracle/crash-<sha>.
                // Triage via the mismatch-minimizer in ORACLE-TOOLCHAIN §12.
                panic!(
                    "DIFFERENTIAL DIVERGENCE\n  sql: {s}\n  subject: {a:?}\n  reference: {b:?}"
                );
            }
        }
    }
});

fn collect_rows(c: &rusqlite::Connection, sql: &str) -> Result<Vec<Vec<String>>, String> {
    let mut stmt = c.prepare(sql).map_err(|e| e.to_string())?;
    let col_count = stmt.column_count();
    let rows = stmt
        .query_map([], |row| {
            let r: Vec<String> = (0..col_count)
                .map(|i| {
                    let v: rusqlite::types::Value = row.get(i).unwrap_or(rusqlite::types::Value::Null);
                    render_value(&v)
                })
                .collect();
            Ok(r)
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())
}

fn render_value(v: &rusqlite::types::Value) -> String {
    use rusqlite::types::Value;
    match v {
        Value::Null       => "NULL".into(),
        Value::Integer(i) => i.to_string(),
        Value::Real(f)    => {
            if f.is_nan() { "NaN".into() }
            else if f.is_infinite() { if f.is_sign_positive() { "Inf".into() } else { "-Inf".into() } }
            else { format!("{f:.15}") }
        }
        Value::Text(s)    => format!("'{s}'"),
        Value::Blob(b)    => format!("X'{}'", hex::encode(b)),
    }
}
