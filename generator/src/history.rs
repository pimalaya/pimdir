//! # Histories
//!
//! A history is a list of steps, each an event and the store it leaves: a
//! remote's change, a producer's action drained, or a verb run against the
//! scripted remote, with the script it ran and what it answered. Each
//! step's model is the truth io-pimdir's store must hold after it, read
//! through the oracle; each run's pushes, outcomes and events are what its
//! engine must answer.

use std::collections::{BTreeMap, BTreeSet};

use crate::{
    body::{Card, Mail, fnv1a64},
    engine::{Options, Push, Run},
    model::{Collection, Kind, Model, Scope, synced_by},
    name::ObjectName,
    profile::Draw,
    queue::{Action, RowState},
    remote::{Policy, Remote},
    time::Instant,
};

/// One step of a history.
#[derive(Clone, Debug)]
pub struct Step {
    /// What happened.
    pub label: String,
    /// The verb run, if the step ran one.
    pub run: Option<Run>,
    /// The store after the step.
    pub model: Model,
}

/// A history over one source and one mailbox.
#[derive(Clone, Debug)]
pub struct History {
    /// Its steps, in order.
    pub steps: Vec<Step>,
}

/// The page size of a first round, small so seven members span three.
pub const PAGE: usize = 3;

/// The address books [`History::sources`] shares between two sources: the
/// conflict policy of each, and whether `b`'s edit agrees with the one `a`
/// folded.
const SHARED: [(&str, &str, bool); 4] = [
    ("work/shared", "manual", false),
    ("work/incoming", "prefer-incoming", false),
    ("work/existing", "prefer-existing", false),
    ("work/agreeing", "manual", true),
];

/// The address books [`History::sources`] has `b` join unread, and the
/// conflict policy of each.
const UNREAD: [(&str, &str); 2] = [
    ("work/unread", "manual"),
    ("work/unread-incoming", "prefer-incoming"),
];

