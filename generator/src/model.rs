//! # The model
//!
//! The truth a history moves, as plain values: the collections, items,
//! bindings, objects and sources a store holds, keyed and numbered by the
//! rules of STORAGE §9 and §9.1 as a writer applies them. It holds no SQL:
//! [`crate::writer`] turns it into a store and [`crate::oracle`] into what
//! each read of that store answers.

use std::collections::{BTreeMap, BTreeSet};

use rusqlite::types::Value;

use crate::{
    body::{Filed, Person, Stream, fnv1a64},
    name::ObjectName,
    queue::Row,
    time::Instant,
};

/// The kind a collection declares (STORAGE §13).
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Kind {
    /// `message/rfc822`.
    Mail,
    /// `text/vcard`.
    Contact,
    /// `text/calendar`.
    Calendar,
    /// `application/octet-stream`.
    File,
}

impl Kind {
    /// The media type `collections.kind` holds.
    pub fn media_type(&self) -> &'static str {
        match self {
            Self::Mail => "message/rfc822",
            Self::Contact => "text/vcard",
            Self::Calendar => "text/calendar",
            Self::File => "application/octet-stream",
        }
    }
}

/// One collection.
#[derive(Clone, Debug)]
pub struct Collection {
    /// Its id, namespaced by account where the store holds several.
    pub id: String,
    /// Its account, `None` in a single-account store.
    pub account: Option<String>,
    /// Its declared kind, `None` while undeclared (`''`).
    pub kind: Option<Kind>,
    /// Its display name.
    pub name: String,
    /// The role its source states, or none.
    pub role: Option<String>,
    /// The sources syncing it, none for a local collection.
    pub sources: BTreeMap<String, SourceState>,
    /// Its cross-source conflict policy, `manual`, `prefer-incoming` or
    /// `prefer-existing` (STORAGE §13).
    pub conflict: String,
    /// Its handle-space epoch, from 1, bumped by a rekey (STORAGE §12).
    pub generation: i64,
    /// The collection it sits under in its account's hierarchy, none at
    /// the top (STORAGE §14).
    pub parent: Option<String>,
    /// How it is shown, as its source states it.
    pub presentation: Presentation,
}

/// How a collection is shown, each part as its source states it or none
/// (STORAGE §14).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Presentation {
    /// A color as written.
    pub color: Option<String>,
    /// A description.
    pub description: Option<String>,
    /// Its position among its siblings.
    pub sort_order: Option<i64>,
}

impl Collection {
    /// The source an action queued on it runs as, its first (STORAGE
    /// §15.2), or none for a local collection.
    pub fn source(&self) -> Option<&String> {
        self.sources.keys().next()
    }
}

/// One source's sync state in a collection (STORAGE §4.3).
#[derive(Clone, Debug, Default)]
pub struct SourceState {
    /// The checkpoint it last recorded.
    pub checkpoint: Option<Vec<u8>>,
    /// The last round id it drew, the open round's when one is.
    pub rounds: i64,
    /// The scope its last closed round covers, none before one closed.
    pub coverage: Option<Scope>,
    /// The round it opened and did not close, a parked one.
    pub open: Option<OpenRound>,
}

/// A round left open, its last page landed as one before the last (SYNC
/// §5).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpenRound {
    /// What it lists.
    pub scope: Scope,
    /// The checkpoint its pages landed, the source's once it closes.
    pub checkpoint: Option<Vec<u8>>,
    /// The resume cursor its last page landed, none for a parked round,
    /// which resumes from its first page.
    pub cursor: Option<String>,
    /// Whether it lists only the band its coverage lacks (SYNC §5).
    pub band: bool,
}

/// `[since, until)` on a message's summary `date`, either bound open (SYNC
/// §2).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Scope {
    /// Its floor.
    pub since: Option<Instant>,
    /// Its ceiling, excluded.
    pub until: Option<Instant>,
}

impl Scope {
    /// Whether a member dated `date` is in scope: an undated one always is.
    pub fn holds(&self, date: Option<&str>) -> bool {
        let Some(date) = date else {
            return true;
        };
        self.since
            .is_none_or(|since| date >= since.rfc3339().as_str())
            && self
                .until
                .is_none_or(|until| date < until.rfc3339().as_str())
    }

    /// Whether it lies inside `other`, which its checkpoint then serves.
    pub fn within(&self, other: &Scope) -> bool {
        let floor = match (self.since, other.since) {
            (_, None) => true,
            (None, Some(_)) => false,
            (Some(own), Some(other)) => own >= other,
        };
        let ceiling = match (self.until, other.until) {
            (_, None) => true,
            (None, Some(_)) => false,
            (Some(own), Some(other)) => own <= other,
        };
        floor && ceiling
    }

