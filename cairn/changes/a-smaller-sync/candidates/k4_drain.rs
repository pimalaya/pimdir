//! # K4: the queue's drain against `store.mutate`
//!
//! Two sources on one store: `right` binds `mid:L` in T, `left` binds the
//! same message in S and syncs T too. A Copy or a Move of left's item from
//! S to T runs once through the drain and once through `store.mutate`, on
//! the same seed, and each test pins the key and the binding left gets.

#![cfg(feature = "client")]

use std::path::Path;

use io_pimdir::{
    change::PimdirWriteOp,
    client::{PimdirSourceStore, PimdirStore, producer::PimdirProducer},
    codec::PimdirAction,
    collection::{PimdirCheckpoint, PimdirCollectionId},
    hash,
    load::PimdirLoadSelection,
    mutate::PimdirMutation,
    object::PimdirObject,
    placement::{
        PimdirBase, PimdirFlags, PimdirHandle, PimdirLevel, PimdirLinkId, PimdirPlacement,
        PimdirStatus,
    },
    summary::{PimdirSummary, mail::PimdirMailSummary},
};

const BODY: &[u8] = b"Subject: mid:L\r\n\r\nthe shared message\r\n";

fn placement(collection: &str, handle: &str) -> PimdirPlacement {
    PimdirPlacement {
        sort_key: Default::default(),
        collection: PimdirCollectionId(collection.into()),
        handle: PimdirHandle(handle.into()),
        link_id: Some(PimdirLinkId("mid:L".into())),
        object: Some(hash::hash(BODY)),
        level: PimdirLevel::Full,
        summary: Some(PimdirSummary::Mail(PimdirMailSummary {
            subject: "mid:L".into(),
            ..Default::default()
        })),
        flags: PimdirFlags::default(),
        status: PimdirStatus::Clean,
        conflict_revision: None,
        conflict_object: None,
        base: Some(PimdirBase {
            flags: PimdirFlags::default(),
            revision: None,
            object: Some(hash::hash(BODY)),
        }),
        origin: None,
        server_object_id: None,
    }
}

fn seeded(dir: &Path) -> PimdirSourceStore {
    let mut right = PimdirStore::open(dir).unwrap().for_source("right");
    right.ensure_collection("S", "message/rfc822").unwrap();
    right.ensure_collection("T", "message/rfc822").unwrap();
    right
        .write(vec![
            PimdirWriteOp::StoreObject {
                object: PimdirObject {
                    hash: hash::hash(BODY),
                    size: BODY.len(),
                },
                body: Some(BODY.to_vec()),
            },
            PimdirWriteOp::UpsertPlacement(placement("T", "t1")),
        ])
        .unwrap();
    drop(right);
    let mut left = PimdirStore::open(dir).unwrap().for_source("left");
    left.write(vec![
        PimdirWriteOp::UpsertPlacement(placement("S", "s1")),
        PimdirWriteOp::SetCheckpoint {
            collection: PimdirCollectionId("T".into()),
            checkpoint: PimdirCheckpoint(b"cp".to_vec()),
        },
    ])
    .unwrap();
    left
}

#[derive(Debug, PartialEq)]
struct Row {
    source: String,
    handle: String,
    link_id: String,
    seq: i64,
    status_base: i64,
}

fn target(dir: &Path) -> Vec<Row> {
    let conn = rusqlite::Connection::open(dir.join("pimdir.db")).unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT b.source, b.handle, i.link_id, i.seq, b.base_present \
             FROM bindings b JOIN items i ON i.id = b.item \
             WHERE b.collection = 'T' ORDER BY b.source, b.handle",
        )
        .unwrap();
    stmt.query_map([], |row| {
        Ok(Row {
            source: row.get(0)?,
            handle: row.get(1)?,
            link_id: row.get(2)?,
            seq: row.get(3)?,
            status_base: row.get(4)?,
        })
    })
    .unwrap()
    .map(Result::unwrap)
    .collect()
}

fn items(dir: &Path) -> Vec<(String, String, i64)> {
    let conn = rusqlite::Connection::open(dir.join("pimdir.db")).unwrap();
    let mut stmt = conn
        .prepare("SELECT collection, link_id, seq FROM items ORDER BY collection, link_id")
        .unwrap();
    stmt.query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .unwrap()
        .map(Result::unwrap)
        .collect()
}

fn projected(
    store: &PimdirSourceStore,
    collection: &str,
) -> Vec<(String, Option<String>, PimdirStatus)> {
    store
        .load(
            &PimdirCollectionId(collection.into()),
            &PimdirLoadSelection::All,
        )
        .unwrap()
        .placements
        .into_iter()
        .map(|p| (p.handle.0.clone(), p.link_id.map(|l| l.0), p.status))
        .collect()
}

