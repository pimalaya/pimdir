//! # The engine
//!
//! The model of SYNC's verbs over one source and one mail collection: a
//! first round in pages, deltas, the flag axis merged over `(local, base,
//! remote)`, stated removals and a closed round's absences dropped, the
//! consumer's tombstones, creates and flag changes pushed, and an upgrade
//! fetching bodies (SYNC §3 to §6). A run answers what it listed, fetched
//! and pushed, the outcomes and the events, and leaves the model as the
//! store stands after it.
//!
//! The model runs only what it states exactly: one source per collection,
//! no scope, every right, every push accepted, no move, copy, landing,
//! conflict nor refusal, which later parts add (README.md, "Limits").

use std::collections::{BTreeMap, BTreeSet};

use crate::{
    body::Filed,
    model::{Model, Placement, State},
    name::ObjectName,
    remote::{Page, Remote},
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
        /// Its body.
        object: ObjectName,
    },
    /// A delete of a tombstone's member.
    Remove {
        /// Its handle.
        handle: String,
        /// The tombstone's key.
        link_id: String,
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
}

impl Push {
    /// The handle it is pushed for.
    pub fn handle(&self) -> &str {
        match self {
            Self::Add { handle, .. }
            | Self::Remove { handle, .. }
            | Self::SetFlags { handle, .. } => handle,
        }
    }

    /// The idempotency key SYNC §4 derives for it in `collection`.
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
                object,
                ..
            } => {
                fields.extend([String::from("add"), String::from("1"), link_id.clone()]);
                fields.extend(flags(set));
                fields.extend([String::from("0"), String::from("1"), object.0.clone()]);
            }
            Self::Remove { .. } => fields.extend([String::from("remove"), String::from("0")]),
            Self::SetFlags { add, remove, .. } => {
                fields.push(String::from("set-flags"));
                fields.extend(flags(add));
                fields.extend(flags(remove));
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
}

/// What a run reports (SYNC §5).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    /// A member named.
    Added(String),
    /// A member's flags pulled.
    FlagsChanged(String),
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
    /// Syncs `remote`'s collection: a round of pages of `size` when its
    /// source never closed one, else a delta from its checkpoint.
    pub fn sync(&mut self, remote: &mut Remote, size: usize) -> Run {
        let collection = remote.collection.clone();
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
                let index = match self.bound_handle(&collection, &source, &member.handle) {
                    Some(index) => {
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
                        index
                    }
                    None => {
                        let filed = remote.members[&member.handle].filed.clone();
                        let placement = Placement {
                            flags: Some(member.flags.clone()),
                            held: false,
                            handle: Some(member.handle.clone()),
                            revision: None,
                        };
                        events.push(Event::Added(member.handle.clone()));
                        self.file(&collection, filed, placement)
                    }
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
            let absent: Vec<usize> = (0..self.items.len())
                .filter(|index| {
                    let item = &self.items[*index];
                    item.collection == collection
                        && item.binding.as_ref().is_some_and(|binding| {
                            binding.source == source
                                && binding.base_present
                                && !binding.handle.starts_with('\u{1}')
                                && binding.round != Some(round)
                        })
                })
                .collect();
            for index in absent {
                let handle = self.items[index]
                    .binding
                    .as_ref()
                    .map(|binding| binding.handle.clone());
                self.drop_deleted(index);
                events.extend(handle.map(Event::Vanished));
            }
        }

        let pushes = self.derive(&collection, &source, &listed);
        let mut outcomes = Vec::new();
        for push in &pushes {
            outcomes.push(self.push(remote, push, &mut events));
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

    /// A `Deleted` drop: the binding goes, and with it the item's last, so
    /// the item is retained (STORAGE §10, §11).
    fn drop_deleted(&mut self, index: usize) {
        let item = &mut self.items[index];
        let by = item.binding.take().map(|binding| binding.source);
        item.state = State::Retained { by };
    }

    /// The changes the run's placements owe, in handle byte order (SYNC
    /// §3, §5): a tombstone's `Remove`, a pending create's `Add`, a flag
    /// set off its remote's a `SetFlags`.
    fn derive(
        &self,
        collection: &str,
        source: &str,
        listed: &BTreeMap<String, BTreeSet<String>>,
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
            match (&item.state, binding.base_present) {
                (State::Tombstone, true) => pushes.push(Push::Remove {
                    handle: binding.handle.clone(),
                    link_id: item.link_id.clone(),
                }),
                (State::Live, false) => {
                    if let Some(object) = &item.object {
                        pushes.push(Push::Add {
                            handle: binding.handle.clone(),
                            link_id: item.link_id.clone(),
                            flags: item.flags.clone().unwrap_or_default(),
                            object: object.clone(),
                        });
                    }
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

    /// Pushes one change to `remote`, which accepts it, and writes its
    /// outcome (SYNC §5, "Push discipline").
    fn push(&mut self, remote: &mut Remote, push: &Push, events: &mut Vec<Event>) -> Outcome {
        let collection = remote.collection.clone();
        let source = remote.source.clone();
        let index = self
            .bound_handle(&collection, &source, push.handle())
            .expect("a pushed placement");

        match push {
            Push::SetFlags {
                handle,
                add,
                remove,
            } => {
                let held = remote.members[handle].flags.clone();
                let left = held.difference(remove).chain(add.iter()).cloned().collect();
                remote.set_flags(handle, left);
                let item = &mut self.items[index];
                let flags = item.flags.clone();
                item.binding.as_mut().expect("a bound item").base_flags = flags;
                Outcome {
                    handle: handle.clone(),
                    assigned: None,
                }
            }
            Push::Remove { handle, .. } => {
                remote.expunge(handle);
                self.drop_deleted(index);
                Outcome {
                    handle: handle.clone(),
                    assigned: None,
                }
            }
            Push::Add {
                handle,
                flags,
                object,
                ..
            } => {
                let item = &self.items[index];
                let filed = Filed {
                    bytes: self.objects[object].clone(),
                    hint: None,
                    summary: item.summary.clone(),
                    addresses: item.addresses.clone(),
                    sort_key: item.sort_key.clone(),
                    fallback: None,
                };
                let assigned = remote.deliver(filed, flags.clone());
                let item = &mut self.items[index];
                let binding = item.binding.as_mut().expect("a bound item");
                binding.handle = assigned.clone();
                binding.base_present = true;
                binding.base_flags = Some(flags.clone());
                binding.base_object = Some(object.clone());
                binding.shared_object = Some(object.clone());
                events.push(Event::Created(assigned.clone()));
                Outcome {
                    handle: handle.clone(),
                    assigned: Some(assigned),
                }
            }
        }
    }
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
                    "Add" if push["origin"].is_null() && text("link_id").is_some() => {
                        Some(Push::Add {
                            handle,
                            link_id: text("link_id").unwrap(),
                            flags: flags(&push["flags"]).unwrap_or_default(),
                            object: ObjectName(object(push["object"].as_str().unwrap())),
                        })
                    }
                    "Remove" if push["to"].is_null() => Some(Push::Remove {
                        handle,
                        link_id: text("link_id").unwrap_or_default(),
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
