//! # The scripted remote
//!
//! One source's side of a collection: its members by handle, the order it
//! changed them in, and what it answers the three requests of SYNC §4. The
//! answers are plain data, the pages, the fetches and the outcomes a
//! scripted connector hands an engine, in the shape of vectors/sync's
//! `remote`, so a generated run and a vector read alike.
//!
//! A mail remote behaves as an IMAP mailbox with CONDSTORE and QRESYNC:
//! UIDs as handles, a modification sequence as the checkpoint, a listing
//! carrying no body. A DAV remote behaves as a collection answering
//! `sync-collection`: resource names as handles, an ETag per resource as
//! its revision, its sync token as the checkpoint, every page carrying the
//! bodies a multiget read before handing it over.

use std::{
    cmp::Reverse,
    collections::{BTreeMap, BTreeSet},
    mem,
};

use rusqlite::types::Value;

use crate::{body::Filed, engine::Answer, model::Scope, time::Instant};

/// One member a remote holds.
#[derive(Clone, Debug)]
pub struct Member {
    /// Its flags.
    pub flags: BTreeSet<String>,
    /// Its body and what Annex A derives from it, its meta.
    pub filed: Filed,
    /// Its revision, a DAV resource's ETag.
    pub revision: Option<String>,
    /// The sequence it last changed at.
    pub changed: u64,
    /// The order it arrived in, the recency a round lists by.
    pub arrival: u64,
    /// The instant the source received it, which a received-date filter
    /// reads.
    pub received: Instant,
}

/// A source's conflict policy against its own remote (SYNC §5).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Policy {
    /// A divergence recorded for a person.
    #[default]
    Manual,
    /// The remote body pulled, the local edit kept.
    PreferRemote,
    /// The local body pushed over the remote one, which is kept.
    PreferLocal,
    /// `PreferLocal` over a change the source alone made too.
    KeepLocal,
}

/// One source's side of one collection.
#[derive(Clone, Debug)]
pub struct Remote {
    /// The source.
    pub source: String,
    /// The collection it fills.
    pub collection: String,
    /// Whether it holds a mutable kind, revisions and carried bodies.
    pub mutable: bool,
    /// The members by handle.
    pub members: BTreeMap<String, Member>,
    /// The handles it removed, at the sequence each went at.
    pub vanished: BTreeMap<String, u64>,
    /// The highest sequence, its checkpoint.
    pub modseq: u64,
    /// The next number it names a member by.
    pub next: u64,
    /// How the source settles a revision its base lacks against its own
    /// remote (SYNC §5).
    pub policy: Policy,
    /// Whether its pages carry the bodies they list; a mail listing never
    /// does.
    pub carries: bool,
    /// Whether an append names the member it made (an IMAP server with
    /// UIDPLUS, RFC 4315); a mutable remote always does.
    pub uidplus: bool,
    /// The changes it refuses for good, by key, with the reason it gives.
    pub refuse: BTreeMap<String, String>,
    /// The changes it rejects once, by key, a precondition failing.
    pub reject: BTreeSet<String>,
    /// Whether its connector narrows a scoped round by the received date,
    /// two days below the scope's floor (SYNC §5).
    pub narrows: bool,
    /// Whether a narrowed round's last page hands every handle it holds.
    pub enumerates: bool,
    /// The newest members it lists of the collection at most, if it caps.
    pub cap: Option<usize>,
    /// The instant it receives a member stating no date at.
    pub clock: Instant,
}

/// A member as a page lists it.
#[derive(Clone, Debug)]
pub struct Listed {
    /// Its handle.
    pub handle: String,
    /// Its flags.
    pub flags: BTreeSet<String>,
    /// Its revision, none for mail.
    pub revision: Option<String>,
    /// The body its meta is read from.
    pub meta: Vec<u8>,
    /// Whether the page carries that body too (SYNC §4).
    pub carries: bool,
}

