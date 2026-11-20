//! # The queue
//!
//! The actions producers append (STORAGE §15) and what the owner makes of
//! each as its drain applies it, read from STORAGE §15.2, §15.3 and the
//! mutations of SYNC §7: applied with a receipt, parked with a reason, or
//! skipped and left pending. The same application folds a collection's
//! pending rows into what a reader overlays (§15.4), so the overlay the
//! oracle states is the drain's prediction, every row the owner would park
//! folded into nothing.
//!
//! The model applies only what it states exactly: an action whose outcome
//! would turn on a rule it does not model yet (a resolution, a revive, a
//! capability) is never generated (README.md, "Rules it keeps").

use std::collections::BTreeSet;

use serde_json::{Value as Json, json};

use crate::{
    body::Filed,
    model::{Binding, Item, Model, State},
    name::ObjectName,
};

/// One action a producer appends.
#[derive(Clone, Debug)]
pub enum Action {
    /// `add`: a new item from a body.
    Add {
        /// The key the producer states.
        link_id: String,
        /// Its flags.
        flags: BTreeSet<String>,
        /// The body and its derivation.
        filed: Filed,
    },
    /// `set-flags`.
    SetFlags {
        /// The item.
        seq: i64,
        /// The set it leaves, or the set changed into with `base`.
        flags: BTreeSet<String>,
        /// The set the producer read.
        base: Option<BTreeSet<String>>,
    },
    /// `remove`.
    Remove {
        /// The item.
        seq: i64,
        /// The body the producer read.
        if_match: Option<ObjectName>,
    },
    /// `update`: a new body for a mutable item.
    Update {
        /// The item.
        seq: i64,
        /// The new body and its derivation.
        filed: Filed,
        /// The body the producer read.
        if_match: Option<ObjectName>,
    },
    /// `move`.
    Move {
        /// The item.
        seq: i64,
        /// The target collection.
        to: String,
    },
    /// `copy`.
    Copy {
        /// The item.
        seq: i64,
        /// The target collection.
        to: String,
    },
    /// `set-performer`: the source performing an intent capability for the
    /// account of the collection it is queued on.
    SetPerformer {
        /// The capability.
        capability: String,
        /// The source chosen, none withdrawing the choice.
        source: Option<String>,
    },
    /// An intent of Annex B.2, which the store's drain does not perform.
    Intent {
        /// Its name.
        action: String,
        /// Its payload.
        payload: Json,
        /// The body it carries, a submission's message.
        body: Option<Vec<u8>>,
    },
    /// A payload as another program wrote it, malformed or unknown
    /// (vectors/payloads.json).
    Raw {
        /// Its name.
        action: String,
        /// Its payload.
        payload: Json,
        /// Whether an owner knowing its action and version parks it.
        malformed: bool,
    },
}

impl Action {
    /// Its name, `queue.action`.
    pub fn name(&self) -> &str {
        match self {
            Self::Add { .. } => "add",
            Self::SetFlags { .. } => "set-flags",
            Self::Remove { .. } => "remove",
            Self::Update { .. } => "update",
            Self::Move { .. } => "move",
            Self::Copy { .. } => "copy",
            Self::SetPerformer { .. } => "set-performer",
            Self::Intent { action, .. } | Self::Raw { action, .. } => action,
        }
    }

    /// Its payload as the producer writes it, `queue.payload`.
    pub fn payload(&self) -> String {
        let flags = |flags: &BTreeSet<String>| json!(flags.iter().collect::<Vec<_>>());
        let value = match self {
            Self::Add {
                link_id,
                flags: set,
                filed,
            } => json!({
                "v": 1,
                "link_id": link_id,
                "flags": flags(set),
                "object": ObjectName::of(&filed.bytes).0,
            }),
            Self::SetFlags {
                seq,
                flags: set,
                base,
            } => {
                let mut value = json!({ "v": 1, "seq": seq, "flags": flags(set) });
                if let Some(base) = base {
                    value["base"] = flags(base);
                }
                value
            }
            Self::Remove { seq, if_match } => {
                let mut value = json!({ "v": 1, "seq": seq });
                if let Some(name) = if_match {
                    value["if_match"] = json!(name.0);
                }
                value
            }
            Self::Update {
                seq,
                filed,
                if_match,
            } => {
                let mut value = json!({
                    "v": 1,
                    "seq": seq,
                    "object": ObjectName::of(&filed.bytes).0,
                });
                if let Some(name) = if_match {
                    value["if_match"] = json!(name.0);
                }
                value
            }
            Self::Move { seq, to } | Self::Copy { seq, to } => {
                json!({ "v": 1, "seq": seq, "to": to })
            }
            Self::SetPerformer { capability, source } => {
                let mut value = json!({ "v": 1, "capability": capability });
                if let Some(source) = source {
                    value["source"] = json!(source);
                }
                value
            }
            Self::Intent { payload, .. } | Self::Raw { payload, .. } => payload.clone(),
        };
        value.to_string()
    }

