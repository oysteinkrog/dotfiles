//! Shared helpers for the UB syn walkers.

use std::fs;
use std::path::{Path, PathBuf};
use walkdir::{DirEntry, WalkDir};

fn should_descend(entry: &DirEntry) -> bool {
    let name = entry.file_name().to_string_lossy();
    !matches!(
        name.as_ref(),
        ".git"
            | ".hg"
            | ".svn"
            | ".next"
            | ".turbo"
            | ".venv"
            | "build"
            | "dist"
            | "node_modules"
            | "target"
            | "venv"
    )
}

/// Walk every .rs file under `dir`, parse it with syn, yield (path, file).
pub fn walk_files(dir: &Path) -> impl Iterator<Item = (PathBuf, syn::File)> + '_ {
    WalkDir::new(dir)
        .into_iter()
        .filter_entry(should_descend)
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "rs"))
        .filter_map(|e| {
            let path = e.path().to_path_buf();
            let src = fs::read_to_string(&path).ok()?;
            let parsed = syn::parse_file(&src).ok()?;
            Some((path, parsed))
        })
}

/// Heuristic: does a Rust type admit an all-zero bit pattern?
///
/// Returns true for primitive integer types, raw pointers, and bool (0 = false).
/// Returns false for NonZero*, NonNull, references, function pointers, and
/// any composite type we can't analyze locally (caller should treat false as
/// "may not be zero-valid").
pub fn is_zero_valid_typename(name: &str) -> bool {
    let compact: String = name.chars().filter(|c| !c.is_whitespace()).collect();
    if compact.starts_with("*const") || compact.starts_with("*mut") {
        return true;
    }

    matches!(
        compact.as_str(),
        "i8" | "i16"
            | "i32"
            | "i64"
            | "i128"
            | "isize"
            | "u8"
            | "u16"
            | "u32"
            | "u64"
            | "u128"
            | "usize"
            | "f32"
            | "f64"
            | "bool"
            | "char"
    )
    // Note: bool 0=false is valid; bool 1=true; bool 2+ is UB. mem::zeroed::<bool>() is OK.
    // char(0) is '\0' which is valid; mem::zeroed::<char>() is OK.
    // NonZero*, NonNull, &T, &mut T, Box, fn ptr — all NOT zero-valid.
}

/// Extract the `// SAFETY:` or `// Safety:` comment immediately preceding `line`,
/// if any. Returns the comment text (trimmed) and its line count.
pub fn find_safety_comment(src: &str, line: usize) -> Option<(String, usize)> {
    let lines: Vec<&str> = src.lines().collect();
    if line == 0 || line > lines.len() {
        return None;
    }
    let mut out: Vec<&str> = Vec::new();
    for i in (0..line - 1).rev() {
        let trimmed = lines[i].trim();
        if trimmed.starts_with("// SAFETY:") || trimmed.starts_with("// Safety:") {
            out.push(trimmed);
            break;
        }
        if trimmed.starts_with("//") {
            out.push(trimmed);
            continue;
        }
        if !trimmed.is_empty() {
            break;
        }
    }
    if out.is_empty() {
        None
    } else {
        out.reverse();
        let n = out.len();
        Some((out.join("\n"), n))
    }
}

#[cfg(test)]
mod tests {
    use super::is_zero_valid_typename;

    #[test]
    fn zero_validity_includes_primitives_and_raw_pointers() {
        assert!(is_zero_valid_typename("usize"));
        assert!(is_zero_valid_typename("*const u8"));
        assert!(is_zero_valid_typename("* mut crate::Thing"));
    }

    #[test]
    fn zero_validity_rejects_reference_and_nonzero_shapes() {
        assert!(!is_zero_valid_typename("&u8"));
        assert!(!is_zero_valid_typename("NonZeroUsize"));
        assert!(!is_zero_valid_typename("core::ptr::NonNull<u8>"));
    }
}
