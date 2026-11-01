---
cairn: delta
change: the-consumers-gaps-fold-into-draft-08
---

## ADDED Requirements

### Requirement: STORAGE Annex A.1 Lines
A line of a message, in a header block or a multipart body, SHALL end at CRLF, at a bare LF or at the end of the message. One `\r` just before the end of the message SHALL be read as the line break's, never as the line's content; any other `\r` not followed by a LF is the line's content. Content read as octets keeps every octet.

#### Scenario: a closing delimiter cut before its line feed
- GIVEN a multipart/mixed message ending `--b3--\r`, its attachment the last part
- WHEN it is derived
- THEN the mark is 1 and the attachment's stand-in measures 6 octets (vectors/summaries.json)

#### Scenario: a header line holding a lone CR
- GIVEN a message header holding a line `\r\r\n` before its Subject and Message-ID
- WHEN it is derived
- THEN the Subject and the Message-ID are read (vectors/summaries.json)

#### Scenario: a header cut after its CR
- GIVEN a header block alone ending `Subject: Cut short\r`
- WHEN it is derived
- THEN the subject is `Cut short` (vectors/summaries.json, checks/vectors.py)

### Requirement: STORAGE §5 Android's no-replace move
*Note:* On Android, SELinux denies an app `link(2)` on its own data files, so the no-replace move there is `renameat2` with `RENAME_NOREPLACE`, a raw system call below API 30.

## MODIFIED Requirements

### Requirement: SYNC §7 Edit
An edit whose object the base holds SHALL stage nothing for its source, though on a conflicted item it still settles the item's conflict. An `Edit` without `overrule` on a conflicted item, through any binding of it, SHALL give the item the edit's body whatever it is, clear `conflicted`, release `conflict_object`, measure no divergence, retain and report nothing, and move the editing binding's `shared_object` to that body, every other binding's staying.

#### Scenario: a person keeps the item's body through the source it moved away from
- GIVEN vector 102's store, the item at c3 diverged from b's c2
- WHEN a person's `Edit` through b restates c3, with no `overrule`
- THEN the item holds c3 unconflicted, b's `shared_object` is c3, no event and no retained item (vectors/sync/118 to 123 for the six cells)

### Requirement: STORAGE §4.4 Queries
An implementation's own text for one statement name MAY be several statements run in order in one transaction, keeping the name, parameters, result columns and effect, no other connection's write coming between them. A program judging whether it opens a store MAY read `store_meta` with `*`, taking the columns it knows by name; no other statement reads `*`.

### Requirement: STORAGE §17 Conformance
An implementation running text of its own for any statement of its directories SHALL add `(own statement text)` after its profile on its conformance line.

### Requirement: STORAGE §18 A store from elsewhere
A program opening a store it did not create SHOULD set `PRAGMA trusted_schema = OFF` (from SQLite 3.31) and `SQLITE_DBCONFIG_DEFENSIVE` (from 3.26) where its SQLite offers each; a setting the SQLite lacks is no deviation. Below 3.31 it SHOULD instead read `sqlite_master` before any other statement, refuse a store holding a trigger or a view whose text the canonical schema at the store's version does not create, and register no SQL function with a side effect on the connection.

#### Scenario: the floor lacks the pragma and stores the canonical text
- GIVEN SQLite 3.18.2 built as Android 8.0 builds it
- WHEN 0001_init.sql loads there
- THEN `PRAGMA trusted_schema` answers nothing and every trigger's text equals the one a current SQLite stores (checks/floor.sh)