fn seq_in_s(store: &PimdirSourceStore) -> i64 {
    store.list_items("S", None, 10).unwrap()[0].seq
}

fn row(source: &str, handle: &str, link: &str, seq: i64, base: i64) -> Row {
    Row {
        source: source.into(),
        handle: handle.into(),
        link_id: link.into(),
        seq,
        status_base: base,
    }
}

fn seeded_state(dir: &Path, left: &PimdirSourceStore) {
    assert_eq!(target(dir), vec![row("right", "t1", "mid:L", 1, 1)]);
    assert_eq!(
        projected(left, "T"),
        vec![(
            "\u{1}mid:L".to_string(),
            Some("mid:L".to_string()),
            PimdirStatus::Created
        )],
        "the store offers left the item right binds"
    );
}

fn enqueue(dir: &Path, left: &PimdirSourceStore, copy: bool) {
    let seq = seq_in_s(left);
    let to = PimdirCollectionId("T".into());
    let action = match copy {
        true => PimdirAction::Copy { seq, to },
        false => PimdirAction::Move { seq, to },
    };
    let mut producer = PimdirProducer::open(dir, "test").unwrap();
    producer.enqueue("S", &action, None).unwrap();
}

fn mutation(copy: bool) -> PimdirMutation {
    let handle = PimdirHandle("s1".into());
    let target = PimdirCollectionId("T".into());
    match copy {
        true => PimdirMutation::Copy { handle, target },
        false => PimdirMutation::Move { handle, target },
    }
}

const MINTED: &str = "dup:mid:L#\u{1}mid:L";

fn drained(copy: bool) {
    let dir = tempfile::tempdir().unwrap();
    let mut left = seeded(dir.path());
    seeded_state(dir.path(), &left);
    enqueue(dir.path(), &left, copy);

    let report = left.drain().unwrap();

    assert_eq!((report.applied, report.parked), (1, 0));
    assert_eq!(
        target(dir.path()),
        vec![
            row("left", &format!("\u{1}{MINTED}"), MINTED, 2, 0),
            row("right", "t1", "mid:L", 1, 1),
        ],
        "the drain mints a second item with a new seq"
    );
    assert_eq!(
        projected(&left, "T"),
        vec![
            (
                format!("\u{1}{MINTED}"),
                Some(MINTED.to_string()),
                PimdirStatus::Created
            ),
            (
                "\u{1}mid:L".to_string(),
                Some("mid:L".to_string()),
                PimdirStatus::Created
            ),
        ],
        "left still projects the offered copy beside its own create"
    );
    let source = match copy {
        true => PimdirStatus::Clean,
        false => PimdirStatus::Tombstone,
    };
    assert_eq!(projected(&left, "S")[0].2, source);
}

fn mutated(copy: bool) {
    let dir = tempfile::tempdir().unwrap();
    let mut left = seeded(dir.path());
    seeded_state(dir.path(), &left);

    left.mutate("S", mutation(copy)).unwrap();

    assert_eq!(
        target(dir.path()),
        vec![
            row("left", "\u{1}mid:L", "mid:L", 1, 0),
            row("right", "t1", "mid:L", 1, 1),
        ],
        "store.mutate binds left to right's item under the bare key"
    );
    assert_eq!(
        items(dir.path()),
        vec![
            ("S".to_string(), "mid:L".to_string(), 1),
            ("T".into(), "mid:L".into(), 1)
        ]
    );
    assert_eq!(
        projected(&left, "T"),
        vec![(
            "\u{1}mid:L".to_string(),
            Some("mid:L".to_string()),
            PimdirStatus::Created
        )]
    );
    let source = match copy {
        true => PimdirStatus::Clean,
        false => PimdirStatus::Tombstone,
    };
    assert_eq!(projected(&left, "S")[0].2, source);
}

/// K4: a queued Copy into T, where another source binds the identity, mints `dup:` and a second item.
#[test]
fn k4_a_drained_copy_mints_a_second_item_beside_another_sources() {
    drained(true);
}

/// K4: the same Copy through store.mutate joins the other source's item under the bare key.
#[test]
fn k4_a_mutated_copy_joins_the_other_sources_item() {
    mutated(true);
}

/// K4: a queued Move into T, where another source binds the identity, mints `dup:` and a second item.
#[test]
fn k4_a_drained_move_mints_a_second_item_beside_another_sources() {
    drained(false);
}

/// K4: the same Move through store.mutate joins the other source's item under the bare key.
#[test]
fn k4_a_mutated_move_joins_the_other_sources_item() {
    mutated(false);
}