impl History {
    /// One source and one mailbox (README.md, "Events and histories"): a
    /// first round in pages, an upgrade, remote changes, local changes
    /// drained and pushed, a flag changed on both sides, and a run with
    /// nothing left to do.
    pub fn mail(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        model.declare(Collection {
            id: String::from("work/INBOX"),
            account: Some(String::from("work")),
            kind: Some(Kind::Mail),
            name: String::from("INBOX"),
            role: Some(String::from("inbox")),
            sources: synced_by(&[&String::from("work-imap")]),
            conflict: String::from("manual"),
            generation: 1,
        });
        let mut remote = Remote::new("work-imap", "work/INBOX");
        for index in 0..7 {
            let flags = match index % 3 {
                0 => BTreeSet::new(),
                1 => set(&["\\Seen"]),
                _ => set(&["\\Seen", "$label1"]),
            };
            remote.deliver(draw.message(false).file(), flags);
        }

        let mut steps = vec![Step {
            label: String::from("a mailbox declared, never synced"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: &str, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label: String::from(label),
                run,
                model: model.clone(),
            });
        };

        let run = model.sync(&mut remote, PAGE);
        record("a first round in pages", Some(run), &model);

        let handles: Vec<String> = ["1", "2", "3"].map(String::from).to_vec();
        let run = model.upgrade(&remote, &handles);
        record("an upgrade fetching three bodies", Some(run), &model);

        let mut flagged = remote.members["1"].flags.clone();
        flagged.insert(String::from("\\Flagged"));
        remote.set_flags("1", flagged);
        remote.deliver(draw.message(false).file(), BTreeSet::new());
        remote.expunge("2");
        let mut unlabelled = remote.members["6"].flags.clone();
        unlabelled.remove("$label1");
        remote.set_flags("6", unlabelled);
        record("another client flags, delivers and expunges", None, &model);

        let (seq, flags) = model.bound_seq("work/INBOX", "3");
        let mut tagged = flags.clone();
        tagged.insert(String::from("$label2"));
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::SetFlags {
                seq,
                flags: tagged,
                base: Some(flags),
            },
        );
        model.drain(id);
        let (seq, _) = model.bound_seq("work/INBOX", "4");
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::Remove {
                seq,
                if_match: None,
            },
        );
        model.drain(id);
        let message = draw.message(false);
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::Add {
                link_id: message.message_id.clone().unwrap_or_default(),
                flags: set(&["\\Seen"]),
                filed: message.file(),
            },
        );
        model.drain(id);
        record(
            "a flag change, a delete and a message filed, drained",
            None,
            &model,
        );

        let run = model.sync(&mut remote, PAGE);
        record("a delta pulling and pushing", Some(run), &model);

        let mut labelled = remote.members["5"].flags.clone();
        labelled.insert(String::from("$Work"));
        remote.set_flags("5", labelled);
        let (seq, flags) = model.bound_seq("work/INBOX", "5");
        let mut answered = flags.clone();
        answered.insert(String::from("\\Answered"));
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::SetFlags {
                seq,
                flags: answered,
                base: Some(flags),
            },
        );
        model.drain(id);
        record("one member's flags changed on both sides", None, &model);

        let run = model.sync(&mut remote, PAGE);
        record("a delta merging both sides", Some(run), &model);

        let run = model.sync(&mut remote, PAGE);
        record("a delta with nothing left to do", Some(run), &model);

        Self { steps }
    }

    /// One source and one address book over DAV (README.md, "Events and
    /// histories"): a first round carrying bodies, a body edited on the
    /// server and pulled, one edited locally and pushed gated on its
    /// revision, one edited on both sides and recorded in conflict, a
    /// person's resolution pushed, a delete each way, and a run with
    /// nothing left to do.
    pub fn cards(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        model.declare(Collection {
            id: String::from("work/contacts"),
            account: Some(String::from("work")),
            kind: Some(Kind::Contact),
            name: String::from("Contacts"),
            role: Some(String::from("default")),
            sources: synced_by(&[&String::from("work-carddav")]),
            conflict: String::from("manual"),
            generation: 1,
        });
        let mut remote = Remote::dav("work-carddav", "work/contacts");
        let mut cards = Vec::new();
        for _ in 0..5 {
            let card = draw.card();
            remote.deliver(card.file(), BTreeSet::new());
            cards.push(card);
        }
        let renamed = |card: &Card, name: &str| Card {
            name: String::from(name),
            ..card.clone()
        };

        let mut steps = vec![Step {
            label: String::from("an address book declared, never synced"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: &str, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label: String::from(label),
                run,
                model: model.clone(),
            });
        };

        let run = model.sync(&mut remote, PAGE);
        record("a first round carrying every body", Some(run), &model);

        remote.edit("r1.vcf", renamed(&cards[0], "Edited On The Server").file());
        let (seq, object) = model.bound_card("work/contacts", "r2.vcf");
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: renamed(&cards[1], "Edited Here").file(),
                if_match: Some(object),
                resolves: None,
            },
        );
        model.drain(id);
        record(
            "a body edited on the server, another edited here",
            None,
            &model,
        );

        let run = model.sync(&mut remote, PAGE);
        record(
            "a delta pulling one body and pushing the other",
            Some(run),
            &model,
        );

        remote.edit("r3.vcf", renamed(&cards[2], "Their Version").file());
        let (seq, object) = model.bound_card("work/contacts", "r3.vcf");
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: renamed(&cards[2], "Our Version").file(),
                if_match: Some(object),
                resolves: None,
            },
        );
        model.drain(id);
        record("one body edited on both sides", None, &model);

        let run = model.sync(&mut remote, PAGE);
        record("a delta recording the conflict", Some(run), &model);

        let (seq, _) = model.bound_card("work/contacts", "r3.vcf");
        let diverging = model.items[model.bound_index("work/contacts", "r3.vcf")]
            .bindings
            .first()
            .and_then(|binding| binding.conflict_object.clone());
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: renamed(&cards[2], "Our Merged Version").file(),
                if_match: None,
                resolves: diverging.map(|name| vec![name]),
            },
        );
        model.drain(id);
        let (seq, object) = model.bound_card("work/contacts", "r4.vcf");
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Remove {
                seq,
                if_match: Some(object),
            },
        );
        model.drain(id);
        remote.expunge("r5.vcf");
        record(
            "a person's resolution, a delete here and one there",
            None,
            &model,
        );

        let run = model.sync(&mut remote, PAGE);
        record(
            "a delta pushing the resolution and the delete",
            Some(run),
            &model,
        );

        let run = model.sync(&mut remote, PAGE);
        record("a delta with nothing left to do", Some(run), &model);

        Self { steps }
    }

    /// One source over two mailboxes of one account (README.md, "Events
    /// and histories"): a move whose source syncs first, relocating into
    /// the target's create, which the target's listing lands; a copy
    /// pushed by a server-side copy from its origin; a move whose target
    /// syncs first, the source then deleting what moved; and runs with
    /// nothing left to do.
    pub fn moves(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        let mut remotes = BTreeMap::new();
        for (id, name, role) in [
            ("work/INBOX", "INBOX", "inbox"),
            ("work/Archive", "Archive", "archive"),
        ] {
            model.declare(Collection {
                id: String::from(id),
                account: Some(String::from("work")),
                kind: Some(Kind::Mail),
                name: String::from(name),
                role: Some(String::from(role)),
                sources: synced_by(&[&String::from("work-imap")]),
                conflict: String::from("manual"),
                generation: 1,
            });
            remotes.insert(String::from(id), Remote::new("work-imap", id));
        }
        for index in 0..5 {
            let flags = if index % 2 == 0 {
                set(&["\\Seen"])
            } else {
                BTreeSet::new()
            };
            let inbox = remotes.get_mut("work/INBOX").expect("an inbox");
            inbox.deliver(draw.message(false).file(), flags);
        }
        let archive = remotes.get_mut("work/Archive").expect("an archive");
        archive.deliver(draw.message(false).file(), set(&["\\Seen"]));

        let mut steps = vec![Step {
            label: String::from("two mailboxes declared, never synced"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: &str, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label: String::from(label),
                run,
                model: model.clone(),
            });
        };

        let run = model.sync_in(&mut remotes, "work/INBOX", PAGE, &Options::default());
        record("the inbox's first round", Some(run), &model);
        let run = model.sync_in(&mut remotes, "work/Archive", PAGE, &Options::default());
        record("the archive's first round", Some(run), &model);
        let handles: Vec<String> = ["1", "2", "3", "4", "5"].map(String::from).to_vec();
        let run = model.upgrade(&remotes["work/INBOX"], &handles);
        record("the inbox's bodies fetched", Some(run), &model);

        let (seq, _) = model.bound_seq("work/INBOX", "1");
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::Move {
                seq,
                to: String::from("work/Archive"),
            },
        );
        model.drain(id);
        let (seq, _) = model.bound_seq("work/INBOX", "2");
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::Copy {
                seq,
                to: String::from("work/Archive"),
            },
        );
        model.drain(id);
        record("a move and a copy into the archive, drained", None, &model);

        let run = model.sync_in(&mut remotes, "work/INBOX", PAGE, &Options::default());
        record("the source syncs first and relocates", Some(run), &model);
        let run = model.sync_in(&mut remotes, "work/Archive", PAGE, &Options::default());
        record(
            "the target lands the relocation and copies",
            Some(run),
            &model,
        );

        let (seq, _) = model.bound_seq("work/INBOX", "3");
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::Move {
                seq,
                to: String::from("work/Archive"),
            },
        );
        model.drain(id);
        record("another move, drained", None, &model);

        let run = model.sync_in(&mut remotes, "work/Archive", PAGE, &Options::default());
        record("the target syncs first and copies", Some(run), &model);
        let run = model.sync_in(&mut remotes, "work/INBOX", PAGE, &Options::default());
        record("the source deletes what moved", Some(run), &model);

        let run = model.sync_in(&mut remotes, "work/Archive", PAGE, &Options::default());
        record("the archive with nothing left to do", Some(run), &model);
        let run = model.sync_in(&mut remotes, "work/INBOX", PAGE, &Options::default());
        record("the inbox with nothing left to do", Some(run), &model);

        Self { steps }
    }

    /// One source and one address book whose remote refuses and rejects
    /// (README.md, "Events and histories"): a create refused for good and
    /// held while it stands, an edit rejected once and pushed again, the
    /// create edited and pushed under its new key, an add stating a
    /// `hash:` key its body does not give parked beside one stating its
    /// own, and a run with nothing left to do.
    pub fn refusals(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        model.declare(Collection {
            id: String::from("work/contacts"),
            account: Some(String::from("work")),
            kind: Some(Kind::Contact),
            name: String::from("Contacts"),
            role: Some(String::from("default")),
            sources: synced_by(&[&String::from("work-carddav")]),
            conflict: String::from("manual"),
            generation: 1,
        });
        let mut remote = Remote::dav("work-carddav", "work/contacts");
        let mut cards = Vec::new();
        for _ in 0..3 {
            let card = draw.card();
            remote.deliver(card.file(), BTreeSet::new());
            cards.push(card);
        }

        let mut steps = vec![Step {
            label: String::from("an address book declared, never synced"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: &str, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label: String::from(label),
                run,
                model: model.clone(),
            });
        };

        let run = model.sync(&mut remote, PAGE);
        record("a first round", Some(run), &model);

        let created = draw.card();
        let link_id = created.uid.clone().unwrap_or_default();
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Add {
                link_id: link_id.clone(),
                flags: BTreeSet::new(),
                filed: created.file(),
            },
        );
        model.drain(id);
        let refused = Push::Add {
            handle: format!("\u{1}{link_id}"),
            link_id: link_id.clone(),
            flags: BTreeSet::new(),
            origin: None,
            object: ObjectName::of(&created.file().bytes),
        };
        remote.refuse.insert(
            refused.key("work/contacts"),
            String::from("the address book takes no contact of this kind"),
        );
        let (seq, object) = model.bound_card("work/contacts", "r1.vcf");
        let edited = Card {
            name: String::from("Edited Here"),
            ..cards[0].clone()
        };
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: edited.file(),
                if_match: Some(object),
                resolves: None,
            },
        );
        model.drain(id);
        let base_revision = model.items[model.bound_index("work/contacts", "r1.vcf")]
            .bindings
            .first()
            .and_then(|binding| binding.base_revision.clone());
        let rejected = Push::Update {
            handle: String::from("r1.vcf"),
            object: ObjectName::of(&edited.file().bytes),
            if_match: base_revision,
        };
        remote.reject.insert(rejected.key("work/contacts"));
        record(
            "a create and an edit the remote will turn down",
            None,
            &model,
        );

        let run = model.sync(&mut remote, PAGE);
        record("the create refused, the edit rejected", Some(run), &model);
        let run = model.sync(&mut remote, PAGE);
        record("the create held, the edit pushed again", Some(run), &model);

        let seq = model.items[model.bound_index("work/contacts", &format!("\u{1}{link_id}"))].seq;
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: Card {
                    org: Some(String::from("A Kind It Takes")),
                    ..created.clone()
                }
                .file(),
                if_match: None,
                resolves: None,
            },
        );
        model.drain(id);
        record("the refused create edited", None, &model);
        let run = model.sync(&mut remote, PAGE);
        record(
            "the edited create pushed under its new key",
            Some(run),
            &model,
        );

        let mut anonymous = draw.card();
        anonymous.uid = None;
        let stranger = draw.card().file();
        let id = model.enqueue(
            "x-importer",
            "work/contacts",
            Action::Add {
                link_id: format!("hash:{}", fnv1a64(&stranger.bytes)),
                flags: BTreeSet::new(),
                filed: anonymous.file(),
            },
        );
        model.drain(id);
        let id = model.enqueue(
            "x-importer",
            "work/contacts",
            Action::Add {
                link_id: format!("hash:{}", fnv1a64(&anonymous.file().bytes)),
                flags: BTreeSet::new(),
                filed: anonymous.file(),
            },
        );
        model.drain(id);
        record(
            "an add stating another body's hash: key, one stating its own",
            None,
            &model,
        );
        let run = model.sync(&mut remote, PAGE);
        record("the card keyed by its hash pushed", Some(run), &model);
        let run = model.sync(&mut remote, PAGE);
        record("a delta with nothing left to do", Some(run), &model);

        Self { steps }
    }

    /// One mailbox on a server without UIDPLUS (README.md, "Events and
    /// histories"): an add accepted with no handle, recorded delivered and
    /// landed by the listing naming its member.
    pub fn appends(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        model.declare(Collection {
            id: String::from("work/Sent"),
            account: Some(String::from("work")),
            kind: Some(Kind::Mail),
            name: String::from("Sent"),
            role: Some(String::from("sent")),
            sources: synced_by(&[&String::from("work-imap")]),
            conflict: String::from("manual"),
            generation: 1,
        });
        let mut remote = Remote::new("work-imap", "work/Sent");
        remote.uidplus = false;
        for _ in 0..3 {
            remote.deliver(draw.message(false).file(), set(&["\\Seen"]));
        }

        let mut steps = vec![Step {
            label: String::from("a mailbox on a server without UIDPLUS"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: &str, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label: String::from(label),
                run,
                model: model.clone(),
            });
        };

        let run = model.sync(&mut remote, PAGE);
        record("a first round", Some(run), &model);
        let message = draw.message(false);
        let id = model.enqueue(
            "himalaya",
            "work/Sent",
            Action::Add {
                link_id: message.message_id.clone().unwrap_or_default(),
                flags: set(&["\\Seen"]),
                filed: message.file(),
            },
        );
        model.drain(id);
        record("a sent copy filed", None, &model);
        let run = model.sync(&mut remote, PAGE);
        record("the append accepted with no handle", Some(run), &model);
        let run = model.sync(&mut remote, PAGE);
        record("the listing lands it", Some(run), &model);
        let run = model.sync(&mut remote, PAGE);
        record("a delta with nothing left to do", Some(run), &model);

        Self { steps }
    }

    /// One address book per conflict policy (README.md, "Events and
    /// histories"): under `PreferRemote` an edit on both sides pulled and
    /// the local edit kept; under `PreferLocal` the server's body kept and
    /// the local one pushed over it, or recorded while unread; under
    /// `KeepLocal` a change the server alone made kept and pushed over, or
    /// recorded while unread; each followed by a run with nothing to do.
    pub fn policies(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        let mut steps = vec![Step {
            label: String::from("an empty store"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: String, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label,
                run,
                model: model.clone(),
            });
        };

        let books = [
            ("work/remote-wins", Policy::PreferRemote, false, true),
            ("work/local-wins", Policy::PreferLocal, true, true),
            ("work/local-unread", Policy::PreferLocal, false, true),
            ("work/keep-local", Policy::KeepLocal, true, false),
            ("work/keep-unread", Policy::KeepLocal, false, false),
        ];
        for (id, policy, carries, local_edit) in books {
            model.declare(Collection {
                id: String::from(id),
                account: Some(String::from("work")),
                kind: Some(Kind::Contact),
                name: String::from(id),
                role: None,
                sources: synced_by(&[&format!("dav-{id}")]),
                conflict: String::from("manual"),
                generation: 1,
            });
            let mut remote = Remote::dav(&format!("dav-{id}"), id);
            remote.policy = policy;
            let mut cards = Vec::new();
            for _ in 0..2 {
                let card = draw.card();
                remote.deliver(card.file(), BTreeSet::new());
                cards.push(card);
            }
            let run = model.sync(&mut remote, PAGE);
            record(format!("{id}: a first round"), Some(run), &model);

            remote.carries = carries;
            remote.edit(
                "r1.vcf",
                Card {
                    name: String::from("Their Version"),
                    ..cards[0].clone()
                }
                .file(),
            );
            if local_edit {
                let (seq, object) = model.bound_card(id, "r1.vcf");
                let id_row = model.enqueue(
                    "cardamum",
                    id,
                    Action::Update {
                        seq,
                        filed: Card {
                            name: String::from("Our Version"),
                            ..cards[0].clone()
                        }
                        .file(),
                        if_match: Some(object),
                        resolves: None,
                    },
                );
                model.drain(id_row);
            }
            record(format!("{id}: a body edited on the server"), None, &model);
            let run = model.sync(&mut remote, PAGE);
            record(format!("{id}: settled by its policy"), Some(run), &model);
            let run = model.sync(&mut remote, PAGE);
            record(format!("{id}: nothing left to do"), Some(run), &model);
        }

        Self { steps }
    }

    /// Two sources on one collection (SYNC §9). On each address book of
    /// `SHARED`: `a` names four cards, one keyed `hash:`; `b` joins one
    /// holding the same body, one holding another, and names one of its
    /// own, each lacking what the other holds offered it but the `hash:`
    /// one; `a` pulls an edit `b` then owes, `b`'s server edits the card too,
    /// its pull diverging from the item or agreeing with it, its next run
    /// pushing what the fold left it owing, then edits it again; `a`'s server deletes a card, which `b` then removes. On a
    /// mailbox: `b` joins a message `a` holds and mints another reusing its
    /// `Message-ID`, and a flag one server sets reaches the other. On the
    /// address books of `UNREAD`: `b` joins two cards without their bodies,
    /// recorded in conflict, and its upgrade reads one equal to the item's,
    /// clearing it, and one differing, settled by the policy.
    pub fn sources(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        let mut steps = vec![Step {
            label: String::from("an empty store"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: String, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label,
                run,
                model: model.clone(),
            });
        };

        for (id, conflict, agreeing) in SHARED {
            let (a, b) = (format!("{id}-a"), format!("{id}-b"));
            model.declare(Collection {
                id: String::from(id),
                account: Some(String::from("work")),
                kind: Some(Kind::Contact),
                name: String::from(id),
                role: None,
                sources: synced_by(&[&a, &b]),
                conflict: String::from(conflict),
                generation: 1,
            });
            let mut ra = Remote::dav(&a, id);
            let mut rb = Remote::dav(&b, id);
            rb.policy = Policy::PreferRemote;
            let cards: Vec<Card> = (0..5).map(|_| draw.card()).collect();
            let nameless = Card {
                uid: None,
                ..cards[4].clone()
            };
            for card in [&cards[0], &cards[1], &cards[2], &nameless] {
                ra.deliver(card.file(), BTreeSet::new());
            }
            let theirs = Card {
                name: String::from("Their Copy"),
                ..cards[1].clone()
            };
            for card in [&cards[0], &theirs, &cards[3]] {
                rb.deliver(card.file(), BTreeSet::new());
            }

            let run = model.sync(&mut ra, PAGE);
            record(format!("{id}: a's first round"), Some(run), &model);
            let run = model.sync(&mut rb, PAGE);
            record(format!("{id}: b joins a's cards"), Some(run), &model);
            let run = model.sync(&mut ra, PAGE);
            record(format!("{id}: a takes what b named"), Some(run), &model);

            let ours = Card {
                name: String::from("Edited At A"),
                ..cards[0].clone()
            };
            ra.edit("r1.vcf", ours.file());
            let run = model.sync(&mut ra, PAGE);
            record(format!("{id}: a pulls an edit b owes"), Some(run), &model);

            let other = match agreeing {
                true => ours,
                false => Card {
                    name: String::from("Edited At B"),
                    ..cards[0].clone()
                },
            };
            rb.edit("r1.vcf", other.file());
            let run = model.sync(&mut rb, PAGE);
            record(format!("{id}: b's edit meets the item"), Some(run), &model);
            let run = model.sync(&mut rb, PAGE);
            record(format!("{id}: b's next run"), Some(run), &model);
            let again = Card {
                name: String::from("Edited Again At B"),
                ..cards[0].clone()
            };
            rb.edit("r1.vcf", again.file());
            let run = model.sync(&mut rb, PAGE);
            record(
                format!("{id}: b's server edits it again"),
                Some(run),
                &model,
            );

            ra.expunge("r3.vcf");
            let run = model.sync(&mut ra, PAGE);
            record(
                format!("{id}: a's server deletes a card"),
                Some(run),
                &model,
            );
            let run = model.sync(&mut rb, PAGE);
            record(format!("{id}: b removes it"), Some(run), &model);
        }

        let id = "work/INBOX";
        model.declare(Collection {
            id: String::from(id),
            account: Some(String::from("work")),
            kind: Some(Kind::Mail),
            name: String::from("INBOX"),
            role: Some(String::from("inbox")),
            sources: synced_by(&["imap-a", "imap-b"]),
            conflict: String::from("manual"),
            generation: 1,
        });
        let mut ra = Remote::new("imap-a", id);
        ra.carries = true;
        let mut rb = Remote::new("imap-b", id);
        let messages: Vec<Mail> = (0..2).map(|_| draw.message(false)).collect();
        ra.deliver(messages[0].file(), set(&["\\Answered"]));
        ra.deliver(messages[1].file(), BTreeSet::new());
        let reused = Mail {
            subject: String::from("Another Message Entirely"),
            ..messages[0].clone()
        };
        rb.deliver(messages[0].file(), set(&["\\Seen"]));
        rb.deliver(reused.file(), BTreeSet::new());

        let run = model.sync(&mut ra, PAGE);
        record(format!("{id}: a's first round"), Some(run), &model);
        let run = model.sync(&mut rb, PAGE);
        record(format!("{id}: b joins and mints"), Some(run), &model);
        let run = model.sync(&mut ra, PAGE);
        record(format!("{id}: a takes b's flag"), Some(run), &model);
        rb.set_flags("1", set(&["\\Answered", "\\Flagged", "\\Seen"]));
        let run = model.sync(&mut rb, PAGE);
        record(format!("{id}: b pulls a flag"), Some(run), &model);
        let run = model.sync(&mut ra, PAGE);
        record(format!("{id}: a pushes it"), Some(run), &model);

        for (id, conflict) in UNREAD {
            let (a, b) = (format!("{id}-a"), format!("{id}-b"));
            model.declare(Collection {
                id: String::from(id),
                account: Some(String::from("work")),
                kind: Some(Kind::Contact),
                name: String::from(id),
                role: None,
                sources: synced_by(&[&a, &b]),
                conflict: String::from(conflict),
                generation: 1,
            });
            let mut ra = Remote::dav(&a, id);
            let mut rb = Remote::dav(&b, id);
            rb.carries = false;
            let cards: Vec<Card> = (0..2).map(|_| draw.card()).collect();
            for card in &cards {
                ra.deliver(card.file(), BTreeSet::new());
            }
            let theirs = Card {
                name: String::from("Their Copy"),
                ..cards[1].clone()
            };
            rb.deliver(cards[0].file(), BTreeSet::new());
            rb.deliver(theirs.file(), BTreeSet::new());

            let run = model.sync(&mut ra, PAGE);
            record(format!("{id}: a's first round"), Some(run), &model);
            let run = model.sync(&mut rb, PAGE);
            record(format!("{id}: b joins unread"), Some(run), &model);
            let handles = [String::from("r1.vcf"), String::from("r2.vcf")];
            let run = model.upgrade(&rb, &handles);
            record(format!("{id}: b's upgrade reads them"), Some(run), &model);
        }

        Self { steps }
    }

    /// One source's rounds under scopes (SYNC §5), a mailbox each: on
    /// work/INBOX a round over October, one widened to September, one over
    /// everything, a delta narrowing the coverage, then a round over
    /// September finding the absence in its scope alone while a create dated
    /// August waits, and one over everything pushing it; on work/Archive a
    /// connector narrowing by received date, its round proving no absence
    /// until it enumerates; on work/Sent Items a capped round proving none;
    /// on work/Junk a mass absence and on work/Drafts an empty listing
    /// parking their rounds until the run accepts the absences.
    pub fn scopes(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        let mut steps = vec![Step {
            label: String::from("an empty store"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: String, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label,
                run,
                model: model.clone(),
            });
        };
        let mut dated = |date: Option<Instant>| Mail {
            date,
            ..draw.message(false)
        };
        let day = |month: u32, day: u32| Some(Instant::at(2026, month, day, 9, 0, 0));
        let from = |month: u32| Options {
            scope: Scope {
                since: Some(Instant::at(2026, month, 1, 0, 0, 0)),
                until: None,
            },
            accept_absences: false,
        };
        let everything = Options::default();
        let mailbox = |model: &mut Model, id: &str, source: &str| {
            model.declare(Collection {
                id: String::from(id),
                account: Some(String::from("work")),
                kind: Some(Kind::Mail),
                name: String::from(id),
                role: None,
                sources: synced_by(&[source]),
                conflict: String::from("manual"),
                generation: 1,
            });
            Remote::new(source, id)
        };

        let id = "work/INBOX";
        let mut remote = mailbox(&mut model, id, "inbox-imap");
        for message in [
            dated(day(8, 10)),
            dated(day(9, 10)),
            dated(day(10, 10)),
            dated(None),
            dated(day(8, 20)),
            dated(day(9, 20)),
        ] {
            remote.deliver(message.file(), BTreeSet::new());
        }
        let run = model.sync_with(&mut remote, PAGE, &from(10));
        record(format!("{id}: a round over October on"), Some(run), &model);
        let run = model.sync_with(&mut remote, PAGE, &from(9));
        record(
            format!("{id}: a round widened to September"),
            Some(run),
            &model,
        );
        let run = model.sync_with(&mut remote, PAGE, &everything);
        record(format!("{id}: a round over everything"), Some(run), &model);
        remote.forget("1");
        remote.forget("2");
        let run = model.sync_with(&mut remote, PAGE, &from(10));
        record(
            format!("{id}: a delta narrowing the coverage"),
            Some(run),
            &model,
        );
        for message in [dated(day(8, 25)), dated(day(10, 25))] {
            let row = model.enqueue(
                "himalaya",
                id,
                Action::Add {
                    link_id: message.message_id.clone().unwrap_or_default(),
                    flags: BTreeSet::new(),
                    filed: message.file(),
                },
            );
            model.drain(row);
        }
        let run = model.sync_with(&mut remote, PAGE, &from(9));
        record(format!("{id}: a round over September"), Some(run), &model);
        let run = model.sync_with(&mut remote, PAGE, &everything);
        record(
            format!("{id}: a round over everything again"),
            Some(run),
            &model,
        );

        let id = "work/Archive";
        let mut remote = mailbox(&mut model, id, "archive-graph");
        remote.narrows = true;
        remote.deliver(dated(day(9, 10)).file(), BTreeSet::new());
        let early = dated(day(9, 5)).file();
        remote.deliver_at(early, BTreeSet::new(), Instant::at(2026, 5, 1, 9, 0, 0));
        remote.deliver(dated(day(10, 10)).file(), BTreeSet::new());
        let margin = dated(day(9, 12)).file();
        remote.deliver_at(margin, BTreeSet::new(), Instant::at(2026, 8, 31, 9, 0, 0));
        let run = model.sync_with(&mut remote, PAGE, &everything);
        record(format!("{id}: a first round"), Some(run), &model);
        remote.forget("1");
        let run = model.sync_with(&mut remote, PAGE, &from(10));
        record(
            format!("{id}: a delta narrowing the coverage"),
            Some(run),
            &model,
        );
        let run = model.sync_with(&mut remote, PAGE, &from(9));
        record(format!("{id}: a narrowed round"), Some(run), &model);
        let run = model.sync_with(&mut remote, PAGE, &from(10));
        record(
            format!("{id}: a delta narrowing it again"),
            Some(run),
            &model,
        );
        remote.enumerates = true;
        let run = model.sync_with(&mut remote, PAGE, &from(9));
        record(
            format!("{id}: a narrowed round enumerating"),
            Some(run),
            &model,
        );

        let id = "work/Sent Items";
        let mut remote = mailbox(&mut model, id, "sent-imap");
        for date in [day(9, 1), day(9, 15), day(10, 1), day(10, 15)] {
            remote.deliver(dated(date).file(), BTreeSet::new());
        }
        let run = model.sync_with(&mut remote, PAGE, &everything);
        record(format!("{id}: a first round"), Some(run), &model);
        remote.forget("1");
        let run = model.sync_with(&mut remote, PAGE, &from(10));
        record(
            format!("{id}: a delta narrowing the coverage"),
            Some(run),
            &model,
        );
        remote.cap = Some(2);
        let run = model.sync_with(&mut remote, PAGE, &everything);
        record(format!("{id}: a capped round"), Some(run), &model);

        for (id, count, kept) in [("work/Junk", 21, 1), ("work/Drafts", 2, 0)] {
            let source = format!("{}-imap", &id[5..].to_lowercase());
            let mut remote = mailbox(&mut model, id, &source);
            for _ in 0..count {
                remote.deliver(dated(day(10, 1)).file(), BTreeSet::new());
            }
            let run = model.sync_with(&mut remote, PAGE, &everything);
            record(format!("{id}: a first round"), Some(run), &model);
            for number in 1 + kept..=count {
                remote.forget(&number.to_string());
            }
            let run = model.sync_with(&mut remote, PAGE, &from(10));
            record(
                format!("{id}: a delta narrowing the coverage"),
                Some(run),
                &model,
            );
            let staged = dated(day(10, 2));
            let row = model.enqueue(
                "himalaya",
                id,
                Action::Add {
                    link_id: staged.message_id.clone().unwrap_or_default(),
                    flags: BTreeSet::new(),
                    filed: staged.file(),
                },
            );
            model.drain(row);
            let run = model.sync_with(&mut remote, PAGE, &everything);
            record(format!("{id}: a round parks"), Some(run), &model);
            let run = model.sync_with(&mut remote, PAGE, &everything);
            record(
                format!("{id}: the round resumed parks again"),
                Some(run),
                &model,
            );
            let accepting = Options {
                accept_absences: true,
                ..Options::default()
            };
            let run = model.sync_with(&mut remote, PAGE, &accepting);
            record(format!("{id}: the absences accepted"), Some(run), &model);
        }

        Self { steps }
    }

    /// One source renumbering its members (SYNC §8). On work/INBOX, 25
    /// messages, one filed twice under one `Message-ID`: a renumbering from
    /// one with the first message gone, its handle handed to another; one
    /// carrying every message and the minted copy; a delta after it; one
    /// missing most messages, parked, then accepted; and a capped one
    /// missing some, parked. On work/contacts: a renumbering over a card the
    /// server edited and one edited on both sides, then an edit over the
    /// card pulled unread, its upgrade reading the base, its push.
    pub fn rekeys(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        let mut steps = vec![Step {
            label: String::from("an empty store"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: String, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label,
                run,
                model: model.clone(),
            });
        };
        let accepting = Options {
            accept_absences: true,
            ..Options::default()
        };

        let id = "work/INBOX";
        model.declare(Collection {
            id: String::from(id),
            account: Some(String::from("work")),
            kind: Some(Kind::Mail),
            name: String::from("INBOX"),
            role: Some(String::from("inbox")),
            sources: synced_by(&["work-imap"]),
            conflict: String::from("manual"),
            generation: 1,
        });
        let mut remote = Remote::new("work-imap", id);
        let messages: Vec<Mail> = (0..24).map(|_| draw.message(false)).collect();
        for message in &messages {
            remote.deliver(message.file(), set(&["\\Seen"]));
        }
        remote.deliver(messages[5].file(), BTreeSet::new());
        let run = model.sync(&mut remote, PAGE);
        record(format!("{id}: a first round"), Some(run), &model);

        remote.forget("1");
        remote.renumber(1);
        let run = model.rekey(&remote, &Options::default());
        record(
            format!("{id}: renumbered from one, a message gone"),
            Some(run),
            &model,
        );
        remote.renumber(200);
        let run = model.rekey(&remote, &Options::default());
        record(
            format!("{id}: renumbered, every message carried"),
            Some(run),
            &model,
        );
        let run = model.sync(&mut remote, PAGE);
        record(format!("{id}: a delta after it"), Some(run), &model);

        for number in 200..215 {
            remote.forget(&number.to_string());
        }
        remote.renumber(300);
        let run = model.rekey(&remote, &Options::default());
        record(
            format!("{id}: renumbered, most messages missing"),
            Some(run),
            &model,
        );
        let run = model.rekey(&remote, &accepting);
        record(format!("{id}: the absences accepted"), Some(run), &model);
        remote.cap = Some(5);
        remote.renumber(400);
        let run = model.rekey(&remote, &Options::default());
        record(format!("{id}: renumbered, capped"), Some(run), &model);

        let id = "work/contacts";
        model.declare(Collection {
            id: String::from(id),
            account: Some(String::from("work")),
            kind: Some(Kind::Contact),
            name: String::from("contacts"),
            role: None,
            sources: synced_by(&["work-carddav"]),
            conflict: String::from("manual"),
            generation: 1,
        });
        let mut remote = Remote::dav("work-carddav", id);
        let cards: Vec<Card> = (0..3).map(|_| draw.card()).collect();
        for card in &cards {
            remote.deliver(card.file(), BTreeSet::new());
        }
        let run = model.sync(&mut remote, PAGE);
        record(format!("{id}: a first round"), Some(run), &model);

        let (seq, object) = model.bound_card(id, "r1.vcf");
        let ours = Card {
            name: String::from("Our Version"),
            ..cards[0].clone()
        };
        let row = model.enqueue(
            "cardamum",
            id,
            Action::Update {
                seq,
                filed: ours.file(),
                if_match: Some(object),
                resolves: None,
            },
        );
        model.drain(row);
        for (handle, card) in [("r1.vcf", &cards[0]), ("r2.vcf", &cards[1])] {
            let theirs = Card {
                name: String::from("Their Version"),
                ..card.clone()
            };
            remote.edit(handle, theirs.file());
        }
        remote.renumber(10);
        let run = model.rekey(&remote, &Options::default());
        record(format!("{id}: renumbered over edits"), Some(run), &model);

        let (seq, _) = model.bound_seq(id, "r11.vcf");
        let edited = Card {
            name: String::from("Edited Unread"),
            ..cards[1].clone()
        };
        let row = model.enqueue(
            "cardamum",
            id,
            Action::Update {
                seq,
                filed: edited.file(),
                if_match: None,
                resolves: None,
            },
        );
        model.drain(row);
        record(format!("{id}: an edit over a body unread"), None, &model);
        let run = model.upgrade(&remote, &[String::from("r11.vcf")]);
        record(
            format!("{id}: the upgrade reads the base"),
            Some(run),
            &model,
        );
        let run = model.sync(&mut remote, PAGE);
        record(format!("{id}: the edit pushed"), Some(run), &model);

        Self { steps }
    }

    /// Runs cut by a crash (SYNC §5). On work/INBOX, eight messages: a first
    /// round interrupted after its first page, resumed from its cursor;
    /// then a staged add and two flag changes whose run is cut after the
    /// add was taken and before its outcome was written, the next run
    /// landing the add on its arrival and pushing the flags. On two address
    /// books, one listing bodies and one not: a staged edit whose run is cut
    /// after the server took it, the next run meeting the pushed body.
    pub fn crashes(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        let mut steps = vec![Step {
            label: String::from("an empty store"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: String, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label,
                run,
                model: model.clone(),
            });
        };

        let id = "work/INBOX";
        model.declare(Collection {
            id: String::from(id),
            account: Some(String::from("work")),
            kind: Some(Kind::Mail),
            name: String::from("INBOX"),
            role: Some(String::from("inbox")),
            sources: synced_by(&["work-imap"]),
            conflict: String::from("manual"),
            generation: 1,
        });
        let mut remote = Remote::new("work-imap", id);
        for _ in 0..8 {
            remote.deliver(draw.message(false).file(), BTreeSet::new());
        }
        remote.interrupt = Some(1);
        let run = model.sync(&mut remote, PAGE);
        record(
            format!("{id}: a round cut after its first page"),
            Some(run),
            &model,
        );
        let run = model.sync(&mut remote, PAGE);
        record(format!("{id}: the round resumed"), Some(run), &model);

        let message = draw.message(false);
        let row = model.enqueue(
            "himalaya",
            id,
            Action::Add {
                link_id: message.message_id.clone().unwrap_or_default(),
                flags: set(&["\\Seen"]),
                filed: message.file(),
            },
        );
        model.drain(row);
        for handle in ["1", "2"] {
            let (seq, _) = model.bound_seq(id, handle);
            let row = model.enqueue(
                "himalaya",
                id,
                Action::SetFlags {
                    seq,
                    flags: set(&["\\Flagged"]),
                    base: None,
                },
            );
            model.drain(row);
        }
        remote.crash = Some(1);
        let run = model.sync(&mut remote, PAGE);
        record(
            format!("{id}: a run cut after its add was taken"),
            Some(run),
            &model,
        );
        let run = model.sync(&mut remote, PAGE);
        record(format!("{id}: the next run"), Some(run), &model);

        for (id, carries) in [("work/contacts", true), ("work/directory", false)] {
            let source = format!("{}-carddav", &id[5..]);
            model.declare(Collection {
                id: String::from(id),
                account: Some(String::from("work")),
                kind: Some(Kind::Contact),
                name: String::from(&id[5..]),
                role: None,
                sources: synced_by(&[&source]),
                conflict: String::from("manual"),
                generation: 1,
            });
            let mut remote = Remote::dav(&source, id);
            let card = draw.card();
            remote.deliver(card.file(), BTreeSet::new());
            let run = model.sync(&mut remote, PAGE);
            record(format!("{id}: a first round"), Some(run), &model);
            remote.carries = carries;

            let (seq, object) = model.bound_card(id, "r1.vcf");
            let ours = Card {
                name: String::from("Our Version"),
                ..card
            };
            let row = model.enqueue(
                "cardamum",
                id,
                Action::Update {
                    seq,
                    filed: ours.file(),
                    if_match: Some(object),
                    resolves: None,
                },
            );
            model.drain(row);
            remote.crash = Some(1);
            let run = model.sync(&mut remote, PAGE);
            record(
                format!("{id}: a run cut after its edit was taken"),
                Some(run),
                &model,
            );
            let run = model.sync(&mut remote, PAGE);
            record(format!("{id}: the next run"), Some(run), &model);
            let run = model.upgrade(&remote, &[String::from("r1.vcf")]);
            record(format!("{id}: an upgrade"), Some(run), &model);
        }

        Self { steps }
    }
}

