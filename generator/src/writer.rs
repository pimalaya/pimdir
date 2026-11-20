//! # The writer
//!
//! A model written into a store as its owner, through the canonical
//! statements alone, in the order GUIDE §5 runs them: the bodies first,
//! each through a temporary and a link that never replaces (GUIDE §4),
//! then one transaction declaring the collections and their sources,
//! storing the objects, naming each item (`seq_for_link_any`, else
//! `bump_next_seq`), writing its row, flags, summary, addresses and lists
//! and its binding, and settling the refcounts.
//!
//! Every `seq` the store draws is held to the model's: a disagreement is
//! the model and the statements reading STORAGE §9.1 two ways.

use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::Path,
};

use rusqlite::{ToSql, types::Value};

use crate::{
    error::{Error, Result},
    model::{Item, Model, Table, split_flags},
    name::ObjectName,
    store::{Store, create_private_dir},
};

/// Writes `model` into `store`, which holds nothing yet.
pub fn materialise(model: &Model, store: &Store) -> Result<()> {
    for (name, bytes) in &model.objects {
        write_blob(&store.dir, name, bytes)?;
    }

    store.begin()?;

    for collection in model.collections.values() {
        let account = text(collection.account.as_deref());
        let id = Value::Text(collection.id.clone());
        match collection.kind {
            Some(kind) => {
                let kind = Value::Text(String::from(kind.media_type()));
                run(
                    store,
                    "storage/owner/set_collection_kind",
                    &[("collection", &id), ("account", &account), ("kind", &kind)],
                )?;
            }
            None => run(
                store,
                "storage/queue/ensure_collection",
                &[("collection", &id), ("account", &account)],
            )?,
        }
        let name = Value::Text(collection.name.clone());
        run(
            store,
            "storage/owner/set_collection_name",
            &[("collection", &id), ("account", &account), ("name", &name)],
        )?;
        if let Some(role) = &collection.role {
            let role = Value::Text(role.clone());
            run(
                store,
                "storage/owner/set_collection_role",
                &[("collection", &id), ("role", &role)],
            )?;
        }
        if let Some(source) = &collection.source {
            let source = Value::Text(source.clone());
            let checkpoint = collection
                .checkpoint
                .clone()
                .map_or(Value::Null, Value::Blob);
            run(
                store,
                "storage/owner/upsert_checkpoint",
                &[
                    ("collection", &id),
                    ("source", &source),
                    ("checkpoint", &checkpoint),
                ],
            )?;
        }
    }

    for (name, bytes) in &model.objects {
        let hash = Value::Text(name.0.clone());
        let size = Value::Integer(bytes.len() as i64);
        run(
            store,
            "storage/queue/store_object",
            &[("hash", &hash), ("size", &size)],
        )?;
    }

    for item in &model.items {
        write_item(store, item)?;
    }

    store.run("storage/owner/recompute_refcounts", &[])?;
    store.commit()
}

fn write_item(store: &Store, item: &Item) -> Result<()> {
    let collection = Value::Text(item.collection.clone());
    let link_id = Value::Text(item.link_id.clone());

    let seq = draw_seq(store, item)?;
    if seq != item.seq {
        return Err(Error::Disagreement {
            what: format!("the seq of {} in {}", item.link_id, item.collection),
            detail: format!("the store draws {seq}, the model {}", item.seq),
        });
    }

    let (flags_known, marks, others) = flag_columns(item.flags.as_ref());
    let object = text(item.object.as_ref().map(|name| name.0.as_str()));
    run(
        store,
        "storage/owner/insert_item",
        &[
            ("collection", &collection),
            ("link_id", &link_id),
            ("seq", &Value::Integer(seq)),
            ("flags_known", &flags_known),
            ("marks", &marks),
            ("object_hash", &object),
            ("sort_key", &Value::Text(item.sort_key.clone())),
            ("level", &Value::Integer(item.level)),
            ("deleted", &Value::Integer(i64::from(item.deleted))),
            ("conflicted", &Value::Integer(0)),
            ("conflict_object", &Value::Null),
        ],
    )?;
    if !others.is_empty() {
        store.bind_slot("flags", &others)?;
        let key = [
            ("collection", &collection as &dyn ToSql),
            ("link_id", &link_id),
        ];
        store.run("storage/owner/retain_flags", &key)?;
        store.run("storage/owner/add_flags", &key)?;
    }

    write_summary(store, item, &collection, &link_id)?;

    if let Some(binding) = &item.binding {
        let source = Value::Text(binding.source.clone());
        let (base_flags_known, base_marks, base_others) = flag_columns(binding.base_flags.as_ref());
        let name = |name: &Option<ObjectName>| text(name.as_ref().map(|name| name.0.as_str()));
        run(
            store,
            "storage/owner/insert_binding",
            &[
                ("collection", &collection),
                ("link_id", &link_id),
                ("source", &source),
                ("handle", &Value::Text(binding.handle.clone())),
                ("base_flags_known", &base_flags_known),
                ("base_marks", &base_marks),
                ("base_object", &name(&binding.base_object)),
                ("base_revision", &text(binding.base_revision.as_deref())),
                ("base_present", &Value::Integer(1)),
                ("conflicted", &Value::Integer(0)),
                ("conflict_revision", &Value::Null),
                ("conflict_object", &Value::Null),
                ("shared_object", &name(&binding.shared_object)),
            ],
        )?;
        if !base_others.is_empty() {
            store.bind_slot("flags", &base_others)?;
            let key = [
                ("collection", &collection as &dyn ToSql),
                ("link_id", &link_id),
                ("source", &source),
            ];
            store.run("storage/owner/retain_base_flags", &key)?;
            store.run("storage/owner/add_base_flags", &key)?;
        }
    }

    Ok(())
}

