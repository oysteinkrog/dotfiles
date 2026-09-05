//! validity — flag value-validity hazards such as invalid zeroing and
//! unchecked initialization.

use std::env;
use std::process::ExitCode;
use syn::spanned::Spanned;
use syn::visit::{self, Visit};
use syn::{Expr, ExprCall, ExprMethodCall};
use ub_syn_walkers::is_zero_valid_typename;

struct Visitor<'a> {
    path: &'a std::path::Path,
    issues: usize,
}

fn q<T: quote::ToTokens>(node: &T) -> String {
    quote::quote!(#node).to_string()
}

fn compact(s: &str) -> String {
    s.chars().filter(|c| !c.is_whitespace()).collect()
}

fn call_name(func: &Expr) -> String {
    compact(&q(func))
}

fn callee_named(func: &Expr, name: &str) -> bool {
    match func {
        Expr::Path(path) => path
            .path
            .segments
            .last()
            .map(|segment| segment.ident == name)
            .unwrap_or(false),
        _ => false,
    }
}

fn callee_is_any(func: &Expr, names: &[&str]) -> bool {
    names.iter().any(|name| callee_named(func, name))
}

fn explicit_generic_type(func: &Expr) -> Option<String> {
    let rendered = q(func);
    let start = rendered.find('<')?;
    let end = rendered.rfind('>')?;
    if end <= start {
        return None;
    }
    Some(compact(rendered[start + 1..end].trim()))
}

fn zero_valid_type_name(ty: &str) -> &str {
    let ty = ty.trim_matches(|c: char| c == '<' || c == '>' || c == ' ');
    if ty.starts_with("*const") || ty.starts_with("*mut") {
        return ty;
    }

    ty.rsplit("::")
        .next()
        .unwrap_or(ty)
        .trim_matches(|c: char| c == '<' || c == '>' || c == ' ')
}

#[cfg(test)]
mod tests {
    use super::{callee_is_any, callee_named, zero_valid_type_name};

    fn parsed_callee(src: &str) -> syn::Expr {
        let call: syn::ExprCall = syn::parse_str(src).expect("call expression should parse");
        *call.func
    }

    #[test]
    fn zero_valid_type_name_preserves_raw_pointer_targets() {
        assert_eq!(zero_valid_type_name("*mutcrate::Thing"), "*mutcrate::Thing");
        assert_eq!(
            zero_valid_type_name("*conststd::ffi::c_void"),
            "*conststd::ffi::c_void"
        );
    }

    #[test]
    fn zero_valid_type_name_reduces_qualified_non_pointer_names() {
        assert_eq!(
            zero_valid_type_name("core::num::NonZeroUsize"),
            "NonZeroUsize"
        );
    }

    #[test]
    fn callee_matching_uses_path_segments() {
        assert!(callee_named(
            &parsed_callee("std::mem::zeroed::<u8>()"),
            "zeroed"
        ));
        assert!(callee_named(&parsed_callee("zeroed::<u8>()"), "zeroed"));
        assert!(!callee_named(
            &parsed_callee("crate::not_zeroed::<u8>()"),
            "zeroed"
        ));
        assert!(callee_is_any(
            &parsed_callee("from_raw_parts(ptr, len)"),
            &["from_raw_parts", "from_raw_parts_mut"]
        ));
    }
}

impl<'a, 'ast> Visit<'ast> for Visitor<'a> {
    fn visit_expr_call(&mut self, node: &'ast ExprCall) {
        let name = call_name(&node.func);
        if callee_named(&node.func, "zeroed") {
            match explicit_generic_type(&node.func) {
                Some(ty) if is_zero_valid_typename(zero_valid_type_name(&ty)) => {}
                Some(ty) => {
                    println!(
                        "{}:{}: `mem::zeroed::<{}>()` may create an invalid value",
                        self.path.display(),
                        node.span().start().line,
                        ty
                    );
                    self.issues += 1;
                }
                None => {
                    println!(
                        "{}:{}: `mem::zeroed()` with inferred type — verify the inferred type is zero-valid",
                        self.path.display(),
                        node.span().start().line
                    );
                    self.issues += 1;
                }
            }
        }

        let dangerous = [
            "from_utf8_unchecked",
            "from_raw_parts",
            "from_raw_parts_mut",
            "unreachable_unchecked",
        ];
        if callee_is_any(&node.func, &dangerous) {
            println!(
                "{}:{}: `{}` requires external validity proof",
                self.path.display(),
                node.span().start().line,
                name
            );
            self.issues += 1;
        }

        visit::visit_expr_call(self, node);
    }

    fn visit_expr_method_call(&mut self, node: &'ast ExprMethodCall) {
        if node.method == "assume_init"
            || node.method == "assume_init_read"
            || node.method == "set_len"
        {
            println!(
                "{}:{}: method `{}` requires a written-initialized/valid-length proof",
                self.path.display(),
                node.span().start().line,
                node.method
            );
            self.issues += 1;
        }
        visit::visit_expr_method_call(self, node);
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let dir = match args.get(1) {
        Some(d) => std::path::PathBuf::from(d),
        None => {
            eprintln!("Usage: validity <source-dir>");
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
