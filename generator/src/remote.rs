//! # The scripted remote
//!
//! One source's side of a collection: its members by handle, the order it
//! changed them in, and what it answers the three requests of SYNC §4. The
//! answers are plain data, the pages, the fetches and the outcomes a
//! scripted connector hands an engine, in the shape of vectors/sync's
//! `remote`, so a generated run and a vector read alike.
//!
//! The remote behaves as an IMAP mailbox with CONDSTORE and QRESYNC: UIDs
//! as handles, a modification sequence as the checkpoint, a delta listing
//! every member changed above it and every UID it expunged.

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
    /// The modification sequence it last changed at.
    pub changed: u64,
}

/// One source's side of one collection.
#[derive(Clone, Debug)]
pub struct Remote {
    /// The source.
    pub source: String,
    /// The collection it fills.
    pub collection: String,
    /// The members by handle.
    pub members: BTreeMap<String, Member>,
    /// The handles it expunged, at the sequence each went at.
    pub vanished: BTreeMap<String, u64>,
    /// The highest modification sequence, its checkpoint.
    pub modseq: u64,
    /// The next UID it hands out.
    pub next_uid: u64,
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
    /// The body its meta is read from; a listing carries no body.
    pub meta: Vec<u8>,
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
            members: BTreeMap::new(),
            vanished: BTreeMap::new(),
            modseq: 1,
            next_uid: 1,
        }
    }

    /// Delivers a message, answering its handle.
    pub fn deliver(&mut self, filed: Filed, flags: BTreeSet<String>) -> String {
        let handle = self.next_uid.to_string();
        self.next_uid += 1;
        self.modseq += 1;
        self.members.insert(
            handle.clone(),
            Member {
                flags,
                filed,
                changed: self.modseq,
            },
        );
        handle
    }

    /// Changes a member's flags, as another client does.
    pub fn set_flags(&mut self, handle: &str, flags: BTreeSet<String>) {
        self.modseq += 1;
        if let Some(member) = self.members.get_mut(handle) {
            member.flags = flags;
            member.changed = self.modseq;
        }
    }

    /// Expunges a member.
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
        newest.sort_by_key(|(handle, _)| Reverse(handle.parse::<u64>().unwrap_or(0)));
        let chunks: Vec<&[(&String, &Member)]> = newest.chunks(size.max(1)).collect();
        let count = chunks.len().max(1);

        (0..count)
            .map(|index| {
                let chunk = chunks.get(index).copied().unwrap_or(&[]);
                let last = index + 1 == count;
                Page {
                    items: listed(chunk.iter().copied()),
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
    /// handles expunged above it.
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
            items: listed(changed),
            vanished,
            complete: false,
            last: true,
            cursor: None,
            checkpoint: Some(self.checkpoint()),
        }
    }
}

fn listed<'a>(members: impl Iterator<Item = (&'a String, &'a Member)>) -> Vec<Listed> {
    let mut items: Vec<Listed> = members
        .map(|(handle, member)| Listed {
            handle: handle.clone(),
            flags: member.flags.clone(),
            revision: None,
            meta: member.filed.bytes.clone(),
        })
        .collect();
    items.sort_by(|a, b| a.handle.cmp(&b.handle));
    items
}