impl Model {
    /// The `seq` and known flags of the item a handle binds in `collection`.
    fn bound_seq(&self, collection: &str, handle: &str) -> (i64, BTreeSet<String>) {
        let item = self
            .items
            .iter()
            .find(|item| {
                item.collection == collection
                    && item
                        .bindings
                        .first()
                        .is_some_and(|binding| binding.handle == handle)
            })
            .expect("a bound handle");
        (item.seq, item.flags.clone().unwrap_or_default())
    }

    fn bound_index(&self, collection: &str, handle: &str) -> usize {
        self.items
            .iter()
            .position(|item| {
                item.collection == collection
                    && item
                        .bindings
                        .first()
                        .is_some_and(|binding| binding.handle == handle)
            })
            .expect("a bound handle")
    }

    /// The `seq` and body of the card a handle binds in `collection`.
    fn bound_card(&self, collection: &str, handle: &str) -> (i64, ObjectName) {
        let item = &self.items[self.bound_index(collection, handle)];
        (item.seq, item.object.clone().expect("a held body"))
    }
}

fn set(flags: &[&str]) -> BTreeSet<String> {
    flags.iter().map(|flag| String::from(*flag)).collect()
}

/// Whether every row of a model's queue was applied or parked.
pub fn drained(model: &Model) -> bool {
    model.queue.iter().all(|row| row.state != RowState::Pending)
}

