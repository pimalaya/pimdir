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
};

use crate::body::Filed;

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
        }
    }

    /// An empty DAV collection.
    pub fn dav(source: &str, collection: &str) -> Self {
        Self {
            mutable: true,
            ..Self::new(source, collection)
        }
    }

    /// Takes a member in, answering its handle and its revision.
    pub fn deliver(&mut self, filed: Filed, flags: BTreeSet<String>) -> (String, Option<String>) {
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
            },
        );
        (handle, revision)
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

    /// A round over every member, newest first, `size` a page, each page's
    /// members in handle byte order, the checkpoint on the first.
    pub fn round(&self, size: usize) -> Vec<Page> {
        let mut newest: Vec<(&String, &Member)> = self.members.iter().collect();
        newest.sort_by_key(|(_, member)| Reverse(member.arrival));
        let chunks: Vec<&[(&String, &Member)]> = newest.chunks(size.max(1)).collect();
        let count = chunks.len().max(1);

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
                }
            })
            .collect()
    }

    /// A delta from `checkpoint`: the members changed above it and the
    /// handles removed above it.
    pub fn delta(&self, checkpoint: &str) -> Page {
        let since: u64 = checkpoint.parse().unwrap_or(0);
        let changed = self
            .members
            .iter()
            .filter(|(_, member)| member.changed > since);
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
        }
    }

    fn listed<'a>(&self, members: impl Iterator<Item = (&'a String, &'a Member)>) -> Vec<Listed> {
        let mut items: Vec<Listed> = members
            .map(|(handle, member)| Listed {
                handle: handle.clone(),
                flags: member.flags.clone(),
                revision: member.revision.clone(),
                meta: member.filed.bytes.clone(),
                carries: self.mutable,
            })
            .collect();
        items.sort_by(|a, b| a.handle.cmp(&b.handle));
        items
    }
}
