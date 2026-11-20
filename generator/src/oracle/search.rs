//! # The store's own searches and sums
//!
//! What `count_mail_by_day`, `sum_mail`, the four `search_` statements and
//! the `_by_link` list loads answer (STORAGE §14.1): a `LIKE` pattern
//! matched as SQLite matches one, ASCII letters folded and `\` escaping,
//! over each kind's collections merged in their order.

use std::{
    collections::{BTreeMap, BTreeSet},
    ops::Range,
};

use rusqlite::types::Value;

use crate::{
    error::Result,
    model::{Item, Kind, State, Table},
    oracle::{Oracle, pages, row, seen_bit, text},
    time::Instant,
};

/// The patterns every search is asked, a literal underscore and a single
/// character among them.
const PATTERNS: [&str; 7] = ["%", "%e%", "%sync%", "a%", "%example.org%", "%\\_%", "_%"];

impl Oracle<'_> {
    pub(crate) fn searches(&mut self) -> Result<()> {
        let model = self.model;
        let live = |item: &&Item| item.state == State::Live;

        let mut sets: BTreeMap<(Kind, Option<&String>), Vec<&String>> = BTreeMap::new();
        for collection in model.collections.values() {
            if let Some(kind) = collection.kind {
                sets.entry((kind, collection.account.as_ref()))
                    .or_default()
                    .push(&collection.id);
                sets.entry((kind, None)).or_default().push(&collection.id);
            }
        }

        for ((kind, account), set) in &sets {
            let slot = (
                String::from("collections"),
                set.iter()
                    .map(|id| Value::Text((*id).clone()))
                    .collect::<Vec<_>>(),
            );
            let members: Vec<&Item> = model
                .items
                .iter()
                .filter(live)
                .filter(|item| set.contains(&&item.collection))
                .collect();

            if *kind == Kind::Mail && account.is_some() {
                for (shift, seen) in [(None, None), (Some(120), None), (Some(-300), Some(0))] {
                    let mut days: BTreeMap<Option<String>, i64> = BTreeMap::new();
                    for item in members
                        .iter()
                        .filter(|item| seen.is_none_or(|seen| seen_bit(item) == seen))
                    {
                        let day = day_of(&item.sort_key, shift.unwrap_or(0));
                        *days.entry(day).or_default() += 1;
                    }
                    let rows = days
                        .into_iter()
                        .rev()
                        .map(|(day, count)| vec![text(day.as_deref()), Value::Integer(count)])
                        .collect();
                    let params = [
                        ("shift", shift.map_or(Value::Null, Value::Integer)),
                        ("seen", seen.map_or(Value::Null, Value::Integer)),
                        ("attachment", Value::Null),
                        ("since", Value::Null),
                    ];
                    self.expect("count_mail_by_day", &params, rows);
                    self.last().slot = Some(slot.clone());
                }

                let middle = members
                    .iter()
                    .map(|item| item.sort_key.as_str())
                    .filter(|key| !key.is_empty())
                    .collect::<BTreeSet<_>>()
                    .into_iter()
                    .nth(3)
                    .map(String::from);
                for (since, until, held) in [
                    (None, None, None),
                    (middle.clone(), None, Some(1)),
                    (None, middle, Some(0)),
                ] {
                    let mut groups: BTreeMap<i64, (Option<i64>, bool)> = BTreeMap::new();
                    for item in members.iter().filter(|item| {
                        item.sort_key.as_str() >= since.as_deref().unwrap_or("")
                            && until
                                .as_deref()
                                .is_none_or(|until| item.sort_key.as_str() < until)
                    }) {
                        let size = match item.summary.get("size") {
                            Value::Integer(size) => Some(size),
                            _ => None,
                        };
                        let entry = groups.entry(item.seq).or_insert((None, false));
                        entry.0 = entry.0.max(size);
                        entry.1 |= item.object.is_some();
                    }
                    let kept: Vec<(Option<i64>, bool)> = groups
                        .into_values()
                        .filter(|(_, held_one)| {
                            held.is_none_or(|held| i64::from(*held_one) == held)
                        })
                        .collect();
                    let bytes: i64 = kept.iter().filter_map(|(size, _)| *size).sum();
                    let unsized_ = kept.iter().filter(|(size, _)| size.is_none()).count();
                    let params = [
                        ("seen", Value::Null),
                        ("attachment", Value::Null),
                        ("since", text(since.as_deref())),
                        ("until", text(until.as_deref())),
                        ("held", held.map_or(Value::Null, Value::Integer)),
                    ];
                    let rows = vec![vec![
                        Value::Integer(kept.len() as i64),
                        Value::Integer(bytes),
                        Value::Integer(unsized_ as i64),
                    ]];
                    self.expect("sum_mail", &params, rows);
                    self.last().slot = Some(slot.clone());
                }
            }

            let (name, descending): (&str, bool) = match kind {
                Kind::Mail => ("search_mail", true),
                Kind::Contact => ("search_contacts", false),
                Kind::Calendar => ("search_calendar", false),
                Kind::File => ("search_files", false),
            };
            let columns = self.columns(name)?;
            for pattern in PATTERNS {
                let mut hits: Vec<&Item> = members
                    .iter()
                    .copied()
                    .filter(|item| matches(item, *kind, pattern))
                    .collect();
                hits.sort_by(|a, b| {
                    let order = (a.sort_key.as_str(), a.seq, a.collection.as_str()).cmp(&(
                        b.sort_key.as_str(),
                        b.seq,
                        b.collection.as_str(),
                    ));
                    if descending { order.reverse() } else { order }
                });
                let mut after = (Value::Null, Value::Null, Value::Null);
                for page in pages(&hits, self.page) {
                    let mut params = vec![
                        ("after_key", after.0.clone()),
                        ("after_seq", after.1.clone()),
                        ("after_collection", after.2.clone()),
                        ("pattern", Value::Text(String::from(pattern))),
                        ("limit", Value::Integer(self.page)),
                    ];
                    if *kind == Kind::Mail {
                        params.push(("attachment", Value::Null));
                        params.push(("seen", Value::Null));
                    }
                    let rows = page
                        .iter()
                        .map(|item| match kind {
                            Kind::Calendar => {
                                let mut cells = row(item, &columns[..7], None);
                                let component = match item.summary.table {
                                    Table::Event => "event",
                                    Table::Task => "task",
                                    _ => "journal",
                                };
                                cells.push(Value::Text(String::from(component)));
                                cells.push(item.summary.get("summary"));
                                cells
                            }
                            _ => row(item, &columns, Some(item.summary.table)),
                        })
                        .collect();
                    self.expect(name, &params, rows);
                    self.last().slot = Some(slot.clone());
                    if let Some(last) = page.last() {
                        after = (
                            Value::Text(last.sort_key.clone()),
                            Value::Integer(last.seq),
                            Value::Text(last.collection.clone()),
                        );
                    }
                }
            }
        }

        for id in model.collections.keys() {
            let rows: Vec<&Item> = model
                .items
                .iter()
                .filter(|item| &item.collection == id)
                .collect();
            let mut links: Vec<Value> = rows
                .iter()
                .map(|item| Value::Text(item.link_id.clone()))
                .collect();
            links.push(Value::Text(String::from("absent@pimdir.invalid")));
            let mut sorted = rows.clone();
            sorted.sort_by(|a, b| a.link_id.cmp(&b.link_id));
            let lists =
                [
                    (
                        "load_in_reply_to_by_link",
                        sorted
                            .iter()
                            .flat_map(|item| {
                                item.summary
                                    .in_reply_to
                                    .iter()
                                    .enumerate()
                                    .map(|(position, id)| {
                                        vec![
                                            Value::Text(item.link_id.clone()),
                                            Value::Integer(position as i64),
                                            Value::Text(id.clone()),
                                        ]
                                    })
                            })
                            .collect::<Vec<_>>(),
                    ),
                    (
                        "load_categories_by_link",
                        sorted
                            .iter()
                            .flat_map(|item| {
                                item.summary.categories.iter().enumerate().map(
                                    |(position, value)| {
                                        vec![
                                            Value::Text(item.link_id.clone()),
                                            Value::Integer(position as i64),
                                            Value::Text(value.clone()),
                                        ]
                                    },
                                )
                            })
                            .collect::<Vec<_>>(),
                    ),
                ];
            for (name, rows) in lists {
                self.expect(name, &[("collection", Value::Text(id.clone()))], rows);
                self.last().slot = Some((String::from("links"), links.clone()));
            }
        }

        Ok(())
    }
}

