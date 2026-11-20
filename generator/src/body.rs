//! # Surface bodies
//!
//! Bodies rendered from the model in a form whose STORAGE Annex A
//! derivation is the value the model drew: ASCII header fields written
//! once and unfolded, dates in UTC at whole seconds, addresses already
//! canonical, iCalendar and vCard values needing no escape. Each renderer
//! answers the bytes and what Annex A derives from them, never by parsing.

use rusqlite::types::Value;

use crate::{
    model::{Address, Summary, Table},
    time::Instant,
};

/// A body and what Annex A derives from it.
#[derive(Clone, Debug)]
pub struct Filed {
    /// The bytes.
    pub bytes: Vec<u8>,
    /// The identity hint the content declares, `None` when it declares
    /// none usable (STORAGE §9).
    pub hint: Option<String>,
    /// The summary row and its lists.
    pub summary: Summary,
    /// The address rows.
    pub addresses: Vec<Address>,
    /// The sort key (STORAGE §9.3).
    pub sort_key: String,
    /// The key a writer gives content stating no hint, where the kind's
    /// fallback is not derived from the bytes (a file's `file:` key).
    pub fallback: Option<String>,
}

/// A person a body names.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Person {
    /// The display name, ASCII letters and spaces, or none.
    pub name: Option<String>,
    /// The canonical addr-spec.
    pub address: String,
}

/// A message (STORAGE Annex A.1).
#[derive(Clone, Debug)]
pub struct Mail {
    /// The bare `Message-ID`, or none.
    pub message_id: Option<String>,
    /// The `Subject`, ASCII words.
    pub subject: String,
    /// The one `From` mailbox.
    pub from: Person,
    /// The `To` mailboxes.
    pub to: Vec<Person>,
    /// The `Cc` mailboxes.
    pub cc: Vec<Person>,
    /// The `Date`, or none.
    pub date: Option<Instant>,
    /// The bare `In-Reply-To` ids.
    pub in_reply_to: Vec<String>,
    /// The text of its body.
    pub text: String,
    /// One attached file, its name and bytes.
    pub attachment: Option<(String, Vec<u8>)>,
    /// The run-scoped mark.
    pub run: String,
}

impl Mail {
    /// Renders the message and derives its row.
    pub fn file(&self) -> Filed {
        let mut head = String::new();
        if let Some(id) = &self.message_id {
            head.push_str(&format!("Message-ID: <{id}>\r\n"));
        }
        if let Some(date) = self.date {
            head.push_str(&format!("Date: {}\r\n", date.rfc5322()));
        }
        head.push_str(&format!("From: {}\r\n", mailbox(&self.from)));
        if !self.to.is_empty() {
            let list: Vec<String> = self.to.iter().map(mailbox).collect();
            head.push_str(&format!("To: {}\r\n", list.join(", ")));
        }
        if !self.cc.is_empty() {
            let list: Vec<String> = self.cc.iter().map(mailbox).collect();
            head.push_str(&format!("Cc: {}\r\n", list.join(", ")));
        }
        head.push_str(&format!("Subject: {}\r\n", self.subject));
        if !self.in_reply_to.is_empty() {
            let list: Vec<String> = self
                .in_reply_to
                .iter()
                .map(|id| format!("<{id}>"))
                .collect();
            head.push_str(&format!("In-Reply-To: {}\r\n", list.join(" ")));
        }
        head.push_str(&format!("X-Generator-Run: {}\r\n", self.run));
        head.push_str("MIME-Version: 1.0\r\n");

        let body = match &self.attachment {
            None => format!(
                "Content-Type: text/plain; charset=utf-8\r\n\r\n{}\r\n",
                self.text
            ),
            Some((name, bytes)) => {
                let boundary = format!("part-{}", self.run);
                format!(
                    "Content-Type: multipart/mixed; boundary=\"{boundary}\"\r\n\r\n\
                     --{boundary}\r\n\
                     Content-Type: text/plain; charset=utf-8\r\n\r\n\
                     {}\r\n\
                     --{boundary}\r\n\
                     Content-Type: application/octet-stream\r\n\
                     Content-Disposition: attachment; filename=\"{name}\"\r\n\
                     Content-Transfer-Encoding: base64\r\n\r\n\
                     {}\r\n\
                     --{boundary}--\r\n",
                    self.text,
                    base64(bytes)
                )
            }
        };
        let bytes = format!("{head}{body}").into_bytes();

        let date = self.date.map(|date| date.rfc3339());
        let mut summary = Summary::new(Table::Mail);
        summary.set("message_id", text_or_null(self.message_id.as_deref()));
        summary.set("subject", Value::Text(self.subject.clone()));
        summary.set("sender", Value::Text(self.from.address.clone()));
        summary.set("sender_name", text_or_null(self.from.name.as_deref()));
        summary.set("date", text_or_null(date.as_deref()));
        summary.set("size", Value::Integer(bytes.len() as i64));
        summary.set(
            "attachment",
            Value::Integer(i64::from(self.attachment.is_some())),
        );
        summary.set("invitation", Value::Null);
        summary.in_reply_to = self.in_reply_to.clone();

        let mut addresses = vec![Address::of("from", 0, &self.from)];
        for (role, list) in [("to", &self.to), ("cc", &self.cc)] {
            for (position, person) in list.iter().enumerate() {
                addresses.push(Address::of(role, position, person));
            }
        }

        let hint = self.message_id.clone();

        Filed {
            fallback: None,
            bytes,
            hint,
            summary,
            addresses,
            sort_key: date.unwrap_or_default(),
        }
    }
}

