//! # Capabilities
//!
//! What a source declares it can push (STORAGE §15.6, Annex B), and the
//! owner's backstop the model's drain runs: the capabilities an action
//! needs, read against the sources it concerns, a declared source without
//! one parking it.

use std::collections::BTreeSet;

use serde_json::Value as Json;

use crate::{
    model::{Address, Item, Kind, MARKS, Model, State, Table},
    queue::Action,
};

/// The capabilities read only where a row states one (Annex B).
pub const LATER: [&str; 3] = [
    "calendar.component.vtodo",
    "mail.flags.important",
    "mail.flags.junk",
];

/// How a source stands toward a capability in a collection.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Gate {
    /// Its row there has some support.
    Supported,
    /// It is declared and its row there is `none`, or it states none of a
    /// capability of the base set.
    Unsupported,
    /// It is undeclared, or states nothing of a capability read only where
    /// a row states it: nothing gates it.
    Ungated,
}

impl Model {
    /// How `source` stands toward `capability` in `collection`, its row
    /// there overriding its source-wide one (STORAGE §15.6).
    pub fn support(&self, source: &str, collection: &str, capability: &str) -> Gate {
        let rows: Vec<_> = self
            .capabilities
            .iter()
            .filter(|row| row.source == source)
            .collect();
        if rows.is_empty() {
            return Gate::Ungated;
        }
        let row = rows
            .iter()
            .find(|row| row.name == capability && row.collection.as_deref() == Some(collection))
            .or_else(|| {
                rows.iter()
                    .find(|row| row.name == capability && row.collection.is_none())
            });
        match row {
            Some(row) if row.support == "none" => Gate::Unsupported,
            Some(_) => Gate::Supported,
            None if LATER.contains(&capability) => Gate::Ungated,
            None => Gate::Unsupported,
        }
    }

    /// Why the owner's backstop parks `action` queued on `collection`, if
    /// it does: a capability it needs that a declared source it concerns
    /// does not support.
    pub fn backstop(&self, collection: &str, action: &Action) -> Option<String> {
        let mut needed: Vec<(String, String, String)> = Vec::new();

        match action {
            Action::Intent {
                action, payload, ..
            } => {
                let source = payload["source"].as_str()?;
                for capability in intent_needs(action, payload) {
                    needed.push((String::from(source), String::from(collection), capability));
                }
            }
            Action::Add { flags, filed, .. } => {
                let kind = self.collections[collection].kind?;
                for source in self.syncing(collection) {
                    let mut caps = vec![verb(kind, "add")];
                    caps.extend(self.flag_needs(&source, flags.iter()));
                    if scheduled(&filed.addresses) {
                        caps.push(String::from("calendar.scheduling"));
                    }
                    if filed.summary.table == Table::Task {
                        caps.push(String::from("calendar.component.vtodo"));
                    }
                    for capability in caps {
                        needed.push((source.clone(), String::from(collection), capability));
                    }
                }
            }
            Action::SetFlags { seq, flags, base } => {
                let item = self.live_item(collection, *seq)?;
                let current = item.flags.clone();
                let left: BTreeSet<String> = match (base, &current) {
                    (Some(base), Some(held)) => held
                        .iter()
                        .filter(|flag| !base.contains(*flag) || flags.contains(*flag))
                        .chain(flags.iter().filter(|flag| !base.contains(*flag)))
                        .cloned()
                        .collect(),
                    _ => flags.clone(),
                };
                let current = current.unwrap_or_default();
                let changed: Vec<&String> = left.symmetric_difference(&current).collect();
                for binding in item.bindings.iter() {
                    for capability in self.flag_needs(&binding.source, changed.iter().copied()) {
                        needed.push((binding.source.clone(), String::from(collection), capability));
                    }
                }
            }
            Action::Remove { seq, .. } => {
                let item = self.live_item(collection, *seq)?;
                let kind = self.collections[collection].kind?;
                for binding in item.bindings.iter().filter(|binding| binding.base_present) {
                    let mut caps = vec![verb(kind, "remove")];
                    if scheduled(&item.addresses) {
                        caps.push(String::from("calendar.scheduling"));
                    }
                    for capability in caps {
                        needed.push((binding.source.clone(), String::from(collection), capability));
                    }
                }
            }
            Action::Update { seq, filed, .. } => {
                let item = self.live_item(collection, *seq)?;
                let kind = self.collections[collection].kind?;
                for binding in item.bindings.iter() {
                    let mut caps = vec![verb(kind, "update")];
                    if scheduled(&filed.addresses) {
                        caps.push(String::from("calendar.scheduling"));
                    }
                    if filed.summary.table == Table::Task {
                        caps.push(String::from("calendar.component.vtodo"));
                    }
                    for capability in caps {
                        needed.push((binding.source.clone(), String::from(collection), capability));
                    }
                }
            }
            Action::Move { seq, to } | Action::Copy { seq, to } => {
                let item = self.live_item(collection, *seq)?;
                let kind = self.collections[collection].kind?;
                let word = match action {
                    Action::Move { .. } => "move",
                    _ => "copy",
                };
                for binding in item.bindings.iter().filter(|binding| binding.base_present) {
                    needed.push((
                        binding.source.clone(),
                        String::from(collection),
                        verb(kind, word),
                    ));
                }
                if self.collections.contains_key(to) {
                    for source in self.syncing(to) {
                        let mut caps = vec![verb(kind, "add")];
                        caps.extend(self.flag_needs(&source, item.flags.iter().flatten()));
                        if item.summary.table == Table::Task {
                            caps.push(String::from("calendar.component.vtodo"));
                        }
                        for capability in caps {
                            needed.push((source.clone(), to.clone(), capability));
                        }
                    }
                }
            }
            Action::SetPerformer { capability, source } => {
                let source = source.as_ref()?;
                if self.support(source, collection, capability) != Gate::Supported {
                    return Some(format!("{source} does not declare {capability}"));
                }
            }
            Action::Raw { .. } => {}
        }

        needed.into_iter().find_map(|(source, at, capability)| {
            (self.support(&source, &at, &capability) == Gate::Unsupported)
                .then(|| format!("{capability} unsupported by {source}"))
        })
    }