    /// The band it adds to `coverage` on one side, adjoining it, which a
    /// round may list alone when its source's checkpoint is bound to no
    /// scope (SYNC §5); none when it widens both sides or none.
    pub fn band(&self, coverage: &Scope) -> Option<Scope> {
        let lower = match (self.since, coverage.since) {
            (None, Some(floor)) => Some((None, floor)),
            (Some(own), Some(floor)) if own < floor => Some((Some(own), floor)),
            _ => None,
        };
        let upper = match (self.until, coverage.until) {
            (None, Some(ceiling)) => Some((ceiling, None)),
            (Some(own), Some(ceiling)) if own > ceiling => Some((ceiling, Some(own))),
            _ => None,
        };
        let same_floor = self.since == coverage.since;
        let same_ceiling = self.until == coverage.until;
        match (lower, upper) {
            (Some((since, floor)), None) if same_ceiling => Some(Scope {
                since,
                until: Some(floor),
            }),
            (None, Some((ceiling, until))) if same_floor => Some(Scope {
                since: Some(ceiling),
                until,
            }),
            _ => None,
        }
    }
    /// Its bounds as the store holds them, `NULL` for an open one.
    pub fn values(&self) -> (Value, Value) {
        let bound = |instant: Option<Instant>| {
            instant.map_or(Value::Null, |instant| Value::Text(instant.rfc3339()))
        };
        (bound(self.since), bound(self.until))
    }
}

/// The sync state of a collection its `sources` sync, none of them synced
/// yet.
pub fn synced_by<S: AsRef<str>>(sources: &[S]) -> BTreeMap<String, SourceState> {
    sources
        .iter()
        .map(|source| (String::from(source.as_ref()), SourceState::default()))
        .collect()
}

/// The table a summary row lives in (STORAGE §4.3).
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Table {
    /// `mail_summary`.
    Mail,
    /// `contact_summary`.
    Contact,
    /// `event_summary`.
    Event,
    /// `task_summary`.
    Task,
    /// `journal_summary`.
    Journal,
    /// `file_summary`.
    File,
}

impl Table {
    /// The kind of the collection an item of this table is filed in.
    pub fn kind(&self) -> Kind {
        match self {
            Self::Mail => Kind::Mail,
            Self::Contact => Kind::Contact,
            Self::Event | Self::Task | Self::Journal => Kind::Calendar,
            Self::File => Kind::File,
        }
    }

    /// The suffix of its statements' names, `mail` for
    /// `upsert_mail_summary`.
    pub fn stem(&self) -> &'static str {
        match self {
            Self::Mail => "mail",
            Self::Contact => "contact",
            Self::Event => "event",
            Self::Task => "task",
            Self::Journal => "journal",
            Self::File => "file",
        }
    }
}

/// A summary row of Annex A, its columns by name, and the lists it
/// derives.
#[derive(Clone, Debug, PartialEq)]
pub struct Summary {
    /// Its table.
    pub table: Table,
    /// Its columns but `item`, by name.
    pub columns: BTreeMap<String, Value>,
    /// A message's `In-Reply-To` ids, in document order.
    pub in_reply_to: Vec<String>,
    /// A task's categories, in document order.
    pub categories: Vec<String>,
}

impl Summary {
    /// An empty row of `table`.
    pub fn new(table: Table) -> Self {
        Self {
            table,
            columns: BTreeMap::new(),
            in_reply_to: Vec::new(),
            categories: Vec::new(),
        }
    }

    /// Sets the column `name`.
    pub fn set(&mut self, name: &str, value: Value) {
        self.columns.insert(String::from(name), value);
    }

    /// The column `name`, `NULL` when the row does not state it.
    pub fn get(&self, name: &str) -> Value {
        self.columns.get(name).cloned().unwrap_or(Value::Null)
    }
}

/// One row of `item_address` (STORAGE Annex A.6).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Address {
    /// Its role.
    pub role: String,
    /// Its 0-based position within the role.
    pub position: i64,
    /// The canonical address.
    pub address: String,
    /// The display name, or none.
    pub name: Option<String>,
}

impl Address {
    /// The row naming `person` at `position` under `role`.
    pub fn of(role: &str, position: usize, person: &Person) -> Self {
        Self {
            role: String::from(role),
            position: position as i64,
            address: person.address.clone(),
            name: person.name.clone(),
        }
    }
}

