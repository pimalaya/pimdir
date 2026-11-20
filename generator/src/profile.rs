//! # Profiles
//!
//! What a seed is drawn into. A profile fixes the shape of a store and the
//! cases it must hold; the seed chooses its surface (names, subjects,
//! dates, counts within bounds).

use std::{collections::BTreeSet, fs};

use rusqlite::types::Value;
use serde_json::{Value as Json, json};

use crate::{
    body::{Card, Document, Event, Filed, Journal, Mail, Person, Task, Time},
    error::{Error, Result},
    fixture,
    model::{
        Capability, Collection, Item, Kind, Model, Placement, Reference, Refusal, State, Summary,
        Table,
    },
    name::ObjectName,
    queue::{Action, Outcome, RowState},
    rng::Rng,
    spec::Spec,
    time::Instant,
};

/// A profile a seed is drawn under.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Profile {
    /// Every case of the catalogue once, small (README.md, "Profiles").
    Structure,
}

impl Profile {
    /// The store a seed gives under this profile.
    pub fn generate(&self, spec: &Spec, seed: u64) -> Result<Model> {
        match self {
            Self::Structure => Draw::new(seed).structure(spec),
        }
    }
}

/// The lab account's attachments collection (STORAGE §14.3).
const STAND_INS: &str = "lab/\u{1}attachments";

const FIRST: [&str; 12] = [
    "Alice", "Bob", "Carol", "Dave", "Erin", "Frank", "Gina", "Hugo", "Ines", "Jules", "Karim",
    "Lena",
];
const LAST: [&str; 8] = [
    "Martin", "Bernard", "Dubois", "Petit", "Durand", "Leroy", "Moreau", "Simon",
];
const WORDS: [&str; 24] = [
    "sync", "notes", "budget", "review", "plan", "release", "draft", "invoice", "meeting",
    "garden", "trip", "report", "lunch", "design", "audit", "backup", "server", "family", "music",
    "school", "project", "weekly", "summer", "update",
];
const DOMAINS: [&str; 3] = ["example.org", "example.com", "example.net"];

struct Draw {
    rng: Rng,
    run: String,
    counter: u32,
}

impl Draw {
    fn new(seed: u64) -> Self {
        Self {
            rng: Rng::new(seed, 0x7069_6d64_6972),
            run: format!("structure-{seed}"),
            counter: 0,
        }
    }

    fn structure(mut self, spec: &Spec) -> Result<Model> {
        let mut model = Model::new();

        let mailboxes = [
            ("work/INBOX", Some("work"), "INBOX", Some("inbox")),
            ("work/Archive", Some("work"), "Archive", Some("archive")),
            ("work/Sent Items", Some("work"), "Sent Items", Some("sent")),
            ("work/Empty", Some("work"), "Empty", None),
            ("home/INBOX", Some("home"), "INBOX", Some("inbox")),
        ];
        for (id, account, name, role) in mailboxes {
            let source = format!("{}-imap", account.unwrap_or("local"));
            model.declare(collection(
                id,
                account,
                Kind::Mail,
                name,
                role,
                Some(&source),
            ));
        }
        model.declare(collection(
            "work/contacts",
            Some("work"),
            Kind::Contact,
            "Contacts",
            Some("default"),
            Some("work-carddav"),
        ));
        model.declare(collection(
            "work/calendar",
            Some("work"),
            Kind::Calendar,
            "Calendar",
            Some("default"),
            Some("work-caldav"),
        ));
        model.declare(collection(
            "work/holidays",
            Some("work"),
            Kind::Calendar,
            "Holidays",
            None,
            Some("work-caldav"),
        ));
        model.declare(collection(
            "home/folder:0f",
            Some("home"),
            Kind::File,
            "Papers",
            None,
            None,
        ));
        model.declare(Collection {
            id: String::from("home/x-vlist"),
            account: Some(String::from("home")),
            kind: None,
            name: String::from("home/x-vlist"),
            role: None,
            source: None,
            checkpoint: None,
        });

        self.mail(&mut model);
        self.contacts(&mut model);
        self.calendar(&mut model);
        self.files(&mut model);
        self.fixtures(&mut model, spec)?;
        self.conflicts(&mut model);
        self.capabilities(&mut model);
        self.references(&mut model);
        self.queue(&mut model, spec)?;
        Ok(model)
    }