#[cfg(test)]
mod tests {
    use std::{
        collections::{BTreeMap, BTreeSet},
        env, fs, process,
    };

    use rusqlite::types::Value;

    use crate::{
        body::Card,
        engine::{Answer, Event, Push, Run},
        history::{History, PAGE, SHARED, UNREAD, drained, set},
        model::{Item, Model, Scope, State},
        name::ObjectName,
        oracle,
        profile::Draw,
        queue::{Action, Outcome, RowState},
        remote::Remote,
        spec::Spec,
        store::Store,
        time::Instant,
        writer,
    };

    fn history() -> History {
        History::mail(11)
    }

    #[test]
    fn every_step_leaves_a_store_the_statements_write_and_read_back() {
        let spec = Spec::load_default().unwrap();
        let histories = [
            history(),
            History::cards(13),
            History::moves(17),
            History::refusals(19),
            History::appends(23),
            History::policies(29),
            History::sources(31),
            History::scopes(37),
            History::rekeys(41),
            History::crashes(43),
        ];
        for (index, step) in histories
            .iter()
            .flat_map(|history| history.steps.iter())
            .enumerate()
        {
            let dir = env::temp_dir().join(format!(
                "pimdir-generator-history-{}-{index}",
                process::id()
            ));
            let _ = fs::remove_dir_all(&dir);
            let store = Store::create(&spec, &dir).unwrap();
            writer::materialise(&step.model, &store).unwrap();
            let expectations = oracle::expectations(&step.model, &spec).unwrap();
            let disagreements = oracle::check(&store, &expectations).unwrap();
            assert!(
                disagreements.is_empty(),
                "{}: {disagreements:#?}",
                step.label
            );
            let faults = oracle::feed::order(&store).unwrap();
            assert!(faults.is_empty(), "{}: {faults:#?}", step.label);
            drop(store);
            fs::remove_dir_all(&dir).unwrap();
        }
    }

    #[test]
    fn a_first_round_names_every_member_at_meta_page_by_page() {
        let history = history();
        let step = &history.steps[1];
        let run = step.run.as_ref().unwrap();

        assert_eq!(run.pages.len(), 7usize.div_ceil(PAGE));
        assert!(run.pages.iter().all(|page| page.complete));
        assert!(run.pages[0].checkpoint.is_some());
        assert!(run.pages[1..].iter().all(|page| page.checkpoint.is_none()));
        assert_eq!(run.pages.last().unwrap().cursor, None);
        assert_eq!(
            run.events
                .iter()
                .filter(|event| matches!(event, Event::Added(_)))
                .count(),
            7
        );
        assert!(run.pushes.is_empty());

        let sync = &step.model.collections["work/INBOX"].sources["work-imap"];
        assert_eq!(sync.rounds, 1);
        assert_eq!(
            sync.checkpoint.as_deref(),
            run.pages[0].checkpoint.as_deref().map(str::as_bytes)
        );
        for item in &step.model.items {
            assert_eq!((item.level, item.object.is_none()), (1, true));
            assert_eq!(item.bindings.first().unwrap().round, Some(1));
        }
    }

    #[test]
    fn an_upgrade_fetches_a_body_into_the_item_and_its_base() {
        let history = history();
        let run = history.steps[2].run.as_ref().unwrap();
        assert_eq!(run.fetch.len(), 3);
        for item in history.steps[2]
            .model
            .items
            .iter()
            .filter(|item| item.object.is_some())
        {
            let binding = item.bindings.first().unwrap();
            assert_eq!(item.level, 2);
            assert_eq!(binding.base_object, item.object);
        }
    }

    #[test]
    fn a_delta_pulls_what_another_client_did_and_pushes_what_was_drained() {
        let history = history();
        assert!(drained(&history.steps[4].model));
        let step = &history.steps[5];
        let run = step.run.as_ref().unwrap();

        let kinds: Vec<&str> = run.pushes.iter().map(|(push, _)| push.name()).collect();
        assert_eq!(kinds, ["add", "set-flags", "remove"]);
        let Push::SetFlags { add, remove, .. } = &run.pushes[1].0 else {
            panic!("a flag push");
        };
        assert_eq!(add.iter().collect::<Vec<_>>(), ["$label2"]);
        assert!(remove.is_empty());

        assert!(run.events.contains(&Event::FlagsChanged(String::from("1"))));
        assert!(run.events.contains(&Event::FlagsChanged(String::from("6"))));
        let six = step
            .model
            .items
            .iter()
            .find(|item| {
                item.bindings
                    .first()
                    .is_some_and(|binding| binding.handle == "6")
            })
            .unwrap();
        assert!(
            !six.flags.as_ref().unwrap().contains("$label1"),
            "a flag the remote removed goes"
        );
        assert!(run.events.contains(&Event::Vanished(String::from("2"))));
        assert!(run.events.contains(&Event::Added(String::from("8"))));
        assert!(
            run.events
                .iter()
                .any(|event| matches!(event, Event::Created(_)))
        );

        for handle in ["2", "4"] {
            let gone = step.model.items.iter().find(|item| {
                history.steps[4].model.items.iter().any(|before| {
                    before.seq == item.seq
                        && before
                            .bindings
                            .first()
                            .is_some_and(|binding| binding.handle == handle)
                })
            });
            let gone = gone.unwrap();
            assert_eq!(
                gone.state,
                State::Retained {
                    by: Some(String::from("work-imap"))
                },
                "{handle}"
            );
        }
    }

    #[test]
    fn both_sides_merge_and_push_only_what_the_remote_lacks() {
        let history = history();
        let run = history.steps[7].run.as_ref().unwrap();
        assert_eq!(run.pushes.len(), 1);
        let Push::SetFlags {
            handle,
            add,
            remove,
        } = &run.pushes[0].0
        else {
            panic!("a flag push");
        };
        assert_eq!(handle, "5");
        assert_eq!(add.iter().collect::<Vec<_>>(), ["\\Answered"]);
        assert!(remove.is_empty());
        assert!(run.events.contains(&Event::FlagsChanged(String::from("5"))));

        let item = history.steps[7]
            .model
            .items
            .iter()
            .find(|item| {
                item.bindings
                    .first()
                    .is_some_and(|binding| binding.handle == "5")
            })
            .unwrap();
        let flags = item.flags.as_ref().unwrap();
        assert!(flags.contains("$Work") && flags.contains("\\Answered"));
    }

    #[test]
    fn a_run_after_convergence_changes_nothing() {
        let history = history();
        let last = &history.steps[8];
        let run = last.run.as_ref().unwrap();
        assert!(run.pushes.is_empty(), "{:?}", run.pushes);
        assert!(run.events.is_empty(), "{:?}", run.events);
    }

    fn card(model: &Model, handle: &str) -> Item {
        model
            .items
            .iter()
            .find(|item| {
                item.bindings
                    .first()
                    .is_some_and(|binding| binding.handle == handle)
            })
            .cloned()
            .unwrap()
    }

    #[test]
    fn a_dav_round_names_every_member_with_the_body_it_carries() {
        let history = History::cards(13);
        let step = &history.steps[1];
        let run = step.run.as_ref().unwrap();
        assert!(
            run.pages
                .iter()
                .flat_map(|page| &page.items)
                .all(|member| member.carries)
        );
        assert_eq!(run.events.len(), 5);
        for item in &step.model.items {
            let binding = item.bindings.first().unwrap();
            assert_eq!(item.level, 2);
            assert_eq!(binding.base_object, item.object);
            assert!(binding.base_revision.is_some());
        }
    }

    #[test]
    fn a_server_edit_is_pulled_and_a_local_one_pushed_on_its_revision() {
        let history = History::cards(13);
        let before = &history.steps[2].model;
        let step = &history.steps[3];
        let run = step.run.as_ref().unwrap();

        assert!(
            run.events
                .contains(&Event::ContentChanged(String::from("r1.vcf")))
        );
        let pulled = card(&step.model, "r1.vcf");
        assert_eq!(
            pulled.summary.get("fn"),
            Value::Text(String::from("Edited On The Server"))
        );
        assert_eq!(pulled.bindings.first().unwrap().base_object, pulled.object);
        assert_eq!(
            pulled.sort_key, "edited on the server",
            "a pull restates the sort key"
        );

        assert_eq!(run.pushes.len(), 1);
        let Push::Update {
            handle,
            if_match,
            object,
        } = &run.pushes[0].0
        else {
            panic!("an update");
        };
        assert_eq!(handle, "r2.vcf");
        assert_eq!(
            if_match,
            &card(before, "r2.vcf").bindings[0].clone().base_revision
        );
        let pushed = card(&step.model, "r2.vcf");
        let binding = pushed.bindings.first().unwrap();
        assert_eq!(binding.base_object.as_ref(), Some(object));
        assert_eq!(binding.base_revision, run.outcomes[0].revision);
        assert!(run.outcomes[0].revision.is_some());
    }

    #[test]
    fn an_edit_on_both_sides_is_recorded_in_conflict_and_pushes_nothing() {
        let history = History::cards(13);
        let step = &history.steps[5];
        let run = step.run.as_ref().unwrap();
        assert_eq!(run.events, [Event::Conflicted(String::from("r3.vcf"))]);
        assert!(run.pushes.is_empty());

        let item = card(&step.model, "r3.vcf");
        let binding = item.bindings.first().unwrap();
        assert!(binding.conflicted);
        assert!(binding.conflict_object.is_some() && binding.conflict_revision.is_some());
        assert_eq!(
            item.summary.get("fn"),
            Value::Text(String::from("Our Version"))
        );
        assert_ne!(binding.base_object, item.object);
    }