/// One source's binding of an item, after a sync that agreed on it.
#[derive(Clone, Debug)]
pub struct Binding {
    /// The source.
    pub source: String,
    /// The handle it knows the item by.
    pub handle: String,
    /// The base flag set, `None` unknown.
    pub base_flags: Option<BTreeSet<String>>,
    /// The base body.
    pub base_object: Option<ObjectName>,
    /// The base revision.
    pub base_revision: Option<String>,
    /// Whether a base exists: a pending create holds none.
    pub base_present: bool,
    /// The body last agreed with the shared item.
    pub shared_object: Option<ObjectName>,
    /// Whether the binding is in conflict with its remote.
    pub conflicted: bool,
    /// The remote revision observed in conflict.
    pub conflict_revision: Option<String>,
    /// The remote body observed in conflict, `None` while unread.
    pub conflict_object: Option<ObjectName>,
    /// The refusal standing on the binding (SYNC §5).
    pub refusal: Option<Refusal>,
    /// The id of the last round that listed its handle.
    pub round: Option<i64>,
}

/// A change a remote refused for good (STORAGE §13).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Refusal {
    /// The reason it gave.
    pub reason: String,
    /// The idempotency key of the change, sixteen hexadecimal digits.
    pub key: String,
}

/// One item, its row of `items` and what hangs off it.
#[derive(Clone, Debug)]
pub struct Item {
    /// Its collection.
    pub collection: String,
    /// Its key (STORAGE §9).
    pub link_id: String,
    /// Its public id (STORAGE §9.1).
    pub seq: i64,
    /// Its flag set, `None` unknown.
    pub flags: Option<BTreeSet<String>>,
    /// Its body, `None` when not held.
    pub object: Option<ObjectName>,
    /// Its level, 1 meta or 2 full.
    pub level: i64,
    /// Its sort key.
    pub sort_key: String,
    /// Whether it is live, a tombstone or retained.
    pub state: State,
    /// Whether two sources disagree on it (SYNC §9).
    pub conflicted: bool,
    /// The diverging body, `None` while unread.
    pub conflict_object: Option<ObjectName>,
    /// Its summary row.
    pub summary: Summary,
    /// Its address rows.
    pub addresses: Vec<Address>,
    /// Its bindings, one per source binding it, in source order.
    pub bindings: Vec<Binding>,
}

/// The state of an item's row (STORAGE §11).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum State {
    /// Live: `deleted` 0.
    Live,
    /// A tombstone a source still binds: `deleted` 1, no `retained_at`.
    Tombstone,
    /// Retained: `deleted` 1, `retained_at` stamped, no binding.
    Retained {
        /// The source whose removal retired it.
        by: Option<String>,
    },
}

impl Item {
    /// Its summary `date`, a message's alone, which a scope reads (SYNC §2).
    pub fn date(&self) -> Option<String> {
        match (self.summary.table, self.summary.get("date")) {
            (Table::Mail, Value::Text(date)) => Some(date),
            _ => None,
        }
    }

    /// The binding `source` holds of it.
    pub fn bound(&self, source: &str) -> Option<&Binding> {
        self.bindings
            .iter()
            .find(|binding| binding.source == source)
    }

    /// The binding `source` holds of it, to write.
    pub fn bound_mut(&mut self, source: &str) -> Option<&mut Binding> {
        self.bindings
            .iter_mut()
            .find(|binding| binding.source == source)
    }

    /// Adds a binding, the bindings kept in source order.
    pub fn bind(&mut self, binding: Binding) {
        let at = self
            .bindings
            .partition_point(|held| held.source < binding.source);
        self.bindings.insert(at, binding);
    }
}

/// How an item is placed in a collection.
#[derive(Clone, Debug, Default)]
pub struct Placement {
    /// Its flag set, `None` unknown.
    pub flags: Option<BTreeSet<String>>,
    /// Whether the store holds its body.
    pub held: bool,
    /// The handle its source knows it by, for a synced collection.
    pub handle: Option<String>,
    /// The revision its source states.
    pub revision: Option<String>,
    /// The source binding it, its collection's first when none is named.
    pub source: Option<String>,
}

