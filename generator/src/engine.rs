//! # The engine
//!
//! The model of SYNC's verbs over one source and one collection: a first
//! round in pages, deltas, the flag axis merged over `(local, base,
//! remote)`, the content axis of a mutable kind (a remote revision pulled,
//! a local body pushed gated on its base revision, both a conflict
//! recorded under `Manual`), stated removals and a closed round's absences
//! dropped, the consumer's tombstones, creates and changes pushed, and an
//! upgrade fetching bodies (SYNC §3 to §6). A run answers what it listed,
//! fetched and pushed, the outcomes and the events, and leaves the model
//! as the store stands after it.
//!
//! The model runs only what it states exactly: one source per collection,
//! no scope, every right, every push accepted, the `Manual` policy, no
//! move, copy, landing nor refusal, which later parts add (README.md,
//! "Limits").

use std::collections::{BTreeMap, BTreeSet};

use crate::{
    body::Filed,
    model::{Model, Placement, State, Summary, Table},
    name::ObjectName,
    remote::{Listed, Page, Remote},
};

/// One change a run pushes (SYNC §4).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Push {
    /// An upload of a pending create.
    Add {
        /// Its provisional handle.
        handle: String,
        /// Its key.
        link_id: String,
        /// Its flags.
        flags: BTreeSet<String>,
        /// The binding it copies from server-side, its collection and
        /// handle (SYNC §3).
        origin: Option<(String, String)>,
        /// Its body.
        object: ObjectName,
    },
    /// A delete of a tombstone's member.
    Remove {
        /// Its handle.
        handle: String,
        /// The collection it relocates into, its destination.
        to: Option<String>,
        /// The tombstone's key.
        link_id: String,
        /// The revision it is gated on, a mutable kind's base revision.
        if_match: Option<String>,
    },
    /// A flag change.
    SetFlags {
        /// Its handle.
        handle: String,
        /// The flags to add.
        add: BTreeSet<String>,
        /// The flags to remove.
        remove: BTreeSet<String>,
    },
    /// A new body for a mutable member.
    Update {
        /// Its handle.
        handle: String,
        /// The body.
        object: ObjectName,
        /// The revision it is gated on, the base's.
        if_match: Option<String>,
    },
}

impl Push {
    /// The handle it is pushed for.
    pub fn handle(&self) -> &str {
        match self {
            Self::Add { handle, .. }
            | Self::Remove { handle, .. }
            | Self::SetFlags { handle, .. }
            | Self::Update { handle, .. } => handle,
        }
    }

    /// The change's name, as its key spells it.
    pub fn name(&self) -> &'static str {
        match self {
            Self::Add { .. } => "add",
            Self::Remove { .. } => "remove",
            Self::SetFlags { .. } => "set-flags",
            Self::Update { .. } => "update",
        }
    }

    /// The idempotency key SYNC §4 derives for it in `collection`, its
    /// precondition left out.
    pub fn key(&self, collection: &str) -> String {
        let flags = |set: &BTreeSet<String>| {
            let mut fields = vec![String::from("known"), set.len().to_string()];
            let mut sorted: Vec<&String> = set.iter().collect();
            sorted.sort_by(|a, b| a.chars().cmp(b.chars()));
            fields.extend(sorted.into_iter().cloned());
            fields
        };
        let mut fields = vec![String::from(collection), String::from(self.handle())];
        match self {
            Self::Add {
                link_id,
                flags: set,
                origin,
                object,
                ..
            } => {
                fields.extend([String::from("add"), String::from("1"), link_id.clone()]);
                fields.extend(flags(set));
                match origin {
                    Some((collection, handle)) => {
                        fields.extend([String::from("1"), collection.clone(), handle.clone()]);
                    }
                    None => fields.push(String::from("0")),
                }
                fields.extend([String::from("1"), object.0.clone()]);
            }
            Self::Remove { to, .. } => {
                fields.push(String::from("remove"));
                match to {
                    Some(to) => fields.extend([String::from("1"), to.clone()]),
                    None => fields.push(String::from("0")),
                }
            }
            Self::SetFlags { add, remove, .. } => {
                fields.push(String::from("set-flags"));
                fields.extend(flags(add));
                fields.extend(flags(remove));
            }
            Self::Update { object, .. } => {
                fields.extend([String::from("update"), object.0.clone()]);
            }
        }
        change_key(&fields)
    }
}

