//! transmute_pairs — extract (Src, Dst) for every transmute call.
//!
//! Output is JSON-line per call so downstream tools can apply layout-compatibility
//! judgments.

use std::env;
use std::process::ExitCode;
use syn::spanned::Spanned;
use syn::visit::{self, Visit};
use syn::{Expr, ExprCall};

struct Visitor {
    path: String,
    issues: usize,
}

fn is_transmute_func(func: &Expr) -> bool {
    match func {
        Expr::Path(path) => path
            .path
            .segments
            .last()
            .map(|segment| segment.ident == "transmute")
            .unwrap_or(false),
        _ => false,
    }
}

fn compact_tokens(text: &str) -> String {
    text.chars().filter(|c| !c.is_whitespace()).collect()
}

impl<'ast> Visit<'ast> for Visitor {
    fn visit_expr(&mut self, node: &'ast Expr) {
        if let Expr::Call(ExprCall { func, .. }) = node {
            if is_transmute_func(func) {
                let fn_str = quote::quote!(#func).to_string();
                let line = node.span().start().line;
                if let (Some(open), Some(close)) = (fn_str.find('<'), fn_str.rfind('>')) {
                    let generics = compact_tokens(&fn_str[open + 1..close]);
                    println!(
                        "{}",
                        serde_json::json!({
                            "file": &self.path,
                            "line": line,
                            "kind": "typed",
                            "generics": generics,
                        })
                    );
                } else {
                    println!(
                        "{}",
                        serde_json::json!({
                            "file": &self.path,
                            "line": line,
                            "kind": "inferred",
                            "generics": serde_json::Value::Null,
                        })
                    );
                }
                self.issues += 1;
            }
        }
        visit::visit_expr(self, node);
    }
}

#[cfg(test)]
mod tests {
    use super::{compact_tokens, is_transmute_func};

    fn parsed_callee(src: &str) -> syn::Expr {
        let call: syn::ExprCall = syn::parse_str(src).expect("call expression should parse");
        *call.func
    }

    #[test]
    fn transmute_match_uses_path_segment_not_substring() {
        assert!(is_transmute_func(&parsed_callee(
            "std::mem::transmute::<u32, i32>(value)"
        )));
        assert!(is_transmute_func(&parsed_callee(
            "core::mem::transmute::<u32, i32>(value)"
        )));
        assert!(!is_transmute_func(&parsed_callee(
            "crate::not_transmute::<u32>(value)"
        )));
    }

    #[test]
    fn compact_tokens_removes_quote_spacing() {
        assert_eq!(
            compact_tokens(" i32 , alloc :: vec :: Vec < u8 > "),
            "i32,alloc::vec::Vec<u8>"
        );
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let dir = match args.get(1) {
        Some(d) => std::path::PathBuf::from(d),
        None => {
            eprintln!("Usage: transmute_pairs <source-dir>");
            return ExitCode::from(64);
        }
    };
    let mut total = 0usize;
    for (path, file) in ub_syn_walkers::walk_files(&dir) {
        let mut v = Visitor {
            path: path.display().to_string(),
            issues: 0,
        };
        v.visit_file(&file);
        total += v.issues;
    }
    eprintln!("{{\"total_transmutes\": {}}}", total);
    ExitCode::SUCCESS
}
