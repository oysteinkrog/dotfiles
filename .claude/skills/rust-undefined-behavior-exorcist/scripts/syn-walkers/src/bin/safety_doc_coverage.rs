//! safety_doc_coverage — flag every `unsafe fn` without a `# Safety` doc
//! comment, every `unsafe { ... }` block without a preceding `// SAFETY:`
//! comment, every SAFETY comment shorter than 40 characters.

use std::env;
use std::fs;
use std::process::ExitCode;
use syn::spanned::Spanned;
use syn::visit::{self, Visit};
use syn::{Expr, ItemFn};
use ub_syn_walkers::find_safety_comment;

struct Visitor<'a> {
    path: &'a std::path::Path,
    src: &'a str,
    issues: usize,
}

fn has_safety_doc(attrs: &[syn::Attribute]) -> bool {
    attrs.iter().any(|a| {
        if !a.path().is_ident("doc") {
            return false;
        }
        let s = quote::quote!(#a).to_string();
        s.contains("# Safety") || s.contains("# safety")
    })
}

impl<'a, 'ast> Visit<'ast> for Visitor<'a> {
    fn visit_item_fn(&mut self, node: &'ast ItemFn) {
        if node.sig.unsafety.is_some() && !has_safety_doc(&node.attrs) {
            let line = node.sig.span().start().line;
            println!(
                "{}:{}: unsafe fn `{}` lacks `# Safety` doc section",
                self.path.display(),
                line,
                node.sig.ident
            );
            self.issues += 1;
        }
        visit::visit_item_fn(self, node);
    }

    fn visit_expr(&mut self, node: &'ast Expr) {
        if let Expr::Unsafe(block) = node {
            let line = block.unsafe_token.span().start().line;
            match find_safety_comment(self.src, line) {
                None => {
                    println!(
                        "{}:{}: unsafe block has no preceding `// SAFETY:` comment",
                        self.path.display(),
                        line
                    );
                    self.issues += 1;
                }
                Some((comment, _)) if comment.len() < 40 => {
                    println!(
                        "{}:{}: unsafe block has weak (<40 char) SAFETY comment: {:?}",
                        self.path.display(),
                        line,
                        comment
                    );
                    self.issues += 1;
                }
                _ => {}
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
            eprintln!("Usage: safety_doc_coverage <source-dir>");
            return ExitCode::from(64);
        }
    };
    let mut total = 0usize;
    for (path, file) in ub_syn_walkers::walk_files(&dir) {
        let src = fs::read_to_string(&path).unwrap_or_default();
        let mut v = Visitor {
            path: &path,
            src: &src,
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
