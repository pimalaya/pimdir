//! # The engine
//!
//! The model of SYNC's verbs over one source and one collection at a time:
//! a first round in pages, deltas, the flag axis merged over `(local, base,
//! remote)`, the content axis of a mutable kind under the source's policy,
//! stated removals and a closed round's absences dropped, moves and copies
//! by origins, destinations, deliveries and landings, the consumer's
//! tombstones, creates and changes pushed and answered accepted, rejected
//! or refused, and an upgrade fetching bodies (SYNC §3 to §6). A run
//! answers what it listed, fetched and pushed, the outcomes and the
//! events, and leaves the model as the store stands after it.
//!
//! The model runs only what it states exactly: one source per collection,
//! no scope, every right, no head, no rekey, which later parts add
//! (README.md, "Limits").

use std::{
    collections::{BTreeMap, BTreeSet},
    mem,
};

use rusqlite::types::Value;

use crate::{
    body::Filed,
    model::{
        Address, Binding, Item, Model, OpenRound, Placement, Refusal, Scope, SourceState, State,
        Summary, Table, key,
    },
    name::ObjectName,
    remote::{Listed, Page, Policy, Remote},
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
    /// What the remote answered.
    pub answer: Answer,
    /// The handle an accepted add was assigned.
    pub assigned: Option<String>,
    /// The revision a mutable member holds once accepted.
    pub revision: Option<String>,
    /// Whether an accepted relocating `Remove` relocated the member.
    pub relocated: Option<bool>,
}

/// What a remote answers one change (SYNC §4).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Answer {
    /// Taken.
    Accepted,
    /// Failed on a precondition a later listing moves past.
    Rejected,
    /// Refused for good as it stands, for this reason.
    Refused(String),
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
    /// An add accepted under its assigned handle, or a create landed.
    Created(String),
    /// A body a policy did not adopt, kept as the retained item it names.
    Overruled {
        /// The handle of the binding that settled it.
        handle: String,
        /// The retained item's key.
        link_id: String,
    },
    /// A change refused this run, or held for a refusal standing.
    Refused {
        /// The handle it was pushed for.
        handle: String,
        /// The reason the remote gave.
        reason: String,
    },
}

/// What a sync is asked (SYNC §5).
#[derive(Clone, Debug, Default)]
pub struct Options {
    /// The scope it lists, a mail collection's.
    pub scope: Scope,
    /// Whether a mass or an empty listing's absences close the round.
    pub accept_absences: bool,
}

/// One verb run over one collection and the script it ran against.
#[derive(Clone, Debug)]
pub struct Run {
    /// `sync`, `upgrade` or `rekey`.
    pub verb: &'static str,
    /// What it was asked, a vector's `run.options`: the scope and whether
    /// absences are accepted.
    pub options: Options,
    /// The source's conflict policy against its remote (SYNC §5).
    pub policy: Policy,
    /// The handles an upgrade raised, none for another verb.
    pub handles: Vec<String>,
    /// The collection.
    pub collection: String,
    /// The source.
    pub source: String,
    /// The head listed before a resumed round's pages, if any.
    pub head: Option<Page>,
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
    /// A round left open by a mass or an empty listing's absence: the
    /// based bindings it found absent and those in its scope (SYNC §5).
    pub parked: Option<(usize, usize)>,
    /// How many based bindings a closing round, capped or narrowed handing
    /// no enumeration, left unlisted, none when it left none (SYNC §5).
    pub unlisted: Option<usize>,
    /// Whether the run failed: interrupted between two pages, or cut after a
    /// push the remote took and before the write recording its outcome.
    pub failed: bool,
}

impl Model {
    /// Syncs `remote`'s collection alone under no scope: [`Model::sync_with`]
    /// and the default options.
    pub fn sync(&mut self, remote: &mut Remote, size: usize) -> Run {
        self.sync_with(remote, size, &Options::default())
    }

    /// Syncs `remote`'s collection alone: [`Model::sync_in`] over the one
    /// remote.
    pub fn sync_with(&mut self, remote: &mut Remote, size: usize, options: &Options) -> Run {
        let collection = remote.collection.clone();
        let mut remotes = BTreeMap::from([(collection.clone(), remote.clone())]);
        let run = self.sync_in(&mut remotes, &collection, size, options);
        *remote = remotes.remove(&collection).expect("the remote synced");
        run
    }