/// A card (STORAGE Annex A.2).
#[derive(Clone, Debug)]
pub struct Card {
    /// The `UID`, or none.
    pub uid: Option<String>,
    /// The `FN`, ASCII letters and spaces.
    pub name: String,
    /// The `KIND`, lowercase, or none.
    pub kind: Option<String>,
    /// The `ORG`, one component, or none.
    pub org: Option<String>,
    /// The `EMAIL` addresses, canonical.
    pub emails: Vec<String>,
    /// The run-scoped mark.
    pub run: String,
}

impl Card {
    /// Renders the card and derives its row.
    pub fn file(&self) -> Filed {
        let mut text = String::from("BEGIN:VCARD\r\nVERSION:4.0\r\n");
        if let Some(uid) = &self.uid {
            text.push_str(&format!("UID:{uid}\r\n"));
        }
        text.push_str(&format!("FN:{}\r\n", self.name));
        if let Some(kind) = &self.kind {
            text.push_str(&format!("KIND:{kind}\r\n"));
        }
        if let Some(org) = &self.org {
            text.push_str(&format!("ORG:{org}\r\n"));
        }
        for email in &self.emails {
            text.push_str(&format!("EMAIL:{email}\r\n"));
        }
        text.push_str(&format!("X-GENERATOR-RUN:{}\r\nEND:VCARD\r\n", self.run));
        let bytes = text.into_bytes();

        let mut summary = Summary::new(Table::Contact);
        summary.set("uid", text_or_null(self.uid.as_deref()));
        summary.set("fn", Value::Text(self.name.clone()));
        summary.set("kind", text_or_null(self.kind.as_deref()));
        summary.set("org", text_or_null(self.org.as_deref()));

        let addresses = self
            .emails
            .iter()
            .enumerate()
            .map(|(position, email)| Address {
                role: String::from("email"),
                position: position as i64,
                address: email.clone(),
                name: None,
            })
            .collect();

        Filed {
            fallback: None,
            hint: usable(self.uid.as_deref()),
            sort_key: String::from(self.name.to_lowercase().trim()),
            bytes,
            summary,
            addresses,
        }
    }
}

/// A calendar time as a body writes it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Time {
    /// A UTC date-time, `Z` suffixed.
    Utc(Instant),
    /// A floating date-time, read as UTC for the sort key.
    Floating(Instant),
    /// A date, `VALUE=DATE`.
    Date(Instant),
}

impl Time {
    fn property(&self, name: &str) -> String {
        match self {
            Self::Utc(at) => format!("{name}:{}\r\n", at.ical_utc()),
            Self::Floating(at) => format!("{name}:{}\r\n", at.ical_floating()),
            Self::Date(at) => format!("{name};VALUE=DATE:{}\r\n", at.ical_date()),
        }
    }

    fn verbatim(&self) -> String {
        match self {
            Self::Utc(at) => at.ical_utc(),
            Self::Floating(at) => at.ical_floating(),
            Self::Date(at) => at.ical_date(),
        }
    }

