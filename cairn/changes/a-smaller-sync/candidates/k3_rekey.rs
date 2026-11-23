//! # K3: the rekey's own rules, R0 to R8
//!
//! Each test pins what io-pimdir 131f9bf does today in a case only a
//! rekey has, run through the real store.

#![cfg(feature = "client")]

#[allow(dead_code)]
#[path = "engine/common.rs"]
mod common;

use std::{convert::Infallible, fs};

use io_pimdir::{
    change::{PimdirChange, PimdirChangeKind, PimdirDropReason, PimdirWriteOp},
    client::blobs::PimdirBlobs,
    collection::PimdirCollectionId,
    coroutine::{PimdirArg, PimdirCoroutine, PimdirCoroutineState, PimdirWritten, PimdirYield},
    mutate::PimdirMutation,
    object::{PimdirHash, PimdirObject},
    placement::{
        PimdirFlags, PimdirHandle, PimdirLevel, PimdirLinkId, PimdirPlacement, PimdirStatus,
    },
    rekey::{PimdirRekey, PimdirRekeyReport},
    remote::{
        PimdirEnumerate, PimdirEnumerated, PimdirFetchedBody, PimdirFetchedItem, PimdirPushResult,
        PimdirRemote, PimdirRemoteItem, PimdirRemoteMeta, PimdirTier,
    },
    summary::{PimdirSummary, mail::PimdirMailSummary},
    sync::{PimdirSyncEvent, PimdirSyncOptions, PimdirSyncReport},
};

use crate::common::{Client, MemRemote, hash, summary_of};

const BASE: &[u8] = b"the ancestor body";
const LOCAL: &[u8] = b"the local body";
const REMOTE: &[u8] = b"the remote body";

#[derive(Default)]
struct Scripted {
    inner: MemRemote,
    listing: Option<Vec<PimdirRemoteItem>>,
    unassign_adds: bool,
    pushed: Vec<String>,
}

impl PimdirRemote for Scripted {
    type Error = Infallible;

    fn enumerate(
        &mut self,
        collection: &PimdirCollectionId,
        request: PimdirEnumerate,
    ) -> Result<PimdirEnumerated, Infallible> {
        let round = request.checkpoint().is_none();
        let mut answer = self.inner.enumerate(collection, request)?;
        if let (true, Some(items), PimdirEnumerated::Page(page)) =
            (round, &self.listing, &mut answer)
        {
            page.items = items.clone();
        }
        Ok(answer)
    }

    fn fetch(
        &mut self,
        collection: &PimdirCollectionId,
        handles: Vec<PimdirHandle>,
        tier: PimdirTier,
    ) -> Result<Vec<PimdirFetchedItem>, Infallible> {
        self.inner.fetch(collection, handles, tier)
    }

    fn push(
        &mut self,
        collection: &PimdirCollectionId,
        changes: Vec<PimdirChange>,
    ) -> Result<Vec<PimdirPushResult>, Infallible> {
        for change in &changes {
            let kind = match &change.kind {
                PimdirChangeKind::Add { .. } => "add",
                PimdirChangeKind::Remove { .. } => "remove",
                PimdirChangeKind::SetFlags { .. } => "set-flags",
                PimdirChangeKind::Update { .. } => "update",
            };
            self.pushed.push(kind.to_string());
        }
        let mut results = self.inner.push(collection, changes)?;
        if self.unassign_adds {
            for result in &mut results {
                if result.handle.is_provisional() {
                    result.assigned = None;
                    result.revision = None;
                }
            }
        }
        Ok(results)
    }
}

fn remote(mutable: bool) -> Scripted {
    let mut inner = MemRemote::default();
    inner.mutable = mutable;
    Scripted {
        inner,
        ..Default::default()
    }
}

fn listing(remote: &MemRemote, collection: &str) -> Vec<PimdirRemoteItem> {
    remote
        .items
        .get(&PimdirCollectionId::from(collection))
        .into_iter()
        .flatten()
        .map(|(handle, item)| PimdirRemoteItem {
            handle: handle.clone(),
            flags: item.flags.clone(),
            revision: remote.mutable.then(|| item.rev.to_string()),
            meta: PimdirRemoteMeta {
                link_id: item.link_id.clone(),
                summary: Some(summary_of(&item.link_id)),
                sort_key: Default::default(),
                body: remote.mutable.then(|| PimdirFetchedBody::Inline {
                    hash: hash(&item.body),
                    bytes: item.body.clone(),
                }),
                server_object_id: None,
            },
        })
        .collect()
}

fn mail(subject: &str) -> PimdirSummary {
    PimdirSummary::Mail(PimdirMailSummary {
        subject: subject.to_string(),
        ..Default::default()
    })
}

fn flags(set: &[&str]) -> PimdirFlags {
    PimdirFlags::from_iter(set.iter().copied())
}

fn object(body: &[u8]) -> PimdirObject {
    PimdirObject {
        hash: hash(body),
        size: body.len(),
    }
}

fn h(handle: &str) -> PimdirHandle {
    PimdirHandle::from(handle)
}

struct Recorded<T> {
    out: T,
    ops: Vec<PimdirWriteOp>,
    written: Vec<PimdirWritten>,
}

impl<T> Recorded<T> {
    fn drops(&self) -> Vec<(String, PimdirDropReason)> {
        self.ops
            .iter()
            .filter_map(|op| match op {
                PimdirWriteOp::DropPlacement { handle, reason, .. } => {
                    Some((handle.as_str().to_string(), *reason))
                }
                _ => None,
            })
            .collect()
    }

    fn stores(&self) -> usize {
        self.ops
            .iter()
            .filter(|op| matches!(op, PimdirWriteOp::StoreObject { .. }))
            .count()
    }

