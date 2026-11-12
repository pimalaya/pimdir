-- SPDX-License-Identifier: MIT OR Apache-2.0
--
-- A rehearsal migration, never shipped under migrations/: what STORAGE.md §6
-- says raises neither compatibility version. An index, a table, and a column
-- a reader may ignore on a table producers write and on two they do not,
-- nullable or with a default. Run by step 3 as it stands: one transaction,
-- foreign keys on.
CREATE INDEX rehearsal_items_by_level ON items(level);
CREATE TABLE rehearsal_notes (
    id   INTEGER PRIMARY KEY,
    note TEXT CHECK (typeof(note) IN ('text', 'null'))
);
ALTER TABLE queue ADD COLUMN rehearsal_note TEXT;
ALTER TABLE collections ADD COLUMN rehearsal_icon TEXT;
ALTER TABLE items ADD COLUMN rehearsal_pinned INTEGER NOT NULL DEFAULT 0;