    #[test]
    fn a_resolution_pushes_on_the_revision_it_resolved_and_deletes_travel_both_ways() {
        let history = History::cards(13);
        let resolved = &history.steps[6].model;
        assert!(drained(resolved));
        assert!(
            resolved
                .queue
                .iter()
                .all(|row| matches!(row.state, RowState::Applied(_)))
        );
        let conflicted = card(&history.steps[5].model, "r3.vcf").bindings[0].clone();
        let settled = card(resolved, "r3.vcf").bindings[0].clone();
        assert!(!settled.conflicted);
        assert_eq!(settled.base_revision, conflicted.conflict_revision);
        assert_eq!(settled.base_object, conflicted.conflict_object);

        let step = &history.steps[7];
        let run = step.run.as_ref().unwrap();
        let names: Vec<&str> = run.pushes.iter().map(|(push, _)| push.name()).collect();
        assert_eq!(names, ["update", "remove"]);
        let Push::Update { if_match, .. } = &run.pushes[0].0 else {
            panic!("an update");
        };
        assert_eq!(if_match, &conflicted.conflict_revision);
        let Push::Remove { if_match, .. } = &run.pushes[1].0 else {
            panic!("a remove");
        };
        assert!(if_match.is_some());
        assert!(
            run.events
                .contains(&Event::Vanished(String::from("r5.vcf")))
        );

        let retained = step
            .model
            .items
            .iter()
            .filter(|item| matches!(item.state, State::Retained { .. }))
            .count();
        assert_eq!(retained, 2);
        assert!(history.steps[8].run.as_ref().unwrap().pushes.is_empty());
        assert!(history.steps[8].run.as_ref().unwrap().events.is_empty());
    }