    fn upserted(&self, handle: &str) -> PimdirPlacement {
        self.ops
            .iter()
            .find_map(|op| match op {
                PimdirWriteOp::UpsertPlacement(p) if p.handle.as_str() == handle => Some(p.clone()),
                _ => None,
            })
            .unwrap_or_else(|| panic!("the batch upserts {handle:?}"))
    }

    fn overruled(&self) -> Vec<(String, String)> {
        self.written
            .iter()
            .flat_map(|w| w.overruled.iter())
            .map(|(handle, link)| (handle.as_str().to_string(), link.as_str().to_string()))
            .collect()
    }
}

fn run<T, E: std::fmt::Debug>(
    client: &mut Client<Scripted>,
    mut coroutine: impl PimdirCoroutine<Yield = PimdirYield, Return = Result<T, E>>,
) -> Recorded<T> {
    let mut ops = Vec::new();
    let mut written = Vec::new();
    let mut arg = None;
    loop {
        let yielded = match coroutine.resume(arg.take()) {
            PimdirCoroutineState::Complete(out) => {
                return Recorded {
                    out: out.expect("the run completes"),
                    ops,
                    written,
                };
            }
            PimdirCoroutineState::Yielded(yielded) => yielded,
        };
        if let PimdirYield::WantsWrite(batch) = &yielded {
            ops.extend(batch.iter().cloned());
        }
        arg = Some(
            match client.store.service(yielded).expect("the store serves") {
                Ok(PimdirArg::Written(answer)) => {
                    written.push(answer.clone());
                    PimdirArg::Written(answer)
                }
                Ok(arg) => arg,
                Err(PimdirYield::WantsEnumerate {
                    collection,
                    request,
                }) => PimdirArg::Enumerate(client.remote.enumerate(&collection, request).unwrap()),
                Err(PimdirYield::WantsFetch {
                    collection,
                    handles,
                    tier,
                }) => PimdirArg::Fetch(client.remote.fetch(&collection, handles, tier).unwrap()),
                Err(PimdirYield::WantsPush {
                    collection,
                    changes,
                }) => PimdirArg::Push(client.remote.push(&collection, changes).unwrap()),
                Err(other) => panic!("unexpected yield {other:?}"),
            },
        );
    }
}

fn rekey(client: &mut Client<Scripted>, collection: &str) -> Recorded<PimdirRekeyReport> {
    run(client, PimdirRekey::new(collection))
}

fn sync_recorded(client: &mut Client<Scripted>, collection: &str) -> Recorded<PimdirSyncReport> {
    let coroutine = client
        .store
        .prepare_sync(
            collection,
            PimdirSyncOptions::default(),
            client.remote.scope_bound(),
        )
        .unwrap()
        .heads(client.remote.heads());
    run(client, coroutine)
}

fn sync(client: &mut Client<Scripted>, collection: &str) -> PimdirSyncReport {
    client
        .sync(collection, PimdirSyncOptions::default())
        .unwrap()
}

fn db(client: &Client<Scripted>) -> rusqlite::Connection {
    rusqlite::Connection::open(client.path().join("pimdir.db")).unwrap()
}

fn refcount(client: &Client<Scripted>, body: &[u8]) -> Option<i64> {
    db(client)
        .query_row(
            "SELECT refcount FROM objects WHERE hash = ?1",
            [hash(body).as_str()],
            |row| row.get(0),
        )
        .ok()
}

#[derive(Debug, PartialEq)]
struct ItemRow {
    link_id: String,
    object: Option<String>,
    level: i64,
    deleted: i64,
    retained: bool,
    conflicted: i64,
}

fn items(client: &Client<Scripted>, collection: &str) -> Vec<ItemRow> {
    let conn = db(client);
    let mut stmt = conn
        .prepare(
            "SELECT i.link_id, o.hash, i.level, i.deleted, i.retained_at IS NOT NULL, i.conflicted \
             FROM items i LEFT JOIN objects o ON o.id = i.object \
             WHERE i.collection = ?1 ORDER BY i.link_id",
        )
        .unwrap();
    stmt.query_map([collection], |row| {
        Ok(ItemRow {
            link_id: row.get(0)?,
            object: row.get::<_, Option<String>>(1)?.as_deref().map(named),
            level: row.get(2)?,
            deleted: row.get(3)?,
            retained: row.get(4)?,
            conflicted: row.get(5)?,
        })
    })
    .unwrap()
    .map(Result::unwrap)
    .collect()
}

#[derive(Debug, PartialEq)]
struct BindingRow {
    source: String,
    handle: String,
    link_id: String,
    conflicted: i64,
    conflict_revision: Option<String>,
    conflict_object: Option<String>,
    base_present: i64,
    base_revision: Option<String>,
    base_object: Option<String>,
    base_flags_known: i64,
    shared_object: Option<String>,
}

fn bindings(client: &Client<Scripted>, collection: &str) -> Vec<BindingRow> {
    let conn = db(client);
    let mut stmt = conn
        .prepare(
            "SELECT b.source, b.handle, i.link_id, b.conflicted, b.conflict_revision, c.hash, \
             b.base_present, b.base_revision, o.hash, b.base_flags_known, s.hash \
             FROM bindings b JOIN items i ON i.id = b.item \
             LEFT JOIN objects c ON c.id = b.conflict_object \
             LEFT JOIN objects o ON o.id = b.base_object \
             LEFT JOIN objects s ON s.id = b.shared_object \
             WHERE b.collection = ?1 ORDER BY b.source, b.handle",
        )
        .unwrap();
    stmt.query_map([collection], |row| {
        Ok(BindingRow {
            source: row.get(0)?,
            handle: row.get(1)?,
            link_id: row.get(2)?,
            conflicted: row.get(3)?,
            conflict_revision: row.get(4)?,
            conflict_object: row.get::<_, Option<String>>(5)?.as_deref().map(named),
            base_present: row.get(6)?,
            base_revision: row.get(7)?,
            base_object: row.get::<_, Option<String>>(8)?.as_deref().map(named),
            base_flags_known: row.get(9)?,
            shared_object: row.get::<_, Option<String>>(10)?.as_deref().map(named),
        })
    })
    .unwrap()
    .map(Result::unwrap)
    .collect()
}