    /// The body it carries, stored and pinned with it.
    pub fn body(&self) -> Option<&[u8]> {
        match self {
            Self::Add { filed, .. } | Self::Update { filed, .. } => Some(&filed.bytes),
            Self::Intent { body, .. } => body.as_deref(),
            _ => None,
        }
    }

    /// The collection its payload names, `queue.target_collection`.
    pub fn target(&self) -> Option<&str> {
        match self {
            Self::Move { to, .. } | Self::Copy { to, .. } => Some(to),
            _ => None,
        }
    }
}

/// One row of the queue, or one applied since.
#[derive(Clone, Debug)]
pub struct Row {
    /// Its id, the order of its append.
    pub id: i64,
    /// The program that appended it.
    pub producer: String,
    /// The collection it was queued on.
    pub collection: String,
    /// The action.
    pub action: Action,
    /// What became of it.
    pub state: RowState,
}

/// What became of a row.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RowState {
    /// Waiting for the drain, or skipped by it.
    Pending,
    /// Parked with this error, its attempt counted.
    Parked(String),
    /// An intent whose outcome is unknown, `unconfirmed: ` and this detail.
    Unconfirmed(String),
    /// Applied or acknowledged, its receipt naming this `seq`.
    Applied(Option<i64>),
}

/// What the owner makes of a row (STORAGE §15.2).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Outcome {
    /// Applied, acting on or leaving the item of this `seq`.
    Applied(Option<i64>),
    /// Parked, for this reason.
    Parked(String),
    /// Left pending and untouched.
    Skipped,
}

impl Model {
    /// Appends `action` on `collection` as `producer` does, its body stored
    /// and pinned, answering the row's id.
    pub fn enqueue(&mut self, producer: &str, collection: &str, action: Action) -> i64 {
        if let Some(body) = action.body() {
            self.objects.insert(ObjectName::of(body), body.to_vec());
        }
        let id = self.queue.len() as i64 + 1;
        self.queue.push(Row {
            id,
            producer: String::from(producer),
            collection: String::from(collection),
            action,
            state: RowState::Pending,
        });
        id
    }

    /// Drains the row `id` as the owner does, recording what became of it.
    pub fn drain(&mut self, id: i64) -> Outcome {
        let row = self.queue[id as usize - 1].clone();
        let outcome = self.apply(&row.collection, &row.action);
        self.queue[id as usize - 1].state = match &outcome {
            Outcome::Applied(seq) => RowState::Applied(*seq),
            Outcome::Parked(reason) => RowState::Parked(reason.clone()),
            Outcome::Skipped => RowState::Pending,
        };
        outcome
    }

    /// Drains every pending row in append order, as one pass of the owner's
    /// drain does.
    pub fn drain_all(&mut self) {
        let pending: Vec<i64> = self
            .queue
            .iter()
            .filter(|row| row.state == RowState::Pending)
            .map(|row| row.id)
            .collect();
        for id in pending {
            self.drain(id);
        }
    }

    /// Records the outcome of an intent its performer reached.
    pub fn settle(&mut self, id: i64, state: RowState) {
        self.queue[id as usize - 1].state = state;
    }

    /// The live items of `collection` as a reader overlaying its pending
    /// rows shows them, each folded as the owner would apply it, a row it
    /// would park or skip folded into nothing (STORAGE §15.4).
    pub fn overlay(&self, collection: &str) -> Vec<Item> {
        let mut folded = self.clone();
        for row in self
            .queue
            .iter()
            .filter(|row| row.collection == collection && row.state == RowState::Pending)
        {
            folded.apply(&row.collection, &row.action);
        }
        folded.live(collection).cloned().collect()
    }

