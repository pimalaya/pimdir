//! # The oracle
//!
//! What each read statement answers over the store a model leaves, stated
//! from the model alone as an [`Expectation`] per statement and parameter
//! point: the collections and accounts, each collection's count, every
//! listing page by page under its keyset cursor, every live item by its
//! `seq`, every key's `seq` and every item's addresses (STORAGE §14.1).
//!
//! [`check`] runs them on a store and names each disagreement: the
//! self-check of README.md, holding the writer to the statements and the
//! model to the store.

use rusqlite::{ToSql, types::Value};

use crate::{
    error::Result,
    model::{Item, Kind, Model, Table},
    spec::Spec,
    store::Store,
};

/// One statement at one parameter point and the rows it answers.
#[derive(Clone, Debug)]
pub struct Expectation {
    /// The statement's name.
    pub statement: String,
    /// Its parameters by name.
    pub params: Vec<(String, Value)>,
    /// The rows it answers, in its order.
    pub rows: Vec<Vec<Value>>,
}

/// The page size the listings are walked at, small so every listing of the
/// structure profile spans several pages.
pub const PAGE: i64 = 3;

/// Every expectation the model states over the reads it covers.
pub fn expectations(model: &Model, spec: &Spec) -> Result<Vec<Expectation>> {
    let mut out = Vec::new();

    out.push(Expectation {
        statement: String::from("storage/read/list_collections"),
        params: Vec::new(),
        rows: model
            .collections
            .values()
            .map(|collection| {
                vec![
                    Value::Text(collection.id.clone()),
                    text(collection.account.as_deref()),
                    Value::Text(String::from(
                        collection.kind.map_or("", |kind| kind.media_type()),
                    )),
                    Value::Text(collection.name.clone()),
                    Value::Null,
                    Value::Null,
                    Value::Null,
                    Value::Null,
                    Value::Integer(1),
                    text(collection.role.as_deref()),
                    Value::Null,
                    Value::Null,
                    Value::Null,
                ]
            })
            .collect(),
    });

    let mut accounts: Vec<&String> = model
        .collections
        .values()
        .filter_map(|collection| collection.account.as_ref())
        .collect();
    accounts.sort();
    accounts.dedup();
    out.push(Expectation {
        statement: String::from("storage/read/list_accounts"),
        params: Vec::new(),
        rows: accounts
            .into_iter()
            .map(|account| vec![Value::Text(account.clone())])
            .collect(),
    });

    for collection in model.collections.values() {
        let id = Value::Text(collection.id.clone());
        let live: Vec<&Item> = model.live(&collection.id).collect();

        out.push(Expectation {
            statement: String::from("storage/read/count_items"),
            params: vec![(String::from("collection"), id.clone())],
            rows: vec![vec![Value::Integer(live.len() as i64)]],
        });

        let mut listings = vec![
            ("storage/read/list_items_page_asc", None, false),
            ("storage/read/list_items_page_desc", None, true),
        ];
        match collection.kind {
            Some(Kind::Mail) => {
                listings.push(("storage/read/list_mail_page_desc", Some(Table::Mail), true));
            }
            Some(Kind::Contact) => listings.push((
                "storage/read/list_contacts_page_asc",
                Some(Table::Contact),
                false,
            )),
            Some(Kind::Calendar) => {
                for (name, table) in [
                    ("storage/read/list_events_page_asc", Table::Event),
                    ("storage/read/list_tasks_page_asc", Table::Task),
                    ("storage/read/list_journals_page_asc", Table::Journal),
                ] {
                    listings.push((name, Some(table), false));
                }
            }
            Some(Kind::File) => {
                listings.push(("storage/read/list_files_page_asc", Some(Table::File), false));
            }
            None => {}
        }
        for (name, table, descending) in listings {
            let columns = &spec.statement(name)?.columns;
            let mut sorted = live.clone();
            sorted.sort_by(|a, b| {
                let order = (a.sort_key.as_str(), a.seq).cmp(&(b.sort_key.as_str(), b.seq));
                if descending { order.reverse() } else { order }
            });
            let mut after: (Value, Value) = (Value::Null, Value::Null);
            for page in sorted.chunks(PAGE as usize).chain([&[][..]]) {
                out.push(Expectation {
                    statement: String::from(name),
                    params: vec![
                        (String::from("collection"), id.clone()),
                        (String::from("after_key"), after.0.clone()),
                        (String::from("after_seq"), after.1.clone()),
                        (String::from("limit"), Value::Integer(PAGE)),
                    ],
                    rows: page.iter().map(|item| row(item, columns, table)).collect(),
                });
                if let Some(last) = page.last() {
                    after = (Value::Text(last.sort_key.clone()), Value::Integer(last.seq));
                }
            }
        }

        let columns = &spec.statement("storage/read/list_items_page")?.columns;
        let mut by_link = live.clone();
        by_link.sort_by(|a, b| a.link_id.cmp(&b.link_id));
        let mut after = Value::Null;
        for page in by_link.chunks(PAGE as usize).chain([&[][..]]) {
            out.push(Expectation {
                statement: String::from("storage/read/list_items_page"),
                params: vec![
                    (String::from("collection"), id.clone()),
                    (String::from("after"), after.clone()),
                    (String::from("limit"), Value::Integer(PAGE)),
                ],
                rows: page.iter().map(|item| row(item, columns, None)).collect(),
            });
            if let Some(last) = page.last() {
                after = Value::Text(last.link_id.clone());
            }
        }
    }

    for item in &model.items {
        let collection = Value::Text(item.collection.clone());
        let link_id = Value::Text(item.link_id.clone());
        let seq = Value::Integer(item.seq);
        let by_seq = vec![
            (String::from("collection"), collection.clone()),
            (String::from("seq"), seq.clone()),
        ];
        let by_link = vec![
            (String::from("collection"), collection.clone()),
            (String::from("link_id"), link_id.clone()),
        ];

        if !item.deleted {
            let name = "storage/read/get_item";
            out.push(Expectation {
                statement: String::from(name),
                params: by_seq.clone(),
                rows: vec![row(item, &spec.statement(name)?.columns, None)],
            });
            let name = format!("storage/read/get_{}", item.summary.table.stem());
            out.push(Expectation {
                rows: vec![row(
                    item,
                    &spec.statement(&name)?.columns,
                    Some(item.summary.table),
                )],
                statement: name,
                params: by_seq,
            });
        }

        out.push(Expectation {
            statement: String::from("storage/read/seq_by_link"),
            params: by_link.clone(),
            rows: vec![vec![seq]],
        });

        let mut addresses = item.addresses.clone();
        addresses.sort_by(|a, b| (a.role.as_str(), a.position).cmp(&(b.role.as_str(), b.position)));
        out.push(Expectation {
            statement: String::from("storage/read/load_addresses"),
            params: by_link,
            rows: addresses
                .into_iter()
                .map(|address| {
                    vec![
                        Value::Text(address.role),
                        Value::Integer(address.position),
                        Value::Text(address.address),
                        text(address.name.as_deref()),
                    ]
                })
                .collect(),
        });
    }

    Ok(out)
}