fn edit(client: &mut Client<Scripted>, handle: &str, body: &[u8]) {
    let resolves = client.shown("inbox", &h(handle));
    client
        .mutate(
            "inbox",
            PimdirMutation::Edit {
                overrule: false,
                if_match: None,
                resolves,
                handle: h(handle),
                object: object(body),
                body: body.to_vec(),
                summary: None,
                sort_key: None,
            },
        )
        .unwrap();
}

fn remove(client: &mut Client<Scripted>, handle: &str) {
    let resolves = client.shown("inbox", &h(handle));
    client
        .mutate(
            "inbox",
            PimdirMutation::Remove {
                handle: h(handle),
                if_match: None,
                resolves,
            },
        )
        .unwrap();
}

fn add(client: &mut Client<Scripted>, link: &str, set: &[&str], body: &[u8]) {
    client
        .mutate(
            "inbox",
            PimdirMutation::Add {
                link_id: PimdirLinkId::from(link),
                flags: flags(set),
                object: object(body),
                body: body.to_vec(),
                summary: None,
                sort_key: Default::default(),
            },
        )
        .unwrap();
}

fn renumber(client: &mut Client<Scripted>) {
    client.remote.inner.renumber("inbox", 2);
}

fn list_inner(client: &mut Client<Scripted>) {
    client.remote.listing = Some(listing(&client.remote.inner, "inbox"));
}

fn named(hash_text: &str) -> String {
    let known: [(&str, &[u8]); 9] = [
        ("BASE", BASE),
        ("LOCAL", LOCAL),
        ("REMOTE", REMOTE),
        ("bystander", b"the bystander body"),
        ("five", b"Subject: five\r\n\r\nbody five\r\n"),
        ("six", b"Subject: six\r\n\r\nbody six\r\n"),
        ("one", b"one"),
        ("bodyone", b"body one"),
        ("bodytwo", b"body two"),
    ];
    known
        .iter()
        .find(|(_, body)| hash(body).as_str() == hash_text)
        .map(|(name, _)| name.to_string())
        .unwrap_or_else(|| hash_text.to_string())
}

fn hn(hash: &Option<PimdirHash>) -> Option<String> {
    hash.as_ref().map(|h| named(h.as_str()))
}

fn subject(summary: &Option<PimdirSummary>) -> Option<String> {
    match summary {
        Some(PimdirSummary::Mail(mail)) => Some(mail.subject.clone()),
        _ => None,
    }
}

fn base_of(p: &PimdirPlacement) -> Option<(PimdirFlags, Option<String>, Option<String>)> {
    p.base
        .as_ref()
        .map(|b| (b.flags.clone(), b.revision.clone(), hn(&b.object)))
}

fn item(client: &Client<Scripted>, link: &str) -> ItemRow {
    items(client, "inbox")
        .into_iter()
        .find(|i| i.link_id == link)
        .unwrap_or_else(|| panic!("an item keyed {link:?}"))
}

fn binding(client: &Client<Scripted>, source: &str, handle: &str) -> BindingRow {
    bindings(client, "inbox")
        .into_iter()
        .find(|b| b.source == source && b.handle == handle)
        .unwrap_or_else(|| panic!("a binding of {source} at {handle:?}"))
}

fn links(client: &Client<Scripted>) -> Vec<String> {
    items(client, "inbox")
        .into_iter()
        .map(|i| i.link_id)
        .collect()
}

fn member(handle: &str, link: &str, set: &[&str], subject: &str, sort: &str) -> PimdirRemoteItem {
    PimdirRemoteItem {
        handle: h(handle),
        flags: flags(set),
        revision: None,
        meta: PimdirRemoteMeta {
            link_id: PimdirLinkId::from(link),
            summary: Some(mail(subject)),
            sort_key: sort.into(),
            body: None,
            server_object_id: None,
        },
    }
}

fn conflicted() -> Client<Scripted> {
    let mut c = Client::new(remote(true));
    c.remote.inner.seed("inbox", "m1", "l1", &[], BASE);
    c.remote
        .inner
        .seed("inbox", "m2", "l2", &["seen"], b"the bystander body");
    sync(&mut c, "inbox");
    c.upgrade("inbox", vec![h("m1"), h("m2")], PimdirTier::Full)
        .unwrap();
    edit(&mut c, "m1", LOCAL);
    c.remote.inner.edit("inbox", "m1", REMOTE);
    sync(&mut c, "inbox");
    c.upgrade("inbox", vec![h("m1")], PimdirTier::Full).unwrap();
    c
}

fn conflicted_tombstone() -> (Client<Scripted>, Client<Scripted>) {
    let mut a = Client::new(remote(true));
    a.remote.inner.seed("inbox", "m1", "l1", &[], BASE);
    a.remote
        .inner
        .seed("inbox", "m2", "l2", &["seen"], b"the bystander body");
    sync(&mut a, "inbox");
    a.upgrade("inbox", vec![h("m1"), h("m2")], PimdirTier::Full)
        .unwrap();
    let mut b = a.sharing(remote(true), "right");
    b.remote.inner.seed("inbox", "b1", "l1", &[], BASE);
    b.remote
        .inner
        .seed("inbox", "b2", "l2", &["seen"], b"the bystander body");
    sync(&mut b, "inbox");
    edit(&mut a, "m1", LOCAL);
    a.remote.inner.edit("inbox", "m1", REMOTE);
    sync(&mut a, "inbox");
    a.upgrade("inbox", vec![h("m1")], PimdirTier::Full).unwrap();
    remove(&mut b, "b1");
    (a, b)
}

