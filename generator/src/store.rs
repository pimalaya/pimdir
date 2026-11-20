//! # A store
//!
//! A pimdir store created and written as its owner through the canonical
//! text of a [`Spec`] alone: the directory and its files private, the owner
//! lock held, migrations/storage/0001_init.sql and `init_store_meta` in one
//! transaction (GUIDE §2, §3), then every write by a statement's name. The
//! only SQL of the crate's own is a pragma or a transaction's boundary.

use std::{
    cell::RefCell,
    collections::BTreeSet,
    fs::{self, File, OpenOptions},
    path::{Path, PathBuf},
};

use rusqlite::{Connection, ToSql, types::Value};

use crate::{
    error::{Error, Result},
    spec::Spec,
};

/// The Annex A revision the generator derives summaries, addresses and
/// sort keys under (STORAGE Annex A, §6).
pub const DERIVATION: i64 = 3;

/// A store the generator owns.
pub struct Store<'a> {
    /// Its directory.
    pub dir: PathBuf,
    spec: &'a Spec,
    conn: Connection,
    checked: RefCell<BTreeSet<String>>,
    _lock: File,
}

impl<'a> Store<'a> {
    /// Creates a store in `dir`, which must not exist yet.
    pub fn create(spec: &'a Spec, dir: &Path) -> Result<Self> {
        create_private_dir(dir)?;

        let lock_path = dir.join("owner.lock");
        let lock = private_file(&lock_path)?;
        lock.try_lock()
            .map_err(|_| Error::Locked(dir.to_path_buf()))?;

        let db_path = dir.join("pimdir.db");
        private_file(&db_path)?;
        let mut conn = Connection::open(&db_path).map_err(|source| sql("open", source))?;
        conn.execute_batch(
            "PRAGMA foreign_keys = ON; PRAGMA synchronous = FULL; PRAGMA secure_delete = ON;",
        )
        .map_err(|source| sql("pragmas", source))?;

        let versions = &spec.migrations["storage"];
        if let Some(version) = versions.keys().find(|version| **version != 1) {
            return Err(Error::Signature {
                statement: format!("migrations/storage/{version:04}"),
                detail: String::from("a draft store is created from 0001_init.sql alone"),
            });
        }
        let init = spec.statement("storage/owner/init_store_meta")?;

        let tx = conn.transaction().map_err(|source| sql("BEGIN", source))?;
        tx.execute_batch(&versions[&1].text)
            .map_err(|source| sql("migrations/storage/0001_init.sql", source))?;
        tx.execute(
            &init.text,
            rusqlite::named_params! { ":version": 1, ":derivation": DERIVATION },
        )
        .map_err(|source| sql(&init.name, source))?;
        tx.pragma_update(None, "user_version", 1)
            .map_err(|source| sql("user_version", source))?;
        tx.commit().map_err(|source| sql("COMMIT", source))?;

        conn.execute_batch("PRAGMA journal_mode = WAL; PRAGMA journal_size_limit = 1048576;")
            .map_err(|source| sql("journal_mode", source))?;

        let store = Self {
            dir: dir.to_path_buf(),
            spec,
            conn,
            checked: RefCell::new(BTreeSet::new()),
            _lock: lock,
        };
        create_private_dir(&dir.join("objects"))?;
        store.run("storage/read/create_param", &[])?;
        Ok(store)
    }

