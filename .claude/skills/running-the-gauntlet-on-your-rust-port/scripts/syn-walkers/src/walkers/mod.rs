//! Walker modules. Each subcommand dispatches into one of these.

pub mod public_api_diff;
pub mod extern_c_signatures;
pub mod no_mangle_symbols;
pub mod pyfunction_coverage;

use anyhow::Result;
use std::path::Path;
use walkdir::WalkDir;

/// Walk every `.rs` file under `root/src/`, parsing each into a `syn::File`,
/// invoking `visitor` on it. Errors on parse failures are logged but don't halt.
pub fn walk_rs_files<F: FnMut(&Path, syn::File)>(root: &Path, mut visitor: F) -> Result<()> {
    let src = root.join("src");
    if !src.exists() {
        anyhow::bail!("no src/ under {}", root.display());
    }
    for entry in WalkDir::new(&src).into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("rs") {
            continue;
        }
        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("read {}: {e}", path.display());
                continue;
            }
        };
        let file = match syn::parse_file(&content) {
            Ok(f) => f,
            Err(e) => {
                eprintln!("parse {}: {e}", path.display());
                continue;
            }
        };
        visitor(path, file);
    }
    Ok(())
}