/// One page an enumeration answers (SYNC §4).
#[derive(Clone, Debug)]
pub struct Page {
    /// Its members, in handle byte order.
    pub items: Vec<Listed>,
    /// The handles the source states removed.
    pub vanished: Vec<String>,
    /// Whether it belongs to a round.
    pub complete: bool,
    /// Whether it closes its listing.
    pub last: bool,
    /// The resume cursor of a page before the last.
    pub cursor: Option<String>,
    /// The checkpoint it carries.
    pub checkpoint: Option<String>,
    /// Whether a date filter narrowed the round's listing.
    pub narrowed: bool,
    /// On a narrowed round's last page, every handle the source holds.
    pub enumerated: Option<Vec<String>>,
    /// Whether the source caps what it lists of the collection.
    pub capped: bool,
}

impl Member {
    /// Its summary `date`, a message's, which a connector checks a scope
    /// against.
    pub fn date(&self) -> Option<String> {
        match self.filed.summary.get("date") {
            Value::Text(date) => Some(date),
            _ => None,
        }
    }
}

impl Remote {
    /// An empty mailbox.
    pub fn new(source: &str, collection: &str) -> Self {
        Self {
            source: String::from(source),
            collection: String::from(collection),
            mutable: false,
            members: BTreeMap::new(),
            vanished: BTreeMap::new(),
            modseq: 1,
            next: 1,
            uidplus: true,
            policy: Policy::Manual,
            carries: false,
            refuse: BTreeMap::new(),
            reject: BTreeSet::new(),
            narrows: false,
            enumerates: false,
            cap: None,
            clock: Instant::at(2026, 10, 1, 9, 0, 0),
        }
    }

    /// An empty DAV collection.
    pub fn dav(source: &str, collection: &str) -> Self {
        Self {
            mutable: true,
            carries: true,
            ..Self::new(source, collection)
        }
    }

    /// Takes a member in, received at its date or else at the remote's
    /// clock, answering its handle and its revision.
    pub fn deliver(&mut self, filed: Filed, flags: BTreeSet<String>) -> (String, Option<String>) {
        let received = match filed.summary.get("date") {
            Value::Text(date) => Instant::from_rfc3339(&date),
            _ => self.clock,
        };
        self.deliver_at(filed, flags, received)
    }

    /// Delivers a member the source received at `received`, whatever its
    /// date says.
    pub fn deliver_at(
        &mut self,
        filed: Filed,
        flags: BTreeSet<String>,
        received: Instant,
    ) -> (String, Option<String>) {
        let number = self.next;
        self.next += 1;
        self.modseq += 1;
        let handle = match self.mutable {
            true => format!("r{number}.vcf"),
            false => number.to_string(),
        };
        let revision = self.mutable.then(|| format!("\"e{}\"", self.modseq));
        self.members.insert(
            handle.clone(),
            Member {
                flags,
                filed,
                revision: revision.clone(),
                changed: self.modseq,
                arrival: number,
                received,
            },
        );
        (handle, revision)
    }

    /// What it answers the change keyed `key` (SYNC §4).
    pub fn answer(&mut self, key: &str) -> Answer {
        if let Some(reason) = self.refuse.get(key) {
            return Answer::Refused(reason.clone());
        }
        match self.reject.remove(key) {
            true => Answer::Rejected,
            false => Answer::Accepted,
        }
    }

    /// Changes a member's flags, as another client does.
    pub fn set_flags(&mut self, handle: &str, flags: BTreeSet<String>) {
        self.modseq += 1;
        if let Some(member) = self.members.get_mut(handle) {
            member.flags = flags;
            member.changed = self.modseq;
        }
    }

    /// Replaces a member's body, as another client or an accepted
    /// `Update` does, answering its new revision.
    pub fn edit(&mut self, handle: &str, filed: Filed) -> Option<String> {
        self.modseq += 1;
        let revision = format!("\"e{}\"", self.modseq);
        let member = self.members.get_mut(handle)?;
        member.filed = filed;
        member.revision = Some(revision.clone());
        member.changed = self.modseq;
        Some(revision)
    }

