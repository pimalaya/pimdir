//! # The oracle
//!
//! What each read statement answers over the store a model leaves, stated
//! from the model alone as an [`Expectation`] per statement and parameter
//! point (STORAGE §14.1): the collections and their sources, each
//! collection's counts and listings walked page by page under their keyset
//! cursors, every item by its `seq` and its key, its bindings and lists,
//! the trash, the identities and bodies held in several places, the mail
//! of each account counted and merged, and the people items name.
//!
//! [`check`] runs them on a store and names each disagreement: the
//! self-check of README.md, holding the writer to the statements and the
//! model to the store.

pub mod feed;
mod links;
mod rights;
mod search;

use std::{
    collections::{BTreeMap, BTreeSet},
    iter,
};

use rusqlite::{ToSql, types::Value};

use crate::{
    error::{Error, Result},
    model::{Binding, Collection, Item, Kind, MARKS, Model, Refusal, Scope, State, Table},
    name::ObjectName,
    queue::{Action, RowState},
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
    /// The list slot it reads and the values bound there, if any.
    pub slot: Option<(String, Vec<Value>)>,
    /// The rows it answers.
    pub rows: Vec<Vec<Value>>,
    /// Whether its order is total, so the rows compare as a list; a
    /// statement ordering by part of a row compares them as a multiset.
    pub ordered: bool,
}

/// The page size the listings are walked at, small so every listing of the
/// structure profile spans several pages.
pub const PAGE: i64 = 3;

/// The columns SQLite stamps with the instant of the write, compared by
/// their presence and shape alone (STORAGE §13).
pub const INSTANTS: [&str; 6] = [
    "created_at",
    "retained_at",
    "applied_at",
    "refused_at",
    "covered_at",
    "round_started_at",
];

/// The marker the model states for an instant SQLite stamps.
pub const INSTANT: &str = "instant";

/// The marker the model states for a change stamp (STORAGE §4.5).
pub const STAMP: &str = "stamp";

/// The marker the model states for the store's id.
pub const STORE_ID: &str = "store id";

/// Every expectation the model states over the reads it covers.
pub fn expectations(model: &Model, spec: &Spec) -> Result<Vec<Expectation>> {
    let mut oracle = Oracle {
        model,
        spec,
        page: PAGE,
        out: Vec::new(),
        store: None,
        disagreements: Vec::new(),
        failure: None,
    };
    oracle.state()?;
    Ok(oracle.out)
}

/// Runs every expectation the model states on `store` as it is stated,
/// none held but the one stated last, pages `page` rows long: a store of
/// the count profile, whose expectations would not fit in memory at once.
/// Names each one the store does not meet, as [`check`] does.
pub fn check_model(store: &Store, model: &Model, spec: &Spec, page: i64) -> Result<Vec<String>> {
    let mut oracle = Oracle {
        model,
        spec,
        page,
        out: Vec::new(),
        store: Some(store),
        disagreements: Vec::new(),
        failure: None,
    };
    oracle.state()?;
    oracle.flush();
    match oracle.failure {
        Some(error) => Err(error),
        None => Ok(oracle.disagreements),
    }
}

impl Oracle<'_> {
    fn state(&mut self) -> Result<()> {
        let model = self.model;
        let oracle = self;
        oracle.collections()?;
        for id in model.collections.keys() {
            oracle.collection(id)?;
        }
        for item in &model.items {
            oracle.item(item)?;
        }
        oracle.identities();
        oracle.mail()?;
        oracle.people();
        oracle.conflicts();
        oracle.queue();
        oracle.rights();
        oracle.links();
        oracle.feed();
        oracle.searches()?;
        Ok(())
    }
}

/// Runs every expectation on `store`, naming each one it does not meet.
pub fn check(store: &Store, expectations: &[Expectation]) -> Result<Vec<String>> {
    let mut disagreements = Vec::new();
    for expectation in expectations {
        disagreements.extend(check_one(store, expectation)?);
    }
    Ok(disagreements)
}

/// Runs one expectation on `store`, naming it when it is not met.
fn check_one(store: &Store, expectation: &Expectation) -> Result<Option<String>> {
    {
        if let Some((slot, values)) = &expectation.slot {
            store.bind_slot(slot, values)?;
        }
        let params: Vec<(&str, &dyn ToSql)> = expectation
            .params
            .iter()
            .map(|(name, value)| (name.as_str(), value as &dyn ToSql))
            .collect();
        let mut rows = store.run(&expectation.statement, &params)?;
        let columns = &store.spec().statement(&expectation.statement)?.columns;

        let mut want = expectation.rows.clone();
        for row in rows.iter_mut().chain(want.iter_mut()) {
            normalise(columns, row);
        }
        if !expectation.ordered {
            rows.sort_by_key(|row| format!("{row:?}"));
            want.sort_by_key(|row| format!("{row:?}"));
        }
        let same = rows.len() == want.len()
            && rows
                .iter()
                .zip(&want)
                .all(|(got, want)| same_row(columns, got, want));
        if !same {
            return Ok(Some(format!(
                "{} at {:?} {:?}: the store answers {:?}, the model {:?}",
                expectation.statement, expectation.params, expectation.slot, rows, want
            )));
        }
    }

    Ok(None)
}

struct Oracle<'a> {
    model: &'a Model,
    spec: &'a Spec,
    /// The rows a listing's page holds.
    page: i64,
    out: Vec<Expectation>,
    /// The store each expectation runs on as it is stated, if any.
    store: Option<&'a Store<'a>>,
    disagreements: Vec<String>,
    failure: Option<Error>,
}

