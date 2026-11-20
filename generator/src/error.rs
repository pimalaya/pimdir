//! # Errors
//!
//! What loading the canonical text and writing a store fail with.

use std::{fmt, io, path::PathBuf};

/// A failure of the generator, naming what it was reading or running.
#[derive(Debug)]
pub enum Error {
    /// A file of the tree could not be read or written.
    Io {
        /// The file.
        path: PathBuf,
        /// What the system answered.
        source: io::Error,
    },
    /// A JSON file of the tree does not parse as expected.
    Json {
        /// The file.
        path: PathBuf,
        /// What the parser answered.
        source: serde_json::Error,
    },
    /// SQLite refused a statement.
    Sql {
        /// The statement's name, or the pragma or boundary run.
        statement: String,
        /// What SQLite answered.
        source: rusqlite::Error,
    },
    /// No statement of that name is loaded.
    UnknownStatement(String),
    /// A statement and its line in queries/signatures.json disagree.
    Signature {
        /// The statement's name.
        statement: String,
        /// How they disagree.
        detail: String,
    },
    /// A statement was run with other parameters than its signature names.
    Parameters {
        /// The statement's name.
        statement: String,
        /// The parameters given and the ones named.
        detail: String,
    },
    /// The owner lock of a store is held by another handle.
    Locked(PathBuf),
    /// The store answered other than the model predicts.
    Disagreement {
        /// What was compared.
        what: String,
        /// The two answers.
        detail: String,
    },
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io { path, source } => write!(f, "Cannot access {}: {source}", path.display()),
            Self::Json { path, source } => write!(f, "Cannot parse {}: {source}", path.display()),
            Self::Sql { statement, source } => write!(f, "Cannot run {statement}: {source}"),
            Self::UnknownStatement(name) => write!(f, "Cannot find statement {name}"),
            Self::Signature { statement, detail } => {
                write!(
                    f,
                    "Statement {statement} disagrees with its signature: {detail}"
                )
            }
            Self::Parameters { statement, detail } => {
                write!(f, "Cannot bind statement {statement}: {detail}")
            }
            Self::Locked(path) => write!(f, "Cannot take the owner lock of {}", path.display()),
            Self::Disagreement { what, detail } => write!(f, "Disagreement on {what}: {detail}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            Self::Json { source, .. } => Some(source),
            Self::Sql { source, .. } => Some(source),
            _ => None,
        }
    }
}

/// The result of every fallible call of the crate.
pub type Result<T> = std::result::Result<T, Error>;
