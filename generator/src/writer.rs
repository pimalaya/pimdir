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
    collections::BTreeSet,
    fs::{self, File, OpenOptions},
    io::Write,
    path::Path,
    process,
};

use rusqlite::{ToSql, types::Value};

use crate::{
    error::{Error, Result},
    model::{Collection, Item, Model, State, Table, split_flags},
    name::ObjectName,
    queue::{Row, RowState},
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

    let sources: BTreeSet<&String> = model.capabilities.iter().map(|row| &row.source).collect();
    for source in sources {
        let source_value = Value::Text(source.clone());
        run(
            store,
            "storage/owner/delete_capabilities",
            &[("source", &source_value)],
        )?;
        for row in model
            .capabilities
            .iter()
            .filter(|row| &row.source == source)
        {
            run(
                store,
                "storage/owner/set_capability",
                &[
                    ("account", &text(row.account.as_deref())),
                    ("source", &source_value),
                    ("collection", &text(row.collection.as_deref())),
                    ("capability", &Value::Text(row.name.clone())),
                    ("support", &Value::Text(row.support.clone())),
                    ("detail", &text(row.detail.as_deref())),
                ],
            )?;
        }
    }
    for ((account, capability), source) in &model.performers {
        run(
            store,
            "storage/owner/set_performer",
            &[
                ("account", &text(account.as_deref())),
                ("capability", &Value::Text(capability.clone())),
                ("source", &Value::Text(source.clone())),
            ],
        )?;
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

    for collection in model.collections.values() {
        write_rounds(store, model, collection)?;
    }

    for reference in &model.references {
        let answered = run_rows(
            store,
            "storage/owner/add_reference",
            &[
                (
                    "from_kind",
                    &Value::Text(String::from(reference.from_kind.media_type())),
                ),
                ("from_link_id", &Value::Text(reference.from_link_id.clone())),
                (
                    "to_kind",
                    &Value::Text(String::from(reference.to_kind.media_type())),
                ),
                ("to_link_id", &Value::Text(reference.to_link_id.clone())),
                ("role", &Value::Text(reference.role.clone())),
                ("origin", &Value::Text(reference.origin.clone())),
            ],
        )?;
        if answered.is_empty() {
            return Err(Error::Disagreement {
                what: format!(
                    "the reference {} to {}",
                    reference.from_link_id, reference.to_link_id
                ),
                detail: String::from("add_reference records nothing the model holds"),
            });
        }
    }

    for row in &model.queue {
        write_row(store, model, row)?;
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
    let object = name(&item.object);
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
            (
                "deleted",
                &Value::Integer(i64::from(item.state != State::Live)),
            ),
            ("conflicted", &Value::Integer(i64::from(item.conflicted))),
            ("conflict_object", &name(&item.conflict_object)),
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
                (
                    "base_present",
                    &Value::Integer(i64::from(binding.base_present)),
                ),
                ("conflicted", &Value::Integer(i64::from(binding.conflicted))),
                (
                    "conflict_revision",
                    &text(binding.conflict_revision.as_deref()),
                ),
                ("conflict_object", &name(&binding.conflict_object)),
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
        if let Some(refusal) = &binding.refusal {
            run(
                store,
                "storage/owner/refuse_binding",
                &[
                    ("reason", &Value::Text(refusal.reason.clone())),
                    ("key", &Value::Text(refusal.key.clone())),
                    ("collection", &collection),
                    ("source", &source),
                    ("handle", &Value::Text(binding.handle.clone())),
                ],
            )?;
        }
    }

    if let State::Retained { by } = &item.state {
        run(
            store,
            "storage/owner/retain_item",
            &[
                ("collection", &collection),
                ("link_id", &link_id),
                ("source", &text(by.as_deref())),
            ],
        )?;
    }

    Ok(())
}

/// Replays the rounds a collection's source closed, each opened, its
/// handles stamped and closed in turn, so the round ids, the stamps and
/// the coverage stand as the model holds them (STORAGE §4.3, SYNC §5). The
/// checkpoint the declaration wrote is kept, a round closing with none.
fn write_rounds(store: &Store, model: &Model, collection: &Collection) -> Result<()> {
    let Some(source) = &collection.source else {
        return Ok(());
    };
    let id = Value::Text(collection.id.clone());
    let source = Value::Text(source.clone());

    for round in 1..=collection.rounds {
        run(
            store,
            "storage/owner/open_round",
            &[
                ("collection", &id),
                ("source", &source),
                ("since", &Value::Null),
                ("until", &Value::Null),
                ("band", &Value::Integer(0)),
            ],
        )?;
        let handles: Vec<Value> = model
            .items
            .iter()
            .filter(|item| item.collection == collection.id)
            .filter_map(|item| item.binding.as_ref())
            .filter(|binding| binding.round == Some(round))
            .map(|binding| Value::Text(binding.handle.clone()))
            .collect();
        store.bind_slot("handles", &handles)?;
        run(
            store,
            "storage/owner/stamp_bindings",
            &[("collection", &id), ("source", &source)],
        )?;
        run(
            store,
            "storage/owner/close_round",
            &[
                ("checkpoint", &Value::Null),
                ("since", &Value::Null),
                ("until", &Value::Null),
                ("collection", &id),
                ("source", &source),
            ],
        )?;
    }

    Ok(())
}

fn write_row(store: &Store, model: &Model, row: &Row) -> Result<()> {
    let collection = Value::Text(row.collection.clone());
    let account = text(model.collections[&row.collection].account.as_deref());
    run(
        store,
        "storage/queue/ensure_collection",
        &[("collection", &collection), ("account", &account)],
    )?;

    let object = row.action.body().map(ObjectName::of);
    if let Some(object) = &object {
        let hash = Value::Text(object.0.clone());
        run(store, "storage/queue/pin_object", &[("hash", &hash)])?;
    }
    run(
        store,
        "storage/queue/enqueue_action",
        &[
            ("producer", &Value::Text(row.producer.clone())),
            ("collection", &collection),
            ("action", &Value::Text(String::from(row.action.name()))),
            ("payload", &Value::Text(row.action.payload())),
            ("target_collection", &text(row.action.target())),
            ("object_hash", &name(&object)),
        ],
    )?;
    let id = store.last_insert_rowid();
    if id != row.id {
        return Err(Error::Disagreement {
            what: String::from("a queue row's id"),
            detail: format!("the store draws {id}, the model {}", row.id),
        });
    }

    let id = Value::Integer(id);
    match &row.state {
        RowState::Pending => {}
        RowState::Parked(error) => run(
            store,
            "storage/owner/park_action",
            &[("error", &Value::Text(error.clone())), ("id", &id)],
        )?,
        RowState::Unconfirmed(detail) => {
            let answered = run_rows(
                store,
                "storage/owner/unconfirm_action",
                &[("detail", &Value::Text(detail.clone())), ("id", &id)],
            )?;
            if answered.is_empty() {
                return Err(Error::Disagreement {
                    what: format!("unconfirm_action on row {}", row.id),
                    detail: format!("it refuses a {} row", row.action.name()),
                });
            }
        }
        RowState::Applied(seq) => {
            run(store, "storage/owner/claim_action", &[("id", &id)])?;
            let seq = seq.map_or(Value::Null, Value::Integer);
            run(
                store,
                "storage/owner/record_receipt",
                &[("id", &id), ("collection", &collection), ("seq", &seq)],
            )?;
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

fn flag_columns(flags: Option<&BTreeSet<String>>) -> (Value, Value, Vec<Value>) {
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

fn name(name: &Option<ObjectName>) -> Value {
    text(name.as_ref().map(|name| name.0.as_str()))
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
    let temporary = shard.join(format!(".{}-{}", process::id(), &name.0[..8]));
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