/// The truth of one store.
#[derive(Clone, Debug, Default)]
pub struct Model {
    /// The collections by id.
    pub collections: BTreeMap<String, Collection>,
    /// The items in the order they were filed, the order seqs were drawn.
    pub items: Vec<Item>,
    /// The bodies by name.
    pub objects: BTreeMap<ObjectName, Vec<u8>>,
    /// The bodies too large to hold, by name, rendered when written.
    pub streams: BTreeMap<ObjectName, Stream>,
    /// The rows the bodies an item does not hold derive, a diverging one
    /// kept for an item that may adopt it later.
    pub rows: BTreeMap<ObjectName, Derived>,
    /// The next `seq` to draw, `store_meta.next_seq`.
    pub next_seq: i64,
    /// The rows purged, objects collected and collections deleted or
    /// renamed, `store_meta.purges` (STORAGE §4.5).
    pub purges: i64,
    /// The queue's rows, applied ones included, by id.
    pub queue: Vec<Row>,
    /// What each source declares it can do (STORAGE §15.6).
    pub capabilities: Vec<Capability>,
    /// The performer chosen per account and capability.
    pub performers: BTreeMap<(Option<String>, String), String>,
    /// The references between items (STORAGE §14.2).
    pub references: Vec<Reference>,
}

/// What Annex A derives from a body, kept apart from any item.
#[derive(Clone, Debug)]
pub struct Derived {
    /// Its summary row.
    pub summary: Summary,
    /// Its address rows.
    pub addresses: Vec<Address>,
    /// Its sort key.
    pub sort_key: String,
}

/// One row a source declares (STORAGE §15.6, Annex B).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Capability {
    /// The account the source syncs for.
    pub account: Option<String>,
    /// The source.
    pub source: String,
    /// The collection it overrides the source-wide row in, if any.
    pub collection: Option<String>,
    /// The capability's name.
    pub name: String,
    /// `full`, `partial` or `none`.
    pub support: String,
    /// What a person reads about it.
    pub detail: Option<String>,
}

/// A reference from one item to another (STORAGE §14.2).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Reference {
    /// The kind of the collection holding its start.
    pub from_kind: Kind,
    /// The key of its start.
    pub from_link_id: String,
    /// The kind of the collection holding its end.
    pub to_kind: Kind,
    /// The key of its end.
    pub to_link_id: String,
    /// Its role.
    pub role: String,
    /// `auto` for a rule's, `user` for a person's.
    pub origin: String,
}

/// The prefixes a writer derives keys under (STORAGE §9).
pub const RESERVED: [&str; 6] = ["alt:", "hash:", "dup:", "part:", "file:", "esc:"];

/// The system flags `marks` holds, each by its exact bytes (STORAGE §13).
pub const MARKS: [(&str, i64); 5] = [
    ("\\Seen", 1),
    ("\\Answered", 2),
    ("\\Flagged", 4),
    ("\\Draft", 8),
    ("\\Deleted", 16),
];

impl Model {
    /// An empty store's truth.
    pub fn new() -> Self {
        Self {
            next_seq: 1,
            ..Self::default()
        }
    }

    /// Declares a collection.
    pub fn declare(&mut self, collection: Collection) {
        self.collections.insert(collection.id.clone(), collection);
    }

    /// Files a body in `collection` as a writer naming it does: the key
    /// from the hint, escaped, or the fallback, minted over the handle
    /// while held (STORAGE §9), the `seq` shared or drawn (§9.1).
    pub fn file(&mut self, collection: &str, filed: Filed, placement: Placement) -> usize {
        let base = key(&filed);
        let handle = placement
            .handle
            .clone()
            .unwrap_or_else(|| format!("\u{1}{base}"));
        let mut link_id = base;
        while self.holds(collection, &link_id) {
            link_id = format!("dup:{link_id}#{handle}");
        }

        let seq = self.seq_for(collection, &link_id, &filed.summary);
        self.place(collection, link_id, seq, handle, filed, placement)
    }

    /// Files a body under a key and a `seq` the caller settled as
    /// [`Model::file`] would, the binding under `handle`: a profile filing
    /// fresh identities at scale, which a scan of every held key per item
    /// would not finish.
    pub fn place(
        &mut self,
        collection: &str,
        link_id: String,
        seq: i64,
        handle: String,
        filed: Filed,
        placement: Placement,
    ) -> usize {
        let object = ObjectName::of(&filed.bytes);
        if placement.held {
            self.objects.insert(object.clone(), filed.bytes.clone());
        }
        let object = placement.held.then_some(object);

        let source = placement
            .source
            .clone()
            .or_else(|| self.collections[collection].source().cloned());
        let binding = source.map(|source| Binding {
            source,
            handle,
            base_flags: placement.flags.clone(),
            base_object: object.clone(),
            base_revision: placement.revision.clone(),
            base_present: true,
            shared_object: object.clone(),
            conflicted: false,
            conflict_revision: None,
            conflict_object: None,
            refusal: None,
            round: None,
        });

        self.items.push(Item {
            collection: String::from(collection),
            link_id,
            seq,
            flags: placement.flags,
            level: if object.is_some() { 2 } else { 1 },
            object,
            sort_key: filed.sort_key,
            state: State::Live,
            conflicted: false,
            conflict_object: None,
            summary: filed.summary,
            addresses: filed.addresses,
            bindings: binding.into_iter().collect(),
        });
        self.items.len() - 1
    }