    /// Applies `action` queued on `collection` as the owner's drain does,
    /// with no network (STORAGE §15.2, §15.3; SYNC §7).
    pub fn apply(&mut self, collection: &str, action: &Action) -> Outcome {
        if let Action::Raw { malformed, .. } = action {
            return match malformed {
                true => Outcome::Parked(String::from("malformed payload")),
                false => Outcome::Skipped,
            };
        }
        if let Some(reason) = self.backstop(collection, action) {
            return Outcome::Parked(reason);
        }

        match action {
            Action::Raw { .. } | Action::Intent { .. } => Outcome::Skipped,
            Action::SetPerformer { capability, source } => {
                let account = self.collections[collection].account.clone();
                let key = (account, capability.clone());
                match source {
                    Some(source) => self.performers.insert(key, source.clone()),
                    None => self.performers.remove(&key),
                };
                Outcome::Applied(None)
            }
            Action::Add {
                link_id,
                flags,
                filed,
            } => self.apply_add(collection, link_id, flags, filed),
            Action::SetFlags { seq, flags, base } => {
                let Some(index) = self.bound(collection, *seq) else {
                    return Outcome::Parked(String::from("the item is not bound yet"));
                };
                let item = &mut self.items[index];
                let set = match (base, &item.flags) {
                    (None, _) => flags.clone(),
                    (Some(_), None) => {
                        return Outcome::Parked(String::from("the item's flags are unknown"));
                    }
                    (Some(base), Some(held)) => held
                        .iter()
                        .filter(|flag| !base.contains(*flag) || flags.contains(*flag))
                        .chain(flags.iter().filter(|flag| !base.contains(*flag)))
                        .cloned()
                        .collect(),
                };
                item.flags = Some(set);
                Outcome::Applied(Some(item.seq))
            }
            Action::Remove { seq, if_match } => {
                let Some(index) = self.found(collection, *seq) else {
                    return Outcome::Applied(None);
                };
                if let Some(reason) = self.gate(index, if_match.as_ref()) {
                    return Outcome::Parked(reason);
                }
                let item = &mut self.items[index];
                match &item.binding {
                    Some(binding) if binding.base_present => item.state = State::Tombstone,
                    Some(binding) => {
                        let by = Some(binding.source.clone());
                        item.binding = None;
                        item.state = State::Retained { by };
                    }
                    None => item.state = State::Retained { by: None },
                }
                Outcome::Applied(Some(item.seq))
            }
            Action::Update {
                seq,
                filed,
                if_match,
            } => {
                let Some(index) = self.bound(collection, *seq) else {
                    return Outcome::Parked(String::from("the item is not bound yet"));
                };
                if let Some(reason) = self.gate(index, if_match.as_ref()) {
                    return Outcome::Parked(reason);
                }
                let name = ObjectName::of(&filed.bytes);
                self.objects.insert(name.clone(), filed.bytes.clone());
                let item = &mut self.items[index];
                item.object = Some(name);
                item.level = 2;
                item.summary = filed.summary.clone();
                item.addresses = filed.addresses.clone();
                item.sort_key = filed.sort_key.clone();
                Outcome::Applied(Some(item.seq))
            }
            Action::Move { seq, to } => self.apply_copy(collection, *seq, to, true),
            Action::Copy { seq, to } => self.apply_copy(collection, *seq, to, false),
        }
    }

    fn apply_add(
        &mut self,
        collection: &str,
        link_id: &str,
        flags: &BTreeSet<String>,
        filed: &Filed,
    ) -> Outcome {
        if self.live(collection).any(|item| item.link_id == link_id) {
            return Outcome::Parked(String::from("a live item holds the key"));
        }
        let seq = self.seq_for(collection, link_id, &filed.summary);
        let name = ObjectName::of(&filed.bytes);
        self.objects.insert(name.clone(), filed.bytes.clone());
        let binding = self.created(collection, link_id);
        self.items.push(Item {
            collection: String::from(collection),
            link_id: String::from(link_id),
            seq,
            flags: Some(flags.clone()),
            object: Some(name),
            level: 2,
            sort_key: filed.sort_key.clone(),
            state: State::Live,
            conflicted: false,
            conflict_object: None,
            summary: filed.summary.clone(),
            addresses: filed.addresses.clone(),
            binding,
        });
        Outcome::Applied(Some(seq))
    }