/// Whether an item answers a search of its kind for `pattern`, as the
/// statement of that kind reads its summary and addresses.
fn matches(item: &Item, kind: Kind, pattern: &str) -> bool {
    let like_column = |column: &str| match item.summary.get(column) {
        Value::Text(text) => like(&text, pattern),
        _ => false,
    };
    match (kind, item.summary.table) {
        (Kind::Mail, Table::Mail) => {
            like_column("subject") || like_column("sender") || like_column("sender_name")
        }
        (Kind::Contact, Table::Contact) => {
            like_column("fn")
                || item
                    .addresses
                    .iter()
                    .any(|address| address.role == "email" && like(&address.address, pattern))
        }
        (Kind::Calendar, Table::Event) => like_column("summary") || like_column("location"),
        (Kind::Calendar, Table::Task | Table::Journal) => like_column("summary"),
        (Kind::File, Table::File) => like_column("name"),
        _ => false,
    }
}

/// SQLite's `LIKE` with `ESCAPE '\'`: `%` any run, `_` one character, a
/// letter of ASCII matching either case, `\` making the next literal.
pub(crate) fn like(text: &str, pattern: &str) -> bool {
    let text: Vec<char> = text.chars().collect();
    let pattern: Vec<char> = pattern.chars().collect();
    like_from(&text, &pattern)
}