impl Oracle<'_> {
    /// Runs the expectation stated last on the store, if one runs them as
    /// they are stated, and lets it go.
    fn flush(&mut self) {
        let Some(store) = self.store else {
            return;
        };
        for expectation in self.out.drain(..) {
            if self.failure.is_some() {
                break;
            }
            match check_one(store, &expectation) {
                Ok(found) => self.disagreements.extend(found),
                Err(error) => self.failure = Some(error),
            }
        }
    }

    fn expect(&mut self, statement: &str, params: &[(&str, Value)], rows: Vec<Vec<Value>>) {
        self.flush();
        self.out.push(Expectation {
            statement: match statement.contains('/') {
                true => String::from(statement),
                false => format!("storage/read/{statement}"),
            },
            params: params
                .iter()
                .map(|(name, value)| (String::from(*name), value.clone()))
                .collect(),
            slot: None,
            rows,
            ordered: true,
        });
    }

    fn last(&mut self) -> &mut Expectation {
        let at = self.out.len() - 1;
        &mut self.out[at]
    }

    fn columns(&self, statement: &str) -> Result<Vec<String>> {
        Ok(self
            .spec
            .statement(&format!("storage/read/{statement}"))?
            .columns
            .clone())
    }

    fn collections(&mut self) -> Result<()> {
        let model = self.model;
        let row = |id: &str| {
            let collection = &model.collections[id];
            let mut row = vec![
                Value::Text(collection.id.clone()),
                text(collection.account.as_deref()),
                Value::Text(String::from(
                    collection.kind.map_or("", |kind| kind.media_type()),
                )),
                Value::Text(collection.name.clone()),
                text(collection.parent.as_deref()),
                text(collection.presentation.color.as_deref()),
                text(collection.presentation.description.as_deref()),
                collection
                    .presentation
                    .sort_order
                    .map_or(Value::Null, Value::Integer),
                Value::Integer(collection.generation),
                text(collection.role.as_deref()),
            ];
            row.extend(covered(collection));
            row
        };

        let mut listed: Vec<&Collection> = model.collections.values().collect();
        listed.sort_by_key(|collection| {
            let order = collection.presentation.sort_order;
            (order.is_none(), order, collection.id.as_str())
        });
        let all = listed
            .iter()
            .map(|collection| row(&collection.id))
            .collect();
        self.expect("list_collections", &[], all);

        let accounts: BTreeSet<Option<&String>> = model
            .collections
            .values()
            .map(|collection| collection.account.as_ref())
            .collect();
        for account in &accounts {
            let rows = listed
                .iter()
                .filter(|collection| collection.account.as_ref() == *account)
                .map(|collection| row(&collection.id))
                .collect();
            let account = text(account.map(String::as_str));
            self.expect("list_collections_by_account", &[("account", account)], rows);
        }
        let named = accounts
            .into_iter()
            .flatten()
            .map(|account| vec![Value::Text(account.clone())])
            .collect();
        self.expect("list_accounts", &[], named);

        let sources: BTreeSet<&String> = model
            .items
            .iter()
            .flat_map(|item| item.bindings.iter().map(|binding| &binding.source))
            .collect();
        let rows = sources
            .into_iter()
            .map(|source| vec![Value::Text(source.clone())])
            .collect();
        self.expect("list_sources", &[], rows);

        Ok(())
    }

    fn collection(&mut self, id: &str) -> Result<()> {
        let model = self.model;
        let collection = &model.collections[id];
        let key = [("collection", Value::Text(String::from(id)))];

        let kind = collection.kind.map_or("", |kind| kind.media_type());
        self.expect(
            "load_kind",
            &key,
            vec![vec![Value::Text(String::from(kind))]],
        );
        let account = text(collection.account.as_deref());
        self.expect("load_account", &key, vec![vec![account]]);
        let conflict = Value::Text(collection.conflict.clone());
        self.expect("storage/owner/load_conflict", &key, vec![vec![conflict]]);
        let generation = Value::Integer(collection.generation);
        self.expect("load_generation", &key, vec![vec![generation]]);
        let instant = |held: bool| match held {
            false => Value::Null,
            true => Value::Text(String::from(INSTANT)),
        };
        let coverage = collection
            .sources
            .iter()
            .map(|(source, sync)| {
                let (since, until) = sync.coverage.clone().unwrap_or_default().values();
                let (round_since, round_until) = sync
                    .open
                    .as_ref()
                    .map(|open| open.scope.clone())
                    .unwrap_or_default()
                    .values();
                vec![
                    Value::Text(source.clone()),
                    since,
                    until,
                    instant(sync.coverage.is_some()),
                    instant(sync.open.is_some()),
                    round_since,
                    round_until,
                ]
            })
            .collect();
        self.expect("list_coverage", &key, coverage);
        for (source, sync) in &collection.sources {
            let mut params = key.to_vec();
            params.push(("source", Value::Text(source.clone())));
            let (since, until) = sync
                .open
                .as_ref()
                .map(|open| open.scope.clone())
                .unwrap_or_default()
                .values();
            let cursor = sync
                .open
                .as_ref()
                .and_then(|open| open.cursor.clone())
                .map_or(Value::Null, |cursor| Value::Blob(cursor.into_bytes()));
            let checkpoint = sync
                .open
                .as_ref()
                .and_then(|open| open.checkpoint.clone())
                .map_or(Value::Null, Value::Blob);
            let row = vec![
                Value::Integer(sync.rounds),
                instant(sync.open.is_some()),
                since,
                until,
                cursor,
                checkpoint,
                Value::Integer(i64::from(sync.open.as_ref().is_some_and(|open| open.band))),
            ];
            self.expect("storage/owner/load_round", &params, vec![row]);
        }

        let rows: Vec<&Item> = model
            .items
            .iter()
            .filter(|item| item.collection == id)
            .collect();
        let live: Vec<&Item> = rows
            .iter()
            .copied()
            .filter(|item| item.state == State::Live)
            .collect();
        let deleted: Vec<&Item> = rows
            .iter()
            .copied()
            .filter(|item| item.state != State::Live)
            .collect();

        self.expect(
            "count_items",
            &key,
            vec![vec![Value::Integer(live.len() as i64)]],
        );
        self.expect(
            "count_retained",
            &key,
            vec![vec![Value::Integer(deleted.len() as i64)]],
        );

        let mut listings = vec![
            ("list_items_page_asc", None, false),
            ("list_items_page_desc", None, true),
        ];
        match collection.kind {
            Some(Kind::Mail) => listings.push(("list_mail_page_desc", Some(Table::Mail), true)),
            Some(Kind::Contact) => {
                listings.push(("list_contacts_page_asc", Some(Table::Contact), false))
            }
            Some(Kind::Calendar) => {
                listings.push(("list_events_page_asc", Some(Table::Event), false));
                listings.push(("list_tasks_page_asc", Some(Table::Task), false));
                listings.push(("list_journals_page_asc", Some(Table::Journal), false));
            }
            Some(Kind::File) => listings.push(("list_files_page_asc", Some(Table::File), false)),
            None => {}
        }
        for (name, table, descending) in listings {
            let columns = self.columns(name)?;
            let mut sorted = live.clone();
            sorted.sort_by(|a, b| {
                let order = (a.sort_key.as_str(), a.seq).cmp(&(b.sort_key.as_str(), b.seq));
                if descending { order.reverse() } else { order }
            });
            let mut after = (Value::Null, Value::Null);
            for page in pages(&sorted, self.page) {
                let params = [
                    ("collection", Value::Text(String::from(id))),
                    ("after_key", after.0.clone()),
                    ("after_seq", after.1.clone()),
                    ("limit", Value::Integer(self.page)),
                ];
                let rows = page.iter().map(|item| row(item, &columns, table)).collect();
                self.expect(name, &params, rows);
                if let Some(last) = page.last() {
                    after = (Value::Text(last.sort_key.clone()), Value::Integer(last.seq));
                }
            }
        }

        let columns = self.columns("list_items_page")?;
        let mut by_link = live.clone();
        by_link.sort_by(|a, b| a.link_id.cmp(&b.link_id));
        let mut after = Value::Null;
        for page in pages(&by_link, self.page) {
            let params = [
                ("collection", Value::Text(String::from(id))),
                ("after", after.clone()),
                ("limit", Value::Integer(self.page)),
            ];
            let rows = page.iter().map(|item| row(item, &columns, None)).collect();
            self.expect("list_items_page", &params, rows);
            if let Some(last) = page.last() {
                after = Value::Text(last.link_id.clone());
            }
        }

        let columns = self.columns("list_retained_page")?;
        let mut by_seq = deleted.clone();
        by_seq.sort_by_key(|item| item.seq);
        let mut after = Value::Null;
        for page in pages(&by_seq, self.page) {
            let params = [
                ("collection", Value::Text(String::from(id))),
                ("after", after.clone()),
                ("limit", Value::Integer(self.page)),
            ];
            let rows = page
                .iter()
                .map(|item| {
                    columns
                        .iter()
                        .map(|column| match column.as_str() {
                            "retained_at" => match item.state {
                                State::Retained { .. } => Value::Text(String::from(INSTANT)),
                                _ => Value::Null,
                            },
                            "retained_by" => match &item.state {
                                State::Retained { by } => text(by.as_deref()),
                                _ => Value::Null,
                            },
                            "size" => match &item.object {
                                Some(name) => Value::Integer(model.object_size(name) as i64),
                                None => Value::Null,
                            },
                            column => cell(item, column, None),
                        })
                        .collect()
                })
                .collect();
            self.expect("list_retained_page", &params, rows);
            if let Some(last) = page.last() {
                after = Value::Integer(last.seq);
            }
        }

        let mut lists: Vec<&Item> = rows.clone();
        lists.sort_by(|a, b| a.link_id.cmp(&b.link_id));
        let in_reply_to = lists
            .iter()
            .flat_map(|item| {
                item.summary
                    .in_reply_to
                    .iter()
                    .enumerate()
                    .map(|(position, id)| {
                        vec![
                            Value::Text(item.link_id.clone()),
                            Value::Integer(position as i64),
                            Value::Text(id.clone()),
                        ]
                    })
            })
            .collect();
        self.expect("load_in_reply_to", &key, in_reply_to);
        let categories = lists
            .iter()
            .flat_map(|item| {
                item.summary
                    .categories
                    .iter()
                    .enumerate()
                    .map(|(position, value)| {
                        vec![
                            Value::Text(item.link_id.clone()),
                            Value::Integer(position as i64),
                            Value::Text(value.clone()),
                        ]
                    })
            })
            .collect();
        self.expect("load_categories", &key, categories);

        Ok(())
    }

    fn item(&mut self, item: &Item) -> Result<()> {
        let by_seq = [
            ("collection", Value::Text(item.collection.clone())),
            ("seq", Value::Integer(item.seq)),
        ];
        let by_link = [
            ("collection", Value::Text(item.collection.clone())),
            ("link_id", Value::Text(item.link_id.clone())),
        ];

        if item.state == State::Live {
            let columns = self.columns("get_item")?;
            self.expect("get_item", &by_seq, vec![row(item, &columns, None)]);
            let name = format!("get_{}", item.summary.table.stem());
            let columns = self.columns(&name)?;
            let rows = vec![row(item, &columns, Some(item.summary.table))];
            self.expect(&name, &by_seq, rows);
            if item.summary.table == Table::Mail {
                let columns = self.columns("get_mail_row")?;
                let rows = vec![row(item, &columns, Some(Table::Mail))];
                self.expect("get_mail_row", &by_link, rows);
            }
        }

        self.expect(
            "seq_by_link",
            &by_link,
            vec![vec![Value::Integer(item.seq)]],
        );

        let mut addresses = item.addresses.clone();
        addresses.sort_by(|a, b| (a.role.as_str(), a.position).cmp(&(b.role.as_str(), b.position)));
        let rows = addresses
            .into_iter()
            .map(|address| {
                vec![
                    Value::Text(address.role),
                    Value::Integer(address.position),
                    Value::Text(address.address),
                    text(address.name.as_deref()),
                ]
            })
            .collect();
        self.expect("load_addresses", &by_link, rows);

        let bindings = item
            .bindings
            .iter()
            .map(|binding| {
                vec![
                    Value::Text(item.link_id.clone()),
                    Value::Text(binding.source.clone()),
                    Value::Text(binding.handle.clone()),
                    flag_text(binding.base_flags.as_ref()),
                    text(binding.base_object.as_ref().map(|name| name.0.as_str())),
                    text(binding.base_revision.as_deref()),
                    Value::Integer(i64::from(binding.base_present)),
                    Value::Integer(i64::from(binding.conflicted)),
                    text(binding.conflict_revision.as_deref()),
                    hash(&binding.conflict_object),
                    hash(&binding.shared_object),
                ]
            })
            .collect();
        self.expect("list_item_bindings", &by_link, bindings);

        for binding in &item.bindings {
            let mut params = by_link.to_vec();
            params.push(("source", Value::Text(binding.source.clone())));
            let rows = vec![vec![Value::Text(binding.handle.clone())]];
            self.expect("handle_for_link", &params, rows);
        }

        Ok(())
    }

    fn identities(&mut self) {
        let model = self.model;
        let placed: Vec<&Item> = model
            .items
            .iter()
            .filter(|item| item.state == State::Live)
            .collect();
        let account = |item: &Item| model.collections[&item.collection].account.clone();
        let order = |item: &&Item| {
            let account = account(item);
            (account.is_none(), account, item.collection.clone())
        };

        let mut by_link: BTreeMap<&String, Vec<&Item>> = model
            .items
            .iter()
            .map(|item| (&item.link_id, Vec::new()))
            .collect();
        let mut by_object: BTreeMap<&ObjectName, Vec<&Item>> = model
            .objects
            .keys()
            .chain(model.streams.keys())
            .map(|name| (name, Vec::new()))
            .collect();
        for item in &placed {
            by_link.entry(&item.link_id).or_default().push(item);
            if let Some(holders) = item
                .object
                .as_ref()
                .and_then(|name| by_object.get_mut(name))
            {
                holders.push(item);
            }
        }

        for (link_id, mut holders) in by_link {
            holders.sort_by_key(order);
            let rows = holders
                .iter()
                .map(|item| {
                    vec![
                        Value::Text(item.collection.clone()),
                        text(account(item).as_deref()),
                        Value::Integer(item.seq),
                        text(item.object.as_ref().map(|name| name.0.as_str())),
                        flag_text(item.flags.as_ref()),
                        Value::Integer(item.level),
                    ]
                })
                .collect();
            let params = [("link_id", Value::Text(link_id.clone()))];
            self.expect("list_link_placements", &params, rows);
        }

        for (hash, holders) in by_object {
            let rows = holders
                .iter()
                .map(|item| {
                    vec![
                        Value::Text(item.collection.clone()),
                        text(account(item).as_deref()),
                        Value::Integer(item.seq),
                        Value::Text(item.link_id.clone()),
                        flag_text(item.flags.as_ref()),
                        Value::Integer(item.level),
                    ]
                })
                .collect();
            self.expect(
                "list_object_placements",
                &[("hash", Value::Text(hash.0.clone()))],
                rows,
            );
            self.last().ordered = false;
        }

        let mut endpoints: BTreeMap<(&str, &str), &Item> = BTreeMap::new();
        for item in &placed {
            let Some(kind) = model.collections[&item.collection].kind else {
                continue;
            };
            let key = (kind.media_type(), item.link_id.as_str());
            let first = endpoints.entry(key).or_insert(item);
            if item.collection < first.collection {
                *first = item;
            }
        }
        for ((kind, link_id), item) in endpoints {
            let title = ["subject", "fn", "summary", "name"]
                .iter()
                .map(|column| item.summary.get(column))
                .find(|value| *value != Value::Null)
                .unwrap_or(Value::Null);
            let params = [
                ("kind", Value::Text(String::from(kind))),
                ("link_id", Value::Text(String::from(link_id))),
            ];
            let rows = vec![vec![
                Value::Text(item.collection.clone()),
                Value::Integer(item.seq),
                title,
            ]];
            self.expect("describe_endpoint", &params, rows);
        }

        let retained: BTreeSet<_> = model
            .items
            .iter()
            .filter(|item| matches!(item.state, State::Retained { .. }))
            .filter_map(|item| item.object.as_ref())
            .collect();
        let bytes: usize = retained.iter().map(|name| model.object_size(name)).sum();
        self.expect(
            "retained_bytes",
            &[],
            vec![vec![Value::Integer(bytes as i64)]],
        );
    }

    fn mail(&mut self) -> Result<()> {
        let model = self.model;
        let mailboxes: Vec<&String> = model
            .collections
            .values()
            .filter(|collection| collection.kind == Some(Kind::Mail))
            .map(|collection| &collection.id)
            .collect();
        let mut sets: BTreeMap<Option<&String>, Vec<&String>> = BTreeMap::new();
        for id in &mailboxes {
            let account = model.collections[*id].account.as_ref();
            sets.entry(account).or_default().push(id);
        }
        let mut sets: Vec<Vec<&String>> = sets.into_values().collect();
        sets.push(mailboxes);

        let since = model
            .items
            .iter()
            .filter(|item| item.summary.table == Table::Mail && !item.sort_key.is_empty())
            .map(|item| item.sort_key.as_str())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .nth(4)
            .map(String::from);
        let filters = [
            (None, None, None),
            (Some(0), None, None),
            (Some(1), None, since.clone()),
            (None, Some(1), None),
            (None, Some(0), since),
        ];
        let columns = self.columns("list_mail_page_filtered")?;

        for set in sets {
            let members: BTreeSet<&String> = set.iter().copied().collect();
            let slot = (
                String::from("collections"),
                set.iter().map(|id| Value::Text((*id).clone())).collect(),
            );
            for (seen, attachment, since) in &filters {
                let matching: Vec<&Item> = model
                    .items
                    .iter()
                    .filter(|item| item.state == State::Live && members.contains(&item.collection))
                    .filter(|item| seen.is_none_or(|seen| seen_bit(item) == seen))
                    .filter(|item| {
                        attachment.is_none_or(|wanted| {
                            item.summary.get("attachment") == Value::Integer(wanted)
                        })
                    })
                    .filter(|item| item.sort_key.as_str() >= since.as_deref().unwrap_or(""))
                    .collect();
                let seen = seen.map_or(Value::Null, Value::Integer);
                let attachment = attachment.map_or(Value::Null, Value::Integer);
                let since = text(since.as_deref());

                let params = [
                    ("seen", seen.clone()),
                    ("attachment", attachment.clone()),
                    ("since", since.clone()),
                ];
                self.expect(
                    "count_mail",
                    &params,
                    vec![vec![Value::Integer(matching.len() as i64)]],
                );
                self.last().slot = Some(slot.clone());

                if seen == Value::Null {
                    let mut unread: BTreeMap<&String, i64> = BTreeMap::new();
                    for item in matching.iter().filter(|item| seen_bit(item) == 0) {
                        *unread.entry(&item.collection).or_default() += 1;
                    }
                    let rows = unread
                        .into_iter()
                        .map(|(id, count)| vec![Value::Text(id.clone()), Value::Integer(count)])
                        .collect();
                    let params = [("attachment", attachment.clone()), ("since", since.clone())];
                    self.expect("count_unread", &params, rows);
                    self.last().slot = Some(slot.clone());
                }

                let mut sorted = matching.clone();
                sorted.sort_by(|a, b| {
                    (b.sort_key.as_str(), b.seq, b.collection.as_str()).cmp(&(
                        a.sort_key.as_str(),
                        a.seq,
                        a.collection.as_str(),
                    ))
                });
                let mut after = (Value::Null, Value::Null, Value::Null);
                for page in pages(&sorted, self.page) {
                    let params = [
                        ("since", since.clone()),
                        ("after_key", after.0.clone()),
                        ("after_seq", after.1.clone()),
                        ("after_collection", after.2.clone()),
                        ("seen", seen.clone()),
                        ("attachment", attachment.clone()),
                        ("limit", Value::Integer(self.page)),
                    ];
                    let rows = page
                        .iter()
                        .map(|item| row(item, &columns, Some(Table::Mail)))
                        .collect();
                    self.expect("list_mail_page_filtered", &params, rows);
                    self.last().slot = Some(slot.clone());
                    if let Some(last) = page.last() {
                        after = (
                            Value::Text(last.sort_key.clone()),
                            Value::Integer(last.seq),
                            Value::Text(last.collection.clone()),
                        );
                    }
                }
            }
        }

        let mut ids: BTreeSet<String> = model
            .items
            .iter()
            .flat_map(|item| item.summary.in_reply_to.iter().cloned())
            .collect();
        ids.insert(String::from("nobody@nowhere.invalid"));
        let replied: BTreeSet<&String> = model
            .items
            .iter()
            .filter(|item| item.state == State::Live)
            .filter(|item| {
                let role = model.collections[&item.collection].role.as_deref();
                !matches!(role, Some("sent" | "drafts"))
            })
            .flat_map(|item| item.summary.in_reply_to.iter())
            .collect();
        let rows = replied
            .into_iter()
            .map(|id| vec![Value::Text(id.clone())])
            .collect();
        self.expect("list_replied", &[], rows);
        self.last().slot = Some((
            String::from("ids"),
            ids.into_iter().map(Value::Text).collect(),
        ));

        Ok(())
    }

    fn conflicts(&mut self) {
        let model = self.model;
        let accounts: BTreeSet<Option<&String>> = model
            .collections
            .values()
            .map(|collection| collection.account.as_ref())
            .collect();
        let account_of = |item: &Item| model.collections[&item.collection].account.as_ref();

        for account in accounts {
            let mut items: Vec<&Item> = model
                .items
                .iter()
                .filter(|item| item.conflicted && account_of(item) == account)
                .collect();
            items.sort_by(|a, b| (&a.collection, a.seq).cmp(&(&b.collection, b.seq)));
            let rows = items
                .iter()
                .map(|item| {
                    vec![
                        Value::Text(item.collection.clone()),
                        Value::Text(item.link_id.clone()),
                        Value::Integer(item.seq),
                        hash(&item.object),
                        hash(&item.conflict_object),
                    ]
                })
                .collect();
            let params = [("account", text(account.map(String::as_str)))];
            self.expect("list_conflicted_items", &params, rows);

            let mut bound: Vec<(&Item, &Binding)> = model
                .items
                .iter()
                .filter(|item| account_of(item) == account)
                .flat_map(|item| item.bindings.iter().map(move |binding| (item, binding)))
                .filter(|(_, binding)| binding.conflicted)
                .collect();
            bound.sort_by(|(a, x), (b, y)| {
                (&a.collection, &a.link_id, &x.source).cmp(&(&b.collection, &b.link_id, &y.source))
            });
            let rows = bound
                .iter()
                .map(|(item, binding)| {
                    vec![
                        Value::Text(item.collection.clone()),
                        Value::Text(item.link_id.clone()),
                        Value::Text(binding.source.clone()),
                        Value::Text(binding.handle.clone()),
                        text(binding.conflict_revision.as_deref()),
                        hash(&binding.base_object),
                        hash(&item.object),
                        hash(&binding.conflict_object),
                    ]
                })
                .collect();
            self.expect("list_conflicted_bindings", &params, rows);
        }

        for id in model.collections.keys() {
            let mut refused: Vec<(&Item, &Binding, &Refusal)> = model
                .items
                .iter()
                .filter(|item| &item.collection == id)
                .flat_map(|item| item.bindings.iter().map(move |binding| (item, binding)))
                .filter_map(|(item, binding)| {
                    binding
                        .refusal
                        .as_ref()
                        .map(|refusal| (item, binding, refusal))
                })
                .collect();
            refused.sort_by(|(a, x, _), (b, y, _)| (a.seq, &x.source).cmp(&(b.seq, &y.source)));
            let rows = refused
                .iter()
                .map(|(item, binding, refusal)| {
                    vec![
                        Value::Integer(item.seq),
                        Value::Text(binding.source.clone()),
                        Value::Text(binding.handle.clone()),
                        Value::Text(refusal.reason.clone()),
                        Value::Text(refusal.key.clone()),
                        Value::Text(String::from(INSTANT)),
                    ]
                })
                .collect();
            self.expect(
                "list_refusals",
                &[("collection", Value::Text(id.clone()))],
                rows,
            );
        }
    }

    fn queue(&mut self) {
        let model = self.model;
        let instant = || Value::Text(String::from(INSTANT));

        for id in model.collections.keys() {
            let rows = model
                .queue
                .iter()
                .filter(|row| &row.collection == id && row.state == RowState::Pending)
                .map(|row| {
                    vec![
                        Value::Integer(row.id),
                        instant(),
                        Value::Text(row.producer.clone()),
                        Value::Text(String::from(row.action.name())),
                        Value::Text(row.action.payload()),
                        text(row.action.target()),
                        hash(&row.action.body().map(ObjectName::of)),
                        Value::Integer(0),
                    ]
                })
                .collect();
            self.expect(
                "load_pending_actions",
                &[("collection", Value::Text(id.clone()))],
                rows,
            );

            let arrivals = model
                .queue
                .iter()
                .filter(|row| row.action.target() == Some(id.as_str()))
                .filter(|row| row.state == RowState::Pending)
                .filter(|row| matches!(row.action, Action::Move { .. } | Action::Copy { .. }))
                .map(|row| {
                    vec![
                        Value::Integer(row.id),
                        instant(),
                        Value::Text(row.producer.clone()),
                        Value::Text(row.collection.clone()),
                        Value::Text(String::from(row.action.name())),
                        Value::Text(row.action.payload()),
                        hash(&row.action.body().map(ObjectName::of)),
                        Value::Integer(0),
                    ]
                })
                .collect();
            self.expect(
                "load_pending_arrivals",
                &[("collection", Value::Text(id.clone()))],
                arrivals,
            );
        }

        let mut parked = Vec::new();
        for row in &model.queue {
            let id = [("id", Value::Integer(row.id))];
            let error = match &row.state {
                RowState::Pending => Some(Value::Null),
                RowState::Parked(error) => Some(Value::Text(error.clone())),
                RowState::Unconfirmed(detail) => {
                    Some(Value::Text(format!("unconfirmed: {detail}")))
                }
                RowState::Applied(_) => None,
            };
            let action = error.clone().map(|error| {
                vec![
                    Value::Integer(row.id),
                    instant(),
                    Value::Text(row.producer.clone()),
                    Value::Text(row.collection.clone()),
                    Value::Text(String::from(row.action.name())),
                    Value::Text(row.action.payload()),
                    text(row.action.target()),
                    Value::Integer(i64::from(error != Value::Null)),
                    error,
                ]
            });
            if let Some(action) = &action
                && action[8] != Value::Null
            {
                parked.push(action.clone());
            }
            self.expect("load_action", &id, action.into_iter().collect());

            let RowState::Applied(seq) = row.state else {
                self.expect("load_receipt", &id, Vec::new());
                continue;
            };
            let receipt = vec![
                instant(),
                Value::Text(row.collection.clone()),
                seq.map_or(Value::Null, Value::Integer),
            ];
            self.expect("load_receipt", &id, vec![receipt]);

            let account = model.collections[&row.collection].account.as_ref();
            let mut refusals: Vec<Vec<Value>> = model
                .items
                .iter()
                .filter(|item| Some(item.seq) == seq)
                .filter(|item| model.collections[&item.collection].account.as_ref() == account)
                .flat_map(|item| item.bindings.iter().map(move |binding| (item, binding)))
                .filter_map(|(item, binding)| {
                    binding.refusal.as_ref().map(|refusal| {
                        vec![
                            Value::Text(item.collection.clone()),
                            Value::Text(binding.source.clone()),
                            Value::Text(refusal.reason.clone()),
                            instant(),
                        ]
                    })
                })
                .collect();
            refusals.sort_by(|a, b| {
                (as_text(&a[0]), as_text(&a[1])).cmp(&(as_text(&b[0]), as_text(&b[1])))
            });
            self.expect("load_receipt_refusals", &id, refusals);
        }
        self.expect("storage/owner/load_parked_actions", &[], parked);
    }

    fn people(&mut self) {
        let model = self.model;
        let placed: Vec<&Item> = model
            .items
            .iter()
            .filter(|item| item.state == State::Live)
            .collect();
        let context = |item: &Item| {
            let collection = &model.collections[&item.collection];
            (
                Value::Text(item.collection.clone()),
                text(collection.account.as_deref()),
                Value::Text(String::from(
                    collection.kind.map_or("", |kind| kind.media_type()),
                )),
            )
        };

        let addresses: BTreeSet<&String> = placed
            .iter()
            .flat_map(|item| item.addresses.iter().map(|address| &address.address))
            .collect();
        for address in addresses {
            let mut firsts: Vec<(&Item, &String)> = Vec::new();
            for item in &placed {
                let mut roles = BTreeSet::new();
                for row in item.addresses.iter().filter(|row| &row.address == address) {
                    if roles.insert(&row.role) {
                        firsts.push((item, &row.role));
                    }
                }
            }
            let roles: BTreeSet<&String> = firsts.iter().map(|(_, role)| *role).collect();
            let wanted = iter::once(None).chain(roles.into_iter().map(Some));
            for role in wanted {
                let mut rows: Vec<(&Item, &String)> = firsts
                    .iter()
                    .copied()
                    .filter(|(_, held)| role.is_none_or(|role| role == *held))
                    .collect();
                rows.sort_by(|(a, ra), (b, rb)| {
                    (
                        b.sort_key.as_str(),
                        b.seq,
                        b.collection.as_str(),
                        rb.as_str(),
                    )
                        .cmp(&(
                            a.sort_key.as_str(),
                            a.seq,
                            a.collection.as_str(),
                            ra.as_str(),
                        ))
                });
                let mut after = (Value::Null, Value::Null, Value::Null, Value::Null);
                for page in pages(&rows, self.page) {
                    let params = [
                        ("address", Value::Text(address.clone())),
                        ("role", text(role.map(String::as_str))),
                        ("after_key", after.0.clone()),
                        ("after_seq", after.1.clone()),
                        ("after_collection", after.2.clone()),
                        ("after_role", after.3.clone()),
                        ("limit", Value::Integer(self.page)),
                    ];
                    let rows = page
                        .iter()
                        .map(|(item, role)| {
                            let (collection, account, kind) = context(item);
                            vec![
                                Value::Text((*role).clone()),
                                collection,
                                account,
                                kind,
                                Value::Integer(item.seq),
                                Value::Text(item.sort_key.clone()),
                            ]
                        })
                        .collect();
                    self.expect("list_address_placements", &params, rows);
                    if let Some((item, role)) = page.last() {
                        after = (
                            Value::Text(item.sort_key.clone()),
                            Value::Integer(item.seq),
                            Value::Text(item.collection.clone()),
                            Value::Text((*role).clone()),
                        );
                    }
                }
            }
        }

        let domains: BTreeSet<String> = placed
            .iter()
            .flat_map(|item| item.addresses.iter())
            .filter_map(|row| {
                row.address
                    .rsplit_once('@')
                    .map(|(_, domain)| domain.to_ascii_lowercase())
            })
            .collect();
        for domain in domains {
            let suffix = format!("@{domain}");
            let rows = placed
                .iter()
                .flat_map(|item| item.addresses.iter().map(move |row| (item, row)))
                .filter(|(_, row)| {
                    let chars: Vec<char> = row.address.chars().collect();
                    let tail: String = chars[chars.len().saturating_sub(suffix.chars().count())..]
                        .iter()
                        .collect();
                    tail.to_ascii_lowercase() == suffix
                })
                .map(|(item, row)| {
                    let (collection, account, kind) = context(item);
                    vec![
                        Value::Text(row.address.clone()),
                        Value::Text(row.role.clone()),
                        collection,
                        account,
                        kind,
                        Value::Integer(item.seq),
                        Value::Text(item.sort_key.clone()),
                    ]
                })
                .collect();
            let params = [("domain", Value::Text(domain)), ("role", Value::Null)];
            self.expect("list_domain_placements", &params, rows);
            self.last().ordered = false;
        }
    }
}