/// The FNV-1a 64 of fields each followed by one NUL, the idempotency key
/// of SYNC §4.
pub fn change_key(fields: &[String]) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for field in fields {
        for byte in field.bytes().chain([0]) {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x0100_0000_01b3);
        }
    }
    format!("{hash:016x}")
}

/// What a connector answered a push (SYNC §4).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Outcome {
    /// The handle pushed for.
    pub handle: String,
    /// The handle an accepted add was assigned.
    pub assigned: Option<String>,
    /// The revision a mutable member holds once accepted.
    pub revision: Option<String>,
    /// Whether an accepted relocating `Remove` relocated the member.
    pub relocated: Option<bool>,
}

/// What a run reports (SYNC §5).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    /// A member named.
    Added(String),
    /// A member's flags pulled.
    FlagsChanged(String),
    /// A member's body pulled.
    ContentChanged(String),
    /// A divergence recorded.
    Conflicted(String),
    /// A member removed or found absent, dropped.
    Vanished(String),
    /// An add accepted under its assigned handle.
    Created(String),
}

/// One verb run over one collection and the script it ran against.
#[derive(Clone, Debug)]
pub struct Run {
    /// `sync` or `upgrade`.
    pub verb: &'static str,
    /// The collection.
    pub collection: String,
    /// The source.
    pub source: String,
    /// The pages the enumeration answered, a round's or a delta's.
    pub pages: Vec<Page>,
    /// The bodies fetched, by handle.
    pub fetch: BTreeMap<String, Vec<u8>>,
    /// The pushes, in order, keyed.
    pub pushes: Vec<(Push, String)>,
    /// The outcomes fed back.
    pub outcomes: Vec<Outcome>,
    /// The events reported.
    pub events: Vec<Event>,
}

impl Model {
    /// Syncs `remote`'s collection alone: [`Model::sync_in`] over the one
    /// remote.
    pub fn sync(&mut self, remote: &mut Remote, size: usize) -> Run {
        let collection = remote.collection.clone();
        let mut remotes = BTreeMap::from([(collection.clone(), remote.clone())]);
        let run = self.sync_in(&mut remotes, &collection, size);
        *remote = remotes.remove(&collection).expect("the remote synced");
        run
    }

