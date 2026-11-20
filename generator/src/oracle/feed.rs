//! # The change feed
//!
//! What `list_items_changed_since`, `list_collections_changed_since` and
//! `load_change_cursor` answer over a store written from nothing (STORAGE
//! §4.5): every row once, each with a stamp of its own. The stamps
//! themselves are the triggers', so the oracle states that each row holds
//! one, and [`order`] that they order the rows totally.

use std::collections::BTreeSet;

use rusqlite::{ToSql, types::Value};

use crate::{
    error::Result,
    model::State,
    oracle::{INSTANT, Oracle, STAMP, STORE_ID, text},
    store::Store,
};

/// A limit above any page a structure store fills.
const ALL: i64 = 1 << 40;

impl Oracle<'_> {
    pub(crate) fn feed(&mut self) {
        let model = self.model;
        let stamp = || Value::Text(String::from(STAMP));

        let rows = model
            .items
            .iter()
            .map(|item| {
                vec![
                    Value::Text(item.collection.clone()),
                    Value::Text(item.link_id.clone()),
                    Value::Integer(item.seq),
                    stamp(),
                    Value::Integer(i64::from(item.state != State::Live)),
                    match item.state {
                        State::Retained { .. } => Value::Text(String::from(INSTANT)),
                        _ => Value::Null,
                    },
                ]
            })
            .collect();
        let since = [("since", Value::Integer(0)), ("limit", Value::Integer(ALL))];
        self.expect("list_items_changed_since", &since, rows);
        self.last().ordered = false;

        let rows = model
            .collections
            .values()
            .map(|collection| {
                vec![
                    Value::Text(collection.id.clone()),
                    text(collection.account.as_deref()),
                    Value::Text(String::from(
                        collection.kind.map_or("", |kind| kind.media_type()),
                    )),
                    Value::Text(collection.name.clone()),
                    stamp(),
                ]
            })
            .collect();
        self.expect("list_collections_changed_since", &since, rows);
        self.last().ordered = false;

        let cursor = vec![
            stamp(),
            Value::Integer(0),
            Value::Text(String::from(STORE_ID)),
            Value::Integer(1),
        ];
        self.expect("load_change_cursor", &[], vec![cursor]);
    }
}

/// Names each way the store's stamps fail to order its rows totally: a
/// stamp two rows share, a feed not ascending, one above the cursor
/// (STORAGE §4.5).
pub fn order(store: &Store) -> Result<Vec<String>> {
    let since: [(&str, &dyn ToSql); 2] = [("since", &0), ("limit", &ALL)];
    let mut faults = Vec::new();
    let mut seen = BTreeSet::new();

    for statement in [
        "storage/read/list_items_changed_since",
        "storage/read/list_collections_changed_since",
    ] {
        let columns = &store.spec().statement(statement)?.columns;
        let at = columns
            .iter()
            .position(|column| column == "changed")
            .unwrap_or(0);
        let mut last = 0;
        for row in store.run(statement, &since)? {
            let Value::Integer(stamp) = row[at] else {
                faults.push(format!("{statement} answers a row with no stamp"));
                continue;
            };
            if stamp <= last {
                faults.push(format!("{statement} answers {stamp} after {last}"));
            }
            if !seen.insert(stamp) {
                faults.push(format!("two rows share the stamp {stamp}"));
            }
            last = stamp;
        }
    }

    let cursor = store.run("storage/read/load_change_cursor", &[])?;
    if let (Some(Value::Integer(changed)), Some(top)) =
        (cursor.first().map(|row| &row[0]), seen.last())
        && top > changed
    {
        faults.push(format!("a row holds {top}, above the cursor's {changed}"));
    }
    Ok(faults)
}