fn staged_tombstone() -> Client<Scripted> {
    let mut c = Client::new(remote(true));
    c.remote.inner.seed("inbox", "m1", "l1", &[], BASE);
    c.remote
        .inner
        .seed("inbox", "m2", "l2", &[], b"the bystander body");
    sync(&mut c, "inbox");
    c.upgrade("inbox", vec![h("m1"), h("m2")], PimdirTier::Full)
        .unwrap();
    edit(&mut c, "m1", LOCAL);
    remove(&mut c, "m1");
    c.remote.inner.edit("inbox", "m1", REMOTE);
    c
}

fn delivered() -> Client<Scripted> {
    let mut c = Client::new(remote(false));
    c.remote.unassign_adds = true;
    c.remote.inner.seed("inbox", "m1", "l1", &[], b"one");
    sync(&mut c, "inbox");
    add(
        &mut c,
        "l5",
        &["seen"],
        b"Subject: five\r\n\r\nbody five\r\n",
    );
    sync(&mut c, "inbox");
    c.remote.inner.set_flags("inbox", "app-1", &["flagged"]);
    c
}

fn pending() -> Client<Scripted> {
    let mut c = Client::new(remote(false));
    c.remote.inner.seed("inbox", "m1", "l1", &[], b"one");
    sync(&mut c, "inbox");
    add(&mut c, "l6", &[], b"Subject: six\r\n\r\nbody six\r\n");
    c.remote.inner.seed(
        "inbox",
        "m6",
        "l6",
        &[],
        b"Subject: six\r\n\r\nbody six\r\n",
    );
    c
}

fn offered() -> (Client<Scripted>, Client<Scripted>) {
    let mut a = Client::new(remote(false));
    a.remote.inner.seed("inbox", "m1", "l1", &[], b"one");
    sync(&mut a, "inbox");
    let mut b = a.sharing(remote(false), "right");
    b.remote.inner.seed(
        "inbox",
        "b6",
        "l6",
        &[],
        b"Subject: six\r\n\r\nbody six\r\n",
    );
    sync(&mut b, "inbox");
    b.upgrade("inbox", vec![h("b6")], PimdirTier::Full).unwrap();
    a.remote.inner.seed(
        "inbox",
        "m6",
        "l6",
        &[],
        b"Subject: six\r\n\r\nbody six\r\n",
    );
    (a, b)
}

fn baseless_conflict() -> Client<Scripted> {
    let mut c = Client::new(remote(true));
    c.remote.inner.seed("inbox", "m1", "l1", &[], BASE);
    c.remote
        .inner
        .seed("inbox", "m2", "l2", &[], b"the bystander body");
    sync(&mut c, "inbox");
    let mut row = c.storage().placement("inbox", "m1");
    row.base = None;
    row.object = Some(hash(LOCAL));
    row.level = PimdirLevel::Full;
    row.status = PimdirStatus::Dirty;
    c.store
        .write(vec![
            PimdirWriteOp::StoreObject {
                object: object(LOCAL),
                body: Some(LOCAL.to_vec()),
            },
            PimdirWriteOp::UpsertPlacement(row),
        ])
        .unwrap();
    c.remote.inner.set_flags("inbox", "m1", &[]);
    sync(&mut c, "inbox");
    c
}

fn known(set: &[&str]) -> PimdirFlags {
    flags(set)
}

fn repeated() -> Vec<PimdirRemoteItem> {
    vec![
        member("v2-0", "l1", &["seen"], "first", "a"),
        member("v2-0", "l9", &["flagged"], "second", "b"),
    ]
}

/// R0: a rekey listing repeating a handle carries the first member's flags under the last member's identity, summary and sort key, and drops the old binding.
#[test]
fn k3_r0_a_repeated_handle_mixes_the_first_and_the_last_member() {
    let mut c = Client::new(remote(false));
    c.remote.inner.seed("inbox", "m1", "l1", &[], b"one");
    sync(&mut c, "inbox");
    renumber(&mut c);
    c.remote.listing = Some(repeated());

    let run = rekey(&mut c, "inbox");

    assert_eq!(
        run.drops(),
        vec![("m1".to_string(), PimdirDropReason::Deleted)]
    );
    assert_eq!((run.out.rekeyed, run.out.pulled), (0, 1));
    assert_eq!(run.out.events, vec![PimdirSyncEvent::Added(h("v2-0"))]);
    let rows = c.storage().rows("inbox");
    assert_eq!(rows.len(), 1);
    let row = &rows[0];
    assert_eq!(row.handle, h("v2-0"));
    assert_eq!(
        row.link_id,
        Some(PimdirLinkId::from("l9")),
        "the last member's identity"
    );
    assert_eq!(row.flags, known(&["seen"]), "the first member's flags");
    assert_eq!(
        subject(&row.summary).as_deref(),
        Some("second"),
        "the last member's summary"
    );
    assert_eq!(row.sort_key.as_str(), "b", "the last member's sort key");
    let old = item(&c, "l1");
    assert_eq!(
        (old.deleted, old.retained),
        (1, true),
        "the carried item went to the trash"
    );
    assert_eq!(item(&c, "l9").deleted, 0);
}

/// R0, page: a sync page repeating a handle keeps the first member whole.
#[test]
fn k3_r0_a_page_repeating_a_handle_keeps_the_first_member() {
    let mut c = Client::new(remote(false));
    c.remote.inner.seed("inbox", "v2-0", "l1", &[], b"one");
    c.remote.listing = Some(repeated());

    sync(&mut c, "inbox");

    let rows = c.storage().rows("inbox");
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].link_id, Some(PimdirLinkId::from("l1")));
    assert_eq!(rows[0].flags, known(&["seen"]));
    assert_eq!(subject(&rows[0].summary).as_deref(), Some("first"));
    assert_eq!(rows[0].sort_key.as_str(), "a");
    assert_eq!(links(&c), vec!["l1".to_string()]);
}