    /// Syncs `collection` against its remote among `remotes`, the other
    /// collections of the source's account being where a relocation goes,
    /// choosing its listing as SYNC §5 does: the open round resumed when it
    /// lists the scope asked for, a round of pages of `size` opened when no
    /// round closed, one is open over another scope or the scope reaches
    /// outside the coverage (the band it lacks alone where the checkpoint is
    /// bound to no scope), else a delta from the checkpoint, recording a
    /// narrower scope as the coverage. A resumed round lists its delta head
    /// first where the connector lists heads; one whose cursor the source
    /// rejects restarts under a new id; a page handing no cursor, or a cut,
    /// fails the run with what landed kept.
    pub fn sync_in(
        &mut self,
        remotes: &mut BTreeMap<String, Remote>,
        collection: &str,
        size: usize,
        options: &Options,
    ) -> Run {
        let collection = String::from(collection);
        let source = remotes[&collection].source.clone();
        let state = self.collections[&collection]
            .sources
            .get(&source)
            .cloned()
            .unwrap_or_default();
        let scope = &options.scope;
        let band = match remotes[&collection].scope_bound {
            true => None,
            false => state
                .coverage
                .as_ref()
                .and_then(|coverage| scope.band(coverage)),
        };
        let banded = band.is_some();
        let target = band.unwrap_or_else(|| scope.clone());
        let open = state
            .open
            .as_ref()
            .filter(|open| open.scope == target && open.band == banded);
        let (listing, mut round) = match (&state.open, &state.coverage) {
            _ if open.is_some() => (true, state.rounds),
            (Some(_), _) | (None, None) => (true, state.rounds + 1),
            (None, Some(coverage)) if !scope.within(coverage) => (true, state.rounds + 1),
            _ => (false, state.rounds),
        };
        let remote = remotes.get_mut(&collection).expect("a remote");
        let mut cursor = open.and_then(|open| open.cursor.clone());
        let mut landed = open.and_then(|open| open.checkpoint.clone());
        let restarted = cursor.is_some() && mem::take(&mut remote.reject_cursor);
        if restarted {
            round = state.rounds + 1;
            cursor = None;
            landed = None;
        }
        let resuming = open.is_some() && !restarted;
        let from = match banded {
            true => state.checkpoint.clone(),
            false => landed.clone(),
        };
        let head = from
            .filter(|_| resuming && remote.delta_heads)
            .map(|from| remote.delta(&String::from_utf8_lossy(&from), scope));
        let dropped = remote.drop_cursor.take();
        let remote = &remotes[&collection];
        let mut pages = match listing {
            true => remote.round_from(size, &target, cursor.as_deref()),
            false => {
                let checkpoint = state.checkpoint.clone().unwrap_or_default();
                vec![remote.delta(&String::from_utf8_lossy(&checkpoint), scope)]
            }
        };
        if let Some(page) = dropped
            .and_then(|at| pages.get_mut(at))
            .filter(|page| !page.last)
        {
            page.cursor = None;
        }
        if banded {
            for page in &mut pages {
                page.checkpoint = None;
                page.items
                    .retain(|member| remote.members[&member.handle].date().is_some());
            }
        }
        let refused = pages
            .iter()
            .position(|page| !page.last && page.cursor.is_none());
        if let Some(at) = refused {
            pages.truncate(at);
        }
        let interrupt = remotes
            .get_mut(&collection)
            .expect("a remote")
            .interrupt
            .take();
        let interrupted =
            refused.is_some() || (listing && interrupt.is_some_and(|after| after < pages.len()));
        if let (None, Some(after)) = (refused, interrupt.filter(|_| interrupted)) {
            pages.truncate(after);
        }
        let policy = remotes[&collection].policy;
        let mut events = Vec::new();
        let mut listed: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
        let mut owing: BTreeSet<String> = BTreeSet::new();

        for page in head.iter().chain(pages.iter()) {
            for member in &page.items {
                listed.insert(member.handle.clone(), member.flags.clone());
                let filed = remotes[&collection].members[&member.handle].filed.clone();
                let index = match self.bound_handle(&collection, &source, &member.handle) {
                    Some(index) => {
                        if self.refresh(index, member, &filed, &source, policy, &mut events) {
                            owing.insert(member.handle.clone());
                        }
                        index
                    }
                    None => match self.landing(&collection, &source, &filed) {
                        Some(index) => {
                            self.land(index, member, &source);
                            events.push(Event::Created(member.handle.clone()));
                            index
                        }
                        None => match self.joining(&collection, &source, &filed) {
                            Some(index) => {
                                if self.join(index, member, &filed, &source, &mut events) {
                                    owing.insert(member.handle.clone());
                                }
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
                                    source: Some(source.clone()),
                                };
                                events.push(Event::Added(member.handle.clone()));
                                self.file(&collection, filed, placement)
                            }
                        },
                    },
                };
                if listing {
                    let binding = self.items[index].bound_mut(&source).expect("a bound item");
                    binding.round = Some(round);
                }
            }
            for handle in &page.vanished {
                if let Some(index) = self.bound_handle(&collection, &source, handle) {
                    self.drop_deleted(index, &source);
                    events.push(Event::Vanished(handle.clone()));
                }
            }
        }

        let checkpoint = pages
            .iter()
            .rev()
            .chain(head.iter())
            .find_map(|page| page.checkpoint.clone())
            .map(String::into_bytes)
            .or(landed);
        if interrupted {
            let entry = self.sync_state(&collection, &source);
            entry.rounds = round;
            entry.open = Some(OpenRound {
                scope: target,
                band: banded,
                checkpoint,
                cursor: pages.last().and_then(|page| page.cursor.clone()).or(cursor),
            });
            return Run {
                verb: "sync",
                options: options.clone(),
                policy,
                handles: Vec::new(),
                collection,
                source,
                head,
                pages,
                fetch: BTreeMap::new(),
                pushes: Vec::new(),
                outcomes: Vec::new(),
                events,
                parked: None,
                unlisted: None,
                failed: true,
            };
        }

        let (parked, unlisted) = match listing {
            true => {
                let named = head.as_ref().is_some_and(|head| !head.items.is_empty());
                let listed = Listing {
                    pages: &pages,
                    named,
                    scope: &target,
                    band: banded,
                };
                self.absences(&collection, &source, round, listed, options, &mut events)
            }
            false => (None, None),
        };
        let entry = self.sync_state(&collection, &source);
        entry.rounds = round;
        match (listing, parked) {
            (true, Some(_)) => {
                entry.open = Some(OpenRound {
                    scope: target.clone(),
                    band: banded,
                    checkpoint,
                    cursor: None,
                });
            }
            (true, None) => {
                if let Some(checkpoint) = checkpoint {
                    entry.checkpoint = Some(checkpoint);
                }
                entry.open = None;
                entry.coverage = Some(scope.clone());
            }
            (false, _) => {
                if let Some(checkpoint) = checkpoint {
                    entry.checkpoint = Some(checkpoint);
                }
                entry.coverage = Some(scope.clone());
            }
        }