    fn value_type(&self) -> &'static str {
        match self {
            Self::Date(_) => "date",
            _ => "date-time",
        }
    }

    fn instant(&self) -> Instant {
        match self {
            Self::Utc(at) | Self::Floating(at) => *at,
            Self::Date(at) => at.midnight(),
        }
    }
}

/// An event (STORAGE Annex A.3).
#[derive(Clone, Debug)]
pub struct Event {
    /// The `UID`, or none.
    pub uid: Option<String>,
    /// The `SUMMARY`.
    pub summary: String,
    /// The `LOCATION`, or none.
    pub location: Option<String>,
    /// The `DTSTART`.
    pub start: Time,
    /// The `DTEND`, or none.
    pub end: Option<Time>,
    /// A weekly `RRULE` and its `UNTIL`, or none.
    pub until: Option<Instant>,
    /// The `ORGANIZER`, or none.
    pub organizer: Option<Person>,
    /// The `ATTENDEE`s.
    pub attendees: Vec<Person>,
    /// The run-scoped mark.
    pub run: String,
}

impl Event {
    /// Renders the event and derives its row.
    pub fn file(&self) -> Filed {
        let mut text = calendar_head(&self.run);
        text.push_str("BEGIN:VEVENT\r\n");
        if let Some(uid) = &self.uid {
            text.push_str(&format!("UID:{uid}\r\n"));
        }
        text.push_str("DTSTAMP:20260101T000000Z\r\n");
        text.push_str(&format!("SUMMARY:{}\r\n", self.summary));
        if let Some(location) = &self.location {
            text.push_str(&format!("LOCATION:{location}\r\n"));
        }
        text.push_str(&self.start.property("DTSTART"));
        if let Some(end) = &self.end {
            text.push_str(&end.property("DTEND"));
        }
        if let Some(until) = &self.until {
            text.push_str(&format!("RRULE:FREQ=WEEKLY;UNTIL={}\r\n", until.ical_utc()));
        }
        if let Some(organizer) = &self.organizer {
            text.push_str(&format!("ORGANIZER{}\r\n", calendar_person(organizer)));
        }
        for attendee in &self.attendees {
            text.push_str(&format!("ATTENDEE{}\r\n", calendar_person(attendee)));
        }
        text.push_str("END:VEVENT\r\nEND:VCALENDAR\r\n");

        let mut summary = Summary::new(Table::Event);
        summary.set("uid", text_or_null(self.uid.as_deref()));
        summary.set("summary", Value::Text(self.summary.clone()));
        summary.set("location", text_or_null(self.location.as_deref()));
        summary.set("dtstart", Value::Text(self.start.verbatim()));
        summary.set("dtstart_tzid", Value::Null);
        summary.set(
            "dtstart_value",
            Value::Text(String::from(self.start.value_type())),
        );
        summary.set(
            "dtend",
            text_or_null(self.end.map(|end| end.verbatim()).as_deref()),
        );
        summary.set("recurring", Value::Integer(i64::from(self.until.is_some())));
        summary.set(
            "until",
            text_or_null(self.until.map(|until| until.ical_utc()).as_deref()),
        );

        let mut addresses = Vec::new();
        if let Some(organizer) = &self.organizer {
            addresses.push(Address::of("organizer", 0, organizer));
        }
        for (position, attendee) in self.attendees.iter().enumerate() {
            addresses.push(Address::of("attendee", position, attendee));
        }

        Filed {
            fallback: None,
            bytes: text.into_bytes(),
            hint: usable(self.uid.as_deref()),
            sort_key: self.start.instant().rfc3339(),
            summary,
            addresses,
        }
    }
}

/// A task (STORAGE Annex A.4).
#[derive(Clone, Debug)]
pub struct Task {
    /// The `UID`, or none.
    pub uid: Option<String>,
    /// The `SUMMARY`.
    pub summary: String,
    /// The `DUE`, or none.
    pub due: Option<Time>,
    /// The `STATUS`, uppercase, or none.
    pub status: Option<String>,
    /// The `PRIORITY`, 0 to 9, or none.
    pub priority: Option<i64>,
    /// The `CATEGORIES` values, one property.
    pub categories: Vec<String>,
    /// The `CREATED`, or none, `DTSTAMP` then standing for it.
    pub created: Option<Instant>,
    /// The run-scoped mark.
    pub run: String,
}

const DTSTAMP: &str = "20260101T000000Z";