    /// The sources syncing `collection`: its checkpoints' and its
    /// bindings'.
    pub fn syncing(&self, collection: &str) -> BTreeSet<String> {
        let mut sources: BTreeSet<String> = self.collections[collection]
            .sources
            .keys()
            .cloned()
            .collect();
        sources.extend(
            self.items
                .iter()
                .filter(|item| item.collection == collection)
                .flat_map(|item| item.bindings.iter().map(|binding| binding.source.clone())),
        );
        sources
    }

    fn live_item(&self, collection: &str, seq: i64) -> Option<&Item> {
        self.items.iter().find(|item| {
            item.collection == collection && item.seq == seq && item.state == State::Live
        })
    }

    /// The capability a change of each flag needs from `source`, compared
    /// without regard to ASCII case (Annex B.1).
    fn flag_needs<'a>(&self, source: &str, flags: impl Iterator<Item = &'a String>) -> Vec<String> {
        let states = |name: &str| {
            self.capabilities
                .iter()
                .any(|row| row.source == source && row.name == name)
        };
        flags
            .map(|flag| {
                let lower = flag.to_ascii_lowercase();
                let system = MARKS
                    .iter()
                    .find(|(name, _)| name.to_ascii_lowercase() == lower && *name != "\\Deleted");
                match (system, lower.as_str()) {
                    (Some((name, _)), _) => {
                        format!("mail.flags.{}", name[1..].to_ascii_lowercase())
                    }
                    (None, "$important") if states("mail.flags.important") => {
                        String::from("mail.flags.important")
                    }
                    (None, "$junk") if states("mail.flags.junk") => String::from("mail.flags.junk"),
                    _ => String::from("mail.flags.keywords"),
                }
            })
            .collect()
    }
}

/// The capability of `word` on items of `kind`, `mail.message.move`.
pub fn verb(kind: Kind, word: &str) -> String {
    match kind {
        Kind::Mail => format!("mail.message.{word}"),
        Kind::Contact => format!("contacts.card.{word}"),
        Kind::Calendar | Kind::File => format!("calendar.item.{word}"),
    }
}

fn intent_needs(action: &str, payload: &Json) -> Vec<String> {
    let base = match action {
        "submit" => "mail.submit",
        "calendar-reply" => "calendar.reply",
        "calendar-cancel" => "calendar.cancel",
        "collection-create" => "collection.create",
        "collection-rename" => "collection.rename",
        "collection-delete" => "collection.delete",
        _ => return Vec::new(),
    };
    let mut needs = vec![String::from(base)];
    if action == "submit" && payload.get("copy").is_some() {
        needs.push(String::from("mail.submit.copy"));
    }
    if payload.get("recurrence_id").is_some() {
        needs.push(format!("{base}.occurrence"));
    }
    needs
}

/// Whether a resource naming these people is scheduled: it names an
/// attendee, and the generator writes no `SCHEDULE-AGENT` (Annex B.1).
fn scheduled(addresses: &[Address]) -> bool {
    addresses.iter().any(|address| address.role == "attendee")
}