    fn fixtures(&mut self, model: &mut Model, spec: &Spec) -> Result<()> {
        for (id, kind, source) in [
            ("lab/INBOX", Kind::Mail, "lab-imap"),
            ("lab/contacts", Kind::Contact, "lab-carddav"),
            ("lab/calendar", Kind::Calendar, "lab-caldav"),
        ] {
            model.declare(collection(id, Some("lab"), kind, id, None, Some(source)));
        }
        model.declare(Collection {
            id: String::from(STAND_INS),
            account: Some(String::from("lab")),
            kind: Some(Kind::File),
            name: String::from("attachments"),
            role: Some(String::from("attachments")),
            source: None,
            checkpoint: None,
        });

        for fixture in fixture::load(spec)? {
            let (collection, placement) = match fixture.filed.summary.table.kind() {
                Kind::Mail => ("lab/INBOX", self.placement(true)),
                Kind::Contact => ("lab/contacts", self.mutable_placement(true)),
                _ => ("lab/calendar", self.mutable_placement(true)),
            };
            let index = model.file(collection, fixture.filed, placement);
            let link_id = model.items[index].link_id.clone();
            if link_id != fixture.link_id {
                return Err(Error::Disagreement {
                    what: format!("the key of {}", fixture.path),
                    detail: format!(
                        "the model files it {link_id}, summaries.json {}",
                        fixture.link_id
                    ),
                });
            }

            let derived = ["alt:", "dup:", "hash:"]
                .iter()
                .any(|prefix| link_id.starts_with(prefix));
            if derived || fixture.attachments.is_empty() || fixture.attachments.len() > 10 {
                continue;
            }
            let message = link_id.clone();
            for attachment in fixture.attachments {
                let mut summary = Summary::new(Table::File);
                summary.set("name", Value::Text(attachment.name.clone()));
                summary.set(
                    "media_type",
                    attachment
                        .media_type
                        .clone()
                        .map_or(Value::Null, Value::Text),
                );
                summary.set("size", attachment.size.map_or(Value::Null, Value::Integer));
                summary.set("part", Value::Text(attachment.part.clone()));
                let key = format!("part:{message}#{}", attachment.part);
                let filed = Filed {
                    bytes: Vec::new(),
                    hint: None,
                    summary,
                    addresses: Vec::new(),
                    sort_key: String::from(attachment.name.to_lowercase().trim()),
                    fallback: Some(key.clone()),
                };
                let placement = Placement {
                    flags: Some(BTreeSet::new()),
                    held: false,
                    handle: None,
                    revision: None,
                };
                model.file(STAND_INS, filed, placement);
                model.references.push(Reference {
                    from_kind: Kind::Mail,
                    from_link_id: message.clone(),
                    to_kind: Kind::File,
                    to_link_id: key,
                    role: String::from("attachment"),
                    origin: String::from("auto"),
                });
            }
        }

        let saved = model
            .items
            .iter()
            .find(|item| item.collection == STAND_INS)
            .map(|item| {
                (
                    item.link_id.clone(),
                    item.summary.clone(),
                    item.sort_key.clone(),
                )
            })
            .expect("a stand-in");
        model.declare(collection(
            "lab/folder:saved",
            Some("lab"),
            Kind::File,
            "Saved",
            None,
            None,
        ));
        let (key, mut summary, sort_key) = saved;
        let bytes = self.bytes(48);
        summary.set("size", Value::Integer(bytes.len() as i64));
        let filed = Filed {
            bytes,
            hint: None,
            summary,
            addresses: Vec::new(),
            sort_key,
            fallback: Some(key),
        };
        let placement = Placement {
            flags: Some(BTreeSet::new()),
            held: true,
            handle: None,
            revision: None,
        };
        model.file("lab/folder:saved", filed, placement);
        Ok(())
    }

