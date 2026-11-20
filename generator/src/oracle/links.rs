//! # References and attachments
//!
//! What `references_from`, `references_to`, `list_attachments` and
//! `list_attachments_by_account` answer over a model's references and the
//! stand-ins of its messages' parts (STORAGE §14.2, §14.3).

use std::collections::BTreeSet;

use rusqlite::types::Value;

use crate::{
    model::{Item, Kind, Reference, State},
    oracle::{INSTANT, Oracle, PAGE, pages, text},
};

impl Oracle<'_> {
    pub(crate) fn links(&mut self) {
        let model = self.model;
        let row = |reference: &Reference| {
            vec![
                Value::Text(String::from(reference.from_kind.media_type())),
                Value::Text(reference.from_link_id.clone()),
                Value::Text(String::from(reference.to_kind.media_type())),
                Value::Text(reference.to_link_id.clone()),
                Value::Text(reference.role.clone()),
                Value::Text(reference.origin.clone()),
                Value::Text(String::from(INSTANT)),
            ]
        };

        let ends: BTreeSet<(Kind, &String)> = model
            .items
            .iter()
            .filter_map(|item| {
                let kind = model.collections[&item.collection].kind?;
                Some((kind, &item.link_id))
            })
            .collect();
        for (kind, link_id) in ends {
            let params = [
                ("kind", Value::Text(String::from(kind.media_type()))),
                ("link_id", Value::Text(link_id.clone())),
            ];
            let mut from: Vec<&Reference> = model
                .references
                .iter()
                .filter(|reference| {
                    reference.from_kind == kind && &reference.from_link_id == link_id
                })
                .collect();
            from.sort_by(|a, b| {
                (&a.to_link_id, a.to_kind.media_type(), &a.role).cmp(&(
                    &b.to_link_id,
                    b.to_kind.media_type(),
                    &b.role,
                ))
            });
            self.expect(
                "references_from",
                &params,
                from.into_iter().map(row).collect(),
            );

            let mut to: Vec<&Reference> = model
                .references
                .iter()
                .filter(|reference| reference.to_kind == kind && &reference.to_link_id == link_id)
                .collect();
            to.sort_by(|a, b| {
                (&a.from_link_id, a.from_kind.media_type(), &a.role).cmp(&(
                    &b.from_link_id,
                    b.from_kind.media_type(),
                    &b.role,
                ))
            });
            self.expect("references_to", &params, to.into_iter().map(row).collect());
        }

        let account_of = |item: &Item| model.collections[&item.collection].account.clone();
        let kind_of = |item: &Item| model.collections[&item.collection].kind;
        let live = |item: &&Item| item.state == State::Live;
        let attachments = |message: &str| -> Vec<&Reference> {
            model
                .references
                .iter()
                .filter(|reference| {
                    reference.from_kind == Kind::Mail
                        && reference.from_link_id == message
                        && reference.role == "attachment"
                        && reference.to_kind == Kind::File
                })
                .collect()
        };

        let accounts: BTreeSet<Option<String>> = model
            .collections
            .values()
            .map(|collection| collection.account.clone())
            .collect();
        let messages: BTreeSet<&String> = model
            .items
            .iter()
            .filter(|item| kind_of(item) == Some(Kind::Mail))
            .map(|item| &item.link_id)
            .collect();
        for account in &accounts {
            for message in &messages {
                let mut rows: Vec<(i64, String, Vec<Value>)> = Vec::new();
                for reference in attachments(message) {
                    let stand_in = model.items.iter().filter(live).find(|item| {
                        item.link_id == reference.to_link_id
                            && kind_of(item) == Some(Kind::File)
                            && &account_of(item) == account
                    });
                    let Some(stand_in) = stand_in else {
                        continue;
                    };
                    let saved = model
                        .items
                        .iter()
                        .filter(live)
                        .find(|item| {
                            item.link_id == reference.to_link_id
                                && item.object.is_some()
                                && kind_of(item) == Some(Kind::File)
                                && &account_of(item) == account
                        })
                        .and_then(|item| item.object.as_ref().map(|name| name.0.clone()));
                    rows.push((
                        stand_in.seq,
                        stand_in.link_id.clone(),
                        vec![
                            Value::Text(stand_in.link_id.clone()),
                            Value::Text(stand_in.collection.clone()),
                            Value::Integer(stand_in.seq),
                            stand_in.summary.get("name"),
                            stand_in.summary.get("media_type"),
                            stand_in.summary.get("size"),
                            stand_in.summary.get("part"),
                            text(saved.as_deref()),
                        ],
                    ));
                }
                rows.sort_by(|a, b| (a.0, &a.1).cmp(&(b.0, &b.1)));
                let params = [
                    ("account", text(account.as_deref())),
                    ("link_id", Value::Text((*message).clone())),
                ];
                let rows = rows.into_iter().map(|(_, _, row)| row).collect();
                self.expect("list_attachments", &params, rows);
            }

            let mut listed: Vec<(&Item, &Item)> = Vec::new();
            for stand_in in model.items.iter().filter(live) {
                let collection = &model.collections[&stand_in.collection];
                if &collection.account != account
                    || collection.kind != Some(Kind::File)
                    || collection.role.as_deref() != Some("attachments")
                {
                    continue;
                }
                for reference in model.references.iter().filter(|reference| {
                    reference.to_link_id == stand_in.link_id
                        && reference.to_kind == Kind::File
                        && reference.role == "attachment"
                        && reference.from_kind == Kind::Mail
                }) {
                    let message = model.items.iter().filter(live).find(|item| {
                        item.link_id == reference.from_link_id && kind_of(item) == Some(Kind::Mail)
                    });
                    if let Some(message) = message {
                        listed.push((stand_in, message));
                    }
                }
            }
            listed.sort_by(|(a, m), (b, n)| (&n.sort_key, b.seq).cmp(&(&m.sort_key, a.seq)));
            let mut after = (Value::Null, Value::Null);
            for page in pages(&listed) {
                let params = [
                    ("account", text(account.as_deref())),
                    ("after_key", after.0.clone()),
                    ("after_seq", after.1.clone()),
                    ("limit", Value::Integer(PAGE)),
                ];
                let rows = page
                    .iter()
                    .map(|(stand_in, message)| {
                        vec![
                            Value::Text(stand_in.collection.clone()),
                            Value::Integer(stand_in.seq),
                            Value::Text(stand_in.link_id.clone()),
                            stand_in.summary.get("name"),
                            stand_in.summary.get("media_type"),
                            stand_in.summary.get("size"),
                            stand_in.summary.get("part"),
                            Value::Text(message.link_id.clone()),
                            Value::Text(message.collection.clone()),
                            Value::Integer(message.seq),
                            Value::Text(message.sort_key.clone()),
                            message.summary.get("sender"),
                            message.summary.get("sender_name"),
                            message.summary.get("date"),
                        ]
                    })
                    .collect();
                self.expect("list_attachments_by_account", &params, rows);
                if let Some((stand_in, message)) = page.last() {
                    after = (
                        Value::Text(message.sort_key.clone()),
                        Value::Integer(stand_in.seq),
                    );
                }
            }
        }
    }
}
