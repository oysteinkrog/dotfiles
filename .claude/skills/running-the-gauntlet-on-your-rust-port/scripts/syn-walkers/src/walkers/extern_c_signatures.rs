//! extern_c_signatures — enumerate every `extern "C"` function signature.

use anyhow::Result;
use serde::Serialize;
use std::path::Path;
use syn::Item;

#[derive(Serialize, Debug)]
pub struct Report {
    pub schema_version: &'static str,
    pub functions: Vec<ExternCFn>,
}

#[derive(Serialize, Debug)]
pub struct ExternCFn {
    pub name: String,
    pub file: String,
    pub line: usize,
    pub args: Vec<String>,
    pub return_type: String,
}

pub fn run(subject_root: &Path) -> Result<Report> {
    let mut out: Vec<ExternCFn> = Vec::new();

    super::walk_rs_files(subject_root, |path, file| {
        for item in &file.items {
            if let Item::ForeignMod(fmod) = item {
                let abi_is_c = fmod
                    .abi
                    .name
                    .as_ref()
                    .map(|n| n.value() == "C")
                    .unwrap_or(false);
                if !abi_is_c {
                    continue;
                }
                for fi in &fmod.items {
                    if let syn::ForeignItem::Fn(ff) = fi {
                        let args: Vec<String> = ff
                            .sig
                            .inputs
                            .iter()
                            .map(|a| quote::quote!(#a).to_string())
                            .collect();
                        let return_type = match &ff.sig.output {
                            syn::ReturnType::Default => "()".to_string(),
                            syn::ReturnType::Type(_, ty) => quote::quote!(#ty).to_string(),
                        };
                        out.push(ExternCFn {
                            name: ff.sig.ident.to_string(),
                            file: path.display().to_string(),
                            line: ff.sig.ident.span().start().line,
                            args,
                            return_type,
                        });
                    }
                }
            }
            // Also catch `extern "C" fn` declarations (not in foreign-mod).
            if let Item::Fn(item_fn) = item {
                if let Some(abi) = &item_fn.sig.abi {
                    let is_c = abi
                        .name
                        .as_ref()
                        .map(|n| n.value() == "C")
                        .unwrap_or(false);
                    if !is_c {
                        continue;
                    }
                    let args: Vec<String> = item_fn
                        .sig
                        .inputs
                        .iter()
                        .map(|a| quote::quote!(#a).to_string())
                        .collect();
                    let return_type = match &item_fn.sig.output {
                        syn::ReturnType::Default => "()".to_string(),
                        syn::ReturnType::Type(_, ty) => quote::quote!(#ty).to_string(),
                    };
                    out.push(ExternCFn {
                        name: item_fn.sig.ident.to_string(),
                        file: path.display().to_string(),
                        line: item_fn.sig.ident.span().start().line,
                        args,
                        return_type,
                    });
                }
            }
        }
    })?;

    Ok(Report {
        schema_version: "syn-walkers.extern_c_signatures.v1",
        functions: out,
    })
}