    fn mail(&mut self, model: &mut Model) {
        let mut shared = None;
        for mailbox in [
            "work/INBOX",
            "work/Archive",
            "work/Sent Items",
            "home/INBOX",
        ] {
            let count = 4 + self.rng.below(5);
            for _ in 0..count {
                let mail = self.message(true);
                if shared.is_none() && mailbox == "work/INBOX" {
                    shared = Some(mail.clone());
                }
                let placement = self.placement(true);
                model.file(mailbox, mail.file(), placement);
            }
        }

        let filed_twice = shared.expect("a message in work/INBOX");
        let placement = self.placement(true);
        model.file("work/Archive", filed_twice.file(), placement);

        let mut reused = filed_twice.clone();
        reused.subject = format!("{} again", reused.subject);
        let placement = self.placement(true);
        model.file("work/Archive", reused.file(), placement);

        let mut doubled = self.message(true);
        let placement = self.placement(true);
        model.file("work/INBOX", doubled.file(), placement);
        doubled.text.push_str(" (resent)");
        let placement = self.placement(true);
        model.file("work/INBOX", doubled.file(), placement);

        let mut anonymous = self.message(false);
        anonymous.message_id = None;
        let placement = self.placement(true);
        model.file("work/INBOX", anonymous.file(), placement);

        let mut undated = self.message(false);
        undated.date = None;
        let placement = self.placement(true);
        model.file("work/INBOX", undated.file(), placement);

        let mut attached = self.message(false);
        attached.attachment = Some((String::from("report.pdf"), self.bytes(300)));
        let placement = self.placement(true);
        model.file("work/INBOX", attached.file(), placement);

        let listed = self.message(true);
        let mut placement = self.placement(false);
        placement.flags = None;
        model.file("work/INBOX", listed.file(), placement);

        let deleted = self.message(false);
        let placement = self.placement(true);
        let index = model.file("work/INBOX", deleted.file(), placement);
        model.tombstone(index);

        let gone = self.message(false);
        let placement = self.placement(true);
        let index = model.file("work/Archive", gone.file(), placement);
        model.retain(index);

        let keyworded = self.message(true);
        let mut placement = self.placement(true);
        placement.flags = Some(BTreeSet::from([
            String::from("\\Seen"),
            String::from("\\seen"),
            String::from("$Important"),
            String::from("$label1"),
        ]));
        model.file("home/INBOX", keyworded.file(), placement);

        let mut reply = self.message(false);
        reply.in_reply_to = vec![filed_twice.message_id.clone().unwrap_or_default()];
        let placement = self.placement(true);
        model.file("work/INBOX", reply.file(), placement);

        let mut sent_reply = self.message(false);
        sent_reply.in_reply_to = vec![String::from("only-from-sent@pimdir.test")];
        let placement = self.placement(true);
        model.file("work/Sent Items", sent_reply.file(), placement);

        let mut twice = self.message(false);
        let person = self.person();
        twice.to = vec![person.clone(), person];
        let placement = self.placement(true);
        model.file("home/INBOX", twice.file(), placement);
    }

    fn contacts(&mut self, model: &mut Model) {
        let count = 4 + self.rng.below(4);
        for _ in 0..count {
            let card = self.card();
            let placement = self.mutable_placement(true);
            model.file("work/contacts", card.file(), placement);
        }

        let mut without_uid = self.card();
        without_uid.uid = None;
        let placement = self.mutable_placement(true);
        model.file("work/contacts", without_uid.file(), placement);

        let mut reserved = self.card();
        reserved.uid = Some(String::from("hash:0123456789abcdef"));
        let placement = self.mutable_placement(true);
        model.file("work/contacts", reserved.file(), placement);

        let listed = self.card();
        let placement = self.mutable_placement(false);
        let index = model.file("work/contacts", listed.file(), placement);
        model.retain(index);

        let kept = self.card();
        let placement = self.mutable_placement(true);
        let index = model.file("work/contacts", kept.file(), placement);
        model.retain(index);
    }

    fn calendar(&mut self, model: &mut Model) {
        let starts = [
            Time::Utc(self.instant()),
            Time::Floating(self.instant()),
            Time::Date(self.instant().midnight()),
        ];
        for start in starts {
            let event = self.event(start);
            let placement = self.mutable_placement(true);
            model.file("work/calendar", event.file(), placement);
        }

        let start = Time::Utc(self.instant());
        let mut series = self.event(start);
        series.until = Some(Instant(self.instant().0 + 90 * 86_400));
        series.organizer = Some(self.person());
        series.attendees = vec![self.person(), self.person()];
        let placement = self.mutable_placement(true);
        model.file("work/calendar", series.file(), placement);

        for due in [Some(Time::Utc(self.instant())), None] {
            let task = Task {
                uid: Some(self.uid()),
                summary: self.phrase(3),
                due,
                status: Some(String::from("NEEDS-ACTION")),
                priority: Some(i64::from(self.rng.below(10))),
                categories: vec![String::from("inbox"), self.phrase(1)],
                created: due.map(|_| self.instant()),
                run: self.run.clone(),
            };
            let placement = self.mutable_placement(true);
            model.file("work/calendar", task.file(), placement);
        }

        let journal = Journal {
            uid: Some(self.uid()),
            summary: self.phrase(2),
            start: Some(Time::Date(self.instant().midnight())),
            run: self.run.clone(),
        };
        let placement = self.mutable_placement(true);
        model.file("work/calendar", journal.file(), placement);
    }