fn pages<T>(rows: &[T], page: i64) -> impl Iterator<Item = &[T]> {
    rows.chunks(page as usize).chain([&[][..]])
}

fn seen_bit(item: &Item) -> i64 {
    let seen = item
        .flags
        .as_ref()
        .is_some_and(|flags| flags.contains(MARKS[0].0));
    i64::from(seen)
}

fn same_row(columns: &[String], got: &[Value], want: &[Value]) -> bool {
    got.len() == want.len() && columns.len() == got.len() && got == want
}

/// Writes a flag set's text in one order, so rows compare as sets do, and
/// a value no model can predict (an instant SQLite stamps, a change stamp,
/// the store's id) as the marker the model states for it, once its shape
/// is checked.
fn normalise(columns: &[String], row: &mut [Value]) {
    for (column, value) in columns.iter().zip(row.iter_mut()) {
        let marker = match (column.as_str(), &*value) {
            ("flags" | "base_flags", Value::Text(text)) => Some(flag_set(text).join(" ")),
            (column, Value::Text(text)) if INSTANTS.contains(&column) && is_instant(text) => {
                Some(String::from(INSTANT))
            }
            ("changed", Value::Integer(stamp)) if *stamp > 0 => Some(String::from(STAMP)),
            ("store_id", Value::Text(text))
                if text.len() == 32
                    && text
                        .bytes()
                        .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f')) =>
            {
                Some(String::from(STORE_ID))
            }
            _ => None,
        };
        if let Some(marker) = marker {
            *value = Value::Text(marker);
        }
    }
}

