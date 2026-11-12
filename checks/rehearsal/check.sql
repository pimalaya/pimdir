-- SPDX-License-Identifier: MIT OR Apache-2.0
--
-- A rehearsal migration, never shipped under migrations/: a fifth kind added
-- to the closed vocabulary of collections.kind by editing its CHECK in the
-- table's stored text (STORAGE.md §6), no table rebuilt. One transaction,
-- foreign keys on, the connection out of defensive mode; the runner raises
-- PRAGMA schema_version after it and reads integrity_check before the
-- commit. The replaced text is the end of the constraint as 0001_init.sql
-- writes it: the runner fails when the edit did not land once.
PRAGMA writable_schema = ON;
UPDATE sqlite_master
SET sql = replace(sql, '''application/octet-stream''))',
                  '''application/octet-stream'', ''text/x-rehearsal''))')
WHERE type = 'table' AND name = 'collections';
PRAGMA writable_schema = OFF;