impl Task {
    /// Renders the task and derives its row.
    pub fn file(&self) -> Filed {
        let mut text = calendar_head(&self.run);
        text.push_str("BEGIN:VTODO\r\n");
        if let Some(uid) = &self.uid {
            text.push_str(&format!("UID:{uid}\r\n"));
        }
        text.push_str(&format!("DTSTAMP:{DTSTAMP}\r\n"));
        if let Some(created) = &self.created {
            text.push_str(&format!("CREATED:{}\r\n", created.ical_utc()));
        }
        text.push_str(&format!("SUMMARY:{}\r\n", self.summary));
        if let Some(due) = &self.due {
            text.push_str(&due.property("DUE"));
        }
        if let Some(status) = &self.status {
            text.push_str(&format!("STATUS:{status}\r\n"));
        }
        if let Some(priority) = self.priority {
            text.push_str(&format!("PRIORITY:{priority}\r\n"));
        }
        if !self.categories.is_empty() {
            text.push_str(&format!("CATEGORIES:{}\r\n", self.categories.join(",")));
        }
        text.push_str("END:VTODO\r\nEND:VCALENDAR\r\n");

        let created = self
            .created
            .unwrap_or_else(|| Instant::from_ical_utc(DTSTAMP));
        let mut summary = Summary::new(Table::Task);
        summary.set("uid", text_or_null(self.uid.as_deref()));
        summary.set("summary", Value::Text(self.summary.clone()));
        for column in ["dtstart", "dtstart_tzid", "dtstart_value", "due_tzid"] {
            summary.set(column, Value::Null);
        }
        summary.set(
            "due",
            text_or_null(self.due.map(|due| due.verbatim()).as_deref()),
        );
        summary.set(
            "due_value",
            text_or_null(self.due.map(|due| due.value_type())),
        );
        summary.set("status", text_or_null(self.status.as_deref()));
        for column in ["completed", "percent", "until", "parent", "mid"] {
            summary.set(column, Value::Null);
        }
        summary.set("recurring", Value::Integer(0));
        summary.set(
            "priority",
            self.priority.map_or(Value::Null, Value::Integer),
        );
        summary.set("created", Value::Text(created.rfc3339()));
        summary.categories = self.categories.clone();

        Filed {
            fallback: None,
            bytes: text.into_bytes(),
            hint: usable(self.uid.as_deref()),
            sort_key: self
                .due
                .map(|due| due.instant().rfc3339())
                .unwrap_or_default(),
            summary,
            addresses: Vec::new(),
        }
    }
}

/// A journal (STORAGE Annex A.5).
#[derive(Clone, Debug)]
pub struct Journal {
    /// The `UID`, or none.
    pub uid: Option<String>,
    /// The `SUMMARY`.
    pub summary: String,
    /// The `DTSTART`, or none.
    pub start: Option<Time>,
    /// The run-scoped mark.
    pub run: String,
}

impl Journal {
    /// Renders the journal and derives its row.
    pub fn file(&self) -> Filed {
        let mut text = calendar_head(&self.run);
        text.push_str("BEGIN:VJOURNAL\r\n");
        if let Some(uid) = &self.uid {
            text.push_str(&format!("UID:{uid}\r\n"));
        }
        text.push_str(&format!("DTSTAMP:{DTSTAMP}\r\n"));
        text.push_str(&format!("SUMMARY:{}\r\n", self.summary));
        if let Some(start) = &self.start {
            text.push_str(&start.property("DTSTART"));
        }
        text.push_str("END:VJOURNAL\r\nEND:VCALENDAR\r\n");

        let mut summary = Summary::new(Table::Journal);
        summary.set("uid", text_or_null(self.uid.as_deref()));
        summary.set("summary", Value::Text(self.summary.clone()));
        summary.set(
            "dtstart",
            text_or_null(self.start.map(|start| start.verbatim()).as_deref()),
        );
        summary.set("dtstart_tzid", Value::Null);
        summary.set(
            "dtstart_value",
            text_or_null(self.start.map(|start| start.value_type())),
        );

        Filed {
            fallback: None,
            bytes: text.into_bytes(),
            hint: usable(self.uid.as_deref()),
            sort_key: self
                .start
                .map(|start| start.instant().rfc3339())
                .unwrap_or_default(),
            summary,
            addresses: Vec::new(),
        }
    }
}

