//! # Profiles
//!
//! What a seed is drawn into. A profile fixes the shape of a store and the
//! cases it must hold; the seed chooses its surface (names, subjects,
//! dates, counts within bounds).

use std::collections::BTreeSet;

use crate::{
    body::{Card, Document, Event, Journal, Mail, Person, Task, Time},
    model::{Collection, Kind, Model, Placement},
    rng::Rng,
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
    pub fn generate(&self, seed: u64) -> Model {
        match self {
            Self::Structure => Draw::new(seed).structure(),
        }
    }
}

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

    fn structure(mut self) -> Model {
        let mut model = Model::new();

        let mailboxes = [
            ("work/INBOX", Some("work"), "INBOX", Some("inbox")),
            ("work/Archive", Some("work"), "Archive", Some("archive")),
            ("work/Sent Items", Some("work"), "Sent Items", Some("sent")),
            ("work/Empty", Some("work"), "Empty", None),
            ("home/INBOX", Some("home"), "INBOX", Some("inbox")),
        ];
        for (id, account, name, role) in mailboxes {
            model.declare(collection(
                id,
                account,
                Kind::Mail,
                name,
                role,
                Some("imap"),
            ));
        }
        model.declare(collection(
            "work/contacts",
            Some("work"),
            Kind::Contact,
            "Contacts",
            Some("default"),
            Some("carddav"),
        ));
        model.declare(collection(
            "work/calendar",
            Some("work"),
            Kind::Calendar,
            "Calendar",
            Some("default"),
            Some("caldav"),
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
        model
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

        let keyworded = self.message(true);
        let mut placement = self.placement(true);
        placement.flags = Some(BTreeSet::from([
            String::from("\\Seen"),
            String::from("\\seen"),
            String::from("$Important"),
            String::from("$label1"),
        ]));
        model.file("home/INBOX", keyworded.file(), placement);
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
        model.file("work/contacts", listed.file(), placement);
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