    fn placed<'a>(model: &'a Model, collection: &str, link_id: &str) -> Option<&'a Item> {
        model
            .items
            .iter()
            .find(|item| item.collection == collection && item.link_id == link_id)
    }

    #[test]
    fn a_move_staged_tombstones_its_source_and_creates_in_its_target() {
        let history = History::moves(17);
        let model = &history.steps[4].model;
        let moved = card(model, "1");
        assert_eq!(moved.state, State::Tombstone);
        let create = placed(model, "work/Archive", &moved.link_id).unwrap();
        let binding = create.bindings.first().unwrap();
        assert_eq!(binding.handle, format!("\u{1}{}", moved.link_id));
        assert!(!binding.base_present);
        assert_eq!(
            create.seq, moved.seq,
            "a message filed twice shares its seq"
        );
    }

    #[test]
    fn a_source_syncing_first_relocates_into_the_target_create() {
        let history = History::moves(17);
        let moved = card(&history.steps[4].model, "1");
        let step = &history.steps[5];
        let run = step.run.as_ref().unwrap();
        assert_eq!(run.pushes.len(), 1);
        let Push::Remove {
            handle,
            to,
            link_id,
            ..
        } = &run.pushes[0].0
        else {
            panic!("a remove");
        };
        assert_eq!(
            (handle.as_str(), to.as_deref()),
            ("1", Some("work/Archive"))
        );
        assert_eq!(link_id, &moved.link_id);
        assert_eq!(run.outcomes[0].relocated, Some(true));

        assert!(
            placed(&step.model, "work/INBOX", &moved.link_id).is_none(),
            "the source row is purged"
        );
        assert_eq!(step.model.purges, 1);
        let delivered = placed(&step.model, "work/Archive", &moved.link_id).unwrap();
        let binding = delivered.bindings.first().unwrap();
        assert!(
            binding.base_present && binding.base_flags.is_none() && binding.base_object.is_none()
        );
        assert!(binding.handle.starts_with('\u{1}'));
    }

    #[test]
    fn the_target_lands_the_relocation_and_copies_from_its_origin() {
        let history = History::moves(17);
        let before = &history.steps[4].model;
        let moved = card(before, "1");
        let copied = card(before, "2");
        let step = &history.steps[6];
        let run = step.run.as_ref().unwrap();

        let landed = placed(&step.model, "work/Archive", &moved.link_id).unwrap();
        let binding = landed.bindings.first().unwrap();
        assert!(!binding.handle.starts_with('\u{1}'));
        assert_eq!(binding.base_object, landed.object);
        assert!(run.events.contains(&Event::Created(binding.handle.clone())));
        assert!(!run.events.contains(&Event::Added(binding.handle.clone())));

        assert_eq!(run.pushes.len(), 1);
        let Push::Add { origin, .. } = &run.pushes[0].0 else {
            panic!("an add");
        };
        assert_eq!(
            origin,
            &Some((String::from("work/INBOX"), String::from("2")))
        );
        assert!(run.outcomes[0].assigned.is_some());
        assert_eq!(
            placed(&step.model, "work/INBOX", &copied.link_id)
                .unwrap()
                .state,
            State::Live
        );
    }

    #[test]
    fn a_target_syncing_first_copies_and_the_source_then_deletes() {
        let history = History::moves(17);
        let moved = card(&history.steps[7].model, "3");
        let run = history.steps[8].run.as_ref().unwrap();
        let Push::Add { origin, .. } = &run.pushes[0].0 else {
            panic!("an add");
        };
        assert_eq!(
            origin,
            &Some((String::from("work/INBOX"), String::from("3")))
        );

        let step = &history.steps[9];
        let run = step.run.as_ref().unwrap();
        let Push::Remove { to, .. } = &run.pushes[0].0 else {
            panic!("a remove");
        };
        assert_eq!(to, &None, "a create landed leaves no destination");
        assert!(placed(&step.model, "work/INBOX", &moved.link_id).is_none());
        assert_eq!(step.model.purges, 2);

        for quiet in &history.steps[10..] {
            let run = quiet.run.as_ref().unwrap();
            assert!(
                run.pushes.is_empty() && run.events.is_empty(),
                "{}",
                quiet.label
            );
        }
    }

    #[test]
    fn a_refused_create_is_recorded_held_and_released_by_an_edit() {
        let history = History::refusals(19);
        let reason = "the address book takes no contact of this kind";

        let run = history.steps[3].run.as_ref().unwrap();
        let names: Vec<&str> = run.pushes.iter().map(|(push, _)| push.name()).collect();
        assert_eq!(names, ["add", "update"]);
        assert_eq!(
            run.outcomes[0].answer,
            Answer::Refused(String::from(reason))
        );
        assert_eq!(run.outcomes[1].answer, Answer::Rejected);
        let (create, key) = (&run.pushes[0].0, &run.pushes[0].1);
        assert!(run.events.contains(&Event::Refused {
            handle: String::from(create.handle()),
            reason: String::from(reason),
        }));
        let held = card(&history.steps[3].model, create.handle());
        let refusal = held.bindings.first().unwrap().refusal.clone().unwrap();
        assert_eq!((refusal.reason.as_str(), &refusal.key), (reason, key));
        let rejected = card(&history.steps[3].model, "r1.vcf");
        assert_ne!(
            rejected.bindings.first().unwrap().base_object,
            rejected.object
        );

        let run = history.steps[4].run.as_ref().unwrap();
        let names: Vec<&str> = run.pushes.iter().map(|(push, _)| push.name()).collect();
        assert_eq!(names, ["update"], "the refused create is held");
        assert!(run.events.contains(&Event::Refused {
            handle: String::from(create.handle()),
            reason: String::from(reason),
        }));
        assert_eq!(run.outcomes[0].answer, Answer::Accepted);

        let run = history.steps[6].run.as_ref().unwrap();
        assert_eq!(run.pushes.len(), 1);
        assert_ne!(&run.pushes[0].1, key, "an edited create is another change");
        assert_eq!(run.outcomes[0].answer, Answer::Accepted);
        let landed = card(
            &history.steps[6].model,
            run.outcomes[0].assigned.as_ref().unwrap(),
        );
        assert!(landed.bindings.first().unwrap().refusal.is_none());
    }

    #[test]
    fn an_add_stating_a_hash_key_its_body_does_not_give_parks() {
        let history = History::refusals(19);
        let rows: Vec<&RowState> = history.steps[7]
            .model
            .queue
            .iter()
            .filter(|row| row.producer == "x-importer")
            .map(|row| &row.state)
            .collect();
        assert!(matches!(rows[0], RowState::Parked(reason) if reason.contains("hash:")));
        assert!(matches!(rows[1], RowState::Applied(Some(_))));

        let run = history.steps[8].run.as_ref().unwrap();
        let Push::Add { link_id, .. } = &run.pushes[0].0 else {
            panic!("an add");
        };
        assert!(link_id.starts_with("hash:"));
        assert!(history.steps[9].run.as_ref().unwrap().pushes.is_empty());
        assert!(history.steps[9].run.as_ref().unwrap().events.is_empty());
    }

    #[test]
    fn an_add_accepted_with_no_handle_is_delivered_then_landed() {
        let history = History::appends(23);
        let run = history.steps[3].run.as_ref().unwrap();
        assert_eq!(run.outcomes[0].answer, Answer::Accepted);
        assert_eq!(run.outcomes[0].assigned, None);
        assert!(
            run.events.is_empty(),
            "a delivered create reports no Created"
        );
        let (
            Push::Add {
                handle, link_id, ..
            },
            _,
        ) = &run.pushes[0]
        else {
            panic!("an add");
        };
        let delivered = card(&history.steps[3].model, handle);
        let binding = delivered.bindings.first().unwrap();
        assert!(binding.base_present && binding.base_flags.is_none());

        let run = history.steps[4].run.as_ref().unwrap();
        assert!(
            run.pushes.is_empty(),
            "a delivered create is pushed no second time"
        );
        let landed = placed(&history.steps[4].model, "work/Sent", link_id).unwrap();
        let binding = landed.bindings.first().unwrap();
        assert!(!binding.handle.starts_with('\u{1}'));
        assert_eq!(run.events, [Event::Created(binding.handle.clone())]);
        let quiet = history.steps[5].run.as_ref().unwrap();
        assert!(quiet.pushes.is_empty() && quiet.events.is_empty());
    }

    fn card_in(model: &Model, collection: &str, handle: &str) -> Item {
        model
            .items
            .iter()
            .find(|item| {
                item.collection == collection
                    && item
                        .bindings
                        .first()
                        .is_some_and(|binding| binding.handle == handle)
            })
            .cloned()
            .unwrap()
    }

    fn settled(history: &History, book: usize) -> (&Model, &Model, &Run) {
        let step = 1 + 4 * book + 2;
        let run = history.steps[step].run.as_ref().unwrap();
        (
            &history.steps[step - 1].model,
            &history.steps[step].model,
            run,
        )
    }

    fn retained_kept(model: &Model, collection: &str) -> Item {
        model
            .items
            .iter()
            .find(|item| item.collection == collection && item.link_id.starts_with("dup:"))
            .cloned()
            .unwrap()
    }

    #[test]
    fn prefer_remote_pulls_and_keeps_the_local_edit() {
        let history = History::policies(29);
        let (before, after, run) = settled(&history, 0);
        let local = card_in(before, "work/remote-wins", "r1.vcf");
        assert!(run.pushes.is_empty());
        assert_eq!(run.events[0], Event::ContentChanged(String::from("r1.vcf")));
        let Event::Overruled { link_id, .. } = &run.events[1] else {
            panic!("an overruled body");
        };
        assert_eq!(*link_id, format!("dup:{}#r1.vcf", local.link_id));

        let pulled = card_in(after, "work/remote-wins", "r1.vcf");
        assert_eq!(
            (pulled.object.is_none(), pulled.level),
            (true, 1),
            "a member carrying no body empties the item"
        );
        let kept = retained_kept(after, "work/remote-wins");
        assert_eq!(kept.object, local.object);
        assert!(matches!(kept.state, State::Retained { by: Some(_) }));
        assert_ne!(kept.seq, local.seq);
    }

    #[test]
    fn prefer_local_keeps_the_server_body_and_pushes_its_own_on_the_observed_revision() {
        let history = History::policies(29);
        let (before, after, run) = settled(&history, 1);
        let local = card_in(before, "work/local-wins", "r1.vcf");
        assert_eq!(run.events.len(), 1);
        assert!(matches!(run.events[0], Event::Overruled { .. }));
        let Push::Update {
            object, if_match, ..
        } = &run.pushes[0].0
        else {
            panic!("an update");
        };
        assert_eq!(Some(object.clone()), local.object);
        let kept = retained_kept(after, "work/local-wins");
        assert_eq!(
            kept.summary.get("fn"),
            Value::Text(String::from("Their Version"))
        );
        assert_ne!(
            *if_match,
            local.bindings.first().unwrap().base_revision,
            "gated on the observed revision"
        );
        let pushed = card_in(after, "work/local-wins", "r1.vcf");
        assert_eq!(pushed.bindings.first().unwrap().base_object, local.object);
    }

    #[test]
    fn an_unread_server_body_is_recorded_whatever_the_policy() {
        let history = History::policies(29);
        for book in [2, 4] {
            let (_, after, run) = settled(&history, book);
            assert_eq!(
                run.events,
                [Event::Conflicted(String::from("r1.vcf"))],
                "book {book}"
            );
            assert!(run.pushes.is_empty());
            let binding = card_in(
                after,
                [
                    "work/remote-wins",
                    "work/local-wins",
                    "work/local-unread",
                    "work/keep-local",
                    "work/keep-unread",
                ][book],
                "r1.vcf",
            )
            .bindings[0]
                .clone();
            assert!(binding.conflicted && binding.conflict_object.is_none());
        }
    }

    #[test]
    fn keep_local_pushes_over_a_change_the_server_alone_made() {
        let history = History::policies(29);
        let (before, after, run) = settled(&history, 3);
        let local = card_in(before, "work/keep-local", "r1.vcf");
        assert_eq!(
            local.bindings.first().unwrap().base_object,
            local.object,
            "no local edit"
        );
        assert!(matches!(run.events[..], [Event::Overruled { .. }]));
        let Push::Update { object, .. } = &run.pushes[0].0 else {
            panic!("an update");
        };
        assert_eq!(Some(object.clone()), local.object);
        assert_eq!(
            card_in(after, "work/keep-local", "r1.vcf").object,
            local.object
        );
        for book in 0..5 {
            let quiet = history.steps[1 + 4 * book + 3].run.as_ref().unwrap();
            assert!(
                quiet.pushes.is_empty() && quiet.events.is_empty(),
                "book {book}"
            );
        }
    }

    fn shared(history: &History, book: usize, step: usize) -> (&Model, &Run) {
        let step = &history.steps[1 + 9 * book + step];
        (&step.model, step.run.as_ref().unwrap())
    }

    fn held_by<'a>(model: &'a Model, book: usize, source: &str, handle: &str) -> &'a Item {
        let (id, _, _) = SHARED[book];
        let source = format!("{id}-{source}");
        model
            .items
            .iter()
            .find(|item| {
                item.collection == id
                    && item
                        .bound(&source)
                        .is_some_and(|binding| binding.handle == handle)
            })
            .unwrap()
    }

    fn base(item: &Item, book: usize, source: &str) -> Option<ObjectName> {
        let source = format!("{}-{source}", SHARED[book].0);
        item.bound(&source).unwrap().base_object.clone()
    }

    fn kept<'a>(model: &'a Model, item: &Item, handle: &str) -> &'a Item {
        let link_id = format!("dup:{}#{handle}", item.link_id);
        model
            .items
            .iter()
            .find(|kept| kept.collection == item.collection && kept.link_id == link_id)
            .unwrap()
    }

    fn pushed<'a>(run: &'a Run, name: &str, handle: &str) -> Option<&'a Push> {
        run.pushes
            .iter()
            .map(|(push, _)| push)
            .find(|push| push.name() == name && push.handle() == handle)
    }

    #[test]
    fn a_second_source_joins_what_it_shares_and_is_offered_the_rest() {
        let history = History::sources(31);
        let (model, run) = shared(&history, 0, 1);

        let same = held_by(model, 0, "a", "r1.vcf");
        let binding = same.bound("work/shared-b").unwrap();
        assert_eq!(binding.handle, "r1.vcf");
        assert_eq!(binding.base_object, same.object);
        assert_eq!(binding.shared_object, same.object);
        assert!(
            !model
                .items
                .iter()
                .any(|item| item.link_id.starts_with("dup:"))
        );

        let own = held_by(model, 0, "b", "r3.vcf");
        assert_eq!(own.bindings.len(), 1);

        let offered = held_by(model, 0, "a", "r3.vcf");
        let handle = format!("\u{1}{}", offered.link_id);
        assert!(pushed(run, "add", &handle).is_some());
        let assigned = run.outcomes[0].assigned.clone().unwrap();
        let binding = offered.bound("work/shared-b").unwrap();
        assert_eq!(binding.handle, assigned);
        assert!(binding.base_present);

        let (after, run) = shared(&history, 0, 2);
        assert!(pushed(run, "add", &format!("\u{1}{}", own.link_id)).is_some());
        assert_eq!(held_by(after, 0, "b", "r3.vcf").bindings.len(), 2);
        let nameless = held_by(after, 0, "a", "r4.vcf");
        assert!(nameless.link_id.starts_with("hash:"));
        assert_eq!(nameless.bindings.len(), 1);
    }

    #[test]
    fn a_body_diverging_on_joining_is_settled_by_the_collection_policy() {
        let history = History::sources(31);

        let (model, run) = shared(&history, 0, 1);
        let item = held_by(model, 0, "a", "r2.vcf");
        assert!(item.conflicted);
        assert_eq!(item.object, base(item, 0, "a"));
        assert_eq!(item.conflict_object, base(item, 0, "b"));
        assert_eq!(item.bound("work/shared-b").unwrap().shared_object, None);
        assert!(
            run.events
                .contains(&Event::Conflicted(String::from("r2.vcf")))
        );
        let (_, next) = shared(&history, 0, 2);
        assert!(pushed(run, "update", "r2.vcf").is_none());
        assert!(pushed(next, "update", "r2.vcf").is_none());

        let (before, _) = shared(&history, 1, 0);
        let (model, run) = shared(&history, 1, 1);
        let item = held_by(model, 1, "a", "r2.vcf");
        assert!(!item.conflicted);
        assert_eq!(item.object, base(item, 1, "b"));
        let loser = kept(model, item, "r2.vcf");
        assert_eq!(loser.object, held_by(before, 1, "a", "r2.vcf").object);
        assert_eq!(
            loser.state,
            State::Retained {
                by: Some(String::from("work/incoming-b"))
            }
        );
        assert!(run.events.contains(&Event::Overruled {
            handle: String::from("r2.vcf"),
            link_id: loser.link_id.clone(),
        }));
        let (_, next) = shared(&history, 1, 2);
        let Some(Push::Update { object, .. }) = pushed(next, "update", "r2.vcf") else {
            panic!("a owes the body the item adopted");
        };
        assert_eq!(Some(object), item.object.as_ref());

        let (model, run) = shared(&history, 2, 1);
        let item = held_by(model, 2, "a", "r2.vcf");
        assert!(!item.conflicted);
        let loser = kept(model, item, "r2.vcf");
        assert_ne!(loser.object, item.object);
        let binding = item.bound("work/existing-b").unwrap();
        assert_eq!(binding.shared_object, item.object);
        assert!(
            pushed(run, "update", "r2.vcf").is_none(),
            "a change is derived before the fold"
        );
        let (_, next) = shared(&history, 2, 4);
        let Some(Push::Update { object, .. }) = pushed(next, "update", "r2.vcf") else {
            panic!("b's next run pushes the body the item kept");
        };
        assert_eq!(Some(object), item.object.as_ref());
    }

    #[test]
    fn a_change_one_source_pulls_is_owed_by_the_other() {
        let history = History::sources(31);
        for (book, (id, _, _)) in SHARED.iter().enumerate() {
            let (before, _) = shared(&history, book, 2);
            let (model, run) = shared(&history, book, 3);
            let item = held_by(model, book, "a", "r1.vcf");
            assert!(
                run.events
                    .contains(&Event::ContentChanged(String::from("r1.vcf")))
            );
            assert_eq!(item.object, base(item, book, "a"));
            assert_ne!(item.object, base(item, book, "b"));
            let source = format!("{id}-b");
            assert_eq!(
                item.bound(&source).unwrap().shared_object,
                held_by(before, book, "a", "r1.vcf")
                    .bound(&source)
                    .unwrap()
                    .shared_object
            );
        }

        let (model, _) = shared(&history, 1, 6);
        let adopted = held_by(model, 1, "a", "r1.vcf").object.clone();
        let (_, run) = shared(&history, 1, 7);
        let Some(Push::Update { object, .. }) = pushed(run, "update", "r1.vcf") else {
            panic!("a owes the edit b folded");
        };
        assert_eq!(Some(object), adopted.as_ref());
    }

    #[test]
    fn a_pull_diverging_from_the_item_is_settled_by_the_collection_policy() {
        let history = History::sources(31);

        let (before, _) = shared(&history, 0, 3);
        let (model, run) = shared(&history, 0, 4);
        let was = held_by(before, 0, "a", "r1.vcf");
        let item = held_by(model, 0, "a", "r1.vcf");
        assert!(item.conflicted);
        assert_eq!(item.object, was.object);
        assert_eq!(item.conflict_object, base(item, 0, "b"));
        assert_eq!(
            item.bound("work/shared-b").unwrap().shared_object,
            was.bound("work/shared-b").unwrap().shared_object
        );
        assert_eq!(run.events, [Event::Conflicted(String::from("r1.vcf"))]);
        assert!(run.pushes.is_empty());
        let (_, next) = shared(&history, 0, 7);
        assert!(pushed(next, "update", "r1.vcf").is_none());

        let (before, _) = shared(&history, 1, 3);
        let (model, run) = shared(&history, 1, 4);
        let item = held_by(model, 1, "a", "r1.vcf");
        assert_eq!(item.object, base(item, 1, "b"));
        let loser = kept(model, item, "r1.vcf");
        assert_eq!(loser.object, held_by(before, 1, "a", "r1.vcf").object);
        let overruled = run
            .events
            .iter()
            .filter(|event| matches!(event, Event::Overruled { .. }))
            .count();
        assert_eq!(overruled, 1);

        let (before, _) = shared(&history, 2, 3);
        let (model, run) = shared(&history, 2, 4);
        let item = held_by(model, 2, "a", "r1.vcf");
        assert_eq!(item.object, held_by(before, 2, "a", "r1.vcf").object);
        let loser = kept(model, item, "r1.vcf");
        assert_ne!(loser.object, item.object);
        assert!(
            pushed(run, "update", "r1.vcf").is_none(),
            "a change is derived before the fold"
        );
        let binding = item.bound("work/existing-b").unwrap();
        assert_eq!(binding.shared_object, item.object);
        assert_ne!(binding.base_object, item.object);

        let (after, next) = shared(&history, 2, 5);
        let Some(Push::Update {
            object, if_match, ..
        }) = pushed(next, "update", "r1.vcf")
        else {
            panic!("b's next run pushes the body the item kept");
        };
        assert_eq!(Some(object), item.object.as_ref());
        assert_eq!(if_match, &binding.base_revision);
        let item = held_by(after, 2, "a", "r1.vcf");
        assert_eq!(base(item, 2, "b"), item.object);
    }

    #[test]
    fn a_delete_one_source_finds_is_pushed_by_the_other() {
        let history = History::sources(31);
        for (book, (id, _, _)) in SHARED.iter().enumerate() {
            let (model, run) = shared(&history, book, 7);
            assert!(
                run.events
                    .contains(&Event::Vanished(String::from("r3.vcf")))
            );
            let item = held_by(model, book, "b", "r4.vcf");
            assert_eq!(item.state, State::Tombstone);
            assert_eq!(item.bindings.len(), 1);

            let (after, run) = shared(&history, book, 8);
            assert!(pushed(run, "remove", "r4.vcf").is_some());
            let item = after
                .items
                .iter()
                .find(|other| other.collection == item.collection && other.link_id == item.link_id)
                .unwrap();
            assert!(item.bindings.is_empty());
            assert_eq!(
                item.state,
                State::Retained {
                    by: Some(format!("{id}-b"))
                }
            );
        }
    }

    #[test]
    fn an_offered_create_binds_only_on_an_outcome_the_write_records() {
        let history = History::sources(31);
        let (first, _) = shared(&history, 0, 0);
        let mut model = first.clone();
        let mut remote = Remote::dav("work/shared-b", "work/shared");
        let run = model.clone().sync(&mut remote.clone(), PAGE);
        let keys: Vec<(String, String)> = run
            .pushes
            .iter()
            .map(|(push, key)| (String::from(push.handle()), key.clone()))
            .collect();
        assert_eq!(keys.len(), 3);
        let reason = String::from("the address book takes no contact of this kind");
        remote.refuse.insert(keys[0].1.clone(), reason.clone());
        remote.reject.insert(keys[1].1.clone());

        let run = model.sync(&mut remote, PAGE);
        let refused = model
            .items
            .iter()
            .find(|item| {
                item.bound("work/shared-b")
                    .is_some_and(|b| b.handle == keys[0].0)
            })
            .unwrap();
        let binding = refused.bound("work/shared-b").unwrap();
        assert!(!binding.base_present && binding.base_object.is_none());
        assert_eq!(binding.refusal.as_ref().unwrap().key, keys[0].1);
        assert!(model.items.iter().all(|item| {
            item.bound("work/shared-b")
                .is_none_or(|binding| binding.handle != keys[1].0)
        }));
        assert_eq!(run.outcomes[1].answer, Answer::Rejected);

        let run = model.sync(&mut remote, PAGE);
        assert!(pushed(&run, "add", &keys[0].0).is_none());
        assert!(run.events.contains(&Event::Refused {
            handle: keys[0].0.clone(),
            reason,
        }));
        assert!(pushed(&run, "add", &keys[1].0).is_some());
    }

    #[test]
    fn a_pull_agreeing_with_the_item_settles_without_a_conflict() {
        let history = History::sources(31);
        let (model, run) = shared(&history, 3, 4);
        let item = held_by(model, 3, "b", "r1.vcf");
        assert!(!item.conflicted);
        assert_eq!(item.object, base(item, 3, "a"));
        assert_eq!(item.object, base(item, 3, "b"));
        assert_eq!(
            item.bound("work/agreeing-b").unwrap().shared_object,
            item.object
        );
        assert!(run.pushes.is_empty());
        assert!(
            model
                .items
                .iter()
                .filter(|item| item.collection == "work/agreeing")
                .all(|item| !item.link_id.starts_with("dup:"))
        );
    }

    #[test]
    fn a_server_edit_over_an_item_conflict_is_recorded_on_its_binding() {
        let history = History::sources(31);
        let (before, _) = shared(&history, 0, 4);
        let (model, run) = shared(&history, 0, 6);
        let was = held_by(before, 0, "b", "r1.vcf");
        let item = held_by(model, 0, "b", "r1.vcf");
        assert!(item.conflicted);
        assert_eq!(item.object, was.object);
        assert_eq!(item.conflict_object, was.conflict_object);
        let binding = item.bound("work/shared-b").unwrap();
        assert!(binding.conflicted && binding.conflict_object.is_some());
        assert_ne!(binding.conflict_object, item.conflict_object);
        assert_eq!(run.events, [Event::Conflicted(String::from("r1.vcf"))]);
        assert!(run.pushes.is_empty());

        for book in 1..SHARED.len() {
            let (model, run) = shared(&history, book, 6);
            let item = held_by(model, book, "b", "r1.vcf");
            assert!(!item.conflicted);
            assert_eq!(item.object, base(item, book, "b"));
            assert_eq!(run.events, [Event::ContentChanged(String::from("r1.vcf"))]);
        }
    }

    fn inbox(history: &History, step: usize) -> (&Model, &Run) {
        let step = &history.steps[1 + 9 * SHARED.len() + step];
        (&step.model, step.run.as_ref().unwrap())
    }

    fn message<'a>(model: &'a Model, source: &str, handle: &str) -> &'a Item {
        model
            .items
            .iter()
            .find(|item| {
                item.collection == "work/INBOX"
                    && item
                        .bound(source)
                        .is_some_and(|binding| binding.handle == handle)
            })
            .unwrap()
    }

    #[test]
    fn a_message_joins_on_agreeing_and_is_minted_apart_on_disagreeing() {
        let history = History::sources(31);
        let (model, run) = inbox(&history, 1);
        let joined = message(model, "imap-a", "1");
        assert!(joined.object.is_some() && !joined.conflicted);
        let binding = joined.bound("imap-b").unwrap();
        assert_eq!(binding.handle, "1");
        assert_eq!(binding.base_object, joined.object);
        assert_eq!(joined.flags, Some(set(&["\\Answered", "\\Seen"])));

        let minted = message(model, "imap-b", "2");
        assert_eq!(minted.link_id, format!("dup:{}#2", joined.link_id));
        assert_eq!(minted.bindings.len(), 1);
        assert!(minted.object.is_none());
        let offered = message(model, "imap-a", "2");
        assert!(pushed(run, "add", &format!("\u{1}{}", offered.link_id)).is_some());

        let (_, run) = inbox(&history, 2);
        assert!(run.pushes.iter().all(|(push, _)| push.name() != "add"));
        let Some(Push::SetFlags { add, remove, .. }) = pushed(run, "set-flags", "1") else {
            panic!("a owes the flag b joined with");
        };
        assert_eq!((add, remove), (&set(&["\\Seen"]), &BTreeSet::new()));

        let (_, run) = inbox(&history, 3);
        assert_eq!(run.events, [Event::FlagsChanged(String::from("1"))]);
        let (model, run) = inbox(&history, 4);
        let Some(Push::SetFlags { add, .. }) = pushed(run, "set-flags", "1") else {
            panic!("a owes the flag b pulled");
        };
        assert_eq!(add, &set(&["\\Flagged"]));
        let binding = message(model, "imap-a", "1").bound("imap-a").unwrap();
        assert_eq!(
            binding.base_flags,
            Some(set(&["\\Answered", "\\Flagged", "\\Seen"]))
        );
    }

    #[test]
    fn a_resolution_runs_through_the_binding_whose_conflict_it_names() {
        let history = History::sources(31);
        let (before, _) = shared(&history, 0, 6);
        let item = held_by(before, 0, "b", "r1.vcf");
        let binding = item.bound("work/shared-b").unwrap().clone();
        let filed = Card {
            uid: Some(item.link_id.clone()),
            ..Draw::new(1).card()
        }
        .file();
        let update = |resolves: Vec<ObjectName>| Action::Update {
            seq: item.seq,
            filed: filed.clone(),
            if_match: item.object.clone(),
            resolves: Some(resolves),
        };
        let item_conflict = item.conflict_object.clone().unwrap();
        let binding_conflict = binding.conflict_object.clone().unwrap();

        let mut model = before.clone();
        let row = model.enqueue(
            "cardamum",
            "work/shared",
            update(vec![item_conflict.clone()]),
        );
        assert!(matches!(model.drain(row), Outcome::Parked(_)));

        let mut model = before.clone();
        let row = model.enqueue(
            "cardamum",
            "work/shared",
            update(vec![item_conflict, binding_conflict.clone()]),
        );
        assert!(matches!(model.drain(row), Outcome::Applied(_)));
        let item = held_by(&model, 0, "b", "r1.vcf");
        assert!(!item.conflicted);
        let settled = item.bound("work/shared-b").unwrap();
        assert!(!settled.conflicted);
        assert_eq!(settled.base_object, Some(binding_conflict));
        assert_eq!(settled.base_revision, binding.conflict_revision);
    }

    fn scoped(history: &History, step: usize) -> (&Model, &Run) {
        let step = &history.steps[step];
        (&step.model, step.run.as_ref().unwrap())
    }

    fn handled<'a>(model: &'a Model, collection: &str, handle: &str) -> Option<&'a Item> {
        model.items.iter().find(|item| {
            item.collection == collection
                && item.bindings.iter().any(|binding| binding.handle == handle)
        })
    }

    fn coverage(model: &Model, collection: &str) -> Option<Scope> {
        let sources = &model.collections[collection].sources;
        sources.values().next().unwrap().coverage.clone()
    }

    fn since(month: u32) -> Scope {
        Scope {
            since: Some(Instant::at(2026, month, 1, 0, 0, 0)),
            until: None,
        }
    }

    #[test]
    fn a_round_lists_its_scope_and_finds_absences_in_it_alone() {
        let history = History::scopes(37);
        let inbox = "work/INBOX";

        let (model, run) = scoped(&history, 1);
        assert_eq!(model.live(inbox).count(), 2);
        assert!(
            model
                .live(inbox)
                .all(|item| since(10).holds(item.date().as_deref()))
        );
        assert_eq!(coverage(model, inbox), Some(since(10)));
        assert!(run.pages.iter().all(|page| page.complete));

        let (model, _) = scoped(&history, 2);
        assert_eq!(model.live(inbox).count(), 4);
        assert_eq!(coverage(model, inbox), Some(since(9)));

        let (model, run) = scoped(&history, 4);
        assert!(!run.pages[0].complete);
        assert!(run.events.is_empty());
        assert_eq!(coverage(model, inbox), Some(since(10)));

        let (model, run) = scoped(&history, 5);
        assert!(run.pages[0].complete);
        assert!(run.events.contains(&Event::Vanished(String::from("2"))));
        assert!(!run.events.contains(&Event::Vanished(String::from("1"))));
        assert_eq!(handled(model, inbox, "1").unwrap().state, State::Live);
        assert_eq!(coverage(model, inbox), Some(since(9)));

        let (model, run) = scoped(&history, 6);
        assert!(run.events.contains(&Event::Vanished(String::from("1"))));
        assert!(handled(model, inbox, "1").is_none());
        assert_eq!(coverage(model, inbox), Some(Scope::default()));
    }

    #[test]
    fn a_create_dated_out_of_the_scope_waits_for_a_round_holding_it() {
        let history = History::scopes(37);
        let added = |run: &Run| -> Vec<String> {
            run.pushes
                .iter()
                .filter_map(|(push, _)| match push {
                    Push::Add { link_id, .. } => Some(link_id.clone()),
                    _ => None,
                })
                .collect()
        };
        let (model, run) = scoped(&history, 5);
        let dates: Vec<Option<String>> = added(run)
            .iter()
            .map(|link_id| {
                let item = model.items.iter().find(|item| &item.link_id == link_id);
                item.unwrap().date()
            })
            .collect();
        assert_eq!(dates, [Some(String::from("2026-10-25T09:00:00Z"))]);

        let (model, run) = scoped(&history, 6);
        let dates: Vec<Option<String>> = added(run)
            .iter()
            .map(|link_id| {
                let item = model.items.iter().find(|item| &item.link_id == link_id);
                item.unwrap().date()
            })
            .collect();
        assert_eq!(dates, [Some(String::from("2026-08-25T09:00:00Z"))]);
    }

    #[test]
    fn a_narrowed_round_proves_only_what_its_enumeration_lacks() {
        let history = History::scopes(37);
        let archive = "work/Archive";

        let (model, run) = scoped(&history, 9);
        let last = run.pages.last().unwrap();
        assert!(last.narrowed && last.enumerated.is_none());
        assert!(
            last.items.iter().any(|member| member.handle == "4"),
            "a narrowing takes two days below the floor"
        );
        assert!(run.events.is_empty());
        assert_eq!(handled(model, archive, "1").unwrap().state, State::Live);
        assert_eq!(handled(model, archive, "2").unwrap().state, State::Live);
        assert_eq!(coverage(model, archive), Some(since(9)));

        let (model, run) = scoped(&history, 11);
        let last = run.pages.last().unwrap();
        assert!(last.narrowed && last.enumerated.is_some());
        assert!(last.items.iter().all(|member| member.handle != "2"));
        assert_eq!(run.events, [Event::Vanished(String::from("1"))]);
        assert_eq!(handled(model, archive, "2").unwrap().state, State::Live);
    }

    #[test]
    fn a_capped_round_proves_no_absence() {
        let history = History::scopes(37);
        let (model, run) = scoped(&history, 14);
        assert!(run.pages.iter().all(|page| page.capped));
        assert_eq!(
            run.pages.iter().map(|page| page.items.len()).sum::<usize>(),
            2
        );
        assert!(run.events.is_empty());
        assert_eq!(model.live("work/Sent Items").count(), 4);
        assert_eq!(coverage(model, "work/Sent Items"), Some(Scope::default()));
    }

    #[test]
    fn a_mass_or_an_empty_absence_parks_its_round_until_accepted() {
        let history = History::scopes(37);
        for (id, base, absent, bound) in [("work/Junk", 15, 20, 21), ("work/Drafts", 20, 2, 2)] {
            let (before, _) = scoped(&history, base + 1);
            let (model, run) = scoped(&history, base + 2);
            assert_eq!(run.parked, Some((absent, bound)), "{id}");
            assert!(run.events.is_empty());
            assert!(run.pushes.is_empty(), "no add while the round stays open");
            assert_eq!(model.live(id).count(), bound + 1);
            let state = model.collections[id].sources.values().next().unwrap();
            assert_eq!(state.open.as_ref().unwrap().scope, Scope::default());
            assert_eq!(state.coverage, coverage(before, id));

            let (resumed, run) = scoped(&history, base + 3);
            assert_eq!(run.parked, Some((absent, bound)));
            let again = resumed.collections[id].sources.values().next().unwrap();
            assert_eq!(again.rounds, state.rounds);

            let (model, run) = scoped(&history, base + 4);
            assert_eq!(run.parked, None);
            assert_eq!(run.events.len(), absent + 1);
            assert!(matches!(run.pushes[..], [(Push::Add { .. }, _)]));
            assert_eq!(model.live(id).count(), bound - absent + 1);
            let state = model.collections[id].sources.values().next().unwrap();
            assert!(state.open.is_none());
            assert_eq!(state.coverage, Some(Scope::default()));
        }
    }

    #[test]
    fn a_round_left_undecided_reports_what_it_left_unlisted() {
        let history = History::scopes(37);
        let (_, run) = scoped(&history, 9);
        assert_eq!(run.unlisted, Some(2), "narrowed, handing no enumeration");
        let (_, run) = scoped(&history, 11);
        assert_eq!(run.unlisted, None, "narrowed, enumerating");
        let (_, run) = scoped(&history, 14);
        assert_eq!(run.unlisted, Some(2), "capped");
        for step in [1, 5, 6, 17] {
            let (_, run) = scoped(&history, step);
            assert_eq!(run.unlisted, None, "step {step}");
        }
    }

    #[test]
    fn a_member_joining_an_item_is_reported_added_alone() {
        let history = History::sources(31);
        let naming = |run: &Run, handle: &str| -> Vec<Event> {
            run.events
                .iter()
                .filter(|event| match event {
                    Event::Added(named)
                    | Event::Created(named)
                    | Event::FlagsChanged(named)
                    | Event::ContentChanged(named) => named == handle,
                    _ => false,
                })
                .cloned()
                .collect()
        };
        let (_, run) = shared(&history, 0, 1);
        assert_eq!(
            naming(run, "r1.vcf"),
            [Event::Added(String::from("r1.vcf"))]
        );
        let (_, run) = inbox(&history, 1);
        assert_eq!(naming(run, "1"), [Event::Added(String::from("1"))]);
    }

    fn unread(history: &History, book: usize, step: usize) -> (&Model, &Run) {
        let step = &history.steps[1 + 9 * SHARED.len() + 5 + 3 * book + step];
        (&step.model, step.run.as_ref().unwrap())
    }

    #[test]
    fn a_member_joining_unread_is_recorded_until_its_upgrade_reads_it() {
        let history = History::sources(31);
        for (book, (id, _)) in UNREAD.iter().enumerate() {
            let b = format!("{id}-b");
            let card = |model: &Model, handle: &str| -> Item {
                let found = model.items.iter().find(|item| {
                    item.collection == *id
                        && item
                            .bound(&b)
                            .is_some_and(|binding| binding.handle == handle)
                });
                found.cloned().unwrap()
            };

            let (model, run) = unread(&history, book, 1);
            for handle in ["r1.vcf", "r2.vcf"] {
                let item = card(model, handle);
                assert!(item.conflicted && item.conflict_object.is_none(), "{id}");
                let binding = item.bound(&b).unwrap();
                assert!(binding.base_object.is_none() && binding.base_revision.is_some());
                assert_eq!(binding.shared_object, None);
                let named: Vec<&Event> = run
                    .events
                    .iter()
                    .filter(|event| {
                        matches!(event, Event::Added(h) | Event::Conflicted(h) if h == handle)
                    })
                    .collect();
                assert_eq!(
                    named,
                    [
                        &Event::Added(String::from(handle)),
                        &Event::Conflicted(String::from(handle))
                    ]
                );
            }

            let (before, _) = unread(&history, book, 1);
            let (model, run) = unread(&history, book, 2);
            let same = card(model, "r1.vcf");
            assert!(!same.conflicted, "a body read equal to the item's");
            let binding = same.bound(&b).unwrap();
            assert_eq!(binding.base_object, same.object);
            assert_eq!(binding.shared_object, same.object);

            let was = card(before, "r2.vcf");
            let other = card(model, "r2.vcf");
            let read = other.bound(&b).unwrap().base_object.clone();
            assert!(read.is_some() && read != was.object);
            match book {
                0 => {
                    assert!(other.conflicted);
                    assert_eq!(other.conflict_object, read);
                    assert_eq!(other.object, was.object);
                    assert!(run.events.is_empty());
                }
                _ => {
                    assert!(!other.conflicted);
                    assert_eq!(other.object, read);
                    let loser = kept(model, &other, "r2.vcf");
                    assert_eq!(loser.object, was.object);
                    assert_eq!(
                        run.events,
                        [Event::Overruled {
                            handle: String::from("r2.vcf"),
                            link_id: loser.link_id.clone(),
                        }]
                    );
                }
            }
        }
    }

    fn rekeyed(history: &History, step: usize) -> (&Model, &Run) {
        let step = &history.steps[step];
        (&step.model, step.run.as_ref().unwrap())
    }

    /// The `seq`, the key and the flags of each live item of `collection`,
    /// by its handle.
    fn spine(
        model: &Model,
        collection: &str,
    ) -> BTreeMap<String, (i64, String, Option<BTreeSet<String>>)> {
        model
            .live(collection)
            .filter_map(|item| {
                let binding = item.bindings.first()?;
                Some((
                    binding.handle.clone(),
                    (item.seq, item.link_id.clone(), item.flags.clone()),
                ))
            })
            .collect()
    }

    #[test]
    fn a_rekey_carries_every_placement_onto_its_new_handle_by_link_id() {
        let history = History::rekeys(41);
        let inbox = "work/INBOX";

        let (before, _) = rekeyed(&history, 2);
        let (model, run) = rekeyed(&history, 3);
        assert!(run.events.is_empty() && run.pushes.is_empty() && run.parked.is_none());
        let old: BTreeSet<_> = spine(before, inbox).into_values().collect();
        let new: BTreeSet<_> = spine(model, inbox).into_values().collect();
        assert_eq!(old, new, "every seq, key and flag set carried");
        assert!(
            spine(model, inbox)
                .keys()
                .all(|handle| handle.parse::<u64>().unwrap() >= 200)
        );
        assert!(
            new.iter()
                .any(|(_, link_id, _)| link_id.starts_with("dup:"))
        );
        let collection = &model.collections[inbox];
        assert_eq!(
            collection.generation,
            before.collections[inbox].generation + 1
        );
        let checkpoint = collection.sources["work-imap"].checkpoint.clone();
        assert_eq!(
            checkpoint,
            run.pages[0].checkpoint.clone().map(String::into_bytes)
        );

        let (_, run) = rekeyed(&history, 4);
        assert!(
            run.events.is_empty() && run.pushes.is_empty(),
            "the new space's delta"
        );
    }

    #[test]
    fn a_rekey_drops_a_binding_no_member_resolves_to_though_its_handle_is_reused() {
        let history = History::rekeys(41);
        let inbox = "work/INBOX";
        let (before, _) = rekeyed(&history, 1);
        let (model, _) = rekeyed(&history, 2);
        let gone = handled(before, inbox, "1").unwrap();
        let retained = model
            .items
            .iter()
            .find(|item| item.collection == inbox && item.link_id == gone.link_id)
            .unwrap();
        assert_eq!(
            retained.state,
            State::Retained {
                by: Some(String::from("work-imap"))
            }
        );
        let second = handled(before, inbox, "2").unwrap();
        let moved = handled(model, inbox, "1").unwrap();
        assert_eq!((moved.seq, &moved.link_id), (second.seq, &second.link_id));
    }

    #[test]
    fn a_rekey_missing_most_or_capped_parks_until_accepted() {
        let history = History::rekeys(41);
        let inbox = "work/INBOX";
        let (before, _) = rekeyed(&history, 4);
        let (model, run) = rekeyed(&history, 5);
        assert_eq!(run.parked, Some((15, 24)));
        assert_eq!(spine(model, inbox), spine(before, inbox), "nothing written");
        assert_eq!(
            model.collections[inbox].generation,
            before.collections[inbox].generation
        );

        let (model, run) = rekeyed(&history, 6);
        assert_eq!(run.parked, None);
        assert_eq!(model.live(inbox).count(), 9);

        let (after, run) = rekeyed(&history, 7);
        assert_eq!(
            run.parked,
            Some((4, 9)),
            "a capped rekey parks on any absence"
        );
        assert_eq!(spine(after, inbox), spine(model, inbox));
    }

    #[test]
    fn a_rekey_pulls_a_server_edit_and_records_one_over_a_local_edit() {
        let history = History::rekeys(41);
        let id = "work/contacts";
        let (before, _) = rekeyed(&history, 8);
        let (model, run) = rekeyed(&history, 9);
        let revision = |handle: &str| -> Option<String> {
            run.pages
                .iter()
                .flat_map(|page| page.items.iter())
                .find(|member| member.handle == handle)
                .and_then(|member| member.revision.clone())
        };
        let was = |handle: &str| card_in(before, id, handle);

        let both = card_in(model, id, "r10.vcf");
        let binding = both.bindings[0].clone();
        assert!(binding.conflicted);
        assert_eq!(binding.conflict_revision, revision("r10.vcf"));
        assert_eq!(
            binding.base_revision,
            was("r1.vcf").bindings[0].base_revision
        );
        assert!(
            both.object.is_some() && both.object != binding.base_object,
            "the local edit stands"
        );
        assert_eq!(binding.base_object, was("r1.vcf").bindings[0].base_object);

        let pulled = card_in(model, id, "r11.vcf");
        assert_eq!((pulled.object.clone(), pulled.level), (None, 1));
        let binding = &pulled.bindings[0];
        assert_eq!(binding.base_object, None);
        assert_eq!(binding.base_revision, revision("r11.vcf"));

        let carried = card_in(model, id, "r12.vcf");
        assert_eq!(
            carried.bindings[0].base_revision,
            was("r3.vcf").bindings[0].base_revision
        );
        assert_eq!(carried.object, was("r3.vcf").object);
    }

    #[test]
    fn an_upgrade_no_item_conflict_waits_on_only_moves_the_base() {
        let history = History::rekeys(41);
        let id = "work/contacts";
        let staged = &history.steps[10].model;
        let (model, run) = rekeyed(&history, 11);
        let before = card_in(staged, id, "r11.vcf");
        let after = card_in(model, id, "r11.vcf");
        assert!(run.events.is_empty());
        assert!(!after.conflicted && after.conflict_object.is_none());
        let binding = &after.bindings[0];
        assert!(!binding.conflicted);
        assert_eq!(
            after.object, before.object,
            "the local edit stays the item's body"
        );
        let read = run.fetch.get("r11.vcf").map(|bytes| ObjectName::of(bytes));
        assert_eq!(binding.base_object, read);
        assert_eq!(binding.base_revision, before.bindings[0].base_revision);
        assert_eq!(binding.shared_object, before.bindings[0].shared_object);

        let (_, run) = rekeyed(&history, 12);
        let Some(Push::Update {
            object, if_match, ..
        }) = pushed(run, "update", "r11.vcf")
        else {
            panic!("the edit, now over a body read, is pushed");
        };
        assert_eq!(Some(object), after.object.as_ref());
        assert_eq!(if_match, &binding.base_revision);
    }

    #[test]
    fn an_interrupted_round_keeps_what_landed_and_resumes_from_its_cursor() {
        let history = History::crashes(43);
        let inbox = "work/INBOX";
        let (model, run) = rekeyed(&history, 1);
        assert!(run.failed && run.pushes.is_empty());
        let state = &model.collections[inbox].sources["work-imap"];
        let open = state.open.as_ref().unwrap();
        assert_eq!(open.cursor.as_deref(), run.pages[0].cursor.as_deref());
        assert_eq!(
            open.checkpoint,
            run.pages[0].checkpoint.clone().map(String::into_bytes)
        );
        assert_eq!(
            (state.checkpoint.clone(), state.coverage.clone()),
            (None, None)
        );
        let landed: Vec<_> = model.live(inbox).collect();
        assert_eq!(landed.len(), run.pages[0].items.len());
        assert!(
            landed
                .iter()
                .all(|item| item.bindings[0].round == Some(state.rounds))
        );

        let (after, run) = rekeyed(&history, 2);
        assert!(!run.failed);
        assert!(
            run.pages[0].checkpoint.is_none(),
            "resumed past the first page"
        );
        assert!(
            !run.events
                .iter()
                .any(|event| matches!(event, Event::Vanished(_)))
        );
        let state_after = &after.collections[inbox].sources["work-imap"];
        assert_eq!(state_after.rounds, state.rounds, "the same round");
        assert!(state_after.open.is_none());
        assert_eq!(state_after.checkpoint, open.checkpoint);
        assert_eq!(state_after.coverage, Some(Scope::default()));
        assert_eq!(after.live(inbox).count(), 8);
        assert!(
            after
                .live(inbox)
                .all(|item| item.bindings[0].round == Some(state.rounds))
        );
    }

    #[test]
    fn a_push_whose_record_was_lost_is_landed_or_met_not_pushed_again() {
        let history = History::crashes(43);
        let inbox = "work/INBOX";
        let (model, run) = rekeyed(&history, 3);
        assert!(run.failed);
        assert!(matches!(run.pushes[..], [(Push::Add { .. }, _)]));
        assert_eq!(run.outcomes[0].answer, Answer::Accepted);
        let create = model
            .live(inbox)
            .find(|item| item.bindings[0].handle.starts_with('\u{1}'))
            .unwrap();
        assert!(
            !create.bindings[0].base_present,
            "the outcome was never written"
        );

        let (after, run) = rekeyed(&history, 4);
        assert!(
            run.events
                .iter()
                .any(|event| matches!(event, Event::Created(_)))
        );
        assert!(
            run.pushes
                .iter()
                .all(|(push, _)| push.name() == "set-flags")
        );
        assert_eq!(run.pushes.len(), 2);
        let landed = after
            .live(inbox)
            .find(|item| item.link_id == create.link_id)
            .unwrap();
        assert!(landed.bindings[0].base_present);

        for (base, id) in [(5, "work/contacts"), (9, "work/directory")] {
            let (model, run) = rekeyed(&history, base + 1);
            assert!(run.failed && run.outcomes[0].answer == Answer::Accepted);
            let staged = card_in(model, id, "r1.vcf");
            let (after, run) = rekeyed(&history, base + 2);
            assert!(run.pushes.is_empty(), "{id}: the edit is not pushed again");
            let (settled, _) = rekeyed(&history, base + 3);
            let card = card_in(settled, id, "r1.vcf");
            let binding = &card.bindings[0];
            assert!(!binding.conflicted, "{id}");
            assert_eq!(card.object, staged.object, "{id}: the edit stands");
            assert_eq!(binding.base_object, card.object);
            assert_ne!(binding.base_revision, staged.bindings[0].base_revision);
            let met = card_in(after, id, "r1.vcf");
            match id {
                "work/contacts" => assert!(!met.bindings[0].conflicted, "a body listed"),
                _ => assert!(
                    met.bindings[0].conflicted,
                    "a body unread until the upgrade"
                ),
            }
        }
    }
}