fn draw_seq(store: &Store, item: &Item) -> Result<i64> {
    let derived = ["alt:", "hash:", "dup:"]
        .iter()
        .any(|prefix| item.link_id.starts_with(prefix));

    if !derived {
        let mail = |column: &str| match item.summary.table {
            Table::Mail => item.summary.get(column),
            _ => Value::Null,
        };
        let rows = run_rows(
            store,
            "storage/owner/seq_for_link_any",
            &[
                ("collection", &Value::Text(item.collection.clone())),
                ("link_id", &Value::Text(item.link_id.clone())),
                ("subject", &mail("subject")),
                ("date", &mail("date")),
                ("sender", &mail("sender")),
            ],
        )?;
        if let Some(Value::Integer(seq)) = rows.first().and_then(|row| row.first()) {
            return Ok(*seq);
        }
    }

    let rows = store.run("storage/owner/bump_next_seq", &[])?;
    match rows.first().and_then(|row| row.first()) {
        Some(Value::Integer(seq)) => Ok(*seq),
        _ => Err(Error::Disagreement {
            what: String::from("bump_next_seq"),
            detail: String::from("it answered no seq"),
        }),
    }
}

fn write_summary(store: &Store, item: &Item, collection: &Value, link_id: &Value) -> Result<()> {
    let summary = &item.summary;
    let name = format!("storage/owner/upsert_{}_summary", summary.table.stem());
    let statement = store.spec().statement(&name)?;

    let mut values = Vec::new();
    for parameter in &statement.parameters {
        let value = match parameter.as_str() {
            "collection" => collection.clone(),
            "link_id" => link_id.clone(),
            column => match summary.columns.get(column) {
                Some(value) => value.clone(),
                None => {
                    return Err(Error::Parameters {
                        statement: name,
                        detail: format!("the model states no column {column}"),
                    });
                }
            },
        };
        values.push((parameter.as_str(), value));
    }
    let bound: Vec<(&str, &dyn ToSql)> = values
        .iter()
        .map(|(name, value)| (*name, value as &dyn ToSql))
        .collect();
    store.run(&name, &bound)?;

    let key = [
        ("collection", collection as &dyn ToSql),
        ("link_id", link_id),
    ];
    store.run("storage/owner/replace_addresses", &key)?;
    for address in &item.addresses {
        run(
            store,
            "storage/owner/insert_address",
            &[
                ("collection", collection),
                ("link_id", link_id),
                ("role", &Value::Text(address.role.clone())),
                ("position", &Value::Integer(address.position)),
                ("address", &Value::Text(address.address.clone())),
                ("name", &text(address.name.as_deref())),
            ],
        )?;
    }

    if summary.table == Table::Mail {
        store.run("storage/owner/replace_in_reply_to", &key)?;
        for (position, id) in summary.in_reply_to.iter().enumerate() {
            run(
                store,
                "storage/owner/insert_in_reply_to",
                &[
                    ("collection", collection),
                    ("link_id", link_id),
                    ("position", &Value::Integer(position as i64)),
                    ("message_id", &Value::Text(id.clone())),
                ],
            )?;
        }
    }

    if summary.table == Table::Task {
        store.run("storage/owner/replace_categories", &key)?;
        for (position, value) in summary.categories.iter().enumerate() {
            run(
                store,
                "storage/owner/insert_category",
                &[
                    ("collection", collection),
                    ("link_id", link_id),
                    ("position", &Value::Integer(position as i64)),
                    ("value", &Value::Text(value.clone())),
                ],
            )?;
        }
    }

    Ok(())
}

fn flag_columns(flags: Option<&std::collections::BTreeSet<String>>) -> (Value, Value, Vec<Value>) {
    match flags {
        None => (Value::Integer(0), Value::Integer(0), Vec::new()),
        Some(flags) => {
            let (marks, others) = split_flags(flags);
            (
                Value::Integer(1),
                Value::Integer(marks),
                others.into_iter().map(Value::Text).collect(),
            )
        }
    }
}

fn run(store: &Store, name: &str, params: &[(&str, &Value)]) -> Result<()> {
    run_rows(store, name, params).map(|_| ())
}

fn run_rows(store: &Store, name: &str, params: &[(&str, &Value)]) -> Result<Vec<Vec<Value>>> {
    let bound: Vec<(&str, &dyn ToSql)> = params
        .iter()
        .map(|(name, value)| (*name, *value as &dyn ToSql))
        .collect();
    store.run(name, &bound)
}

fn text(text: Option<&str>) -> Value {
    text.map_or(Value::Null, |text| Value::Text(String::from(text)))
}

fn write_blob(dir: &Path, name: &ObjectName, bytes: &[u8]) -> Result<()> {
    let io = |path: &Path| {
        let path = path.to_path_buf();
        move |source| Error::Io { path, source }
    };

    let objects = dir.join("objects");
    let shard = objects.join(&name.0[..2]);
    let created = !shard.exists();
    if created {
        create_private_dir(&shard)?;
    }

    let target = dir.join(name.path());
    let temporary = shard.join(format!(".{}-{}", std::process::id(), &name.0[..8]));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)
        .map_err(io(&temporary))?;
    file.write_all(bytes).map_err(io(&temporary))?;
    file.sync_all().map_err(io(&temporary))?;

    let linked = fs::hard_link(&temporary, &target);
    fs::remove_file(&temporary).map_err(io(&temporary))?;
    linked.map_err(io(&target))?;

    File::open(&shard)
        .and_then(|shard| shard.sync_all())
        .map_err(io(&shard))?;
    if created {
        File::open(&objects)
            .and_then(|objects| objects.sync_all())
            .map_err(io(&objects))?;
    }
    Ok(())
}