    /// Runs the statement `name` with `params`, stepping every row it
    /// answers, which a statement ending in `RETURNING` needs (GUIDE §5).
    ///
    /// The parameters are bound by name and must be exactly the ones its
    /// signature states; its prepared parameters and columns are held to
    /// that signature the first time it runs.
    pub fn run(&self, name: &str, params: &[(&str, &dyn ToSql)]) -> Result<Vec<Vec<Value>>> {
        let statement = self.spec.statement(name)?;

        let given: BTreeSet<&str> = params.iter().map(|(key, _)| *key).collect();
        let wanted: BTreeSet<&str> = statement.parameters.iter().map(String::as_str).collect();
        if given != wanted || given.len() != params.len() {
            return Err(Error::Parameters {
                statement: String::from(name),
                detail: format!("given {given:?}, its signature names {wanted:?}"),
            });
        }

        let mut prepared = self
            .conn
            .prepare_cached(&statement.text)
            .map_err(|source| sql(name, source))?;

        if !self.checked.borrow().contains(name) {
            let parameters: Vec<String> = (1..=prepared.parameter_count())
                .filter_map(|i| prepared.parameter_name(i))
                .map(|param| String::from(param.trim_start_matches(':')))
                .collect();
            let columns: Vec<String> = prepared.column_names().map(String::from).collect();
            if parameters != statement.parameters || columns != statement.columns {
                return Err(Error::Signature {
                    statement: String::from(name),
                    detail: format!("prepared with {parameters:?} answering {columns:?}"),
                });
            }
            self.checked.borrow_mut().insert(String::from(name));
        }

        let named: Vec<(String, &dyn ToSql)> = params
            .iter()
            .map(|(key, value)| (format!(":{key}"), *value))
            .collect();
        let bound: Vec<(&str, &dyn ToSql)> = named
            .iter()
            .map(|(key, value)| (key.as_str(), *value))
            .collect();

        let width = prepared.column_count();
        let mut rows = prepared
            .query(bound.as_slice())
            .map_err(|source| sql(name, source))?;
        let mut answered = Vec::new();
        while let Some(row) = rows.next().map_err(|source| sql(name, source))? {
            let values = (0..width)
                .map(|i| row.get::<_, Value>(i))
                .collect::<rusqlite::Result<Vec<_>>>()
                .map_err(|source| sql(name, source))?;
            answered.push(values);
        }

        Ok(answered)
    }

    /// Fills the list slot `slot` with `values` in order, after emptying
    /// every slot (`clear_param`, then `bind_param` per value, STORAGE §4.4).
    pub fn bind_slot(&self, slot: &str, values: &[Value]) -> Result<()> {
        self.run("storage/read/clear_param", &[])?;
        for (position, value) in values.iter().enumerate() {
            let position = position as i64;
            self.run(
                "storage/read/bind_param",
                &[("slot", &slot), ("position", &position), ("value", value)],
            )?;
        }
        Ok(())
    }

    /// Opens a transaction the next runs write in.
    pub fn begin(&self) -> Result<()> {
        self.conn
            .execute_batch("BEGIN")
            .map_err(|source| sql("BEGIN", source))
    }

    /// Commits the transaction [`Store::begin`] opened.
    pub fn commit(&self) -> Result<()> {
        self.conn
            .execute_batch("COMMIT")
            .map_err(|source| sql("COMMIT", source))
    }

    /// The canonical text the store is written through.
    pub fn spec(&self) -> &Spec {
        self.spec
    }

    /// The id of the row the connection last inserted, the id a producer
    /// follows its enqueue by (STORAGE §15.1).
    pub fn last_insert_rowid(&self) -> i64 {
        self.conn.last_insert_rowid()
    }

    /// Reads a pragma's one value, for the checks of the store's shape.
    pub fn pragma(&self, name: &str) -> Result<Value> {
        self.conn
            .pragma_query_value(None, name, |row| row.get(0))
            .map_err(|source| sql(name, source))
    }
}

fn sql(statement: &str, source: rusqlite::Error) -> Error {
    Error::Sql {
        statement: String::from(statement),
        source,
    }
}

#[cfg(unix)]
pub(crate) fn create_private_dir(dir: &Path) -> Result<()> {
    use std::os::unix::fs::DirBuilderExt;

    fs::DirBuilder::new()
        .mode(0o700)
        .create(dir)
        .map_err(|source| Error::Io {
            path: dir.to_path_buf(),
            source,
        })
}

#[cfg(not(unix))]
pub(crate) fn create_private_dir(dir: &Path) -> Result<()> {
    fs::create_dir(dir).map_err(|source| Error::Io {
        path: dir.to_path_buf(),
        source,
    })
}

#[cfg(unix)]
fn private_file(path: &Path) -> Result<File> {
    use std::os::unix::fs::OpenOptionsExt;

    OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
        .map_err(|source| Error::Io {
            path: path.to_path_buf(),
            source,
        })
}

#[cfg(not(unix))]
fn private_file(path: &Path) -> Result<File> {
    OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|source| Error::Io {
            path: path.to_path_buf(),
            source,
        })
}

#[cfg(test)]
mod tests {
    use std::{
        env,
        fs::{self, File},
        path::PathBuf,
        process,
        sync::atomic::{AtomicU32, Ordering},
    };

    use rusqlite::types::Value;

    use crate::{
        error::Error,
        spec::Spec,
        store::{DERIVATION, Store},
    };

    static NEXT: AtomicU32 = AtomicU32::new(0);