/// R1: a binding conflict whose member the rekey lists with no revision loses its conflict: the op says Conflict with no revision, the hub records none and the row reads Dirty.
#[test]
fn k3_r1_a_conflict_listed_without_revision_is_cleared() {
    let mut c = conflicted();
    let before = binding(&c, "left", "m1");
    assert_eq!(
        (
            before.conflicted,
            before.conflict_revision.as_deref(),
            before.conflict_object.as_deref()
        ),
        (1, Some("1"), Some("REMOTE"))
    );
    renumber(&mut c);
    let mut items = listing(&c.remote.inner, "inbox");
    for item in &mut items {
        item.revision = None;
        item.meta.body = None;
    }
    c.remote.listing = Some(items);

    let run = rekey(&mut c, "inbox");

    assert_eq!((run.out.rekeyed, run.out.dropped), (2, 0));
    let op = run.upserted("v2-0");
    assert_eq!(
        op.status,
        PimdirStatus::Conflict,
        "the op still says Conflict"
    );
    assert_eq!((op.conflict_revision, op.conflict_object), (None, None));
    let row = c.storage().placement("inbox", "v2-0");
    assert_eq!(row.status, PimdirStatus::Dirty);
    assert_eq!(hn(&row.object).as_deref(), Some("LOCAL"));
    assert_eq!(
        base_of(&row),
        Some((known(&[]), Some("0".into()), Some("BASE".into())))
    );
    assert_eq!((row.conflict_revision, row.conflict_object), (None, None));
    let after = binding(&c, "left", "v2-0");
    assert_eq!(
        (
            after.conflicted,
            after.conflict_revision,
            after.conflict_object
        ),
        (0, None, None),
        "the hub records no conflict"
    );
    assert_eq!(
        refcount(&c, REMOTE),
        Some(0),
        "the diverging body is collectable"
    );

    c.remote.listing = None;
    c.remote.pushed.clear();
    let next = sync(&mut c, "inbox");
    assert_eq!(
        c.remote.pushed,
        vec!["update".to_string()],
        "the local edit is pushed"
    );
    assert_eq!(
        (next.pushed, next.rejected),
        (0, 1),
        "the fake refuses the stale if_match"
    );
}

/// R2: a tombstone listed at its base revision with other flags stays a tombstone, its flags and base flags the listed ones.
#[test]
fn k3_r2_a_tombstone_at_its_base_revision_takes_the_listed_flags() {
    let mut c = Client::new(remote(true));
    c.remote.inner.seed("inbox", "m1", "l1", &[], BASE);
    sync(&mut c, "inbox");
    c.upgrade("inbox", vec![h("m1")], PimdirTier::Full).unwrap();
    remove(&mut c, "m1");
    c.remote.inner.set_flags("inbox", "m1", &["flagged"]);
    renumber(&mut c);
    list_inner(&mut c);

    let run = rekey(&mut c, "inbox");

    assert_eq!(
        run.drops(),
        vec![("m1".to_string(), PimdirDropReason::Rekeyed)]
    );
    let row = c.storage().placement("inbox", "v2-0");
    assert_eq!(row.status, PimdirStatus::Tombstone);
    assert_eq!(hn(&row.object).as_deref(), Some("BASE"));
    assert_eq!(row.flags, known(&["flagged"]));
    assert_eq!(
        base_of(&row),
        Some((known(&["flagged"]), Some("0".into()), Some("BASE".into())))
    );
    assert_eq!(item(&c, "l1").deleted, 1);
}

/// R2: a tombstone whose binding is conflicted, listed at its base revision, loses the divergence, and the next sync pushes its Remove.
#[test]
fn k3_r2_a_conflicted_tombstone_at_its_base_revision_loses_the_divergence() {
    let (mut a, _b) = conflicted_tombstone();
    let before = a.storage().placement("inbox", "m1");
    assert_eq!(before.status, PimdirStatus::Tombstone);
    assert_eq!(before.conflict_revision.as_deref(), Some("1"));
    assert_eq!(binding(&a, "left", "m1").conflicted, 1);
    renumber(&mut a);
    let mut items = listing(&a.remote.inner, "inbox");
    for item in &mut items {
        if item.meta.link_id.as_str() == "l1" {
            item.revision = Some("0".into());
            item.flags = flags(&["flagged"]);
            item.meta.body = None;
        }
    }
    a.remote.listing = Some(items);

    rekey(&mut a, "inbox");

    let row = a.storage().placement("inbox", "v2-0");
    assert_eq!(row.status, PimdirStatus::Tombstone);
    assert_eq!(hn(&row.object).as_deref(), Some("LOCAL"));
    assert_eq!(row.flags, known(&["flagged"]));
    assert_eq!(
        base_of(&row),
        Some((known(&["flagged"]), Some("0".into()), Some("BASE".into())))
    );
    assert_eq!((row.conflict_revision, row.conflict_object), (None, None));
    let after = binding(&a, "left", "v2-0");
    assert_eq!((after.conflicted, after.conflict_revision), (0, None));
    assert_eq!(refcount(&a, REMOTE), Some(0));

    a.remote.listing = None;
    a.remote.pushed.clear();
    let next = sync(&mut a, "inbox");
    assert_eq!(
        a.remote.pushed,
        vec!["remove".to_string()],
        "a Remove is derived"
    );
    assert_eq!(next.rejected, 1, "the fake refuses the stale if_match");
}