    fn apply_copy(&mut self, collection: &str, seq: i64, to: &str, moves: bool) -> Outcome {
        let Some(index) = self.bound(collection, seq) else {
            return Outcome::Parked(String::from("the item is not bound yet"));
        };
        let kind = self.collections.get(to).and_then(|target| target.kind);
        if kind.is_none() || kind != self.collections[collection].kind {
            return Outcome::Parked(format!("no collection {to} of the item's kind"));
        }
        if moves && to == collection {
            return Outcome::Parked(format!("a move into {to}, where the item is"));
        }
        if moves && self.conflict(index) {
            return Outcome::Parked(String::from("the item is in conflict"));
        }
        if self.items[index].object.is_none() {
            return Outcome::Parked(String::from("the item holds no body"));
        }

        let source = self.items[index].clone();
        let mut link_id = source.link_id.clone();
        let handle = format!("\u{1}{link_id}");
        while self.holds(to, &link_id) {
            link_id = format!("dup:{link_id}#{handle}");
        }
        let seq = self.seq_for(to, &link_id, &source.summary);
        let binding = self.created(to, &link_id);
        self.items.push(Item {
            collection: String::from(to),
            link_id,
            seq,
            state: State::Live,
            conflicted: false,
            conflict_object: None,
            binding,
            ..source
        });
        if moves {
            self.items[index].state = State::Tombstone;
        }
        Outcome::Applied(Some(seq))
    }

    fn created(&self, collection: &str, link_id: &str) -> Option<Binding> {
        self.collections[collection]
            .source
            .clone()
            .map(|source| Binding {
                source,
                handle: format!("\u{1}{link_id}"),
                base_flags: None,
                base_object: None,
                base_revision: None,
                base_present: false,
                shared_object: None,
                conflicted: false,
                conflict_revision: None,
                conflict_object: None,
                refusal: None,
                round: None,
            })
    }

    fn found(&self, collection: &str, seq: i64) -> Option<usize> {
        self.items.iter().position(|item| {
            item.collection == collection && item.seq == seq && item.state == State::Live
        })
    }

    /// The live item of `seq`, when the owner may act on it: one a source
    /// binds, a pending create included, in a synced collection, any in a
    /// local one (STORAGE §15.3).
    fn bound(&self, collection: &str, seq: i64) -> Option<usize> {
        let index = self.found(collection, seq)?;
        let synced = self.collections[collection].source.is_some();
        match (&self.items[index].binding, synced) {
            (Some(_), _) => Some(index),
            (None, false) => Some(index),
            _ => None,
        }
    }

    fn conflict(&self, index: usize) -> bool {
        let item = &self.items[index];
        item.conflicted
            || item
                .binding
                .as_ref()
                .is_some_and(|binding| binding.conflicted)
    }

    /// Why an `update` or a `remove` stating no resolution parks: a body
    /// other than the one it read, or a conflict (STORAGE §15.3).
    fn gate(&self, index: usize, if_match: Option<&ObjectName>) -> Option<String> {
        let item = &self.items[index];
        if let Some(name) = if_match
            && item.object.as_ref() != Some(name)
        {
            return Some(format!("if_match {} is not the item's body", name.0));
        }
        self.conflict(index)
            .then(|| String::from("the item is in conflict"))
    }
}

#[cfg(test)]
mod tests {
    use std::{env, fs, process};

    use rusqlite::types::Value;

    use crate::{
        model::{Model, State},
        oracle,
        profile::Profile,
        queue::{Action, RowState},
        spec::Spec,
        store::Store,
        writer,
    };

    fn structure() -> Model {
        let spec = Spec::load_default().unwrap();
        Profile::Structure.generate(&spec, 7).unwrap()
    }

    #[test]
    fn an_overlay_folds_an_update_chain_with_its_summary_and_drops_what_parks() {
        let model = structure();
        let shown = model.overlay("work/contacts");

        let rows: Vec<_> = model
            .queue
            .iter()
            .filter(|row| row.collection == "work/contacts" && row.state == RowState::Pending)
            .collect();
        let updates: Vec<_> = rows
            .iter()
            .filter_map(|row| match &row.action {
                Action::Update { seq, filed, .. } => Some((*seq, filed)),
                _ => None,
            })
            .collect();
        assert_eq!(updates.len(), 4);

        let (seq, second) = updates[1];
        let item = shown.iter().find(|item| item.seq == seq).unwrap();
        assert_eq!(
            item.summary, second.summary,
            "a folded update restates the summary"
        );
        assert_ne!(
            item.summary.get("fn"),
            Value::Text(String::from("Stale Edit"))
        );

        let (seq, _) = updates[3];
        let held = model.items.iter().find(|item| item.seq == seq).unwrap();
        let item = shown.iter().find(|item| item.seq == seq).unwrap();
        assert_eq!(
            item.summary, held.summary,
            "an update meeting a conflict folds into nothing"
        );

        let removed = rows
            .iter()
            .find_map(|row| match &row.action {
                Action::Remove { seq, .. } => Some(*seq),
                _ => None,
            })
            .unwrap();
        assert!(shown.iter().all(|item| item.seq != removed));

        let added = rows
            .iter()
            .find_map(|row| match &row.action {
                Action::Add { link_id, .. } => Some(link_id.clone()),
                _ => None,
            })
            .unwrap();
        assert!(shown.iter().any(|item| item.link_id == added));
    }