    /// Marks the item at `index` deleted while its source still binds it, a
    /// tombstone whose delete is still to push (STORAGE §10).
    pub fn tombstone(&mut self, index: usize) {
        self.items[index].state = State::Tombstone;
    }

    /// Retains the item at `index` as its last binding goes, its body kept
    /// (STORAGE §11).
    pub fn retain(&mut self, index: usize) {
        let item = &mut self.items[index];
        let by = item.bindings.first().map(|binding| binding.source.clone());
        item.bindings.clear();
        item.state = State::Retained { by };
    }

    /// Whether a row of `collection` holds `link_id`, whatever its state.
    pub fn holds(&self, collection: &str, link_id: &str) -> bool {
        self.items
            .iter()
            .any(|item| item.collection == collection && item.link_id == link_id)
    }

    /// The live items of `collection`, in filing order.
    pub fn live(&self, collection: &str) -> impl Iterator<Item = &Item> {
        self.items
            .iter()
            .filter(move |item| item.collection == collection && item.state == State::Live)
    }

    pub(crate) fn seq_for(&mut self, collection: &str, link_id: &str, summary: &Summary) -> i64 {
        let derived = ["alt:", "hash:", "dup:"]
            .iter()
            .any(|prefix| link_id.starts_with(prefix));
        let kind = self.collections[collection].kind;

        if !derived {
            let agrees = |held: &Summary| {
                summary.table != Table::Mail
                    || ["subject", "date", "sender"]
                        .iter()
                        .all(|column| held.get(column) == summary.get(column))
            };
            let shared = self
                .items
                .iter()
                .filter(|item| item.link_id == link_id)
                .filter(|item| self.collections[&item.collection].kind == kind)
                .filter(|item| agrees(&item.summary))
                .map(|item| item.seq)
                .min();
            if let Some(seq) = shared {
                return seq;
            }
        }

        let seq = self.next_seq;
        self.next_seq += 1;
        seq
    }

    /// The size of a body held or streamed.
    pub fn object_size(&self, name: &ObjectName) -> usize {
        match self.objects.get(name) {
            Some(bytes) => bytes.len(),
            None => self.streams[name].size(),
        }
    }

    /// Gives the item at `index` a body too large to hold, named `name`
    /// ([`Stream::name`]), its bindings based on it as on a body held.
    pub fn hold_stream(&mut self, index: usize, name: ObjectName, stream: Stream) {
        let item = &mut self.items[index];
        item.object = Some(name.clone());
        item.level = 2;
        for binding in &mut item.bindings {
            binding.base_object = Some(name.clone());
            binding.shared_object = Some(name.clone());
        }
        self.streams.insert(name, stream);
    }

    /// Draws the next `seq`, for an identity no item holds (STORAGE §9.1).
    pub fn fresh_seq(&mut self) -> i64 {
        let seq = self.next_seq;
        self.next_seq += 1;
        seq
    }
}

/// The marks of a flag set and its other flags (STORAGE §13).
pub fn split_flags(flags: &BTreeSet<String>) -> (i64, Vec<String>) {
    let mut marks = 0;
    let mut others = Vec::new();
    for flag in flags {
        match MARKS.iter().find(|(name, _)| name == flag) {
            Some((_, bit)) => marks |= bit,
            None => others.push(flag.clone()),
        }
    }
    (marks, others)
}

/// The key a writer assigns from what a body declares, before minting:
/// its hint, escaped before a reserved prefix, else its kind's fallback
/// (STORAGE §9).
pub fn key(filed: &Filed) -> String {
    match &filed.hint {
        Some(hint) if RESERVED.iter().any(|prefix| hint.starts_with(prefix)) => {
            format!("esc:{hint}")
        }
        Some(hint) => hint.clone(),
        None => fallback(filed),
    }
}

pub(crate) fn fallback(filed: &Filed) -> String {
    match filed.summary.table {
        Table::Mail => {
            let text = |column: &str| match filed.summary.get(column) {
                Value::Text(text) => text,
                _ => String::new(),
            };
            format!(
                "alt:{}|{}|{}",
                text("subject"),
                text("date"),
                text("sender")
            )
        }
        Table::File => filed.fallback.clone().unwrap_or_default(),
        _ => format!("hash:{}", fnv1a64(&filed.bytes)),
    }
}
