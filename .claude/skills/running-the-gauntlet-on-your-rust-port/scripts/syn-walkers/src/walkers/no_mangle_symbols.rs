//! no_mangle_symbols — enumerate `#[no_mangle]` items and flag any whose
//! calling convention isn't `extern "C"` (parity-affecting hazard).

use anyhow::Result;
use serde::Serialize;
use std::path::Path;
use syn::{Item, Meta};

#[derive(Serialize, Debug)]
pub struct Report {
    pub schema_version: &'static str,
    pub symbols: Vec<NoMangleSymbol>,
    pub non_extern_c_violations: Vec<String>,
}

#[derive(Serialize, Debug)]
pub struct NoMangleSymbol {
    pub name: String,
    pub file: String,
    pub line: usize,
    pub kind: &'static str,    // "fn" | "static" | "const"
    pub abi: Option<String>,   // None = default Rust ABI (violation if fn)
}

fn has_no_mangle(attrs: &[syn::Attribute]) -> bool {
    attrs.iter().any(|attr| {
        if let Meta::Path(p) = &attr.meta {
            p.is_ident("no_mangle")
        } else {
            false
        }
    })
}

pub fn run(subject_root: &Path) -> Result<Report> {
    let mut symbols: Vec<NoMangleSymbol> = Vec::new();
    let mut violations: Vec<String> = Vec::new();

    super::walk_rs_files(subject_root, |path, file| {
        for item in &file.items {
            match item {
                Item::Fn(item_fn) if has_no_mangle(&item_fn.attrs) => {
                    let abi = item_fn
                        .sig
                        .abi
                        .as_ref()
                        .and_then(|a| a.name.as_ref().map(|n| n.value()));
                    let name = item_fn.sig.ident.to_string();
                    let line = item_fn.sig.ident.span().start().line;
                    if abi.as_deref() != Some("C") {
                        violations.push(format!(
                            "{name} at {}:{line} has #[no_mangle] but ABI is {:?} (expected \"C\")",
                            path.display(),
                            abi
                        ));
                    }
                    symbols.push(NoMangleSymbol {
                        name,
                        file: path.display().to_string(),
                        line,
                        kind: "fn",
                        abi,
                    });
                }
                Item::Static(item_static) if has_no_mangle(&item_static.attrs) => {
                    symbols.push(NoMangleSymbol {
                        name: item_static.ident.to_string(),
                        file: path.display().to_string(),
                        line: item_static.ident.span().start().line,
                        kind: "static",
                        abi: None,
                    });
                }
                Item::Const(item_const) if has_no_mangle(&item_const.attrs) => {
                    symbols.push(NoMangleSymbol {
                        name: item_const.ident.to_string(),
                        file: path.display().to_string(),
                        line: item_const.ident.span().start().line,
                        kind: "const",
                        abi: None,
                    });
                }
                _ => {}
            }
        }
    })?;

    Ok(Report {
        schema_version: "syn-walkers.no_mangle_symbols.v1",
        symbols,
        non_extern_c_violations: violations,
    })
}