fn is_instant(text: &str) -> bool {
    let bytes = text.as_bytes();
    bytes.len() == 24
        && bytes.iter().enumerate().all(|(i, byte)| match i {
            4 | 7 => *byte == b'-',
            10 => *byte == b'T',
            13 | 16 => *byte == b':',
            19 => *byte == b'.',
            23 => *byte == b'Z',
            _ => byte.is_ascii_digit(),
        })
}

fn flag_set(text: &str) -> Vec<&str> {
    let mut flags: Vec<&str> = text.split(' ').filter(|flag| !flag.is_empty()).collect();
    flags.sort_unstable();
    flags
}

fn flag_text(flags: Option<&BTreeSet<String>>) -> Value {
    flags.map_or(Value::Null, |flags| {
        Value::Text(flags.iter().cloned().collect::<Vec<_>>().join(" "))
    })
}

fn row(item: &Item, columns: &[String], table: Option<Table>) -> Vec<Value> {
    columns
        .iter()
        .map(|column| cell(item, column, table))
        .collect()
}

fn cell(item: &Item, column: &str, table: Option<Table>) -> Value {
    match column {
        "collection" => Value::Text(item.collection.clone()),
        "seq" => Value::Integer(item.seq),
        "link_id" => Value::Text(item.link_id.clone()),
        "flags" => flag_text(item.flags.as_ref()),
        "object_hash" => text(item.object.as_ref().map(|name| name.0.as_str())),
        "sort_key" => Value::Text(item.sort_key.clone()),
        "level" => Value::Integer(item.level),
        column => match table {
            Some(table) if table == item.summary.table => item.summary.get(column),
            _ => Value::Null,
        },
    }
}