    fn scratch() -> PathBuf {
        let dir = env::temp_dir().join(format!(
            "pimdir-generator-{}-{}",
            process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    fn draft_of_init(spec: &Spec) -> String {
        let text = &spec
            .statement("storage/owner/init_store_meta")
            .unwrap()
            .text;
        let start = text.find("'storage-draft-").unwrap() + 1;
        let end = start + text[start..].find('\'').unwrap();
        String::from(&text[start..end])
    }

    #[test]
    fn a_created_store_names_the_draft_its_init_statement_writes() {
        let spec = Spec::load_default().unwrap();
        let dir = scratch();
        let store = Store::create(&spec, &dir).unwrap();

        let rows = store.run("storage/read/load_store_meta", &[]).unwrap();
        assert_eq!(rows.len(), 1);
        let meta = &rows[0];
        let column = |name: &str| {
            let at = spec.statements["storage/read/load_store_meta"]
                .columns
                .iter()
                .position(|column| column == name)
                .unwrap();
            meta[at].clone()
        };

        assert_eq!(column("format"), Value::Text("pimdir".into()));
        assert_eq!(column("format_version"), Value::Text(draft_of_init(&spec)));
        assert_eq!(column("version"), Value::Integer(1));
        assert_eq!(column("read_version"), Value::Integer(1));
        assert_eq!(column("produce_version"), Value::Integer(1));
        assert_eq!(column("hash_algo"), Value::Text("blake3".into()));
        assert_eq!(column("incarnation"), Value::Integer(1));
        assert_eq!(column("derivation"), Value::Integer(DERIVATION));
        assert_eq!(column("sync_version"), Value::Null);
        let Value::Text(id) = column("store_id") else {
            panic!("store_id is no text");
        };
        assert!(
            id.len() == 32
                && id
                    .bytes()
                    .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
        );

        assert_eq!(store.pragma("user_version").unwrap(), Value::Integer(1));
        assert_eq!(store.pragma("auto_vacuum").unwrap(), Value::Integer(2));
        assert_eq!(
            store.pragma("journal_mode").unwrap(),
            Value::Text("wal".into())
        );

        drop(store);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn a_created_store_is_private_to_its_user() {
        use std::os::unix::fs::PermissionsExt;

        let spec = Spec::load_default().unwrap();
        let dir = scratch();
        let store = Store::create(&spec, &dir).unwrap();

        let mode = |path: PathBuf| fs::metadata(path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(dir.clone()), 0o700);
        assert_eq!(mode(dir.join("pimdir.db")), 0o600);
        assert_eq!(mode(dir.join("owner.lock")), 0o600);

        drop(store);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn the_owner_lock_is_held_while_the_store_is_open() {
        let spec = Spec::load_default().unwrap();
        let dir = scratch();
        let store = Store::create(&spec, &dir).unwrap();

        let other = File::options()
            .write(true)
            .open(dir.join("owner.lock"))
            .unwrap();
        assert!(other.try_lock().is_err());
        drop(store);
        assert!(other.try_lock().is_ok());

        drop(other);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn every_storage_statement_prepares_to_its_signature() {
        let spec = Spec::load_default().unwrap();
        let dir = scratch();
        let store = Store::create(&spec, &dir).unwrap();

        for statement in spec.statements.values() {
            if !statement.name.starts_with("storage/") {
                continue;
            }
            let prepared = store.conn.prepare(&statement.text).unwrap();
            let parameters: Vec<String> = (1..=prepared.parameter_count())
                .filter_map(|i| prepared.parameter_name(i))
                .map(|param| String::from(param.trim_start_matches(':')))
                .collect();
            let columns: Vec<String> = prepared.column_names().map(String::from).collect();
            assert_eq!(parameters, statement.parameters, "{}", statement.name);
            assert_eq!(columns, statement.columns, "{}", statement.name);
        }

        drop(store);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_statement_run_with_other_parameters_than_its_signature_is_refused() {
        let spec = Spec::load_default().unwrap();
        let dir = scratch();
        let store = Store::create(&spec, &dir).unwrap();

        let refused = store.run("storage/owner/bump_next_seq", &[("seq", &1)]);
        assert!(matches!(refused, Err(Error::Parameters { .. })));

        drop(store);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn storage_md_states_the_annex_a_revision_the_generator_derives_under() {
        let path = Spec::default_root().join("STORAGE.md");
        let text = fs::read_to_string(path).unwrap();
        assert!(text.contains(&format!("This annex is at **revision {DERIVATION}**")));
    }
}