    /// Syncs `collection` against its remote among `remotes`, the other
    /// collections of the source's account being where a relocation goes:
    /// a round of pages of `size` when its source never closed one, else a
    /// delta from its checkpoint.
    pub fn sync_in(
        &mut self,
        remotes: &mut BTreeMap<String, Remote>,
        collection: &str,
        size: usize,
    ) -> Run {
        let collection = String::from(collection);
        let remote = &remotes[&collection];
        let source = remote.source.clone();
        let first = self.collections[&collection].rounds == 0;
        let pages = match (&self.collections[&collection].checkpoint, first) {
            (Some(checkpoint), false) => {
                vec![remote.delta(&String::from_utf8_lossy(checkpoint))]
            }
            _ => remote.round(size),
        };
        let round = self.collections[&collection].rounds + 1;
        let mut events = Vec::new();
        let mut listed: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();

        for page in &pages {
            for member in &page.items {
                listed.insert(member.handle.clone(), member.flags.clone());
                let filed = remotes[&collection].members[&member.handle].filed.clone();
                let index = match self.bound_handle(&collection, &source, &member.handle) {
                    Some(index) => {
                        self.refresh(index, member, &filed, &mut events);
                        index
                    }
                    None => match self.landing(&collection, &source, &filed) {
                        Some(index) => {
                            self.land(index, member);
                            events.push(Event::Created(member.handle.clone()));
                            index
                        }
                        None => {
                            if member.carries {
                                self.objects
                                    .insert(ObjectName::of(&member.meta), member.meta.clone());
                            }
                            let placement = Placement {
                                flags: Some(member.flags.clone()),
                                held: member.carries,
                                handle: Some(member.handle.clone()),
                                revision: member.revision.clone(),
                            };
                            events.push(Event::Added(member.handle.clone()));
                            self.file(&collection, filed, placement)
                        }
                    },
                };
                if first {
                    let binding = self.items[index].binding.as_mut().expect("a bound item");
                    binding.round = Some(round);
                }
            }
            for handle in &page.vanished {
                if let Some(index) = self.bound_handle(&collection, &source, handle) {
                    self.drop_deleted(index);
                    events.push(Event::Vanished(handle.clone()));
                }
            }
        }

        if first {
            let absent: Vec<String> = self
                .items
                .iter()
                .filter(|item| item.collection == collection)
                .filter_map(|item| item.binding.as_ref())
                .filter(|binding| {
                    binding.source == source
                        && binding.base_present
                        && !binding.handle.starts_with('\u{1}')
                        && binding.round != Some(round)
                })
                .map(|binding| binding.handle.clone())
                .collect();
            for handle in absent {
                if let Some(index) = self.bound_handle(&collection, &source, &handle) {
                    self.drop_deleted(index);
                    events.push(Event::Vanished(handle));
                }
            }
        }

        let mutable = remotes[&collection].mutable;
        let pushes = self.derive(&collection, &source, &listed, mutable);
        let mut outcomes = Vec::new();
        for push in &pushes {
            outcomes.push(self.push(remotes, &collection, push, &mut events));
        }

        let checkpoint = pages.iter().find_map(|page| page.checkpoint.clone());
        let entry = self
            .collections
            .get_mut(&collection)
            .expect("a declared collection");
        if let Some(checkpoint) = checkpoint {
            entry.checkpoint = Some(checkpoint.into_bytes());
        }
        if first {
            entry.rounds = round;
        }

        Run {
            verb: "sync",
            pushes: pushes
                .into_iter()
                .map(|push| {
                    let key = push.key(&collection);
                    (push, key)
                })
                .collect(),
            collection,
            source,
            pages,
            fetch: BTreeMap::new(),
            outcomes,
            events,
        }
    }

    /// Raises the placements of `handles` to `Full`, fetching each body
    /// the store does not hold, the base moving onto it (SYNC §6).
    pub fn upgrade(&mut self, remote: &Remote, handles: &[String]) -> Run {
        let collection = remote.collection.clone();
        let source = remote.source.clone();
        let mut fetch = BTreeMap::new();

        for handle in handles {
            let Some(index) = self.bound_handle(&collection, &source, handle) else {
                continue;
            };
            if self.items[index].object.is_some() {
                continue;
            }
            let bytes = remote.members[handle].filed.bytes.clone();
            let name = ObjectName::of(&bytes);
            self.objects.insert(name.clone(), bytes.clone());
            fetch.insert(handle.clone(), bytes);

            let item = &mut self.items[index];
            item.object = Some(name.clone());
            item.level = 2;
            let binding = item.binding.as_mut().expect("a bound item");
            binding.base_object = Some(name.clone());
            binding.shared_object = Some(name);
        }

        Run {
            verb: "upgrade",
            collection,
            source,
            pages: Vec::new(),
            fetch,
            pushes: Vec::new(),
            outcomes: Vec::new(),
            events: Vec::new(),
        }
    }

    fn bound_handle(&self, collection: &str, source: &str, handle: &str) -> Option<usize> {
        self.items.iter().position(|item| {
            item.collection == collection
                && item
                    .binding
                    .as_ref()
                    .is_some_and(|binding| binding.source == source && binding.handle == handle)
        })
    }

    /// The create of this source a member's arrival lands: a pending or a
    /// delivered create under the member's hint, its message agreeing
    /// (SYNC §6). A minted create is landed by no listing.
    fn landing(&self, collection: &str, source: &str, filed: &Filed) -> Option<usize> {
        let key = filed.hint.clone()?;
        let provisional = format!("\u{1}{key}");
        self.items.iter().position(|item| {
            item.collection == collection
                && item.link_id == key
                && agrees(&item.summary, &filed.summary)
                && item.binding.as_ref().is_some_and(|binding| {
                    binding.source == source && binding.handle == provisional
                })
        })
    }