/// A file its writer names (STORAGE Annex A.7).
#[derive(Clone, Debug)]
pub struct Document {
    /// Its name in its folder.
    pub name: String,
    /// Its media type, lowercase, or none.
    pub media_type: Option<String>,
    /// Its bytes.
    pub bytes: Vec<u8>,
    /// The `file:` key its writer drew (STORAGE Annex A.7).
    pub key: String,
}

impl Document {
    /// Derives the row its writer states; a file states no hint.
    pub fn file(&self) -> Filed {
        let mut summary = Summary::new(Table::File);
        summary.set("name", Value::Text(self.name.clone()));
        summary.set("media_type", text_or_null(self.media_type.as_deref()));
        summary.set("size", Value::Integer(self.bytes.len() as i64));
        summary.set("part", Value::Null);

        Filed {
            fallback: Some(self.key.clone()),
            bytes: self.bytes.clone(),
            hint: None,
            summary,
            addresses: Vec::new(),
            sort_key: String::from(self.name.to_lowercase().trim()),
        }
    }
}

/// The FNV-1a 64 digest of `bytes` in sixteen lowercase hexadecimal
/// digits, the `hash:` fallback key's (STORAGE Annex A.2).
pub fn fnv1a64(bytes: &[u8]) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0100_0000_01b3);
    }
    format!("{hash:016x}")
}

fn calendar_head(run: &str) -> String {
    format!(
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//pimalaya//pimdir generator//EN\r\n\
         X-GENERATOR-RUN:{run}\r\n"
    )
}

fn calendar_person(person: &Person) -> String {
    match &person.name {
        Some(name) => format!(";CN={name}:mailto:{}", person.address),
        None => format!(":mailto:{}", person.address),
    }
}

fn mailbox(person: &Person) -> String {
    match &person.name {
        Some(name) => format!("{name} <{}>", person.address),
        None => person.address.clone(),
    }
}

fn usable(hint: Option<&str>) -> Option<String> {
    hint.filter(|hint| !hint.trim_matches([' ', '\t']).is_empty())
        .map(String::from)
}

fn text_or_null(text: Option<&str>) -> Value {
    text.map_or(Value::Null, |text| Value::Text(String::from(text)))
}

fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();

    for (index, chunk) in bytes.chunks(3).enumerate() {
        if index > 0 && index % 19 == 0 {
            out.push_str("\r\n");
        }
        let group = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(char::from(
                    ALPHABET[((group >> (18 - 6 * i)) & 63) as usize],
                ));
            } else {
                out.push('=');
            }
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use std::fs;

    use rusqlite::types::Value;
    use serde_json::Value as Json;

    use crate::{
        body::{Card, Event, Filed, Mail, Person, Task, Time, base64, fnv1a64},
        spec::Spec,
        time::Instant,
    };

    fn pinned(label: &str) -> Json {
        let path = Spec::default_root().join("vectors/summaries.json");
        let text = fs::read_to_string(path).unwrap();
        let summaries: Json = serde_json::from_str(&text).unwrap();
        summaries["cases"]
            .as_array()
            .unwrap()
            .iter()
            .find(|case| case["label"] == label)
            .unwrap()
            .clone()
    }

    fn json(value: &Value) -> Json {
        match value {
            Value::Null => Json::Null,
            Value::Integer(n) => Json::from(*n),
            Value::Text(text) => Json::from(text.as_str()),
            other => panic!("no summary column holds {other:?}"),
        }
    }

    /// Holds a rendered body's derivation to the row summaries.json pins for
    /// a fixture stating the same fields, every column but those `skip`
    /// names, which depend on bytes the two bodies do not share.
    fn agrees(filed: &Filed, label: &str, skip: &[&str]) {
        let case = pinned(label);
        let summary = case["summary"].as_object().unwrap();
        for (column, value) in summary {
            if skip.contains(&column.as_str()) {
                continue;
            }
            let derived = match column.as_str() {
                "in_reply_to" => Json::from(filed.summary.in_reply_to.clone()),
                "categories" => Json::from(filed.summary.categories.clone()),
                column => json(&filed.summary.get(column)),
            };
            assert_eq!(&derived, value, "{label}: {column}");
        }
        assert_eq!(
            filed.hint.as_deref(),
            case["link_id"].as_str(),
            "{label}: hint"
        );
        assert_eq!(
            filed.sort_key,
            case["sort_key"].as_str().unwrap(),
            "{label}: sort key"
        );

        let addresses: Vec<Json> = filed
            .addresses
            .iter()
            .map(|address| {
                serde_json::json!({
                    "role": address.role,
                    "position": address.position,
                    "address": address.address,
                    "name": address.name,
                })
            })
            .collect();
        assert_eq!(
            Json::from(addresses),
            case["addresses"],
            "{label}: addresses"
        );
    }

    #[test]
    fn rendered_bodies_derive_the_rows_the_vectors_pin() {
        let run = String::from("test");
        let person = |name: Option<&str>, address: &str| Person {
            name: name.map(String::from),
            address: String::from(address),
        };

        let mail = Mail {
            message_id: Some(String::from("basic-1@example.org")),
            subject: String::from("Stand-up notes"),
            from: person(Some("Alice Example"), "alice@example.org"),
            to: vec![
                person(None, "bob@example.org"),
                person(None, "carol@example.org"),
            ],
            cc: Vec::new(),
            date: Some(Instant::at(2026, 8, 1, 10, 0, 0)),
            in_reply_to: vec![String::from("parent-1@example.org")],
            text: String::from("Nothing to report."),
            attachment: None,
            run: run.clone(),
        };
        agrees(&mail.file(), "mail, every field present", &["size"]);

        let card = Card {
            uid: Some(String::from(
                "urn:uuid:4fbe8971-0bc3-4e1f-8a2d-1c9b7f6e5d40",
            )),
            name: String::from("Jane Doe"),
            kind: None,
            org: None,
            emails: vec![
                String::from("jane@example.org"),
                String::from("j.doe@example.com"),
            ],
            run: run.clone(),
        };
        agrees(&card.file(), "card, every field present", &[]);

        let event = |uid: &str, summary: &str, location: Option<&str>, start, end| Event {
            uid: Some(String::from(uid)),
            summary: String::from(summary),
            location: location.map(String::from),
            start,
            end: Some(end),
            until: None,
            organizer: None,
            attendees: Vec::new(),
            run: run.clone(),
        };
        let utc = event(
            "event-utc@example.org",
            "Stand-up",
            Some("Room 2"),
            Time::Utc(Instant::at(2026, 8, 14, 9, 0, 0)),
            Time::Utc(Instant::at(2026, 8, 14, 9, 30, 0)),
        );
        agrees(&utc.file(), "event, UTC DTSTART", &[]);
        let date = event(
            "event-allday@example.org",
            "All day",
            None,
            Time::Date(Instant::at(2026, 8, 11, 0, 0, 0)),
            Time::Date(Instant::at(2026, 8, 12, 0, 0, 0)),
        );
        agrees(&date.file(), "event, date-only DTSTART", &[]);
        let floating = event(
            "event-floating@example.org",
            "Floating",
            None,
            Time::Floating(Instant::at(2026, 8, 11, 9, 0, 0)),
            Time::Floating(Instant::at(2026, 8, 11, 10, 0, 0)),
        );
        agrees(&floating.file(), "event, floating DTSTART", &[]);

        let task = Task {
            uid: Some(String::from("todo-due@example.org")),
            summary: String::from("File the return"),
            due: Some(Time::Utc(Instant::at(2026, 9, 30, 17, 0, 0))),
            status: None,
            priority: None,
            categories: Vec::new(),
            created: Some(Instant::at(2026, 8, 1, 0, 0, 0)),
            run,
        };
        agrees(&task.file(), "todo, DUE and no DTSTART", &[]);
    }

    #[test]
    fn fnv1a64_keys_the_fixture_with_no_uid_as_the_vectors_do() {
        let root = crate::spec::Spec::default_root();
        let bytes = fs::read(root.join("vectors/fixtures/event-no-uid.ics")).unwrap();
        let text = fs::read_to_string(root.join("vectors/summaries.json")).unwrap();
        let key = format!("hash:{}", fnv1a64(&bytes));
        assert!(text.contains(&format!("\"{key}\"")), "{key}");
    }

    #[test]
    fn base64_encodes_the_rfc_4648_cases() {
        let cases = [
            ("", ""),
            ("f", "Zg=="),
            ("fo", "Zm8="),
            ("foo", "Zm9v"),
            ("foob", "Zm9vYg=="),
            ("fooba", "Zm9vYmE="),
            ("foobar", "Zm9vYmFy"),
        ];
        for (input, output) in cases {
            assert_eq!(base64(input.as_bytes()), output);
        }
    }
}