fn like_from(text: &[char], pattern: &[char]) -> bool {
    match pattern.first() {
        None => text.is_empty(),
        Some('%') => (0..=text.len()).any(|skip| like_from(&text[skip..], &pattern[1..])),
        Some('_') => !text.is_empty() && like_from(&text[1..], &pattern[1..]),
        Some(first) => {
            let (wanted, rest) = match (first, pattern.get(1)) {
                ('\\', Some(next)) => (*next, &pattern[2..]),
                _ => (*first, &pattern[1..]),
            };
            match text.first() {
                Some(got) if got.eq_ignore_ascii_case(&wanted) => like_from(&text[1..], rest),
                _ => false,
            }
        }
    }
}

/// SQLite's `date(sort_key, shift || ' minutes')`, `NULL` for an empty key.
fn day_of(sort_key: &str, shift: i64) -> Option<String> {
    if sort_key.len() < 19 {
        return None;
    }
    let number = |range: Range<usize>| sort_key[range].parse::<i64>().unwrap_or(0);
    let at = Instant::at(
        number(0..4),
        number(5..7) as u32,
        number(8..10) as u32,
        number(11..13) as u32,
        number(14..16) as u32,
        number(17..19) as u32,
    );
    let shifted = Instant(at.0 + shift * 60);
    Some(String::from(&shifted.rfc3339()[..10]))
}

#[cfg(test)]
mod tests {
    use crate::oracle::search::like;

    #[test]
    fn like_folds_ascii_alone_and_reads_its_escape() {
        assert!(like("Stand-up", "stand%"));
        assert!(like("ÉCOLE", "%COLE"));
        assert!(!like("École", "école"));
        assert!(like("a_b", "%\\_%"));
        assert!(!like("ab", "%\\_%"));
        assert!(like("x", "_"));
        assert!(!like("", "_%"));
        assert!(like("", "%"));
    }
}