    /// Lands a create on the member naming it: its binding moved to the
    /// listed handle, the base set to the listed flags and the staged body,
    /// the staged flags kept (SYNC §6).
    fn land(&mut self, index: usize, member: &Listed) {
        let item = &mut self.items[index];
        let binding = item.binding.as_mut().expect("a bound create");
        binding.handle = member.handle.clone();
        binding.base_present = true;
        binding.base_flags = Some(member.flags.clone());
        binding.base_object = item.object.clone();
        binding.base_revision = member.revision.clone();
        binding.shared_object = item.object.clone();
    }

    /// A listed member over its binding: the flag axis, then for a mutable
    /// kind the content axis under `Manual` (SYNC §5).
    fn refresh(&mut self, index: usize, member: &Listed, filed: &Filed, events: &mut Vec<Event>) {
        let item = &mut self.items[index];
        let binding = item.binding.as_mut().expect("a bound item");
        let merged = merge(
            item.flags.as_ref(),
            binding.base_flags.as_ref(),
            &member.flags,
        );
        binding.base_flags = Some(member.flags.clone());
        if item.flags.as_ref() != Some(&merged) {
            item.flags = Some(merged);
            events.push(Event::FlagsChanged(member.handle.clone()));
        }

        if member.revision.is_none() || member.revision == binding.base_revision {
            return;
        }
        let carried = member.carries.then(|| ObjectName::of(&member.meta));
        let edited = item.object.is_some() && item.object != binding.base_object;

        if edited || binding.conflicted {
            binding.conflicted = true;
            binding.conflict_revision = member.revision.clone();
            binding.conflict_object = carried.clone();
            events.push(Event::Conflicted(member.handle.clone()));
        } else {
            item.object = carried.clone();
            item.level = if carried.is_some() { 2 } else { 1 };
            item.summary = filed.summary.clone();
            item.addresses = filed.addresses.clone();
            item.sort_key = filed.sort_key.clone();
            binding.base_object = carried.clone();
            binding.base_revision = member.revision.clone();
            if carried.is_some() {
                binding.shared_object = carried.clone();
            }
            events.push(Event::ContentChanged(member.handle.clone()));
        }
        if let Some(name) = carried {
            self.objects.insert(name, member.meta.clone());
        }
    }

    /// A `Deleted` drop: the binding goes, and with it the item's last, so
    /// the item is retained, or purged when its identity is held live in
    /// another collection of the account with its body, a message only by
    /// a row agreeing with it (STORAGE §10, §11.1).
    fn drop_deleted(&mut self, index: usize) {
        let item = &mut self.items[index];
        let by = item.binding.take().map(|binding| binding.source);
        item.state = State::Retained { by };

        let item = &self.items[index];
        let account = &self.collections[&item.collection].account;
        let held = self.items.iter().any(|other| {
            other.collection != item.collection
                && &self.collections[&other.collection].account == account
                && other.link_id == item.link_id
                && other.state == State::Live
                && match &item.object {
                    Some(object) => other.object.as_ref() == Some(object),
                    None => agrees(&other.summary, &item.summary),
                }
        });
        if held {
            self.items.remove(index);
            self.purges += 1;
        }
    }

    /// Where a tombstone's remove relocates: the collection holding a
    /// pending or delivered create of this source under its key (SYNC §3).
    fn destination(&self, collection: &str, source: &str, link_id: &str) -> Option<String> {
        let provisional = format!("\u{1}{link_id}");
        self.items
            .iter()
            .find(|item| {
                item.collection != collection
                    && item.link_id == link_id
                    && item.state == State::Live
                    && item.binding.as_ref().is_some_and(|binding| {
                        binding.source == source && binding.handle == provisional
                    })
            })
            .map(|item| item.collection.clone())
    }