        let mutable = remotes[&collection].mutable;
        let pushes: Vec<Push> = self
            .derive(
                &collection,
                &source,
                &listed,
                mutable,
                scope,
                parked.is_none(),
            )
            .into_iter()
            .filter(|push| !matches!(push, Push::Update { handle, .. } if owing.contains(handle)))
            .filter(|push| {
                let held = self
                    .refusal_on(&collection, &source, push.handle())
                    .filter(|refusal| refusal.key == push.key(&collection));
                if let Some(refusal) = &held {
                    events.push(Event::Refused {
                        handle: String::from(push.handle()),
                        reason: refusal.reason.clone(),
                    });
                }
                held.is_none()
            })
            .collect();
        let crash = remotes.get_mut(&collection).expect("a remote").crash.take();
        let mut outcomes = Vec::new();
        let mut failed = false;
        let mut pushes = pushes;
        for (at, push) in pushes.iter().enumerate() {
            if crash == Some(at + 1) {
                let written = self.clone();
                outcomes.push(self.push(remotes, &collection, push, &mut Vec::new()));
                *self = written;
                failed = true;
                break;
            }
            outcomes.push(self.push(remotes, &collection, push, &mut events));
        }
        pushes.truncate(outcomes.len());

        Run {
            verb: "sync",
            options: options.clone(),
            policy,
            handles: Vec::new(),
            pushes: pushes
                .into_iter()
                .map(|push| {
                    let key = push.key(&collection);
                    (push, key)
                })
                .collect(),
            collection,
            source,
            head,
            pages,
            fetch: BTreeMap::new(),
            outcomes,
            events,
            parked,
            unlisted,
            failed,
        }
    }

    /// What a round finds absent once its last page lands (SYNC §5): the
    /// based bindings of the source in the round's scope, an undated item
    /// in it, that no page stamped, none under a provisional handle; for a
    /// narrowed last page only those its enumeration lacks, none when it
    /// hands none; none for a capped one. They are dropped `Deleted`, unless
    /// more than half of at least 20 in scope or any after a listing naming
    /// nothing are, which parks the round, answered as the absent and the
    /// bound counts, unless the run accepts absences. A closing round that
    /// is capped, or narrowed handing no enumeration, answers too how many
    /// it left unlisted, counted as the deletes are, when it left any.
    fn absences(
        &mut self,
        collection: &str,
        source: &str,
        round: i64,
        listing: Listing,
        options: &Options,
        events: &mut Vec<Event>,
    ) -> (Option<(usize, usize)>, Option<usize>) {
        let pages = listing.pages;
        let Some(last) = pages.last() else {
            return (None, None);
        };
        let scoped: Vec<(String, bool)> = self
            .items
            .iter()
            .filter(|item| item.collection == collection)
            .filter(|item| match item.date() {
                Some(date) => listing.scope.holds(Some(&date)),
                None => !listing.band,
            })
            .filter_map(|item| item.bound(source))
            .filter(|binding| binding.base_present && !binding.handle.starts_with('\u{1}'))
            .map(|binding| (binding.handle.clone(), binding.round == Some(round)))
            .collect();
        let unstamped: Vec<String> = scoped
            .iter()
            .filter(|(_, stamped)| !stamped)
            .map(|(handle, _)| handle.clone())
            .collect();
        let undecided = last.capped || (last.narrowed && last.enumerated.is_none());
        let unlisted = (undecided && !unstamped.is_empty()).then_some(unstamped.len());
        let absent: Vec<String> = unstamped
            .into_iter()
            .filter(|handle| match (last.narrowed, &last.enumerated) {
                (false, _) => !last.capped,
                (true, Some(enumerated)) => !last.capped && !enumerated.contains(handle),
                (true, None) => false,
            })
            .collect();

        let named = listing.named || pages.iter().any(|page| !page.items.is_empty());
        let mass = absent.len() * 2 > scoped.len() && scoped.len() >= 20;
        let empty = !named && !absent.is_empty();
        if (mass || empty) && !options.accept_absences {
            return (Some((absent.len(), scoped.len())), None);
        }
        for handle in absent {
            if let Some(index) = self.bound_handle(collection, source, &handle) {
                self.drop_deleted(index, source);
                events.push(Event::Vanished(handle));
            }
        }
        (None, unlisted)
    }

    /// Rebuilds `remote`'s collection after its source renumbered every
    /// member (SYNC §8): one round over the whole collection read before its
    /// one write, each based binding of the source carried onto the member
    /// resolving to its link id (the copy whose base names the listed
    /// revision first, then the one whose base holds the carried body, then
    /// in old handle order), a member of a mutable kind listed at another
    /// revision pulled to `Meta`, or recorded in conflict over a local edit,
    /// and every binding no member resolves to dropped `Deleted`, the
    /// collection's generation bumped. A rekey missing more than half of at
    /// least 20, naming no member while any is missing, or capped while any
    /// is, writes nothing and parks unless the run accepts absences.
    pub fn rekey(&mut self, remote: &Remote, options: &Options) -> Run {
        let collection = remote.collection.clone();
        let source = remote.source.clone();
        let pages = remote.round(usize::MAX, &Scope::default());
        let mut members: Vec<&Listed> = pages.iter().flat_map(|page| page.items.iter()).collect();
        members.sort_by(|a, b| a.handle.cmp(&b.handle));
        let capped = pages.last().is_some_and(|page| page.capped);

        let mut old: Vec<usize> = self
            .items
            .iter()
            .enumerate()
            .filter(|(_, item)| item.collection == collection)
            .filter(|(_, item)| {
                item.bound(&source).is_some_and(|binding| {
                    binding.base_present && !binding.handle.starts_with('\u{1}')
                })
            })
            .map(|(index, _)| index)
            .collect();
        old.sort_by(|a, b| {
            let handle =
                |index: &usize| self.items[*index].bound(&source).map(|b| b.handle.clone());
            handle(a).cmp(&handle(b))
        });

        let mut taken = BTreeSet::new();
        let mut resolved = Vec::new();
        for member in &members {
            let filed = &remote.members[&member.handle].filed;
            let hint = key(filed);
            let minted = format!("dup:{hint}#");
            let carried = member.carries.then(|| ObjectName::of(&member.meta));
            let candidates: Vec<usize> = old
                .iter()
                .copied()
                .filter(|index| !taken.contains(index))
                .filter(|index| {
                    let item = &self.items[*index];
                    (item.link_id == hint || item.link_id.starts_with(&minted))
                        && agrees(&item.summary, &filed.summary)
                })
                .collect();
            let base = |index: &usize| self.items[*index].bound(&source).expect("a bound item");
            let choice = candidates
                .iter()
                .find(|index| {
                    member.revision.is_some() && base(index).base_revision == member.revision
                })
                .or_else(|| {
                    candidates
                        .iter()
                        .find(|index| carried.is_some() && base(index).base_object == carried)
                })
                .or(candidates.first())
                .copied();
            if let Some(index) = choice {
                taken.insert(index);
            }
            resolved.push((*member, choice));
        }

        let absent: Vec<usize> = old
            .iter()
            .copied()
            .filter(|index| !taken.contains(index))
            .collect();
        let mass = absent.len() * 2 > old.len() && old.len() >= 20;
        let empty = members.is_empty() && !absent.is_empty();
        let parked = ((mass || empty || (capped && !absent.is_empty()))
            && !options.accept_absences)
            .then_some((absent.len(), old.len()));
        let mut events = Vec::new();

        if parked.is_none() {
            let mutable = remote.mutable;
            for (member, choice) in &resolved {
                let Some(index) = choice else {
                    let filed = remote.members[&member.handle].filed.clone();
                    if member.carries {
                        self.objects
                            .insert(ObjectName::of(&member.meta), member.meta.clone());
                    }
                    let placement = Placement {
                        flags: Some(member.flags.clone()),
                        held: member.carries,
                        handle: Some(member.handle.clone()),
                        revision: member.revision.clone(),
                        source: Some(source.clone()),
                    };
                    events.push(Event::Added(member.handle.clone()));
                    self.file(&collection, filed, placement);
                    continue;
                };
                let item = &mut self.items[*index];
                let edited = item.object.is_some()
                    && item.object != item.bound(&source).expect("a bound item").base_object;
                let moved = mutable
                    && member.revision != item.bound(&source).expect("a bound item").base_revision;
                if moved && !edited {
                    item.object = None;
                    item.level = 1;
                }
                let binding = item.bound_mut(&source).expect("a bound item");
                binding.handle = member.handle.clone();
                match (moved, edited) {
                    (true, true) => {
                        binding.conflicted = true;
                        binding.conflict_revision = member.revision.clone();
                        binding.conflict_object = None;
                    }
                    (true, false) => {
                        binding.base_object = None;
                        binding.base_revision = member.revision.clone();
                    }
                    _ => {}
                }
            }
            let mut gone = absent;
            gone.sort_unstable_by(|a, b| b.cmp(a));
            for index in gone {
                self.drop_deleted(index, &source);
            }

            let checkpoint = pages.iter().find_map(|page| page.checkpoint.clone());
            let entry = self
                .collections
                .get_mut(&collection)
                .expect("a declared collection");
            entry.generation += 1;
            if let Some(checkpoint) = checkpoint {
                entry.sources.entry(source.clone()).or_default().checkpoint =
                    Some(checkpoint.into_bytes());
            }
        }

        Run {
            verb: "rekey",
            options: options.clone(),
            policy: remote.policy,
            handles: Vec::new(),
            collection,
            source,
            head: None,
            pages,
            fetch: BTreeMap::new(),
            pushes: Vec::new(),
            outcomes: Vec::new(),
            events,
            parked,
            unlisted: None,
            failed: false,
        }
    }

    /// Raises the placements of `handles` to `Full`, fetching each body
    /// the store does not hold, the base moving onto it, and each a binding
    /// names a revision of and no body while the item holds one, which an
    /// item conflict recorded unread waits for (SYNC §6, §9), and the
    /// diverging body a binding's conflict asks for, which clears it when
    /// it is the placement's own (SYNC §5).
    pub fn upgrade(&mut self, remote: &Remote, handles: &[String]) -> Run {
        let collection = remote.collection.clone();
        let source = remote.source.clone();
        let mut fetch = BTreeMap::new();
        let mut events = Vec::new();

        for handle in handles {
            let Some(index) = self.bound_handle(&collection, &source, handle) else {
                continue;
            };
            let item = &self.items[index];
            let binding = item.bound(&source).expect("a bound item");
            let unread = binding.base_object.is_none() && binding.base_revision.is_some();
            let diverging = binding.conflicted && binding.conflict_object.is_none();
            if item.object.is_some() && !unread && !diverging {
                continue;
            }
            let filed = remote.members[handle].filed.clone();
            let name = ObjectName::of(&filed.bytes);
            self.objects.insert(name.clone(), filed.bytes.clone());
            fetch.insert(handle.clone(), filed.bytes.clone());
            if diverging {
                let item = &mut self.items[index];
                let equal = item.object.as_ref() == Some(&name);
                let binding = item.bound_mut(&source).expect("a bound item");
                match equal {
                    true => {
                        binding.base_object = Some(name.clone());
                        binding.base_revision = binding.conflict_revision.take();
                        binding.shared_object = Some(name);
                        binding.conflicted = false;
                    }
                    false => binding.conflict_object = Some(name),
                }
                continue;
            }
            if self.items[index].object.is_some() {
                self.revisit(index, &source, handle, name, &filed, &mut events);
                continue;
            }

            let item = &mut self.items[index];
            item.object = Some(name.clone());
            item.level = 2;
            let binding = item.bound_mut(&source).expect("a bound item");
            binding.base_object = Some(name.clone());
            binding.shared_object = Some(name);
        }

        Run {
            verb: "upgrade",
            options: Options::default(),
            policy: remote.policy,
            handles: handles.to_vec(),
            collection,
            source,
            head: None,
            pages: Vec::new(),
            fetch,
            pushes: Vec::new(),
            outcomes: Vec::new(),
            events,
            parked: None,
            unlisted: None,
            failed: false,
        }
    }

    /// Settles a body an upgrade read for a binding naming a revision and no
    /// body, over an item holding one (SYNC §6, §9): the base takes it, and
    /// that is all unless an item conflict waits for that body. Then one
    /// equal to the item's is no divergence, the conflict clearing; another
    /// is settled by the collection's policy as a carried one would have been, `manual`
    /// landing it as the item's `conflict_object`, `prefer-incoming` and
    /// `prefer-existing` keeping the body not adopted over the handle, the
    /// conflict cleared. The base takes the body read; the shared body the
    /// one the item settles on, unless it stays conflicted.
    fn revisit(
        &mut self,
        index: usize,
        source: &str,
        handle: &str,
        fetched: ObjectName,
        filed: &Filed,
        events: &mut Vec<Event>,
    ) {
        let item = &self.items[index];
        if !item.conflicted || item.conflict_object.is_some() {
            let item = &mut self.items[index];
            let binding = item.bound_mut(source).expect("a bound item");
            binding.base_object = Some(fetched);
            return;
        }
        let policy = self.collections[&item.collection].conflict.clone();
        let equal = item.object.as_ref() == Some(&fetched);
        let kept = match (equal, policy.as_str()) {
            (true, _) => None,
            (false, "prefer-incoming") => {
                let kept = Kept {
                    object: item.object.clone(),
                    flags: item.flags.clone(),
                    summary: item.summary.clone(),
                    addresses: item.addresses.clone(),
                    sort_key: item.sort_key.clone(),
                };
                let item = &mut self.items[index];
                item.object = Some(fetched.clone());
                item.summary = filed.summary.clone();
                item.addresses = filed.addresses.clone();
                item.sort_key = filed.sort_key.clone();
                Some(kept)
            }
            (false, "prefer-existing") => Some(Kept {
                object: Some(fetched.clone()),
                flags: item.flags.clone(),
                summary: filed.summary.clone(),
                addresses: filed.addresses.clone(),
                sort_key: filed.sort_key.clone(),
            }),
            (false, _) => {
                let item = &mut self.items[index];
                item.conflict_object = Some(fetched.clone());
                let binding = item.bound_mut(source).expect("a bound item");
                binding.base_object = Some(fetched);
                return;
            }
        };

        let item = &mut self.items[index];
        item.conflicted = false;
        item.conflict_object = None;
        let settled = item.object.clone();
        let binding = item.bound_mut(source).expect("a bound item");
        binding.base_object = Some(fetched);
        binding.shared_object = settled;
        if let Some(kept) = kept {
            let link_id = self.keep(index, handle, kept, source);
            events.push(Event::Overruled {
                handle: String::from(handle),
                link_id,
            });
        }
    }

    /// The sync state `source` keeps in `collection`, to write.
    fn sync_state(&mut self, collection: &str, source: &str) -> &mut SourceState {
        self.collections
            .get_mut(collection)
            .expect("a declared collection")
            .sources
            .entry(String::from(source))
            .or_default()
    }

    fn bound_handle(&self, collection: &str, source: &str, handle: &str) -> Option<usize> {
        self.items.iter().position(|item| {
            item.collection == collection
                && item
                    .bound(source)
                    .is_some_and(|binding| binding.handle == handle)
        })
    }

    /// The create of this source a member's arrival lands: a pending or a
    /// delivered create under the member's hint, its message agreeing
    /// (SYNC §6). A minted create is landed by no listing.
    fn landing(&self, collection: &str, source: &str, filed: &Filed) -> Option<usize> {
        let key = key(filed);
        let provisional = format!("\u{1}{key}");
        self.items.iter().position(|item| {
            item.collection == collection
                && item.link_id == key
                && agrees(&item.summary, &filed.summary)
                && item.bound(source).is_some_and(|binding| {
                    binding.source == source && binding.handle == provisional
                })
        })
    }

    /// The item a member of a source binding none of it joins: the live one
    /// holding its key, which other sources bind or none does, its summary
    /// agreeing (SYNC §6).
    fn joining(&self, collection: &str, source: &str, filed: &Filed) -> Option<usize> {
        let key = key(filed);
        self.items.iter().position(|item| {
            item.collection == collection
                && item.link_id == key
                && item.state == State::Live
                && item.bound(source).is_none()
                && agrees(&item.summary, &filed.summary)
        })
    }

    /// Joins a member to the item holding its key: a binding of this
    /// source, the flags folded with no base, and the body absorbed (SYNC
    /// §9): filling an item holding none, the shared body standing for an
    /// immutable kind, an agreeing body taken as the base, a diverging one
    /// settled by the collection's policy.
    fn join(
        &mut self,
        index: usize,
        member: &Listed,
        filed: &Filed,
        source: &str,
        events: &mut Vec<Event>,
    ) -> bool {
        let carried = member.carries.then(|| ObjectName::of(&member.meta));
        if let Some(name) = &carried {
            self.objects.insert(name.clone(), member.meta.clone());
        }
        let mutable = self.items[index].summary.table != Table::Mail;
        let item = &mut self.items[index];
        item.flags = Some(merge(item.flags.as_ref(), None, &member.flags));
        item.bind(Binding {
            source: String::from(source),
            handle: member.handle.clone(),
            base_flags: Some(member.flags.clone()),
            base_object: None,
            base_revision: member.revision.clone(),
            base_present: true,
            shared_object: None,
            conflicted: false,
            conflict_revision: None,
            conflict_object: None,
            refusal: None,
            round: None,
        });
        events.push(Event::Added(member.handle.clone()));

        let agreed = match (&item.object, &carried) {
            (None, Some(_)) => {
                item.object = carried.clone();
                item.level = 2;
                item.summary = filed.summary.clone();
                item.addresses = filed.addresses.clone();
                item.sort_key = filed.sort_key.clone();
                carried
            }
            (Some(object), _) if !mutable => Some(object.clone()),
            (Some(object), Some(incoming)) if object == incoming => carried,
            (None, None) => None,
            _ => return self.diverge(index, member, filed, carried, source, events),
        };
        let binding = item.bound_mut(source).expect("a joined item");
        binding.base_object = agreed.clone();
        binding.shared_object = agreed;
        false
    }

    /// An upsert diverging from the shared item (SYNC §9): recorded on the
    /// item as `manual` records it, whatever the policy, when either body is
    /// one nobody has read; else the collection's policy adopts the
    /// incoming body or keeps the item's, the body not adopted kept as a
    /// retained item over the member's handle. The binding's base moves to
    /// the incoming body; its shared body only to the one the item settles
    /// on, and not while the item is conflicted. Answers whether the fold
    /// leaves the binding owing the item's body, which the source's next
    /// run pushes (SYNC §5).
    /// on, and not while the item is conflicted.
    fn diverge(
        &mut self,
        index: usize,
        member: &Listed,
        filed: &Filed,
        carried: Option<ObjectName>,
        source: &str,
        events: &mut Vec<Event>,
    ) -> bool {
        let item = &self.items[index];
        let policy = self.collections[&item.collection].conflict.clone();
        let unread = carried.is_none() || item.object.is_none();
        let settled = match (unread, policy.as_str()) {
            (false, "prefer-incoming") => {
                let kept = Kept {
                    object: item.object.clone(),
                    flags: item.flags.clone(),
                    summary: item.summary.clone(),
                    addresses: item.addresses.clone(),
                    sort_key: item.sort_key.clone(),
                };
                let item = &mut self.items[index];
                item.object = carried.clone();
                item.level = 2;
                item.summary = filed.summary.clone();
                item.addresses = filed.addresses.clone();
                item.sort_key = filed.sort_key.clone();
                events.push(Event::ContentChanged(member.handle.clone()));
                Some(kept)
            }
            (false, "prefer-existing") => Some(Kept {
                object: carried.clone(),
                flags: item.flags.clone(),
                summary: filed.summary.clone(),
                addresses: filed.addresses.clone(),
                sort_key: filed.sort_key.clone(),
            }),
            _ => {
                let item = &mut self.items[index];
                item.conflicted = true;
                item.conflict_object = carried.clone();
                events.push(Event::Conflicted(member.handle.clone()));
                None
            }
        };

        let item = &mut self.items[index];
        let shared = settled.is_some().then(|| item.object.clone()).flatten();
        let binding = item.bound_mut(source).expect("a bound item");
        let owing = shared.is_some() && shared != carried;
        binding.base_object = carried;
        binding.base_revision = member.revision.clone();
        if shared.is_some() {
            binding.shared_object = shared;
        }
        if let Some(kept) = settled {
            let link_id = self.keep(index, &member.handle, kept, source);
            events.push(Event::Overruled {
                handle: member.handle.clone(),
                link_id,
            });
        }
        owing
    }

    /// Lands a create on the member naming it: its binding moved to the
    /// listed handle, the base set to the listed flags and the staged body,
    /// the staged flags kept (SYNC §6).
    fn land(&mut self, index: usize, member: &Listed, source: &str) {
        let item = &mut self.items[index];
        let object = item.object.clone();
        let binding = item.bound_mut(source).expect("a bound create");
        binding.handle = member.handle.clone();
        binding.base_present = true;
        binding.base_flags = Some(member.flags.clone());
        binding.base_object = object.clone();
        binding.base_revision = member.revision.clone();
        binding.shared_object = object;
    }

    /// A listed member over its binding: the flag axis, then for a mutable
    /// kind the content axis under the source's policy (SYNC §5): a divergence
    /// recorded, pulled keeping the local edit, or kept and pushed over; a
    /// body nobody has read recorded whatever the policy.
    fn refresh(
        &mut self,
        index: usize,
        member: &Listed,
        filed: &Filed,
        source: &str,
        policy: Policy,
        events: &mut Vec<Event>,
    ) -> bool {
        let item = &mut self.items[index];
        let flags = item.flags.clone();
        let binding = item.bound_mut(source).expect("a bound item");
        let merged = merge(flags.as_ref(), binding.base_flags.as_ref(), &member.flags);
        binding.base_flags = Some(member.flags.clone());
        let base_revision = binding.base_revision.clone();
        if flags.as_ref() != Some(&merged) {
            item.flags = Some(merged);
            events.push(Event::FlagsChanged(member.handle.clone()));
        }

        if member.revision.is_none() || member.revision == base_revision {
            return false;
        }
        let carried = member.carries.then(|| ObjectName::of(&member.meta));
        if let Some(name) = &carried {
            self.objects.insert(name.clone(), member.meta.clone());
        }
        if carried.is_some() && carried == self.items[index].object {
            let item = &mut self.items[index];
            let binding = item.bound_mut(source).expect("a bound item");
            binding.base_object = carried.clone();
            binding.base_revision = member.revision.clone();
            binding.shared_object = carried;
            binding.conflicted = false;
            binding.conflict_revision = None;
            binding.conflict_object = None;
            return false;
        }
        let item = &self.items[index];
        let binding = item.bound(source).expect("a bound item");
        let edited = item.object.is_some() && item.object != binding.base_object;
        let conflicted = binding.conflicted || item.conflicted;

        let settle = match (policy, edited, conflicted) {
            (_, _, true) => Settle::Record,
            (Policy::Manual, true, _) => Settle::Record,
            (Policy::PreferRemote, true, _) => Settle::PullKeepingLocal,
            (Policy::PreferLocal, true, _) | (Policy::KeepLocal, _, _) if item.object.is_some() => {
                match carried {
                    Some(_) => Settle::KeepRemote,
                    None => Settle::Record,
                }
            }
            _ => Settle::Pull,
        };

        match settle {
            Settle::Record => {
                let binding = self.items[index].bound_mut(source).expect("a bound item");
                binding.conflicted = true;
                binding.conflict_revision = member.revision.clone();
                binding.conflict_object = carried;
                events.push(Event::Conflicted(member.handle.clone()));
            }
            Settle::Pull | Settle::PullKeepingLocal => {
                let item = &self.items[index];
                let binding = item.bound(source).expect("a bound item");
                let agreed = binding
                    .shared_object
                    .clone()
                    .or_else(|| binding.base_object.clone());
                let fills = item.object.is_none() && binding.base_object.is_none();
                let changed = item.object != agreed;
                if !fills && carried != binding.base_object && changed && carried != item.object {
                    return self.diverge(index, member, filed, carried, source, events);
                }
                let dropped = settle == Settle::PullKeepingLocal && !changed;
                let kept = dropped.then(|| {
                    let item = &self.items[index];
                    Kept {
                        object: item.object.clone(),
                        flags: item.flags.clone(),
                        summary: item.summary.clone(),
                        addresses: item.addresses.clone(),
                        sort_key: item.sort_key.clone(),
                    }
                });
                let item = &mut self.items[index];
                item.object = carried.clone();
                item.level = if carried.is_some() { 2 } else { 1 };
                item.summary = filed.summary.clone();
                item.addresses = filed.addresses.clone();
                item.sort_key = filed.sort_key.clone();
                let binding = item.bound_mut(source).expect("a bound item");
                binding.base_object = carried.clone();
                binding.base_revision = member.revision.clone();
                if carried.is_some() {
                    binding.shared_object = carried;
                }
                events.push(Event::ContentChanged(member.handle.clone()));
                if let Some(kept) = kept {
                    let link_id = self.keep(index, &member.handle, kept, source);
                    events.push(Event::Overruled {
                        handle: member.handle.clone(),
                        link_id,
                    });
                }
            }
            Settle::KeepRemote => {
                let item = &self.items[index];
                let kept = Kept {
                    object: carried.clone(),
                    flags: item.flags.clone(),
                    summary: filed.summary.clone(),
                    addresses: filed.addresses.clone(),
                    sort_key: filed.sort_key.clone(),
                };
                let link_id = self.keep(index, &member.handle, kept, source);
                let binding = self.items[index].bound_mut(source).expect("a bound item");
                binding.base_object = carried;
                binding.base_revision = member.revision.clone();
                events.push(Event::Overruled {
                    handle: member.handle.clone(),
                    link_id,
                });
            }
        }
        false
    }

    /// Keeps a body a policy did not adopt as a retained item, keyed by
    /// minting over the binding's handle, minted again while held, a `seq`
    /// of its own, retained by the binding's source (SYNC §9, STORAGE §9).
    fn keep(&mut self, index: usize, handle: &str, kept: Kept, source: &str) -> String {
        let item = &self.items[index];
        let collection = item.collection.clone();
        let source = item.bound(source).map(|binding| binding.source.clone());
        let mut link_id = format!("dup:{}#{handle}", item.link_id);
        while self.holds(&collection, &link_id) {
            link_id = format!("dup:{link_id}#{handle}");
        }
        let seq = self.seq_for(&collection, &link_id, &kept.summary);
        self.items.push(Item {
            collection,
            link_id: link_id.clone(),
            seq,
            flags: kept.flags,
            level: if kept.object.is_some() { 2 } else { 1 },
            object: kept.object,
            sort_key: kept.sort_key,
            state: State::Retained { by: source },
            conflicted: false,
            conflict_object: None,
            summary: kept.summary,
            addresses: kept.addresses,
            bindings: Vec::new(),
        });
        link_id
    }

    /// A `Deleted` drop: the binding goes, and with it the item's last, so
    /// the item is retained, or purged when its identity is held live in
    /// another collection of the account with its body, a message only by
    /// a row agreeing with it (STORAGE §10, §11.1).
    fn drop_deleted(&mut self, index: usize, source: &str) {
        let item = &mut self.items[index];
        item.bindings.retain(|binding| binding.source != source);
        if !item.bindings.is_empty() {
            item.state = State::Tombstone;
            return;
        }
        item.state = State::Retained {
            by: Some(String::from(source)),
        };

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
                    && item.bound(source).is_some_and(|binding| {
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
            let binding = item.bound(source)?;
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
    /// owe none. No `Add` while the round stays open, nor for a create with
    /// no origin dated out of the run's scope, which may be an arrival no
    /// page of that scope lists.
    fn derive(
        &self,
        collection: &str,
        source: &str,
        listed: &BTreeMap<String, BTreeSet<String>>,
        mutable: bool,
        scope: &Scope,
        creating: bool,
    ) -> Vec<Push> {
        let mut pushes = Vec::new();
        for item in self
            .items
            .iter()
            .filter(|item| item.collection == collection)
        {
            let Some(binding) = item.bound(source) else {
                if let Some(push) = self.offer(collection, source, item) {
                    pushes.push(push);
                }
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
                (State::Live, true) if binding.conflicted || item.conflicted => {}
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
        pushes.retain(|push| {
            let Push::Add {
                link_id, origin, ..
            } = push
            else {
                return true;
            };
            let dated = self
                .items
                .iter()
                .find(|item| {
                    item.collection == collection
                        && &item.link_id == link_id
                        && item.state == State::Live
                })
                .and_then(Item::date);
            creating && (origin.is_some() || scope.holds(dated.as_deref()))
        });
        pushes.sort_by(|a, b| a.handle().cmp(b.handle()));
        pushes
    }

    /// The `Add` a source lacking a live item owes it, offered only when
    /// the store holds its body and its key asserts an identity, a `hash:`
    /// key asserting none (SYNC §3, §9).
    fn offer(&self, collection: &str, source: &str, item: &Item) -> Option<Push> {
        let object = item.object.as_ref()?;
        if item.state != State::Live || item.link_id.starts_with("hash:") {
            return None;
        }
        Some(Push::Add {
            handle: format!("\u{1}{}", item.link_id),
            link_id: item.link_id.clone(),
            flags: item.flags.clone().unwrap_or_default(),
            origin: self.origin(collection, source, &item.link_id, object),
            object: object.clone(),
        })
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
        let offered = self
            .bound_handle(collection, &source, push.handle())
            .is_none();
        let index = match offered {
            false => self
                .bound_handle(collection, &source, push.handle())
                .expect("a pushed placement"),
            true => self.bind_offer(collection, &source, push),
        };
        let key = push.key(collection);
        let answer = remotes.get_mut(collection).expect("a remote").answer(&key);
        let mut outcome = Outcome {
            handle: String::from(push.handle()),
            answer: answer.clone(),
            assigned: None,
            revision: None,
            relocated: None,
        };
        match answer {
            Answer::Accepted => {}
            Answer::Rejected => {
                if offered {
                    self.items[index]
                        .bindings
                        .retain(|binding| binding.source != source);
                }
                return outcome;
            }
            Answer::Refused(reason) => {
                let binding = self.items[index].bound_mut(&source).expect("a bound item");
                binding.refusal = Some(Refusal {
                    reason: reason.clone(),
                    key,
                });
                events.push(Event::Refused {
                    handle: String::from(push.handle()),
                    reason,
                });
                return outcome;
            }
        }
        if let Some(binding) = self.items[index].bound_mut(&source) {
            binding.refusal = None;
        }

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
                item.bound_mut(&source).expect("a bound item").base_flags = flags;
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
                            && item.bound(&source).is_some_and(|binding| {
                                binding.source == source && binding.handle == provisional
                            })
                    });
                    if let Some(binding) = delivered.and_then(|item| item.bound_mut(&source))
                        && !binding.base_present
                    {
                        binding.base_present = true;
                    }
                }
                self.drop_deleted(index, &source);
            }
            Push::Update { handle, object, .. } => {
                let filed = self.filed(index, object);
                let remote = remotes.get_mut(collection).expect("a remote");
                outcome.revision = remote.edit(handle, filed);
                let binding = self.items[index].bound_mut(&source).expect("a bound item");
                binding.base_object = Some(object.clone());
                binding.base_revision = outcome.revision.clone();
                binding.shared_object = Some(object.clone());
            }
            Push::Add { flags, object, .. } => {
                let filed = self.filed(index, object);
                let remote = remotes.get_mut(collection).expect("a remote");
                let (assigned, revision) = remote.deliver(filed, flags.clone());
                let binding = self.items[index].bound_mut(&source).expect("a bound item");
                if !remote.uidplus && !remote.mutable {
                    binding.base_present = true;
                    return outcome;
                }
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

    /// Binds an offered create to the source pushing its `Add`, as its own
    /// pending create under the provisional handle the `Add` was pushed
    /// under, no base: the write recording the push's outcome binds it
    /// (SYNC §5, STORAGE §14).
    fn bind_offer(&mut self, collection: &str, source: &str, push: &Push) -> usize {
        let Push::Add { link_id, .. } = push else {
            panic!("only an add is offered");
        };
        let index = self
            .items
            .iter()
            .position(|item| {
                item.collection == collection
                    && &item.link_id == link_id
                    && item.state == State::Live
            })
            .expect("an offered item");
        self.items[index].bind(Binding {
            source: String::from(source),
            handle: String::from(push.handle()),
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
        });
        index
    }
    fn refusal_on(&self, collection: &str, source: &str, handle: &str) -> Option<Refusal> {
        let index = self.bound_handle(collection, source, handle)?;
        self.items[index].bound(source)?.refusal.clone()
    }

    fn filed(&self, index: usize, object: &ObjectName) -> Filed {
        let item = &self.items[index];
        Filed {
            bytes: self.objects[object].clone(),
            hint: declared(&item.summary),
            summary: item.summary.clone(),
            addresses: item.addresses.clone(),
            sort_key: item.sort_key.clone(),
            fallback: None,
        }
    }
}

/// The hint a body declares, read back from the summary derived from it:
/// a message's `Message-ID`, a resource's usable `UID` (Annex A).
fn declared(summary: &Summary) -> Option<String> {
    let column = match summary.table {
        Table::Mail => "message_id",
        Table::File => return None,
        _ => "uid",
    };
    match summary.get(column) {
        Value::Text(hint) if !hint.trim_matches([' ', '\t']).is_empty() => Some(hint),
        _ => None,
    }
}

/// What a round listed, as its absences read it: its pages, whether a head
/// named a member, and the scope it lists, a band or not.
struct Listing<'a> {
    pages: &'a [Page],
    named: bool,
    scope: &'a Scope,
    band: bool,
}

/// How a run settles a remote revision its base does not hold.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Settle {
    /// Pulled.
    Pull,
    /// Pulled, the local edit kept as a retained item.
    PullKeepingLocal,
    /// The member's body kept as a retained item, the base moved onto it,
    /// the store's body pushed over it.
    KeepRemote,
    /// Recorded in conflict on the binding.
    Record,
}

/// A body a policy keeps, and what the retained item holding it shows.
struct Kept {
    object: Option<ObjectName>,
    flags: Option<BTreeSet<String>>,
    summary: Summary,
    addresses: Vec<Address>,
    sort_key: String,
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