/// R2: a tombstone whose binding is conflicted, listed at its conflict revision, is revived clean and bodiless, the staged edit kept by no retained item.
#[test]
fn k3_r2_a_conflicted_tombstone_at_its_conflict_revision_is_revived_clean() {
    let (mut a, _b) = conflicted_tombstone();
    renumber(&mut a);
    list_inner(&mut a);

    let run = rekey(&mut a, "inbox");

    assert_eq!(run.overruled(), Vec::<(String, String)>::new());
    let row = a.storage().placement("inbox", "v2-0");
    assert_eq!(row.status, PimdirStatus::Clean);
    assert_eq!((hn(&row.object), row.level), (None, PimdirLevel::Meta));
    assert_eq!(base_of(&row), Some((known(&[]), Some("1".into()), None)));
    assert_eq!((row.conflict_revision, row.conflict_object), (None, None));
    let shared = item(&a, "l1");
    assert_eq!(
        (shared.deleted, shared.object),
        (0, None),
        "the item is live again, bodiless"
    );
    assert!(
        a.storage().retained("inbox").is_empty(),
        "no retained item keeps LOCAL"
    );
    assert_eq!(
        binding(&a, "left", "v2-0").shared_object.as_deref(),
        Some("LOCAL")
    );
    assert_eq!(
        refcount(&a, LOCAL),
        Some(1),
        "pinned by the binding's shared_object alone"
    );
    assert_eq!(refcount(&a, REMOTE), Some(0));
}

/// R3: a tombstone holding a staged edit, the remote edited, through a rekey: revived as a pull, the staged edit kept as a retained item the write reports overruled and the rekey report does not.
#[test]
fn k3_r3_a_staged_edit_under_a_tombstone_survives_as_a_retained_item() {
    let mut c = staged_tombstone();
    let before = c.storage().placement("inbox", "m1");
    assert_eq!(before.status, PimdirStatus::Tombstone);
    assert_eq!(hn(&before.object).as_deref(), Some("LOCAL"));
    assert_eq!(refcount(&c, LOCAL), Some(2));
    renumber(&mut c);
    list_inner(&mut c);

    let run = rekey(&mut c, "inbox");

    assert_eq!((run.out.rekeyed, run.out.dropped), (2, 0));
    assert_eq!(
        run.overruled(),
        vec![("v2-0".to_string(), "dup:l1#v2-0".to_string())],
        "the write keeps the staged body as an overruled loser"
    );
    let row = c.storage().placement("inbox", "v2-0");
    assert_eq!(
        row.status,
        PimdirStatus::Clean,
        "revived, no conflict recorded"
    );
    assert_eq!((hn(&row.object), row.level), (None, PimdirLevel::Meta));
    assert_eq!(base_of(&row), Some((known(&[]), Some("1".into()), None)));
    let kept = item(&c, "dup:l1#v2-0");
    assert_eq!(kept.object.as_deref(), Some("LOCAL"));
    assert_eq!((kept.deleted, kept.retained), (1, true));
    let retained = c.storage().retained("inbox");
    assert_eq!(retained.len(), 1);
    assert_eq!(retained[0].link_id.as_str(), "dup:l1#v2-0");
    assert_eq!(hn(&retained[0].object).as_deref(), Some("LOCAL"));
    assert_eq!(item(&c, "l1").object, None);
    assert_eq!(
        refcount(&c, LOCAL),
        Some(2),
        "the retained item and the binding's shared_object"
    );
    assert_eq!(
        binding(&c, "left", "v2-0").shared_object.as_deref(),
        Some("LOCAL")
    );
    assert_eq!(refcount(&c, BASE), Some(0));
}

/// R3, page: a sync page in the same state records a Manual conflict, the staged edit kept in the placement.
#[test]
fn k3_r3_a_page_records_the_both_changed_tombstone_as_a_conflict() {
    let mut c = staged_tombstone();

    let run = sync_recorded(&mut c, "inbox");

    assert_eq!(run.out.conflicts, 1);
    assert_eq!(run.out.events, vec![PimdirSyncEvent::Conflicted(h("m1"))]);
    assert_eq!(run.overruled(), Vec::<(String, String)>::new());
    let row = c.storage().placement("inbox", "m1");
    assert_eq!(row.status, PimdirStatus::Conflict);
    assert_eq!(hn(&row.object).as_deref(), Some("LOCAL"));
    assert_eq!(row.conflict_revision.as_deref(), Some("1"));
    assert_eq!(hn(&row.conflict_object).as_deref(), Some("REMOTE"));
    assert_eq!(
        base_of(&row),
        Some((known(&[]), Some("0".into()), Some("BASE".into())))
    );
    assert_eq!(item(&c, "l1").deleted, 0);
    assert!(c.storage().retained("inbox").is_empty());
}

/// R4: a carried row whose listed flags are unknown takes an unknown base, reads Clean, and the flag it owed is never pushed.
#[test]
fn k3_r4_unknown_listed_flags_become_the_base() {
    let mut c = Client::new(remote(false));
    c.remote.inner.seed("inbox", "m1", "l1", &["seen"], b"one");
    sync(&mut c, "inbox");
    c.mutate(
        "inbox",
        PimdirMutation::SetFlags {
            handle: h("m1"),
            flags: flags(&["seen", "flagged"]),
            base: None,
        },
    )
    .unwrap();
    assert_eq!(
        c.storage().placement("inbox", "m1").status,
        PimdirStatus::Dirty
    );
    renumber(&mut c);
    let mut items = listing(&c.remote.inner, "inbox");
    for item in &mut items {
        item.flags = PimdirFlags::Unknown;
    }
    c.remote.listing = Some(items);

    rekey(&mut c, "inbox");

    let row = c.storage().placement("inbox", "v2-0");
    assert_eq!(row.status, PimdirStatus::Clean);
    assert_eq!(row.flags, known(&["flagged", "seen"]));
    assert_eq!(base_of(&row), Some((PimdirFlags::Unknown, None, None)));
    assert_eq!(binding(&c, "left", "v2-0").base_flags_known, 0);

    c.remote.listing = None;
    c.remote.pushed.clear();
    sync(&mut c, "inbox");
    assert!(c.remote.pushed.is_empty(), "nothing pushed");
    assert_eq!(c.remote.inner.flags_of("inbox", "v2-0"), &known(&["seen"]));
}

