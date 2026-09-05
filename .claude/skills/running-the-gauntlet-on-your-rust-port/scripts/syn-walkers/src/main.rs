//! syn-walkers — AST-precise surface walkers for predicates `ast-grep` can't express.
//!
//! Subcommands:
//!   public-api-diff     — every `pub fn` in subject crate whose name matches a
//!                         reference `__all__` entry but whose argument list differs.
//!   extern-c-signatures — every macro-expanded `extern "C"` whose signature
//!                         drifts from a C header symbol table.
//!   no-mangle-symbols   — every `#[no_mangle]` symbol whose calling convention
//!                         isn't `extern "C"`.
//!   pyfunction-coverage — every `#[pyfunction]`-decorated item, cross-checked
//!                         against a reference `__all__` JSON list.
//!
//! All subcommands emit JSON to stdout for piping into Phase 1 RECON artifacts.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod walkers;

#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Diff `pub fn` signatures in subject crate against a reference export list.
    PublicApiDiff {
        /// Subject crate root (must contain Cargo.toml + src/).
        #[arg(long)]
        subject_root: std::path::PathBuf,

        /// Reference export list — JSON: `{"functions": [{"name": "...", "args": [...]}, ...]}`.
        #[arg(long)]
        reference_exports: std::path::PathBuf,
    },

    /// Enumerate extern "C" function signatures.
    ExternCSignatures {
        #[arg(long)]
        subject_root: std::path::PathBuf,
    },

    /// Enumerate `#[no_mangle]` symbols.
    NoMangleSymbols {
        #[arg(long)]
        subject_root: std::path::PathBuf,
    },

    /// Enumerate `#[pyfunction]` items.
    PyfunctionCoverage {
        #[arg(long)]
        subject_root: std::path::PathBuf,

        /// Reference `__all__` list (JSON array of strings).
        #[arg(long)]
        reference_all_json: std::path::PathBuf,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let report = match cli.cmd {
        Cmd::PublicApiDiff { subject_root, reference_exports } => {
            serde_json::to_value(walkers::public_api_diff::run(&subject_root, &reference_exports)?)?
        }
        Cmd::ExternCSignatures { subject_root } => {
            serde_json::to_value(walkers::extern_c_signatures::run(&subject_root)?)?
        }
        Cmd::NoMangleSymbols { subject_root } => {
            serde_json::to_value(walkers::no_mangle_symbols::run(&subject_root)?)?
        }
        Cmd::PyfunctionCoverage { subject_root, reference_all_json } => {
            serde_json::to_value(walkers::pyfunction_coverage::run(&subject_root, &reference_all_json)?)?
        }
    };
    println!("{}", serde_json::to_string_pretty(&report)?);
    Ok(())
}