    /// What a create copies from: this source's based binding of its
    /// identity in another collection, under a handle no listing gave
    /// provisionally, holding its body as the base (SYNC §3).
    fn origin(
        &self,
        collection: &str,
        source: &str,
        link_id: &str,
        object: &ObjectName,
    ) -> Option<(String, String)> {
        self.items.iter().find_map(|item| {
            let binding = item.binding.as_ref()?;
            (item.collection != collection
                && item.link_id == link_id
                && binding.source == source
                && binding.base_present
                && !binding.handle.starts_with('\u{1}')
                && binding.base_object.as_ref() == Some(object))
            .then(|| (item.collection.clone(), binding.handle.clone()))
        })
    }

    /// The changes the run's placements owe, in handle byte order (SYNC
    /// §3, §5): a tombstone's `Remove`, relocating into its destination,
    /// a pending create's `Add`, by copy from its origin, a local body off
    /// its base an `Update`, a flag set off what the source holds a
    /// `SetFlags`, one change a handle; a conflict and a delivered create
    /// owe none.
    fn derive(
        &self,
        collection: &str,
        source: &str,
        listed: &BTreeMap<String, BTreeSet<String>>,
        mutable: bool,
    ) -> Vec<Push> {
        let mut pushes = Vec::new();
        for item in self
            .items
            .iter()
            .filter(|item| item.collection == collection)
        {
            let Some(binding) = item
                .binding
                .as_ref()
                .filter(|binding| binding.source == source)
            else {
                continue;
            };
            let provisional = binding.handle.starts_with('\u{1}');
            match (&item.state, binding.base_present) {
                (_, true) if provisional => {}
                (State::Tombstone, true) => pushes.push(Push::Remove {
                    handle: binding.handle.clone(),
                    to: self.destination(collection, source, &item.link_id),
                    link_id: item.link_id.clone(),
                    if_match: binding.base_revision.clone(),
                }),
                (State::Live, false) => {
                    if let Some(object) = &item.object {
                        pushes.push(Push::Add {
                            handle: binding.handle.clone(),
                            link_id: item.link_id.clone(),
                            flags: item.flags.clone().unwrap_or_default(),
                            origin: self.origin(collection, source, &item.link_id, object),
                            object: object.clone(),
                        });
                    }
                }
                (State::Live, true) if binding.conflicted => {}
                (State::Live, true)
                    if mutable && item.object.is_some() && item.object != binding.base_object =>
                {
                    pushes.push(Push::Update {
                        handle: binding.handle.clone(),
                        object: item.object.clone().expect("a held body"),
                        if_match: binding.base_revision.clone(),
                    });
                }
                (State::Live, true) => {
                    let (Some(flags), Some(base)) = (&item.flags, &binding.base_flags) else {
                        continue;
                    };
                    let remote = listed.get(&binding.handle).unwrap_or(base);
                    let add: BTreeSet<String> = flags.difference(remote).cloned().collect();
                    let remove: BTreeSet<String> = remote.difference(flags).cloned().collect();
                    if !add.is_empty() || !remove.is_empty() {
                        pushes.push(Push::SetFlags {
                            handle: binding.handle.clone(),
                            add,
                            remove,
                        });
                    }
                }
                _ => {}
            }
        }
        pushes.sort_by(|a, b| a.handle().cmp(b.handle()));
        pushes
    }