    fn files(&mut self, model: &mut Model) {
        for name in ["Tax return.pdf", "notes.txt", "Zebra.png"] {
            let document = Document {
                name: String::from(name),
                media_type: Some(String::from("application/octet-stream")),
                bytes: self.bytes(64),
                key: format!("file:{:016x}{:016x}", self.u64(), self.u64()),
            };
            let placement = Placement {
                flags: Some(BTreeSet::new()),
                held: true,
                handle: None,
                revision: None,
            };
            model.file("home/folder:0f", document.file(), placement);
        }
    }

    fn conflicts(&mut self, model: &mut Model) {
        let cards: Vec<usize> = (0..model.items.len())
            .filter(|index| {
                let item = &model.items[*index];
                item.collection == "work/contacts"
                    && item.state == State::Live
                    && item.object.is_some()
                    && item.binding.is_some()
            })
            .collect();

        let diverging = self.card().file().bytes;
        let name = ObjectName::of(&diverging);
        model.objects.insert(name.clone(), diverging);
        let item = &mut model.items[cards[0]];
        item.conflicted = true;
        item.conflict_object = Some(name.clone());

        let binding = model.items[cards[1]]
            .binding
            .as_mut()
            .expect("a bound card");
        binding.conflicted = true;
        binding.conflict_revision = Some(String::from("\"etag-diverged\""));
        binding.conflict_object = Some(name);

        let binding = model.items[cards[2]]
            .binding
            .as_mut()
            .expect("a bound card");
        binding.conflicted = true;
        binding.conflict_revision = Some(String::from("\"etag-unread\""));
    }

    fn capabilities(&mut self, model: &mut Model) {
        let mail = [
            "mail.message.add",
            "mail.message.copy",
            "mail.message.move",
            "mail.message.remove",
            "mail.flags.seen",
            "mail.flags.flagged",
            "mail.flags.answered",
            "mail.flags.draft",
            "mail.flags.keywords",
            "mail.submit",
            "mail.submit.copy",
        ];
        let contacts = [
            "contacts.card.add",
            "contacts.card.update",
            "contacts.card.remove",
            "contacts.card.move",
            "contacts.card.copy",
        ];
        let calendar = [
            "calendar.item.add",
            "calendar.item.update",
            "calendar.item.remove",
            "calendar.item.move",
            "calendar.item.copy",
            "calendar.occurrence.update",
            "calendar.scheduling",
            "calendar.online-meeting",
            "calendar.reply",
            "calendar.reply.occurrence",
            "calendar.cancel",
            "calendar.cancel.occurrence",
        ];
        let collections = [
            "collection.create",
            "collection.rename",
            "collection.delete",
        ];
        let gaps: [(&str, &str, &str); 7] = [
            (
                "work-imap",
                "mail.message.copy",
                "the server offers no copy",
            ),
            ("work-imap", "mail.flags.junk", "junk is a folder there"),
            ("work-imap", "collection.create", "the account is paired"),
            (
                "work-caldav",
                "calendar.scheduling",
                "the server notifies nobody",
            ),
            (
                "work-caldav",
                "calendar.online-meeting",
                "no meeting provider",
            ),
            (
                "work-caldav",
                "calendar.reply.occurrence",
                "replies to a whole series",
            ),
            (
                "work-caldav",
                "calendar.cancel.occurrence",
                "cancels a whole series",
            ),
        ];

        let sources = [
            ("work", "work-imap", &mail[..]),
            ("home", "home-imap", &mail[..]),
            ("work", "work-carddav", &contacts[..]),
            ("work", "work-caldav", &calendar[..]),
        ];
        for (account, source, names) in sources {
            for name in names.iter().chain(collections.iter()) {
                let gap = gaps
                    .iter()
                    .find(|(at, gap, _)| *at == source && gap == name);
                model.capabilities.push(Capability {
                    account: Some(String::from(account)),
                    source: String::from(source),
                    collection: None,
                    name: String::from(*name),
                    support: String::from(if gap.is_some() { "none" } else { "full" }),
                    detail: gap.map(|(_, _, detail)| String::from(*detail)),
                });
            }
        }
        for (source, collection, name, support, detail) in [
            (
                "work-imap",
                "work/INBOX",
                "mail.flags.keywords",
                "partial",
                Some("keywords become labels"),
            ),
            (
                "work-imap",
                "work/Empty",
                "mail.message.add",
                "none",
                Some("a reserved folder"),
            ),
            ("work-imap", "work/Empty", "mail.flags.junk", "full", None),
            (
                "work-caldav",
                "work/calendar",
                "calendar.component.vtodo",
                "full",
                None,
            ),
        ] {
            model.capabilities.push(Capability {
                account: Some(String::from("work")),
                source: String::from(source),
                collection: Some(String::from(collection)),
                name: String::from(name),
                support: String::from(support),
                detail: detail.map(String::from),
            });
        }
        model.performers.insert(
            (Some(String::from("work")), String::from("mail.submit")),
            String::from("work-imap"),
        );
    }

