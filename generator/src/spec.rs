//! # The canonical text
//!
//! The migrations under migrations/ and the statements under queries/,
//! loaded at run time from a tree, each statement with the signature
//! queries/signatures.json states for it (STORAGE §4.4). The tree is the
//! directory above this crate's manifest by default: this repository's
//! root, or io-pimdir's spec/ once the crate is vendored there.

use std::{
    collections::BTreeMap,
    env, fs,
    path::{Path, PathBuf},
};

use serde::Deserialize;

use crate::error::{Error, Result};

/// The canonical text of one tree.
#[derive(Clone, Debug)]
pub struct Spec {
    /// The tree the text was read from.
    pub root: PathBuf,
    /// The migrations of each part, by part then version.
    pub migrations: BTreeMap<String, BTreeMap<u32, Migration>>,
    /// The statements by name, `storage/owner/insert_item` for
    /// queries/storage/owner/insert_item.sql.
    pub statements: BTreeMap<String, Statement>,
}

/// One migration script.
#[derive(Clone, Debug)]
pub struct Migration {
    /// The file it was read from.
    pub path: PathBuf,
    /// Its text, run whole in one transaction.
    pub text: String,
}

/// One canonical statement and the signature it binds.
#[derive(Clone, Debug, Deserialize)]
pub struct Statement {
    /// Its name, its path under queries/ without the extension.
    pub name: String,
    /// Its named parameters, in order of first appearance, without `:`.
    pub parameters: Vec<String>,
    /// The list slots of temp.param it reads.
    pub slots: Vec<String>,
    /// The columns it answers, in order.
    pub columns: Vec<String>,
    /// Its text.
    #[serde(skip)]
    pub text: String,
}

impl Spec {
    /// The tree `PIMDIR_GENERATOR_TREE` names, else the one above this
    /// crate's manifest.
    pub fn default_root() -> PathBuf {
        match env::var_os("PIMDIR_GENERATOR_TREE") {
            Some(tree) => PathBuf::from(tree),
            None => Path::new(env!("CARGO_MANIFEST_DIR")).join(".."),
        }
    }

    /// Loads the tree above this crate's manifest.
    pub fn load_default() -> Result<Self> {
        Self::load(&Self::default_root())
    }

    /// Loads the migrations and statements of `root`, refusing a statement
    /// without a signature and a signature without a statement.
    pub fn load(root: &Path) -> Result<Self> {
        let signatures_path = root.join("queries/signatures.json");
        let text = read(&signatures_path)?;
        let signatures: Vec<Statement> =
            serde_json::from_str(&text).map_err(|source| Error::Json {
                path: signatures_path.clone(),
                source,
            })?;
        let mut signatures: BTreeMap<String, Statement> = signatures
            .into_iter()
            .map(|signature| (signature.name.clone(), signature))
            .collect();

        let mut statements = BTreeMap::new();
        for path in sql_files(&root.join("queries"))? {
            let relative = path.strip_prefix(root.join("queries")).unwrap_or(&path);
            let name = relative
                .with_extension("")
                .components()
                .map(|part| part.as_os_str().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
                .join("/");

            let Some(mut statement) = signatures.remove(&name) else {
                return Err(Error::Signature {
                    statement: name,
                    detail: String::from("no line in queries/signatures.json"),
                });
            };
            statement.text = read(&path)?;
            statements.insert(name, statement);
        }

        if let Some(name) = signatures.into_keys().next() {
            return Err(Error::Signature {
                statement: name,
                detail: String::from("no statement file under queries/"),
            });
        }

        let mut migrations = BTreeMap::new();
        for part in ["storage", "search"] {
            let mut versions = BTreeMap::new();
            for path in sql_files(&root.join("migrations").join(part))? {
                let file = path.file_name().unwrap_or_default().to_string_lossy();
                let version = file
                    .split('_')
                    .next()
                    .and_then(|digits| digits.parse::<u32>().ok())
                    .ok_or_else(|| Error::Signature {
                        statement: file.clone().into_owned(),
                        detail: String::from("a migration not named NNNN_name.sql"),
                    })?;
                let text = read(&path)?;
                versions.insert(version, Migration { path, text });
            }
            migrations.insert(String::from(part), versions);
        }

        Ok(Self {
            root: root.to_path_buf(),
            migrations,
            statements,
        })
    }

    /// The statement of that name.
    pub fn statement(&self, name: &str) -> Result<&Statement> {
        self.statements
            .get(name)
            .ok_or_else(|| Error::UnknownStatement(String::from(name)))
    }
}

fn read(path: &Path) -> Result<String> {
    fs::read_to_string(path).map_err(|source| Error::Io {
        path: path.to_path_buf(),
        source,
    })
}

fn sql_files(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    let mut pending = vec![dir.to_path_buf()];

    while let Some(dir) = pending.pop() {
        let entries = fs::read_dir(&dir).map_err(|source| Error::Io {
            path: dir.clone(),
            source,
        })?;
        for entry in entries {
            let path = entry
                .map_err(|source| Error::Io {
                    path: dir.clone(),
                    source,
                })?
                .path();
            if path.is_dir() {
                pending.push(path);
            } else if path.extension().is_some_and(|ext| ext == "sql") {
                files.push(path);
            }
        }
    }

    files.sort();
    Ok(files)
}

#[cfg(test)]
mod tests {
    use crate::spec::Spec;

    #[test]
    fn every_statement_and_migration_of_the_tree_loads() {
        let spec = Spec::load_default().unwrap();

        assert!(
            spec.statements
                .contains_key("storage/owner/init_store_meta")
        );
        assert!(spec.statements.contains_key("search/hit"));
        assert!(spec.migrations["storage"].contains_key(&1));
        assert!(spec.migrations["search"].contains_key(&1));
    }
}