    /// Pushes one change to the collection's remote, which accepts it, and
    /// writes its outcome (SYNC §5, "Push discipline").
    fn push(
        &mut self,
        remotes: &mut BTreeMap<String, Remote>,
        collection: &str,
        push: &Push,
        events: &mut Vec<Event>,
    ) -> Outcome {
        let source = remotes[collection].source.clone();
        let index = self
            .bound_handle(collection, &source, push.handle())
            .expect("a pushed placement");
        let mut outcome = Outcome {
            handle: String::from(push.handle()),
            assigned: None,
            revision: None,
            relocated: None,
        };

        match push {
            Push::SetFlags {
                handle,
                add,
                remove,
            } => {
                let remote = remotes.get_mut(collection).expect("a remote");
                let held = remote.members[handle].flags.clone();
                let left = held.difference(remove).chain(add.iter()).cloned().collect();
                remote.set_flags(handle, left);
                let item = &mut self.items[index];
                let flags = item.flags.clone();
                item.binding.as_mut().expect("a bound item").base_flags = flags;
            }
            Push::Remove {
                handle,
                to,
                link_id,
                ..
            } => {
                let remote = remotes.get_mut(collection).expect("a remote");
                let member = remote.members.get(handle).cloned();
                remote.expunge(handle);
                if let (Some(to), Some(member)) = (to, member) {
                    let target = remotes.get_mut(to).expect("a target remote");
                    target.deliver(member.filed, member.flags);
                    outcome.relocated = Some(true);
                    let provisional = format!("\u{1}{link_id}");
                    let delivered = self.items.iter_mut().find(|item| {
                        &item.collection == to
                            && item.binding.as_ref().is_some_and(|binding| {
                                binding.source == source && binding.handle == provisional
                            })
                    });
                    if let Some(binding) = delivered.and_then(|item| item.binding.as_mut())
                        && !binding.base_present
                    {
                        binding.base_present = true;
                    }
                }
                self.drop_deleted(index);
            }
            Push::Update { handle, object, .. } => {
                let filed = self.filed(index, object);
                let remote = remotes.get_mut(collection).expect("a remote");
                outcome.revision = remote.edit(handle, filed);
                let binding = self.items[index].binding.as_mut().expect("a bound item");
                binding.base_object = Some(object.clone());
                binding.base_revision = outcome.revision.clone();
                binding.shared_object = Some(object.clone());
            }
            Push::Add { flags, object, .. } => {
                let filed = self.filed(index, object);
                let remote = remotes.get_mut(collection).expect("a remote");
                let (assigned, revision) = remote.deliver(filed, flags.clone());
                let binding = self.items[index].binding.as_mut().expect("a bound item");
                binding.handle = assigned.clone();
                binding.base_present = true;
                binding.base_flags = Some(flags.clone());
                binding.base_object = Some(object.clone());
                binding.base_revision = revision.clone();
                binding.shared_object = Some(object.clone());
                events.push(Event::Created(assigned.clone()));
                outcome.assigned = Some(assigned);
                outcome.revision = revision;
            }
        }
        outcome
    }

    fn filed(&self, index: usize, object: &ObjectName) -> Filed {
        let item = &self.items[index];
        Filed {
            bytes: self.objects[object].clone(),
            hint: None,
            summary: item.summary.clone(),
            addresses: item.addresses.clone(),
            sort_key: item.sort_key.clone(),
            fallback: None,
        }
    }
}

/// Whether two summaries name one message: another kind always does, a
/// message by its subject, date and sender (STORAGE §9).
fn agrees(held: &Summary, member: &Summary) -> bool {
    held.table != Table::Mail
        || ["subject", "date", "sender"]
            .iter()
            .all(|column| held.get(column) == member.get(column))
}

