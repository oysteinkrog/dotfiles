//! aliasing — flag high-risk shared-to-mutable pointer patterns.
//!
//! This is a heuristic static sweep. It intentionally reports suspicious
//! shapes that need human follow-up instead of trying to prove aliasing by
//! itself.

use std::env;
use std::process::ExitCode;
use syn::spanned::Spanned;
use syn::visit::{self, Visit};
use syn::{Expr, ExprCall, ExprCast, ExprMethodCall, ExprUnary, UnOp};

struct Visitor<'a> {
    path: &'a std::path::Path,
    issues: usize,
}

fn q<T: quote::ToTokens>(node: &T) -> String {
    quote::quote!(#node).to_string()
}

fn is_mut_raw_pointer_type(ty: &syn::Type) -> bool {
    match ty {
        syn::Type::Ptr(ptr) => ptr.mutability.is_some(),
        _ => q(ty).contains("* mut") || q(ty).contains("*mut"),
    }
}

fn expr_mentions_shared_ref(expr: &Expr) -> bool {
    match expr {
        Expr::Reference(reference) => reference.mutability.is_none(),
        Expr::Cast(ExprCast { expr, ty, .. }) => {
            q(ty).contains("* const") || q(ty).contains("*const") || expr_mentions_shared_ref(expr)
        }
        _ => {
            let rendered = q(expr);
            rendered.starts_with('&')
                || rendered.contains("as * const")
                || rendered.contains("as *const")
        }
    }
}

fn call_name(func: &Expr) -> String {
    q(func).replace(' ', "")
}

impl<'a, 'ast> Visit<'ast> for Visitor<'a> {
    fn visit_expr_cast(&mut self, node: &'ast ExprCast) {
        if is_mut_raw_pointer_type(&node.ty) && expr_mentions_shared_ref(&node.expr) {
            println!(
                "{}:{}: shared reference cast toward `*mut` — verify no live `&T` aliases mutation",
                self.path.display(),
                node.span().start().line
            );
            self.issues += 1;
        }
        visit::visit_expr_cast(self, node);
    }

    fn visit_expr_call(&mut self, node: &'ast ExprCall) {
        let name = call_name(&node.func);
        let suspicious = [
            "ptr::write",
            "std::ptr::write",
            "core::ptr::write",
            "ptr::write_volatile",
            "std::ptr::write_volatile",
            "core::ptr::write_volatile",
            "slice::from_raw_parts_mut",
            "std::slice::from_raw_parts_mut",
            "core::slice::from_raw_parts_mut",
        ];
        if suspicious.iter().any(|needle| name.ends_with(needle)) {
            println!(
                "{}:{}: `{}` may mutate through a raw pointer — check aliasing provenance",
                self.path.display(),
                node.span().start().line,
                name
            );
            self.issues += 1;
        }
        visit::visit_expr_call(self, node);
    }

    fn visit_expr_method_call(&mut self, node: &'ast ExprMethodCall) {
        if node.method == "as_mut_ptr"
            || node.method == "get_unchecked_mut"
            || node.method == "as_unchecked_mut"
            || node.method == "get_mut_unchecked"
        {
            println!(
                "{}:{}: method `{}` can create mutable access from aliased state — audit borrow story",
                self.path.display(),
                node.span().start().line,
                node.method
            );
            self.issues += 1;
        }
        visit::visit_expr_method_call(self, node);
    }

    fn visit_expr_unary(&mut self, node: &'ast ExprUnary) {
        if matches!(node.op, UnOp::Deref(_)) {
            let operand = q(&node.expr);
            if operand.contains("* mut")
                || operand.contains("*mut")
                || operand.contains("as_mut_ptr")
            {
                println!(
                    "{}:{}: raw mutable pointer dereference — prove no active shared aliases",
                    self.path.display(),
                    node.span().start().line
                );
                self.issues += 1;
            }
        }
        visit::visit_expr_unary(self, node);
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let dir = match args.get(1) {
        Some(d) => std::path::PathBuf::from(d),
        None => {
            eprintln!("Usage: aliasing <source-dir>");
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
