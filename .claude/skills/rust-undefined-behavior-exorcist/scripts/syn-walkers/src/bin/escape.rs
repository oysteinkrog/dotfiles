//! escape — flag raw pointers that may escape their borrow scope.

use std::env;
use std::process::ExitCode;
use syn::spanned::Spanned;
use syn::visit::{self, Visit};
use syn::ItemFn;

struct Visitor<'a> {
    path: &'a std::path::Path,
    issues: usize,
}

impl<'a, 'ast> Visit<'ast> for Visitor<'a> {
    fn visit_item_fn(&mut self, node: &'ast ItemFn) {
        let sig = &node.sig;
        let takes_ref = sig.inputs.iter().any(|arg| {
            if let syn::FnArg::Typed(pat) = arg {
                let ty = &pat.ty;
                let ty_str = quote::quote!(#ty).to_string();
                ty_str.starts_with("&")
            } else {
                false
            }
        });
        let returns_ptr = if let syn::ReturnType::Type(_, ty) = &sig.output {
            let s = quote::quote!(#ty).to_string();
            s.contains("*const") || s.contains("*mut")
        } else {
            false
        };
        if takes_ref && returns_ptr {
            println!(
                "{}:{}: fn `{}` takes ref + returns raw ptr — escape-suspect; verify lifetime",
                self.path.display(),
                sig.span().start().line,
                sig.ident
            );
            self.issues += 1;
        }
        visit::visit_item_fn(self, node);
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let dir = match args.get(1) {
        Some(d) => std::path::PathBuf::from(d),
        None => {
            eprintln!("Usage: escape <source-dir>");
            return ExitCode::from(64);
        }
    };
    let mut total = 0usize;
    for (path, file) in ub_syn_walkers::walk_files(&dir) {
        let mut v = Visitor {
            path: &path,
            issues: 0,
        };
        v.visit_file(&file);
        total += v.issues;
    }
    eprintln!("{{\"total_issues\": {}}}", total);
    if total == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    }
}