/// The flag axis: a flag both sides carry, or one side added over the
/// base, is kept; one the base carries and a side dropped goes; with no
/// base, the union (SYNC §5).
pub fn merge(
    local: Option<&BTreeSet<String>>,
    base: Option<&BTreeSet<String>>,
    remote: &BTreeSet<String>,
) -> BTreeSet<String> {
    let Some(local) = local else {
        return remote.clone();
    };
    let union: BTreeSet<String> = local.union(remote).cloned().collect();
    match base {
        None => union,
        Some(base) => union
            .into_iter()
            .filter(|flag| (local.contains(flag) && remote.contains(flag)) || !base.contains(flag))
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::BTreeSet, fs};

    use serde_json::Value;

    use crate::{
        engine::{Push, change_key},
        name::ObjectName,
        spec::Spec,
    };

    fn flags(value: &Value) -> Option<BTreeSet<String>> {
        value.as_array().map(|flags| {
            flags
                .iter()
                .filter_map(|flag| flag.as_str().map(String::from))
                .collect()
        })
    }

    #[test]
    fn every_push_of_the_sync_vectors_carries_the_key_this_crate_derives() {
        let root = Spec::default_root().join("vectors");
        let mut checked = 0;
        let mut typed = 0;

        let mut paths: Vec<_> = fs::read_dir(root.join("sync"))
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .collect();
        paths.sort();
        for path in paths {
            let case: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
            let collection = case["run"]["collection"].as_str().unwrap();
            let object = |label: &str| {
                let fixture = [
                    &case["store"]["objects"],
                    &case["expect"]["store"]["objects"],
                ]
                .iter()
                .find_map(|objects| objects[label]["body"].as_str())
                .unwrap();
                ObjectName::of(&fs::read(root.join(fixture)).unwrap()).0
            };
            let option = |value: Option<String>| match value {
                Some(value) => vec![String::from("1"), value],
                None => vec![String::from("0")],
            };
            let set = |set: Option<BTreeSet<String>>| match set {
                None => vec![String::from("unknown")],
                Some(set) => {
                    let mut fields = vec![String::from("known"), set.len().to_string()];
                    fields.extend(set);
                    fields
                }
            };

            for push in case["expect"]["pushes"].as_array().into_iter().flatten() {
                let handle = String::from(push["handle"].as_str().unwrap());
                let text = |name: &str| push[name].as_str().map(String::from);
                let mut fields = vec![String::from(collection), handle.clone()];
                match push["kind"].as_str().unwrap() {
                    "Add" => {
                        fields.push(String::from("add"));
                        fields.extend(option(text("link_id")));
                        fields.extend(set(flags(&push["flags"])));
                        match push["origin"].as_object() {
                            Some(origin) => fields.extend([
                                String::from("1"),
                                String::from(origin["collection"].as_str().unwrap()),
                                String::from(origin["handle"].as_str().unwrap()),
                            ]),
                            None => fields.push(String::from("0")),
                        }
                        fields.extend(option(text("object").map(|label| object(&label))));
                    }
                    "Remove" => {
                        fields.push(String::from("remove"));
                        fields.extend(option(text("to")));
                    }
                    "SetFlags" => {
                        fields.push(String::from("set-flags"));
                        fields.extend(set(flags(&push["add"])));
                        fields.extend(set(flags(&push["remove"])));
                    }
                    _ => {
                        fields.push(String::from("update"));
                        fields.push(object(push["object"].as_str().unwrap()));
                    }
                }
                let key = push["key"].as_str().unwrap();
                assert_eq!(change_key(&fields), key, "{}", path.display());
                checked += 1;

                let typed_push = match push["kind"].as_str().unwrap() {
                    "Add" if text("link_id").is_some() && text("object").is_some() => {
                        Some(Push::Add {
                            handle,
                            link_id: text("link_id").unwrap(),
                            flags: flags(&push["flags"]).unwrap_or_default(),
                            origin: push["origin"].as_object().map(|origin| {
                                (
                                    String::from(origin["collection"].as_str().unwrap()),
                                    String::from(origin["handle"].as_str().unwrap()),
                                )
                            }),
                            object: ObjectName(object(push["object"].as_str().unwrap())),
                        })
                    }
                    "Remove" => Some(Push::Remove {
                        handle,
                        to: text("to"),
                        link_id: text("link_id").unwrap_or_default(),
                        if_match: text("if_match"),
                    }),
                    "Update" => Some(Push::Update {
                        handle,
                        object: ObjectName(object(push["object"].as_str().unwrap())),
                        if_match: text("if_match"),
                    }),
                    "SetFlags" => Some(Push::SetFlags {
                        handle,
                        add: flags(&push["add"]).unwrap_or_default(),
                        remove: flags(&push["remove"]).unwrap_or_default(),
                    }),
                    _ => None,
                };
                if let Some(typed_push) = typed_push {
                    assert_eq!(typed_push.key(collection), key, "{}", path.display());
                    typed += 1;
                }
            }
        }

        assert!(
            checked >= 30 && typed >= 15,
            "{checked} keys, {typed} typed"
        );
    }
}
