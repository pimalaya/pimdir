//! # Capabilities and performers
//!
//! What `load_capabilities`, `load_item_capabilities`,
//! `list_capability_sources` and `load_performer` answer over a model's
//! declarations (STORAGE §15.6).

use std::{collections::BTreeSet, iter};

use rusqlite::types::Value;

use crate::{
    model::Capability,
    oracle::{Oracle, text},
};

impl Oracle<'_> {
    pub(crate) fn rights(&mut self) {
        let model = self.model;
        let effective = |source: &str, collection: &str| {
            let mut rows: Vec<&Capability> = model
                .capabilities
                .iter()
                .filter(|row| row.source == source)
                .filter(|row| match &row.collection {
                    Some(at) => at == collection,
                    None => !model.capabilities.iter().any(|other| {
                        other.source == row.source
                            && other.name == row.name
                            && other.collection.as_deref() == Some(collection)
                    }),
                })
                .collect();
            rows.sort_by(|a, b| a.name.cmp(&b.name));
            rows
        };
        let joined = |source: &str, collection: &str, held: Option<bool>| {
            let rows = effective(source, collection);
            let tail = |row: Option<&Capability>| {
                let mut cells = vec![
                    Value::Text(String::from(source)),
                    text(row.map(|row| row.name.as_str())),
                    text(row.map(|row| row.support.as_str())),
                    text(row.and_then(|row| row.detail.as_deref())),
                ];
                if let Some(held) = held {
                    cells.push(Value::Integer(i64::from(held)));
                }
                cells
            };
            match rows.is_empty() {
                true => vec![tail(None)],
                false => rows
                    .into_iter()
                    .map(|row| tail(Some(row)))
                    .collect::<Vec<_>>(),
            }
        };

        for id in model.collections.keys() {
            let rows = model
                .syncing(id)
                .into_iter()
                .flat_map(|source| joined(&source, id, None))
                .collect();
            self.expect(
                "load_capabilities",
                &[("collection", Value::Text(id.clone()))],
                rows,
            );
        }

        for item in &model.items {
            let rows = item
                .bindings
                .iter()
                .flat_map(|binding| {
                    joined(
                        &binding.source,
                        &item.collection,
                        Some(binding.base_present),
                    )
                })
                .collect();
            let params = [
                ("collection", Value::Text(item.collection.clone())),
                ("seq", Value::Integer(item.seq)),
            ];
            self.expect("load_item_capabilities", &params, rows);
        }

        let accounts: BTreeSet<Option<&String>> = model
            .collections
            .values()
            .map(|collection| collection.account.as_ref())
            .collect();
        let names: BTreeSet<&String> = model.capabilities.iter().map(|row| &row.name).collect();
        for account in &accounts {
            let anchors: Vec<Option<&String>> = iter::once(None)
                .chain(
                    model
                        .collections
                        .values()
                        .filter(|collection| collection.account.as_ref() == *account)
                        .map(|collection| Some(&collection.id)),
                )
                .collect();
            for name in &names {
                for anchor in &anchors {
                    let Some(rows) = candidates(&model.capabilities, *account, name, *anchor)
                    else {
                        continue;
                    };
                    let params = [
                        ("account", text(account.map(String::as_str))),
                        ("capability", Value::Text((*name).clone())),
                        ("collection", text(anchor.map(String::as_str))),
                    ];
                    self.expect("list_capability_sources", &params, rows);
                }

                let performer = model
                    .performers
                    .get(&(account.cloned(), (*name).clone()))
                    .map(|source| vec![Value::Text(source.clone())]);
                let params = [
                    ("account", text(account.map(String::as_str))),
                    ("capability", Value::Text((*name).clone())),
                ];
                self.expect("load_performer", &params, performer.into_iter().collect());
            }
        }
    }
}

/// The rows `list_capability_sources` answers, as its text reads, or none
/// when a source holds several qualifying rows, whose support the
/// statement's grouping picks among.
fn candidates(
    capabilities: &[Capability],
    account: Option<&String>,
    name: &str,
    collection: Option<&String>,
) -> Option<Vec<Vec<Value>>> {
    let some = |row: &&Capability| row.support != "none";
    let qualifying: Vec<&Capability> = capabilities
        .iter()
        .filter(|row| row.account.as_ref() == account && row.name == name)
        .filter(some)
        .filter(|row| {
            let wide_supported = capabilities.iter().any(|wide| {
                wide.source == row.source
                    && wide.name == row.name
                    && wide.collection.is_none()
                    && some(&wide)
            });
            let overridden = |at: &String| {
                capabilities.iter().any(|other| {
                    other.source == row.source
                        && other.name == row.name
                        && other.collection.as_ref() == Some(at)
                })
            };
            match collection {
                None => row.collection.is_none() || !wide_supported,
                Some(at) => {
                    row.collection.as_ref() == Some(at)
                        || (row.collection.is_none() && !overridden(at))
                }
            }
        })
        .collect();

    let mut sources: Vec<&String> = qualifying.iter().map(|row| &row.source).collect();
    sources.sort();
    let mut rows = Vec::new();
    for source in sources.iter().copied().collect::<BTreeSet<_>>() {
        let held: Vec<&&Capability> = qualifying
            .iter()
            .filter(|row| &row.source == source)
            .collect();
        if held.len() > 1 {
            return None;
        }
        rows.push(vec![
            Value::Text(source.clone()),
            Value::Text(held[0].support.clone()),
            text(held[0].detail.as_deref()),
        ]);
    }
    Some(rows)
}