/// A collection's coverage, the narrowest of its sources': the latest floor,
/// the earliest ceiling and the oldest closing as a marker, none while one
/// source has closed no round (STORAGE §14.1).
fn covered(collection: &Collection) -> [Value; 3] {
    let scopes: Option<Vec<&Scope>> = collection
        .sources
        .values()
        .map(|sync| sync.coverage.as_ref())
        .collect();
    let Some(scopes) = scopes.filter(|scopes| !scopes.is_empty()) else {
        return [Value::Null, Value::Null, Value::Null];
    };
    let since = scopes.iter().filter_map(|scope| scope.since).max();
    let until = scopes.iter().filter_map(|scope| scope.until).min();
    let (since, until) = Scope { since, until }.values();
    [since, until, Value::Text(String::from(INSTANT))]
}

fn as_text(value: &Value) -> &str {
    match value {
        Value::Text(text) => text,
        _ => "",
    }
}

fn hash(name: &Option<ObjectName>) -> Value {
    text(name.as_ref().map(|name| name.0.as_str()))
}

fn text(text: Option<&str>) -> Value {
    text.map_or(Value::Null, |text| Value::Text(String::from(text)))
}

#[cfg(test)]
mod tests {
    use std::{collections::BTreeSet, env, fs, path::PathBuf, process};

