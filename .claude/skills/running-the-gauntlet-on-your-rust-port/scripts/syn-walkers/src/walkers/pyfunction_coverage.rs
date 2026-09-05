//! pyfunction_coverage — enumerate every `#[pyfunction]`-decorated item and
//! cross-check against the reference's `__all__` JSON list. Reports
//! coverage_pct + per-item presence so the FeatureUniverse loader can drive
//! per-class scoring.

use anyhow::Result;
use serde::Serialize;
use std::collections::HashSet;
use std::path::Path;
use syn::{Item, Meta};

#[derive(Serialize, Debug)]
pub struct Report {
    pub schema_version: &'static str,
    pub subject_pyfunctions: Vec<PyFunction>,
    pub reference_all_count: usize,
    pub covered_count: usize,
    pub coverage_pct: f64,
    pub missing_in_subject: Vec<String>,
    pub extras_in_subject: Vec<String>,
}

#[derive(Serialize, Debug)]
pub struct PyFunction {
    pub name: String,
    pub renamed_to: Option<String>,
    pub file: String,
    pub line: usize,
}

fn has_pyfunction_attr(attrs: &[syn::Attribute]) -> Option<Option<String>> {
    for attr in attrs {
        match &attr.meta {
            Meta::Path(p) if p.is_ident("pyfunction") => return Some(None),
            Meta::List(ml) if ml.path.is_ident("pyfunction") => {
                // Parse `name = "alias"` from the inner tokens.
                let tokens = ml.tokens.to_string();
                if let Some(start) = tokens.find("name") {
                    let after = &tokens[start..];
                    if let Some(eq) = after.find('=') {
                        let rest = after[eq + 1..].trim();
                        let quoted = rest.trim_matches(|c: char| c == '"' || c.is_whitespace());
                        return Some(Some(quoted.trim_end_matches(',').trim().to_string()));
                    }
                }
                return Some(None);
            }
            _ => {}
        }
    }
    None
}

pub fn run(subject_root: &Path, reference_all_json: &Path) -> Result<Report> {
    let raw = std::fs::read_to_string(reference_all_json)?;
    let reference_all: Vec<String> = serde_json::from_str(&raw)?;
    let ref_set: HashSet<String> = reference_all.iter().cloned().collect();

    let mut subject: Vec<PyFunction> = Vec::new();

    super::walk_rs_files(subject_root, |path, file| {
        for item in &file.items {
            if let Item::Fn(item_fn) = item {
                if let Some(renamed) = has_pyfunction_attr(&item_fn.attrs) {
                    let name = item_fn.sig.ident.to_string();
                    subject.push(PyFunction {
                        name,
                        renamed_to: renamed,
                        file: path.display().to_string(),
                        line: item_fn.sig.ident.span().start().line,
                    });
                }
            }
        }
    })?;

    let subject_names: HashSet<String> = subject
        .iter()
        .map(|p| p.renamed_to.clone().unwrap_or_else(|| p.name.clone()))
        .collect();

    let covered_count = subject_names.intersection(&ref_set).count();
    let missing: Vec<String> = ref_set.difference(&subject_names).cloned().collect();
    let extras: Vec<String> = subject_names.difference(&ref_set).cloned().collect();

    let coverage_pct = if reference_all.is_empty() {
        0.0
    } else {
        // truncate to 6 decimal places (per K-5 truncate_score)
        let raw = (covered_count as f64) / (reference_all.len() as f64) * 100.0;
        (raw * 1_000_000.0).trunc() / 1_000_000.0
    };

    Ok(Report {
        schema_version: "syn-walkers.pyfunction_coverage.v1",
        subject_pyfunctions: subject,
        reference_all_count: reference_all.len(),
        covered_count,
        coverage_pct,
        missing_in_subject: missing,
        extras_in_subject: extras,
    })
}