    fn references(&mut self, model: &mut Model) {
        let first = |collection: &str| {
            model
                .items
                .iter()
                .find(|item| {
                    item.collection == collection
                        && !["alt:", "dup:", "hash:"]
                            .iter()
                            .any(|prefix| item.link_id.starts_with(prefix))
                })
                .map(|item| item.link_id.clone())
                .expect("an item of its own key")
        };
        let card = first("work/contacts");
        let message = first("work/INBOX");
        let retained = model
            .items
            .iter()
            .find(|item| {
                matches!(item.state, State::Retained { .. }) && item.collection == "work/Archive"
            })
            .map(|item| item.link_id.clone())
            .expect("a retained message");
        let event = first("work/calendar");
        for (from_kind, from, to_kind, to, role, origin) in [
            (
                Kind::Contact,
                card.clone(),
                Kind::Mail,
                message.clone(),
                "related",
                "user",
            ),
            (
                Kind::Mail,
                message.clone(),
                Kind::Contact,
                card.clone(),
                "sender",
                "auto",
            ),
            (Kind::Contact, card, Kind::Mail, retained, "related", "user"),
            (
                Kind::Calendar,
                event,
                Kind::Mail,
                message,
                "x-generator-note",
                "user",
            ),
        ] {
            model.references.push(Reference {
                from_kind,
                from_link_id: from,
                to_kind,
                to_link_id: to,
                role: String::from(role),
                origin: String::from(origin),
            });
        }
    }

    fn queue(&mut self, model: &mut Model, spec: &Spec) -> Result<()> {
        let pick = |model: &Model, collection: &str, skip: usize, test: &dyn Fn(&Item) -> bool| {
            model
                .items
                .iter()
                .filter(|item| {
                    item.collection == collection && item.state == State::Live && test(item)
                })
                .nth(skip)
                .map(|item| (item.seq, item.flags.clone(), item.object.clone()))
        };
        let known = |item: &Item| item.flags.is_some() && item.binding.is_some();
        let unknown = |item: &Item| item.flags.is_none();
        let free = |item: &Item| {
            !item.conflicted
                && item
                    .binding
                    .as_ref()
                    .is_some_and(|binding| !binding.conflicted)
        };
        let any = |_: &Item| true;

        let (seq, flags, _) = pick(model, "work/INBOX", 0, &known).expect("a message");
        let base = flags.unwrap_or_default();
        let mut read = base.clone();
        read.insert(String::from("\\Seen"));
        model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::SetFlags {
                seq,
                flags: read,
                base: Some(base),
            },
        );

