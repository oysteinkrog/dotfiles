//! pin_walker — flag `Pin::new_unchecked` calls and adjacent `mem::replace`.

use std::env;
use std::process::ExitCode;
use syn::spanned::Spanned;
use syn::visit::{self, Visit};
use syn::{Expr, ExprCall};

struct Visitor<'a> {
    path: &'a std::path::Path,
    issues: usize,
}

impl<'a, 'ast> Visit<'ast> for Visitor<'a> {
    fn visit_expr(&mut self, node: &'ast Expr) {
        if let Expr::Call(ExprCall { func, .. }) = node {
            let fn_str = quote::quote!(#func).to_string();
            if fn_str.contains("Pin :: new_unchecked") || fn_str.contains("Pin::new_unchecked") {
                println!(
                    "{}:{}: `Pin::new_unchecked` — audit that the pinned value never moves",
                    self.path.display(),
                    node.span().start().line
                );
                self.issues += 1;
            }
            if fn_str.contains("mem :: replace") || fn_str.contains("mem::replace") {
                println!(
                    "{}:{}: `mem::replace` — verify target is not Pin<!Unpin>",
                    self.path.display(),
                    node.span().start().line
                );
                self.issues += 1;
            }
        }
        visit::visit_expr(self, node);
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let dir = match args.get(1) {
        Some(d) => std::path::PathBuf::from(d),
        None => {
            eprintln!("Usage: pin_walker <source-dir>");
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
