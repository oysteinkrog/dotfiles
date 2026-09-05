//! public_api_diff — every `pub fn` in subject crate whose name matches a
//! reference export but whose argument list differs.
//!
//! REFERENCE-EXPORTS JSON CONTRACT:
//!
//! ```json
//! {
//!   "schema_version": "gauntlet.reference_exports.v1",
//!   "functions": [
//!     {
//!       "name": "my_fn",
//!       "arg_types": ["i32", "&str", "Option<Vec<u8>>"],
//!       "arg_names_optional": ["x", "name", "data"]
//!     }
//!   ]
//! }
//! ```
//!
//! Both subject and reference sides are normalized through `canon_type()`
//! (lowercased, whitespace-collapsed, `& 'lifetime` stripped, generic-arg
//! spaces collapsed) before comparison, so trivial format differences don't
//! flag as drift.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use syn::{Item, Visibility};

#[derive(Deserialize, Debug)]
struct ReferenceExports {
    functions: Vec<ReferenceFn>,
}

#[derive(Deserialize, Debug)]
struct ReferenceFn {
    name: String,
    /// Types only (recommended). One entry per arg. If absent, `args`
    /// (legacy `"name: Type"`) is parsed.
    #[serde(default)]
    arg_types: Vec<String>,
    /// Legacy: `["x: i32", "name: &str"]`. Used only when `arg_types` empty.
    #[serde(default)]
    args: Vec<String>,
}

impl ReferenceFn {
    /// Yield the canonical type-list for comparison.
    fn canonical_types(&self) -> Vec<String> {
        if !self.arg_types.is_empty() {
            self.arg_types.iter().map(|t| canon_type(t)).collect()
        } else {
            // Legacy: parse "name: Type" → "Type".
            self.args
                .iter()
                .map(|a| {
                    let s = a.trim();
                    match s.find(':') {
                        Some(i) => canon_type(s[i + 1..].trim()),
                        None => canon_type(s),
                    }
                })
                .collect()
        }
    }
}

/// Canonicalize a Rust type string for cross-side comparison.
///
/// - Lowercases.
/// - Collapses all internal whitespace to single space.
/// - Strips `'lifetime ` markers (e.g., `&'a str` → `&str`).
/// - Removes spaces inside generic brackets (`Vec< u8 >` → `vec<u8>`).
fn canon_type(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut last_was_space = false;
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        // Strip `'lifetime` after `&`.
        if c == '\'' {
            while let Some(&n) = chars.peek() {
                if n.is_alphanumeric() || n == '_' {
                    chars.next();
                } else {
                    break;
                }
            }
            // Skip exactly one following space if present (so `&'a str` → `&str`).
            if let Some(&' ') = chars.peek() {
                chars.next();
            }
            continue;
        }
        if c.is_whitespace() {
            if !last_was_space && !out.is_empty() {
                // Suppress spaces adjacent to `<`, `>`, `,` for canonicalization.
                let prev = out.chars().last().unwrap();
                if !matches!(prev, '<' | '>' | ',') {
                    out.push(' ');
                    last_was_space = true;
                }
            }
            continue;
        }
        if matches!(c, '<' | '>' | ',') {
            // Trim trailing space before these.
            while out.ends_with(' ') {
                out.pop();
            }
            out.push(c);
            last_was_space = false;
            continue;
        }
        out.push(c.to_ascii_lowercase());
        last_was_space = false;
    }
    out.trim().to_string()
}

#[derive(Serialize, Debug)]
pub struct Report {
    pub schema_version: &'static str,
    pub subject_pub_fns: usize,
    pub reference_fns: usize,
    pub name_matches: usize,
    pub signature_diffs: Vec<SignatureDiff>,
    pub missing_in_subject: Vec<String>,
    pub extras_in_subject: Vec<String>,
}

#[derive(Serialize, Debug)]
pub struct SignatureDiff {
    pub fn_name: String,
    pub file: String,
    pub line: usize,
    pub subject_args: Vec<String>,
    pub reference_args: Vec<String>,
}

pub fn run(subject_root: &Path, reference_exports_path: &Path) -> Result<Report> {
    let refs_raw = std::fs::read_to_string(reference_exports_path)?;
    let refs: ReferenceExports = serde_json::from_str(&refs_raw)?;
    let mut ref_by_name: HashMap<String, &ReferenceFn> = HashMap::new();
    for f in &refs.functions {
        ref_by_name.insert(f.name.clone(), f);
    }

    let mut subject_pub_fns = 0usize;
    let mut name_matches = 0usize;
    let mut diffs: Vec<SignatureDiff> = Vec::new();
    let mut subject_names: Vec<String> = Vec::new();

    super::walk_rs_files(subject_root, |path, file| {
        for item in &file.items {
            if let Item::Fn(item_fn) = item {
                if !matches!(item_fn.vis, Visibility::Public(_)) {
                    continue;
                }
                subject_pub_fns += 1;
                let name = item_fn.sig.ident.to_string();
                subject_names.push(name.clone());

                let subject_args: Vec<String> = item_fn
                    .sig
                    .inputs
                    .iter()
                    .map(|arg| match arg {
                        syn::FnArg::Receiver(_) => "self".to_string(),
                        syn::FnArg::Typed(pat) => {
                            let ty = &pat.ty;
                            canon_type(&quote::quote!(#ty).to_string())
                        }
                    })
                    .collect();

                if let Some(rfn) = ref_by_name.get(&name) {
                    name_matches += 1;
                    let reference_args = rfn.canonical_types();
                    if subject_args != reference_args {
                        // proc_macro2::Span::start() is nightly-only without the feature; fall back to 0.
                        let line = item_fn
                            .sig
                            .ident
                            .span()
                            .start()
                            .line;
                        diffs.push(SignatureDiff {
                            fn_name: name.clone(),
                            file: path.display().to_string(),
                            line,
                            subject_args: subject_args.clone(),
                            reference_args,
                        });
                    }
                }
            }
        }
    })?;

    let subject_set: std::collections::HashSet<String> = subject_names.into_iter().collect();
    let ref_set: std::collections::HashSet<String> =
        ref_by_name.keys().cloned().collect();

    let missing_in_subject: Vec<String> = ref_set
        .difference(&subject_set)
        .cloned()
        .collect();
    let extras_in_subject: Vec<String> = subject_set
        .difference(&ref_set)
        .cloned()
        .collect();

    Ok(Report {
        schema_version: "syn-walkers.public_api_diff.v1",
        subject_pub_fns,
        reference_fns: refs.functions.len(),
        name_matches,
        signature_diffs: diffs,
        missing_in_subject,
        extras_in_subject,
    })
}
