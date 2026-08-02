# 📁 Pimdir [![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](#license) [![Spec](https://img.shields.io/badge/spec-SPEC.md-informational)](./SPEC.md)

**A store format for text-based personal-information items**: mail, calendar events, contacts, notes, tasks. A pimdir store is a **SQLite database** (the queryable index and mutable state) plus a **content-addressed blob directory** (the immutable item bodies): a hybrid that keeps SQLite's scale, indexing and cross-OS uniformity while keeping large bodies out of the database.

This repository is the **specification only**: no reference implementation. Implementations may use any language with a SQLite binding; the shared, canonical part is the schema and its migration scripts, so every implementation reads and writes the same store.

## The idea in one minute

Every serious PIM store (Apple Mail, Thunderbird, notmuch, evolution-data-server) does the same two things: an **indexed binary store** for state and queries, and the **large immutable content** beside it. Pimdir is that pattern, generalised and written down:

- **Generic**: one store for any text-based item kind, keyed by media type.
- **Scalable and indexed**: hundreds of thousands of items with real indexes (by link id, flag, object), not per-item file opens.
- **Portable**: the SQLite file format is byte-identical across every OS and architecture, sidestepping the case-sensitivity, forbidden-character and `MAX_PATH` problems that file-per-item layouts (Maildir, m2dir, vdir) hit.
- **Transactional**: a whole flag-set change or a multi-item move is one ACID commit, not a sequence of renames a reader can catch half-done.
- **Rebuildable, not sacred**: the database is a *derived* index over the authoritative blobs and the remote; corruption is survivable by re-sync.

A store is one directory: pimdir.db (the database) and objects/ (the sharded, content-addressed blob files). Bodies are deduped by content hash, so a message in two mailboxes is stored once.

## Layout

```
SPEC.md               the store specification (normative, RFC 2119)
migrations/           canonical, forward-only schema migrations (SQL)
  0001_init.sql       schema version 1
README.md             this file
LICENSE-MIT           dual license
LICENSE-APACHE
```

## Status

**Draft.** Schema version 1 is defined and stable in shape; there is no conformance suite yet. Breaking changes bump the schema version and ship as a new migration script.

## Contributing

Issues and proposals against the spec are welcome. Changes should argue from the goals above: keep the store scalable and cross-OS, keep bodies out of the database (so it stays a rebuildable index), and keep the schema and migrations canonical so every implementation stays interoperable.

## License

Licensed under either of [Apache License 2.0](./LICENSE-APACHE) or [MIT license](./LICENSE-MIT) at your option.