    /// Renumbers every member, as a server bumping its `UIDVALIDITY` or
    /// restored from a backup (SYNC §8): the members in arrival order take
    /// the handles from `from` on, and the removals it stated are forgotten,
    /// the new handle space naming none of them.
    pub fn renumber(&mut self, from: u64) {
        let mut members: Vec<Member> = mem::take(&mut self.members).into_values().collect();
        members.sort_by_key(|member| member.arrival);
        self.vanished.clear();
        self.modseq += 1;
        self.next = from;
        for mut member in members {
            let handle = match self.mutable {
                true => format!("r{}.vcf", self.next),
                false => self.next.to_string(),
            };
            self.next += 1;
            member.changed = self.modseq;
            self.members.insert(handle, member);
        }
    }

    /// Loses a member unannounced, as a server whose deletion no delta
    /// states: only a round's absence finds it.
    pub fn forget(&mut self, handle: &str) {
        self.members.remove(handle);
    }

    /// Removes a member.
    pub fn expunge(&mut self, handle: &str) {
        self.modseq += 1;
        if self.members.remove(handle).is_some() {
            self.vanished.insert(String::from(handle), self.modseq);
        }
    }

    /// The checkpoint it hands now.
    pub fn checkpoint(&self) -> String {
        self.modseq.to_string()
    }

    /// A round over `scope`, newest first, `size` a page, each page's
    /// members in handle byte order, the checkpoint on the first (SYNC §4,
    /// §5): the newest members alone where the source caps, those received
    /// from two days below the floor where the connector narrows, a dated
    /// member out of scope dropped by the connector's own check, the last
    /// page of a narrowed round handing every handle where it enumerates.
    pub fn round(&self, size: usize, scope: &Scope) -> Vec<Page> {
        let mut newest: Vec<(&String, &Member)> = self.members.iter().collect();
        newest.sort_by_key(|(_, member)| Reverse(member.arrival));
        if let Some(cap) = self.cap {
            newest.truncate(cap);
        }
        let narrowed = self.narrows && scope != &Scope::default();
        let floor = scope.since.map(|since| Instant(since.0 - 2 * 86_400));
        newest.retain(|(_, member)| {
            let received = !narrowed || floor.is_none_or(|floor| member.received >= floor);
            received && scope.holds(member.date().as_deref())
        });
        let chunks: Vec<&[(&String, &Member)]> = newest.chunks(size.max(1)).collect();
        let count = chunks.len().max(1);
        let enumerated =
            (narrowed && self.enumerates).then(|| self.members.keys().cloned().collect());

        (0..count)
            .map(|index| {
                let chunk = chunks.get(index).copied().unwrap_or(&[]);
                let last = index + 1 == count;
                Page {
                    items: self.listed(chunk.iter().copied()),
                    vanished: Vec::new(),
                    complete: true,
                    last,
                    cursor: (!last).then(|| format!("page-{}", index + 1)),
                    checkpoint: (index == 0).then(|| self.checkpoint()),
                    narrowed,
                    enumerated: enumerated.clone().filter(|_| last),
                    capped: self.cap.is_some(),
                }
            })
            .collect()
    }

    /// A delta from `checkpoint`: the members changed above it, a dated one
    /// out of `scope` dropped, and the handles removed above it.
    pub fn delta(&self, checkpoint: &str, scope: &Scope) -> Page {
        let since: u64 = checkpoint.parse().unwrap_or(0);
        let changed = self
            .members
            .iter()
            .filter(|(_, member)| member.changed > since && scope.holds(member.date().as_deref()));
        let vanished = self
            .vanished
            .iter()
            .filter(|(_, at)| **at > since)
            .map(|(handle, _)| handle.clone())
            .collect();
        Page {
            items: self.listed(changed),
            vanished,
            complete: false,
            last: true,
            cursor: None,
            checkpoint: Some(self.checkpoint()),
            narrowed: false,
            enumerated: None,
            capped: false,
        }
    }

    fn listed<'a>(&self, members: impl Iterator<Item = (&'a String, &'a Member)>) -> Vec<Listed> {
        let mut items: Vec<Listed> = members
            .map(|(handle, member)| Listed {
                handle: handle.clone(),
                flags: member.flags.clone(),
                revision: member.revision.clone(),
                meta: member.filed.bytes.clone(),
                carries: self.carries,
            })
            .collect();
        items.sort_by(|a, b| a.handle.cmp(&b.handle));
        items
    }
}
