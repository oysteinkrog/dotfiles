//! data_races — flag manual `unsafe impl Send/Sync` and Cell-shaped types
//! shared cross-thread.

use std::env;
use std::process::ExitCode;
use syn::spanned::Spanned;
use syn::visit::{self, Visit};
use syn::ItemImpl;

struct Visitor<'a> {
    path: &'a std::path::Path,
    issues: usize,
}

impl<'a, 'ast> Visit<'ast> for Visitor<'a> {
    fn visit_item_impl(&mut self, node: &'ast ItemImpl) {
        if let Some((None, trait_path, _)) = &node.trait_ {
            let trait_ident = trait_path.segments.last().map(|segment| &segment.ident);
            let is_send_sync = trait_ident
                .map(|ident| ident == "Send" || ident == "Sync")
                .unwrap_or(false);
            if is_send_sync && node.unsafety.is_some() {
                let self_ty = &node.self_ty;
                let trait_str = quote::quote!(#trait_path).to_string().replace(" :: ", "::");
                let ty_str = quote::quote!(#self_ty).to_string();
                let cell_shape = ty_str.contains("Cell") || ty_str.contains("UnsafeCell");
                let severity = if cell_shape { "ERROR" } else { "WARN" };
                println!(
                    "{}:{}: [{}] `unsafe impl {} for {}` — verify SAFETY comment names sync story",
                    self.path.display(),
                    node.span().start().line,
                    severity,
                    trait_str,
                    ty_str.trim()
                );
                self.issues += 1;
            }
        }
        visit::visit_item_impl(self, node);
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let dir = match args.get(1) {
        Some(d) => std::path::PathBuf::from(d),
        None => {
            eprintln!("Usage: data_races <source-dir>");
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