        let (seq, ..) = pick(model, "work/INBOX", 1, &known).expect("a message");
        let flagged = BTreeSet::from([String::from("\\Flagged")]);
        model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::SetFlags {
                seq,
                flags: flagged.clone(),
                base: None,
            },
        );

        let (seq, ..) = pick(model, "work/INBOX", 0, &unknown).expect("a listed message");
        model.enqueue(
            "x-tagger",
            "work/INBOX",
            Action::SetFlags {
                seq,
                flags: flagged.clone(),
                base: Some(BTreeSet::new()),
            },
        );

        let (seq, ..) = pick(model, "work/INBOX", 2, &known).expect("a message");
        let to = String::from("work/Archive");
        model.enqueue("himalaya", "work/INBOX", Action::Move { seq, to });
        let (seq, ..) = pick(model, "work/INBOX", 3, &known).expect("a message");
        let to = String::from("home/INBOX");
        let id = model.enqueue("himalaya", "work/INBOX", Action::Copy { seq, to });
        model.drain(id);
        let (seq, ..) = pick(model, "work/INBOX", 4, &known).expect("a message");
        let to = String::from("work/INBOX");
        let id = model.enqueue("himalaya", "work/INBOX", Action::Move { seq, to });
        model.drain(id);

        let (seq, ..) = pick(model, "work/Archive", 0, &known).expect("a message");
        let id = model.enqueue(
            "himalaya",
            "work/Archive",
            Action::SetFlags {
                seq,
                flags: flagged,
                base: None,
            },
        );
        model.drain(id);
        let (seq, ..) = pick(model, "work/Archive", 1, &known).expect("a message");
        let id = model.enqueue(
            "himalaya",
            "work/Archive",
            Action::Remove {
                seq,
                if_match: None,
            },
        );
        model.drain(id);

        let seen = BTreeSet::from([String::from("\\Seen")]);
        let sent = self.message(false);
        let filed = sent.file();
        let link_id = sent.message_id.clone().unwrap_or_default();
        let id = model.enqueue(
            "himalaya",
            "work/Sent Items",
            Action::Add {
                link_id,
                flags: seen.clone(),
                filed,
            },
        );
        if let Outcome::Applied(Some(seq)) = model.drain(id) {
            let created = model
                .items
                .iter_mut()
                .find(|item| item.collection == "work/Sent Items" && item.seq == seq)
                .and_then(|item| item.binding.as_mut());
            if let Some(binding) = created {
                binding.refusal = Some(Refusal {
                    reason: String::from("the server takes appends into its drafts folder alone"),
                    key: format!("{:016x}", self.u64()),
                });
            }
        }

        for state in [
            RowState::Pending,
            RowState::Unconfirmed(String::from(
                "the connection dropped after the message was handed over",
            )),
            RowState::Applied(None),
        ] {
            let mail = self.message(false);
            let rcpts: Vec<&String> = mail.to.iter().map(|person| &person.address).collect();
            let payload = json!({
                "v": 1,
                "source": "work-imap",
                "from": mail.from.address,
                "rcpts": rcpts,
                "subject": mail.subject,
                "copy": "work/Sent Items",
            });
            let body = mail.file().bytes;
            let applied = state == RowState::Applied(None);
            let id = model.enqueue(
                "himalaya",
                "work/Sent Items",
                Action::Intent {
                    action: String::from("submit"),
                    payload,
                    body: Some(body.clone()),
                },
            );
            model.settle(id, state);
            if applied {
                let mut filed = mail.file();
                filed.bytes = body;
                let link_id = mail.message_id.clone().unwrap_or_default();
                model.enqueue(
                    "neverest",
                    "work/Sent Items",
                    Action::Add {
                        link_id,
                        flags: seen.clone(),
                        filed,
                    },
                );
            }
        }
        let payload = json!({ "v": 1, "source": "work-imap", "name": "Projects" });
        model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::Intent {
                action: String::from("collection-create"),
                payload,
                body: None,
            },
        );

        let card = self.card();
        let link_id = card.uid.clone().unwrap_or_default();
        model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Add {
                link_id,
                flags: BTreeSet::new(),
                filed: card.file(),
            },
        );

        let (seq, _, object) = pick(model, "work/contacts", 0, &free).expect("a card");
        let mut edited = self.card();
        edited.uid = model
            .items
            .iter()
            .find(|item| item.collection == "work/contacts" && item.seq == seq)
            .and_then(|item| match item.summary.get("uid") {
                Value::Text(uid) => Some(uid),
                _ => None,
            });
        let first = edited.file();
        let first_name = ObjectName::of(&first.bytes);
        model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: first,
                if_match: object.clone(),
            },
        );
        edited.name = format!("{} Junior", edited.name);
        model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: edited.file(),
                if_match: Some(first_name),
            },
        );
        edited.name = String::from("Stale Edit");
        model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: edited.file(),
                if_match: object,
            },
        );

        let (seq, _, object) = pick(model, "work/contacts", 1, &free).expect("a card");
        model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Remove {
                seq,
                if_match: object,
            },
        );

        let (seq, _, object) = pick(model, "work/contacts", 0, &|item: &Item| item.conflicted)
            .expect("a conflicted card");
        let mut over = self.card();
        over.name = String::from("Over A Conflict");
        model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: over.file(),
                if_match: object,
            },
        );

        let start = Time::Utc(self.instant());
        let event = self.event(start);
        let link_id = event.uid.clone().unwrap_or_default();
        model.enqueue(
            "calendula",
            "work/calendar",
            Action::Add {
                link_id,
                flags: BTreeSet::new(),
                filed: event.file(),
            },
        );
        let (seq, ..) = pick(model, "work/calendar", 0, &any).expect("an event");
        let payload =
            json!({ "v": 1, "source": "work-caldav", "seq": seq, "partstat": "ACCEPTED" });
        model.enqueue(
            "calendula",
            "work/calendar",
            Action::Intent {
                action: String::from("calendar-reply"),
                payload,
                body: None,
            },
        );

        let (seq, ..) = pick(model, "work/calendar", 0, &|item: &Item| {
            item.addresses
                .iter()
                .any(|address| address.role == "attendee")
        })
        .expect("a scheduled series");
        model.enqueue(
            "calendula",
            "work/calendar",
            Action::Remove {
                seq,
                if_match: None,
            },
        );

        let task = Task {
            uid: Some(self.uid()),
            summary: self.phrase(2),
            due: None,
            status: None,
            priority: None,
            categories: Vec::new(),
            created: None,
            run: self.run.clone(),
        };
        let link_id = task.uid.clone().unwrap_or_default();
        let id = model.enqueue(
            "unfog",
            "work/holidays",
            Action::Add {
                link_id,
                flags: BTreeSet::new(),
                filed: task.file(),
            },
        );
        model.drain(id);
        for (collection, capability, source, drained) in [
            ("work/calendar", "calendar.reply", Some("work-caldav"), true),
            ("work/INBOX", "mail.submit", Some("work-caldav"), true),
            ("work/INBOX", "mail.submit", Some("work-imap"), false),
        ] {
            let id = model.enqueue(
                "himalaya",
                collection,
                Action::SetPerformer {
                    capability: String::from(capability),
                    source: source.map(String::from),
                },
            );
            if drained {
                model.drain(id);
            }
        }

        let (seq, ..) = pick(model, "home/folder:0f", 0, &any).expect("a file");
        let keep = BTreeSet::from([String::from("$keep")]);
        model.enqueue(
            "x-files",
            "home/folder:0f",
            Action::SetFlags {
                seq,
                flags: keep,
                base: None,
            },
        );

        let raw = payload_cases(spec)?;
        for (index, (action, payload, malformed)) in raw.into_iter().enumerate() {
            let id = model.enqueue(
                "x-app",
                "home/INBOX",
                Action::Raw {
                    action,
                    payload,
                    malformed,
                },
            );
            if index % 2 == 1 {
                model.drain(id);
            }
        }
        let payload = json!({ "v": 1, "note": "an application's own action" });
        model.enqueue(
            "x-app",
            "home/INBOX",
            Action::Raw {
                action: String::from("x-app-archive"),
                payload,
                malformed: false,
            },
        );

        Ok(())
    }

    fn message(&mut self, cc: bool) -> Mail {
        let domain = self.pick(&DOMAINS);
        Mail {
            message_id: Some(format!("{}.{}@{domain}", self.phrase(1), self.next())),
            subject: self.subject(),
            from: self.person(),
            to: vec![self.person()],
            cc: if cc && self.rng.below(2) == 0 {
                vec![self.person()]
            } else {
                Vec::new()
            },
            date: Some(self.instant()),
            in_reply_to: Vec::new(),
            text: self.phrase(12),
            attachment: None,
            run: self.run.clone(),
        }
    }

    fn card(&mut self) -> Card {
        let person = self.person();
        Card {
            uid: Some(self.uid()),
            name: person.name.unwrap_or_default(),
            kind: Some(String::from("individual")),
            org: (self.rng.below(2) == 0).then(|| String::from("Pimalaya")),
            emails: vec![person.address],
            run: self.run.clone(),
        }
    }

    fn event(&mut self, start: Time) -> Event {
        let end = match start {
            Time::Utc(at) => Some(Time::Utc(Instant(at.0 + 1800))),
            Time::Floating(at) => Some(Time::Floating(Instant(at.0 + 3600))),
            Time::Date(at) => Some(Time::Date(Instant(at.0 + 86_400))),
        };
        Event {
            uid: Some(self.uid()),
            summary: self.subject(),
            location: (self.rng.below(2) == 0).then(|| format!("Room {}", self.rng.below(9) + 1)),
            start,
            end,
            until: None,
            organizer: None,
            attendees: Vec::new(),
            run: self.run.clone(),
        }
    }

    fn placement(&mut self, held: bool) -> Placement {
        let mut flags = BTreeSet::new();
        if self.rng.below(3) > 0 {
            flags.insert(String::from("\\Seen"));
        }
        if self.rng.below(5) == 0 {
            flags.insert(String::from("\\Flagged"));
        }
        Placement {
            flags: Some(flags),
            held,
            handle: Some(self.next().to_string()),
            revision: None,
        }
    }

    fn mutable_placement(&mut self, held: bool) -> Placement {
        let handle = self.next();
        Placement {
            flags: Some(BTreeSet::new()),
            held,
            handle: Some(format!("{handle}.ics")),
            revision: Some(format!("\"etag-{handle}\"")),
        }
    }

    fn person(&mut self) -> Person {
        let first = self.pick(&FIRST);
        let last = self.pick(&LAST);
        let domain = self.pick(&DOMAINS);
        Person {
            name: Some(format!("{first} {last}")),
            address: format!("{}.{}@{domain}", first.to_lowercase(), last.to_lowercase()),
        }
    }

    fn subject(&mut self) -> String {
        let words = 1 + self.rng.below(4) as usize;
        let mut subject = self.phrase(words);
        subject[..1].make_ascii_uppercase();
        subject
    }

    fn phrase(&mut self, words: usize) -> String {
        (0..words)
            .map(|_| self.pick(&WORDS))
            .collect::<Vec<_>>()
            .join(" ")
    }

    fn uid(&mut self) -> String {
        format!("{:08x}-{}@pimdir.test", self.rng.next_u32(), self.next())
    }

    fn instant(&mut self) -> Instant {
        let start = Instant::at(2026, 1, 1, 0, 0, 0);
        Instant(start.0 + i64::from(self.rng.below(365 * 86_400)))
    }

    fn bytes(&mut self, len: usize) -> Vec<u8> {
        (0..len).map(|_| self.rng.next_u32() as u8).collect()
    }

    fn u64(&mut self) -> u64 {
        (u64::from(self.rng.next_u32()) << 32) | u64::from(self.rng.next_u32())
    }

    fn pick(&mut self, list: &[&'static str]) -> &'static str {
        list[self.rng.below(list.len() as u32) as usize]
    }

    fn next(&mut self) -> u32 {
        self.counter += 1;
        self.counter
    }
}

fn collection(
    id: &str,
    account: Option<&str>,
    kind: Kind,
    name: &str,
    role: Option<&str>,
    source: Option<&str>,
) -> Collection {
    Collection {
        id: String::from(id),
        account: account.map(String::from),
        kind: Some(kind),
        name: String::from(name),
        role: role.map(String::from),
        source: source.map(String::from),
        checkpoint: source.map(|_| b"c1".to_vec()),
    }
}

/// Malformed and unknown payloads of store actions from
/// vectors/payloads.json, with whether each is malformed.
fn payload_cases(spec: &Spec) -> Result<Vec<(String, Json, bool)>> {
    let path = spec.root.join("vectors/payloads.json");
    let text = fs::read_to_string(&path).map_err(|source| Error::Io {
        path: path.clone(),
        source,
    })?;
    let payloads: Json =
        serde_json::from_str(&text).map_err(|source| Error::Json { path, source })?;

    let store = ["add", "set-flags", "remove", "move", "copy", "update"];
    let cases = payloads["cases"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|case| store.contains(&case["action"].as_str().unwrap_or_default()))
        .filter_map(|case| {
            let malformed = match case["outcome"].as_str() {
                Some("malformed") => true,
                Some("unknown") => false,
                _ => return None,
            };
            Some((
                String::from(case["action"].as_str().unwrap_or_default()),
                case["payload"].clone(),
                malformed,
            ))
        })
        .collect();
    Ok(cases)
}