/// R5: a delivered create matched by a rekey is carried with a Rekeyed drop, no event, the flags united and the base holding the staged body.
#[test]
fn k3_r5_a_delivered_create_is_carried_not_landed() {
    let mut c = delivered();
    let before = c.storage().placement("inbox", "\u{1}l5");
    assert!(before.delivered());
    renumber(&mut c);
    list_inner(&mut c);

    let run = rekey(&mut c, "inbox");

    assert_eq!(
        (run.out.rekeyed, run.out.pulled, run.out.dropped),
        (2, 0, 0)
    );
    assert!(run.out.events.is_empty(), "no Created event");
    assert_eq!(
        run.drops(),
        vec![
            ("m1".to_string(), PimdirDropReason::Rekeyed),
            ("\u{1}l5".to_string(), PimdirDropReason::Rekeyed),
        ]
    );
    let row = c.storage().placement("inbox", "v2-0");
    assert_eq!(row.link_id, Some(PimdirLinkId::from("l5")));
    assert_eq!(row.status, PimdirStatus::Dirty);
    assert_eq!(
        row.flags,
        known(&["flagged", "seen"]),
        "the staged and the listed flags united"
    );
    assert_eq!(
        base_of(&row),
        Some((known(&["flagged"]), None, Some("five".into())))
    );
}

/// R5, page: a sync page lands the delivered create with a Superseded drop and a Created event, the staged flags pushed over the listed ones.
#[test]
fn k3_r5_a_page_lands_the_delivered_create() {
    let mut c = delivered();
    c.remote.pushed.clear();

    let run = sync_recorded(&mut c, "inbox");

    assert_eq!(run.out.events, vec![PimdirSyncEvent::Created(h("app-1"))]);
    assert_eq!(
        run.drops(),
        vec![("\u{1}l5".to_string(), PimdirDropReason::Superseded)]
    );
    assert_eq!(c.remote.pushed, vec!["set-flags".to_string()]);
    let row = c.storage().placement("inbox", "app-1");
    assert_eq!(row.status, PimdirStatus::Clean);
    assert_eq!(row.flags, known(&["seen"]));
    assert_eq!(
        base_of(&row),
        Some((known(&["seen"]), None, Some("five".into())))
    );
    assert_eq!(c.remote.inner.flags_of("inbox", "app-1"), &known(&["seen"]));
}

/// R6: a pending create whose hint a rekey member states is left as it is, the member minted apart as a second item.
#[test]
fn k3_r6_a_pending_create_is_left_and_the_member_minted_apart() {
    let mut c = pending();
    renumber(&mut c);
    list_inner(&mut c);

    let run = rekey(&mut c, "inbox");

    assert_eq!((run.out.rekeyed, run.out.pulled), (1, 1));
    assert_eq!(run.out.events, vec![PimdirSyncEvent::Added(h("v2-1"))]);
    assert_eq!(
        run.drops(),
        vec![("m1".to_string(), PimdirDropReason::Rekeyed)]
    );
    let create = c.storage().placement("inbox", "\u{1}l6");
    assert_eq!(create.status, PimdirStatus::Created);
    let minted = c.storage().placement("inbox", "v2-1");
    assert_eq!(minted.link_id, Some(PimdirLinkId::from("dup:l6#v2-1")));
    assert_eq!(
        links(&c),
        vec!["dup:l6#v2-1".to_string(), "l1".into(), "l6".into()]
    );
}

/// R6, page: a sync page lands the pending create on the member stating its hint.
#[test]
fn k3_r6_a_page_lands_the_pending_create() {
    let mut c = pending();

    let run = sync_recorded(&mut c, "inbox");

    assert_eq!(run.out.events, vec![PimdirSyncEvent::Created(h("m6"))]);
    assert_eq!(
        run.drops(),
        vec![("\u{1}l6".to_string(), PimdirDropReason::Superseded)]
    );
    let row = c.storage().placement("inbox", "m6");
    assert_eq!(row.link_id, Some(PimdirLinkId::from("l6")));
    assert_eq!(row.status, PimdirStatus::Clean);
    assert_eq!(links(&c), vec!["l1".to_string(), "l6".into()]);
}

/// R6: an offered copy (an item another source binds) whose hint a rekey member states is left offered, the member minted apart as a second item.
#[test]
fn k3_r6_an_offered_copy_is_left_and_the_member_minted_apart() {
    let (mut a, _b) = offered();
    let offer = a.storage().placement("inbox", "\u{1}l6");
    assert_eq!(
        (offer.status, offer.base.is_none()),
        (PimdirStatus::Created, true)
    );
    assert!(
        bindings(&a, "inbox")
            .iter()
            .all(|b| b.source != "left" || b.link_id != "l6")
    );
    renumber(&mut a);
    list_inner(&mut a);

    let run = rekey(&mut a, "inbox");

    assert_eq!(run.out.events, vec![PimdirSyncEvent::Added(h("v2-1"))]);
    let minted = a.storage().placement("inbox", "v2-1");
    assert_eq!(minted.link_id, Some(PimdirLinkId::from("dup:l6#v2-1")));
    assert_eq!(
        a.storage().placement("inbox", "\u{1}l6").status,
        PimdirStatus::Created
    );
    assert_eq!(
        links(&a),
        vec!["dup:l6#v2-1".to_string(), "l1".into(), "l6".into()]
    );
    assert!(
        bindings(&a, "inbox")
            .iter()
            .all(|b| b.source != "left" || b.link_id != "l6")
    );
}