    use crate::{name::ObjectName, oracle, profile::Profile, spec::Spec, store::Store, writer};

    /// The read statements no oracle point answers by itself: the list
    /// slots' own, and the open's, which the store's tests hold.
    const INFRASTRUCTURE: [&str; 4] = [
        "storage/read/bind_param",
        "storage/read/clear_param",
        "storage/read/create_param",
        "storage/read/load_store_meta",
    ];

    fn scratch(seed: u64) -> PathBuf {
        let dir = env::temp_dir().join(format!("pimdir-generator-oracle-{}-{seed}", process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn the_reads_of_a_structure_store_answer_what_its_model_states() {
        let spec = Spec::load_default().unwrap();

        for seed in 0..4 {
            let model = Profile::Structure.generate(&spec, seed).unwrap();
            let dir = scratch(seed);
            let store = Store::create(&spec, &dir).unwrap();
            writer::materialise(&model, &store).unwrap();

            let expectations = oracle::expectations(&model, &spec).unwrap();
            let disagreements = oracle::check(&store, &expectations).unwrap();
            assert!(disagreements.is_empty(), "seed {seed}: {disagreements:#?}");

            let statements: BTreeSet<&str> = expectations
                .iter()
                .map(|expectation| expectation.statement.as_str())
                .collect();
            let uncovered: Vec<&String> = spec
                .statements
                .keys()
                .filter(|name| name.starts_with("storage/read/"))
                .filter(|name| !INFRASTRUCTURE.contains(&name.as_str()))
                .filter(|name| !statements.contains(name.as_str()))
                .collect();
            assert!(
                uncovered.is_empty(),
                "seed {seed}: no expectation for {uncovered:?}"
            );

            let faults = oracle::feed::order(&store).unwrap();
            assert!(faults.is_empty(), "seed {seed}: {faults:#?}");

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
