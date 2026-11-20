//! # The fixture layer
//!
//! The bodies under vectors/fixtures/ with the derivation
//! vectors/summaries.json pins for each: the structure cases of Annex A
//! (encoded words, folding, broken dates, raw octets, charsets, time
//! zones, overrides, the walk's bounds), derived twice already, which the
//! generator files as they stand rather than render.

use std::{collections::BTreeSet, fs};

use rusqlite::types::Value;
use serde_json::Value as Json;

use crate::{
    body::Filed,
    error::{Error, Result},
    model::{Address, Summary, Table},
    name::ObjectName,
    spec::Spec,
};

/// One fixture and the row pinned for it.
#[derive(Clone, Debug)]
pub struct Fixture {
    /// Its path under vectors/.
    pub path: String,
    /// The key summaries.json files it under.
    pub link_id: String,
    /// The body and its derivation.
    pub filed: Filed,
    /// The parts a message's stand-ins name (STORAGE §14.3).
    pub attachments: Vec<Attachment>,
}

/// A part of a message an owner stands a file for.
#[derive(Clone, Debug)]
pub struct Attachment {
    /// Its section in the message.
    pub part: String,
    /// Its file name.
    pub name: String,
    /// Its media type.
    pub media_type: Option<String>,
    /// Its decoded size.
    pub size: Option<i64>,
}

/// Every fixture summaries.json pins a row for, once each, from its first
/// case naming it under its own key (a case minting a key reuses a body).
pub fn load(spec: &Spec) -> Result<Vec<Fixture>> {
    let path = spec.root.join("vectors/summaries.json");
    let text = fs::read_to_string(&path).map_err(|source| Error::Io {
        path: path.clone(),
        source,
    })?;
    let summaries: Json = serde_json::from_str(&text).map_err(|source| Error::Json {
        path: path.clone(),
        source,
    })?;
    let malformed = |detail: &str| Error::Disagreement {
        what: String::from("vectors/summaries.json"),
        detail: String::from(detail),
    };

    let mut seen = BTreeSet::new();
    let mut fixtures = Vec::new();
    for case in summaries["cases"].as_array().into_iter().flatten() {
        if case.get("hint").is_some() {
            continue;
        }
        let fixture = case["fixture"]
            .as_str()
            .ok_or_else(|| malformed("a case names no fixture"))?;
        if !seen.insert(String::from(fixture)) {
            continue;
        }

        let body_path = spec.root.join("vectors").join(fixture);
        let bytes = fs::read(&body_path).map_err(|source| Error::Io {
            path: body_path.clone(),
            source,
        })?;
        if Some(ObjectName::of(&bytes).0.as_str()) != case["body"]["blake3"].as_str() {
            return Err(malformed(&format!(
                "{fixture} does not hash to its stated name"
            )));
        }

        let table = match case["table"].as_str() {
            Some("mail_summary") => Table::Mail,
            Some("contact_summary") => Table::Contact,
            Some("event_summary") => Table::Event,
            Some("task_summary") => Table::Task,
            Some("journal_summary") => Table::Journal,
            Some("file_summary") => Table::File,
            _ => return Err(malformed(&format!("{fixture} names no table"))),
        };
        let mut summary = Summary::new(table);
        for (column, value) in case["summary"].as_object().into_iter().flatten() {
            match column.as_str() {
                "in_reply_to" => summary.in_reply_to = strings(value),
                "categories" => summary.categories = strings(value),
                column => summary.set(column, sql(value)),
            }
        }

        let addresses = case["addresses"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|address| Address {
                role: String::from(address["role"].as_str().unwrap_or_default()),
                position: address["position"].as_i64().unwrap_or_default(),
                address: String::from(address["address"].as_str().unwrap_or_default()),
                name: address["name"].as_str().map(String::from),
            })
            .collect();

        let link_id = String::from(case["link_id"].as_str().unwrap_or_default());
        let hint = if let Some(hint) = link_id.strip_prefix("esc:") {
            Some(String::from(hint))
        } else if link_id.starts_with("alt:") || link_id.starts_with("hash:") {
            None
        } else {
            Some(link_id.clone())
        };

        let attachments = case["attachments"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|part| Attachment {
                part: String::from(part["part"].as_str().unwrap_or_default()),
                name: String::from(part["name"].as_str().unwrap_or_default()),
                media_type: part["media_type"].as_str().map(String::from),
                size: part["size"].as_i64(),
            })
            .collect();

        fixtures.push(Fixture {
            path: String::from(fixture),
            link_id,
            attachments,
            filed: Filed {
                bytes,
                hint,
                summary,
                addresses,
                sort_key: String::from(case["sort_key"].as_str().unwrap_or_default()),
                fallback: None,
            },
        });
    }

    Ok(fixtures)
}

fn strings(value: &Json) -> Vec<String> {
    value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|value| value.as_str().map(String::from))
        .collect()
}

fn sql(value: &Json) -> Value {
    match value {
        Json::Null => Value::Null,
        Json::Bool(value) => Value::Integer(i64::from(*value)),
        Json::Number(number) => number.as_i64().map_or(Value::Null, Value::Integer),
        Json::String(text) => Value::Text(text.clone()),
        other => Value::Text(other.to_string()),
    }
}