/// R6, page: a sync page joins the offered copy's item on the member stating its hint.
#[test]
fn k3_r6_a_page_joins_the_offered_copy() {
    let (mut a, _b) = offered();

    let run = sync_recorded(&mut a, "inbox");

    assert_eq!(run.out.events, vec![PimdirSyncEvent::Added(h("m6"))]);
    assert_eq!(
        run.drops(),
        vec![("\u{1}l6".to_string(), PimdirDropReason::Superseded)]
    );
    assert_eq!(binding(&a, "left", "m6").link_id, "l6");
    assert_eq!(binding(&a, "right", "b6").link_id, "l6");
    assert_eq!(links(&a), vec!["l1".to_string(), "l6".into()]);
}

/// R7: a base-less conflict matched by a rekey is given a base (the listed flags, no revision, no body), its conflict kept.
#[test]
fn k3_r7_a_matched_base_less_conflict_gains_a_base() {
    let mut c = baseless_conflict();
    let before = c.storage().placement("inbox", "m1");
    assert_eq!(
        (before.status, before.base.is_none()),
        (PimdirStatus::Conflict, true)
    );
    assert_eq!(before.conflict_revision.as_deref(), Some("0"));
    assert_eq!(binding(&c, "left", "m1").base_present, 0);
    renumber(&mut c);
    list_inner(&mut c);

    let run = rekey(&mut c, "inbox");

    assert_eq!(
        run.drops(),
        vec![
            ("m1".to_string(), PimdirDropReason::Rekeyed),
            ("m2".to_string(), PimdirDropReason::Rekeyed),
        ]
    );
    let row = c.storage().placement("inbox", "v2-0");
    assert_eq!(row.status, PimdirStatus::Conflict);
    assert_eq!(hn(&row.object).as_deref(), Some("LOCAL"));
    assert_eq!(base_of(&row), Some((known(&[]), None, None)));
    assert_eq!(row.conflict_revision.as_deref(), Some("0"));
    assert_eq!(hn(&row.conflict_object).as_deref(), Some("BASE"));
    let after = binding(&c, "left", "v2-0");
    assert_eq!((after.base_present, after.conflicted), (1, 1));
}

/// R7: a base-less conflict no rekey member matches is re-staged as a pending create, its conflict and diverging body dropped.
#[test]
fn k3_r7_an_unmatched_base_less_conflict_is_restaged() {
    let mut c = baseless_conflict();
    c.remote.inner.remove("inbox", "m1");
    renumber(&mut c);
    list_inner(&mut c);

    let run = rekey(&mut c, "inbox");

    assert_eq!(
        run.drops(),
        vec![
            ("m1".to_string(), PimdirDropReason::Superseded),
            ("m2".to_string(), PimdirDropReason::Rekeyed),
        ]
    );
    let row = c.storage().placement("inbox", "\u{1}l1");
    assert_eq!(row.status, PimdirStatus::Created);
    assert_eq!(hn(&row.object).as_deref(), Some("LOCAL"));
    assert_eq!(row.base, None);
    assert_eq!((row.conflict_revision, row.conflict_object), (None, None));
    let after = binding(&c, "left", "\u{1}l1");
    assert_eq!((after.base_present, after.conflicted), (0, 0));
    assert_eq!(
        refcount(&c, BASE),
        Some(0),
        "the diverging body is collectable"
    );
}

/// R8: a rekey listing whose members carry bodies, inline or persisted, stores none and leaves both members at Meta.
#[test]
fn k3_r8_listed_bodies_are_ignored() {
    let one: &[u8] = b"body one";
    let two: &[u8] = b"body two";
    let mut c = Client::new(remote(true));
    c.remote.inner.seed("inbox", "m1", "l1", &[], one);
    let mut items = listing(&c.remote.inner, "inbox");
    for item in &mut items {
        item.meta.body = None;
    }
    c.remote.listing = Some(items);
    sync(&mut c, "inbox");
    assert_eq!(c.storage().objects(), 0);
    c.remote.inner.seed("inbox", "m2", "l2", &[], two);
    renumber(&mut c);
    let path = PimdirBlobs::open(c.path()).path(&hash(two)).unwrap();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(&path, two).unwrap();
    let mut items = listing(&c.remote.inner, "inbox");
    for item in &mut items {
        if item.meta.link_id.as_str() == "l2" {
            item.meta.body = Some(PimdirFetchedBody::Persisted {
                hash: hash(two),
                size: two.len(),
            });
        }
    }
    assert!(matches!(
        items[0].meta.body,
        Some(PimdirFetchedBody::Inline { .. })
    ));
    c.remote.listing = Some(items);

    let run = rekey(&mut c, "inbox");

    assert_eq!(run.stores(), 0, "no StoreObject");
    assert_eq!(run.out.events, vec![PimdirSyncEvent::Added(h("v2-1"))]);
    for handle in ["v2-0", "v2-1"] {
        let row = c.storage().placement("inbox", handle);
        assert_eq!(
            (row.object, row.level),
            (None, PimdirLevel::Meta),
            "{handle}"
        );
    }
    assert_eq!(c.storage().objects(), 0);
    assert_eq!((refcount(&c, one), refcount(&c, two)), (None, None));
}

/// R8, page: a sync page whose member carries its body stores it at Full.
#[test]
fn k3_r8_a_page_stores_the_listed_body() {
    let one: &[u8] = b"body one";
    let mut c = Client::new(remote(true));
    c.remote.inner.seed("inbox", "m1", "l1", &[], one);

    let run = sync_recorded(&mut c, "inbox");

    assert_eq!(run.stores(), 1);
    let row = c.storage().placement("inbox", "m1");
    assert_eq!(
        (hn(&row.object).as_deref(), row.level),
        (Some("bodyone"), PimdirLevel::Full)
    );
}