    #[test]
    fn an_overlay_shows_flags_changed_by_their_base_and_skips_a_base_over_unknown_flags() {
        let model = structure();
        let shown = model.overlay("work/INBOX");

        for row in model
            .queue
            .iter()
            .filter(|row| row.collection == "work/INBOX")
        {
            let Action::SetFlags { seq, base, .. } = &row.action else {
                continue;
            };
            let held = model
                .items
                .iter()
                .find(|item| item.collection == "work/INBOX" && item.seq == *seq)
                .unwrap();
            let item = shown.iter().find(|item| item.seq == *seq).unwrap();
            match (base, &held.flags) {
                (Some(_), None) => assert_eq!(item.flags, None),
                (Some(base), Some(flags)) => {
                    assert!(item.flags.as_ref().unwrap().contains("\\Seen"));
                    assert!(
                        flags
                            .iter()
                            .filter(|flag| base.contains(*flag))
                            .all(|flag| item.flags.as_ref().unwrap().contains(flag))
                    );
                }
                (None, _) => assert_eq!(item.flags.as_ref().unwrap().len(), 1),
            }
        }

        let moved = model
            .queue
            .iter()
            .filter(|row| row.state == RowState::Pending)
            .find_map(|row| match &row.action {
                Action::Move { seq, .. } => Some(*seq),
                _ => None,
            })
            .unwrap();
        assert!(shown.iter().all(|item| item.seq != moved));
        assert!(
            model
                .overlay("work/Archive")
                .iter()
                .all(|item| item.seq != moved),
            "a move queued on another collection is that collection's to fold"
        );
    }

    #[test]
    fn the_backstop_parks_by_what_the_sources_declare() {
        let model = structure();
        let shown = model.overlay("work/calendar");

        let scheduled = model
            .queue
            .iter()
            .filter(|row| row.collection == "work/calendar" && row.state == RowState::Pending)
            .find_map(|row| match &row.action {
                Action::Remove { seq, .. } => Some(*seq),
                _ => None,
            })
            .unwrap();
        assert!(
            shown.iter().any(|item| item.seq == scheduled),
            "a remove of a scheduled series parks where the source cannot schedule"
        );

        let copied = model
            .queue
            .iter()
            .find(|row| matches!(row.action, Action::Copy { .. }))
            .unwrap();
        assert!(
            matches!(&copied.state, RowState::Parked(reason) if reason.contains("mail.message.copy"))
        );

        let task = model
            .queue
            .iter()
            .find(|row| row.collection == "work/holidays")
            .unwrap();
        assert!(
            matches!(task.state, RowState::Applied(Some(_))),
            "a source stating no calendar.component.vtodo row refuses no task"
        );

        let performers: Vec<&RowState> = model
            .queue
            .iter()
            .filter(|row| matches!(row.action, Action::SetPerformer { .. }))
            .map(|row| &row.state)
            .collect();
        assert!(matches!(performers[0], RowState::Applied(None)));
        assert!(matches!(performers[1], RowState::Parked(_)));
        assert_eq!(performers[2], &RowState::Pending);
    }

    #[test]
    fn a_drained_store_is_one_the_canonical_statements_write_and_read_back() {
        let spec = Spec::load_default().unwrap();
        let mut model = structure();
        model.drain_all();

        assert!(
            model
                .items
                .iter()
                .any(|item| item.state == State::Tombstone && item.collection == "work/INBOX")
        );
        let dir = env::temp_dir().join(format!("pimdir-generator-drained-{}", process::id()));
        let _ = fs::remove_dir_all(&dir);
        let store = Store::create(&spec, &dir).unwrap();
        writer::materialise(&model, &store).unwrap();
        let expectations = oracle::expectations(&model, &spec).unwrap();
        let disagreements = oracle::check(&store, &expectations).unwrap();
        assert!(disagreements.is_empty(), "{disagreements:#?}");

        drop(store);
        fs::remove_dir_all(&dir).unwrap();
    }
}