/// Runs every expectation on `store`, naming each one it does not meet.
pub fn check(store: &Store, expectations: &[Expectation]) -> Result<Vec<String>> {
    let mut disagreements = Vec::new();

    for expectation in expectations {
        let params: Vec<(&str, &dyn ToSql)> = expectation
            .params
            .iter()
            .map(|(name, value)| (name.as_str(), value as &dyn ToSql))
            .collect();
        let rows = store.run(&expectation.statement, &params)?;
        let columns = &store.spec().statement(&expectation.statement)?.columns;

        let same = rows.len() == expectation.rows.len()
            && rows
                .iter()
                .zip(&expectation.rows)
                .all(|(got, want)| same_row(columns, got, want));
        if !same {
            disagreements.push(format!(
                "{} at {:?}: the store answers {:?}, the model {:?}",
                expectation.statement, expectation.params, rows, expectation.rows
            ));
        }
    }

    Ok(disagreements)
}

fn same_row(columns: &[String], got: &[Value], want: &[Value]) -> bool {
    got.len() == want.len()
        && columns
            .iter()
            .zip(got.iter().zip(want))
            .all(|(column, (got, want))| match (column.as_str(), got, want) {
                ("flags" | "base_flags", Value::Text(got), Value::Text(want)) => {
                    flag_set(got) == flag_set(want)
                }
                _ => got == want,
            })
}

fn flag_set(text: &str) -> Vec<&str> {
    let mut flags: Vec<&str> = text.split(' ').filter(|flag| !flag.is_empty()).collect();
    flags.sort_unstable();
    flags
}

fn row(item: &Item, columns: &[String], table: Option<Table>) -> Vec<Value> {
    columns
        .iter()
        .map(|column| match column.as_str() {
            "seq" => Value::Integer(item.seq),
            "link_id" => Value::Text(item.link_id.clone()),
            "flags" => match &item.flags {
                None => Value::Null,
                Some(flags) => Value::Text(flags.iter().cloned().collect::<Vec<_>>().join(" ")),
            },
            "object_hash" => text(item.object.as_ref().map(|name| name.0.as_str())),
            "sort_key" => Value::Text(item.sort_key.clone()),
            "level" => Value::Integer(item.level),
            column => match table {
                Some(table) if table == item.summary.table => item.summary.get(column),
                _ => Value::Null,
            },
        })
        .collect()
}

fn text(text: Option<&str>) -> Value {
    text.map_or(Value::Null, |text| Value::Text(String::from(text)))
}

#[cfg(test)]
mod tests {
    use std::{fs, path::PathBuf};

    use crate::{name::ObjectName, oracle, profile::Profile, spec::Spec, store::Store, writer};

    fn scratch(seed: u64) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "pimdir-generator-oracle-{}-{seed}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn the_reads_of_a_structure_store_answer_what_its_model_states() {
        let spec = Spec::load_default().unwrap();

        for seed in 0..4 {
            let model = Profile::Structure.generate(seed);
            let dir = scratch(seed);
            let store = Store::create(&spec, &dir).unwrap();
            writer::materialise(&model, &store).unwrap();

            let expectations = oracle::expectations(&model, &spec).unwrap();
            assert!(expectations.len() > 200, "seed {seed}");
            let disagreements = oracle::check(&store, &expectations).unwrap();
            assert!(disagreements.is_empty(), "seed {seed}: {disagreements:#?}");

            for (name, bytes) in &model.objects {
                let file = fs::read(dir.join(name.path())).unwrap();
                assert_eq!(&file, bytes);
                assert_eq!(&ObjectName::of(&file), name);
            }

            drop(store);
            fs::remove_dir_all(&dir).unwrap();
        }
    }
}
