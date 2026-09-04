# 📁 Pimdir [![Matrix](https://img.shields.io/badge/chat-%23pimalaya-blue?style=flat&logo=matrix&logoColor=white)](https://matrix.to/#/#pimalaya:matrix.org) [![Mastodon](https://img.shields.io/badge/news-%40pimalaya-blue?style=flat&logo=mastodon&logoColor=white)](https://fosstodon.org/@pimalaya) [![Sponsor](https://img.shields.io/badge/sponsor-pink?style=flat&logo=github-sponsors&logoColor=white)](https://pimalaya.org/sponsor/)

A local-first standard for personal information (mail, contacts, calendars): a portable SQLite-plus-blobs store, with a sync layer that keeps it a replica of every source and a search layer that indexes and queries it

One standard in three parts, one store: the format any language with a SQLite binding reads and writes, the engine that keeps it a replica of every source, and the index and query language over it. The canonical part is the schema, the reference statements and the test vectors, so every implementation agrees on the same store. [io-pimdir](https://github.com/pimalaya/io-pimdir) is the reference implementation of the store and the sync layer; the search layer has none yet.

## Table of contents

- [Features](#features)
- [Specification](#specification)
- [Using the standard](#using-the-standard)
- [Layout](#layout)
- [Status](#status)
- [AI policy](https://github.com/pimalaya/.github/blob/master/AI_POLICY.md)
- [License](#license)
- [Social](#social)
- [Contributing](https://github.com/pimalaya/.github/blob/master/CONTRIBUTING.md)
- [Sponsoring](#sponsoring)

## Features

- **Cross-domain**: one store for mail, contacts, events, tasks and journals, keyed by media type, with typed summaries per kind and one address table across all of them, so "everything about this person" is one seek.
- **Multi-account**: several accounts in one store, so a merged view is a query rather than a fan-out. The account groups collections and partitions no identifier.
- **Scalable and indexed**: hundreds of thousands of items with real secondary indexes, a change feed for anything derived from the store, and keyset pages that cost the same at any depth.
- **Portable**: one SQLite file, byte-identical across every OS and architecture, with none of the pitfalls of file-per-item layouts.
- **Transactional**: a whole flag-set change or a multi-item move is one atomic commit a reader never catches half-done.
- **Deduplicated**: bodies are stored once by content hash, so a message filed in two mailboxes costs one copy.
- **Retentive**: an item the last source dropped is retained rather than erased, so an upstream expunge never destroys the local copy. Purging is explicit, and restoring costs no network.
- **Offline-first**: every edit is staged locally and reconciled by a three-way merge against each source, several sources propagating through one item without a cross-merge.
- **Searchable**: a full-text index over the bodies, calendar occurrences and threads, and a query language every client answers alike.
- **Rebuildable**: the database is a derived index over the bodies and the remote, and the search index is derived from both, so corruption is survivable by re-sync and a dropped index costs a rebuild.

## Specification

The standard is a base and two layers, each a normative part written to RFC 2119 with a status of its own, framed by two informative documents:

- [OVERVIEW.md](./OVERVIEW.md), the **model**: what a store is, the entities, the identifiers, the roles and how sync, retention, the queue and search fit together, with no table, column or statement named. Read it first.
- [STORAGE.md](./STORAGE.md), the **store**, binding by the profile an implementation meets, reader, producer or owner: a SQLite database (the queryable index and mutable state) plus a content-addressed blob directory (the bodies), the per-kind summaries and addresses, the change feed, retention and the action queue.
- [SYNC.md](./SYNC.md), the **sync** layer: how one or more sources are reconciled through the store, the five verbs, the merge rules and what a connector hands the engine.
- [SEARCH.md](./SEARCH.md), the **search** layer: the derived index beside the store, extraction per kind, calendar time, threads, and the query language every client answers alike.
- [GUIDE.md](./GUIDE.md), the **implementation guide**: the parts' rules as numbered procedures and decision tables naming the statements and vectors at each step, and a conformance checklist.

Either layer may be omitted, and an implementation offering one must conform to it. Neither stands without the store: a sync needs a base per source, what that source last agreed to, or a delete on one side and an add on the other are the same picture, and the bindings are that base; a search needs one index with one meaning of a match across sources, which only the store's summaries, addresses and bodies give. The overview and the guide restate and never rule: where either disagrees with a part, the part wins.

Two properties are worth knowing before reading. Removal is a **soft delete**: when the last source drops an item, the store keeps the row and its body, hidden from the sync seam and from the live reads, and only an explicit purge deletes it. And the **action queue** is the write door for every process that does not own the store: a producer appends a kind plus a versioned JSON payload, the owner applies it in append order.

## Using the standard

There are three ways to use it, and the right one depends on the part.

1. **Implement the documents.** Any language with a SQLite binding. The store by profile, reader and producer being small; the engine in full; the index and the query language. The vectors say when it is done.
2. **Use io-pimdir's I/O-free core.** The derivations and the five verbs as coroutines: your code answers the storage and remote requests they yield, so the store can be your own SQLite and the network your own transport, in any runtime.
3. **Use io-pimdir's std client.** The whole thing: store, engine and connector seam, behind one handle per profile.

Readers and producers of the store, and clients of the query language, are expected to implement the documents: that is what the format is for. Owning the store, syncing it and indexing it are large, and io-pimdir exists so nobody has to write them twice; SYNC in particular is doable from the document and the vectors, and is where writing from scratch costs the most and gains the least.

## Layout

```
OVERVIEW.md           the model (informative, read first)
STORAGE.md            the store, the base (normative, RFC 2119)
SYNC.md               the sync layer (normative, optional)
SEARCH.md             the search layer (normative, optional)
GUIDE.md              the implementation guide (informative procedures)
migrations/           canonical, forward-only schema migrations (SQL)
  storage/            the store's, 0001_init.sql = schema version 1
  search/             the search index's, 0001_init.sql = index version 1
queries/              the reference statements, one file per statement named after it
  storage/            the store's: read/ the reader's, queue/ the producer's, owner/ the rest
  search/             the search index's, prepared with the store attached
vectors/              the normative test data (STORAGE.md §16, SYNC.md §11, SEARCH.md §11)
checks/               what a push checks, needing no implementation
flake.nix             the toolchain those checks run under
cairn/                the dated history of what the spec did and why (log/)
AGENTS.md             how a contributing agent records a change here
README.md             this file
LICENSE-MIT           dual license
LICENSE-APACHE
```

The history follows [Cairn](https://github.com/pimalaya/cairn), with one deviation while the format is draft: the three documents are the living spec, so cairn/spec/ stays empty rather than restating them, and a landed change is recorded by its log entry alone. [AGENTS.md](./AGENTS.md) states what ends that.

## Status

Draft. Store schema version 1 and index schema version 1 are defined and stable in shape; the sync and search parts are draft and edited in place.

While a part is draft, its version is edited in place: a change folds into the migration, the version stays 1, and a store or index created by an earlier draft is recreated rather than migrated. After a freeze, a breaking change to the store bumps the version and ships as a new migration; a change to the index is always a rebuild.

## License

This project is licensed under either of:

- [MIT license](LICENSE-MIT)
- [Apache License, Version 2.0](LICENSE-APACHE)

## Social

- Chat on [Matrix](https://matrix.to/#/#pimalaya:matrix.org)
- News on [Mastodon](https://fosstodon.org/@pimalaya) or [RSS](https://fosstodon.org/@pimalaya.rss)
- Mail at [pimalaya.org@posteo.net](mailto:pimalaya.org@posteo.net)

## Sponsoring

[![nlnet](https://nlnet.nl/logo/banner-160x60.png)](https://nlnet.nl/)

Special thanks to the [NLnet foundation](https://nlnet.nl/) and the [European Commission](https://www.ngi.eu/) that have been financially supporting the project for years:

- 2022 → 2023: [NGI Assure](https://nlnet.nl/project/Himalaya/)
- 2023 → 2024: [NGI Zero Entrust](https://nlnet.nl/project/Pimalaya/)
- 2024 → 2026: [NGI Zero Core](https://nlnet.nl/project/Pimalaya-PIM/)
- 2026 → 2027: [NGI Zero Commons Fund](https://nlnet.nl/project/Pimalaya-pimdir/)

This program is part of Pimalaya, free software funded entirely by grants and donations. If you find it useful, consider [sponsoring](https://pimalaya.org/sponsor/) its development:

[![GitHub](https://img.shields.io/badge/-GitHub%20Sponsors-fafbfc?logo=GitHub%20Sponsors)](https://github.com/sponsors/soywod)
[![Ko-fi](https://img.shields.io/badge/-Ko--fi-ff5e5a?logo=Ko-fi&logoColor=ffffff)](https://ko-fi.com/pimalaya)
[![Buy Me a Coffee](https://img.shields.io/badge/-Buy%20Me%20a%20Coffee-ffdd00?logo=Buy%20Me%20A%20Coffee&logoColor=000000)](https://www.buymeacoffee.com/pimalaya)
[![Liberapay](https://img.shields.io/badge/-Liberapay-f6c915?logo=Liberapay&logoColor=222222)](https://liberapay.com/pimalaya)
[![thanks.dev](https://img.shields.io/badge/-thanks.dev-000000?logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQuMDk3IiBoZWlnaHQ9IjE3LjU5NyIgY2xhc3M9InctMzYgbWwtMiBsZzpteC0wIHByaW50Om14LTAgcHJpbnQ6aW52ZXJ0IiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxwYXRoIGQ9Ik05Ljc4MyAxNy41OTdINy4zOThjLTEuMTY4IDAtMi4wOTItLjI5Ny0yLjc3My0uODktLjY4LS41OTMtMS4wMi0xLjQ2Mi0xLjAyLTIuNjA2di0xLjM0NmMwLTEuMDE4LS4yMjctMS43NS0uNjc4LTIuMTk1LS40NTItLjQ0Ni0xLjIzMi0uNjY5LTIuMzQtLjY2OUgwVjcuNzA1aC41ODdjMS4xMDggMCAxLjg4OC0uMjIyIDIuMzQtLjY2OC40NTEtLjQ0Ni42NzctMS4xNzcuNjc3LTIuMTk1VjMuNDk2YzAtMS4xNDQuMzQtMi4wMTMgMS4wMjEtMi42MDZDNS4zMDUuMjk3IDYuMjMgMCA3LjM5OCAwaDIuMzg1djEuOTg3aC0uOTg1Yy0uMzYxIDAtLjY4OC4wMjctLjk4LjA4MmExLjcxOSAxLjcxOSAwIDAgMC0uNzM2LjMwN2MtLjIwNS4xNTYtLjM1OC4zODQtLjQ2LjY4Mi0uMTAzLjI5OC0uMTU0LjY4Mi0uMTU0IDEuMTUxVjUuMjNjMCAuODY3LS4yNDkgMS41ODYtLjc0NSAyLjE1NS0uNDk3LjU2OS0xLjE1OCAxLjAwNC0xLjk4MyAxLjMwNXYuMjE3Yy44MjUuMyAxLjQ4Ni43MzYgMS45ODMgMS4zMDUuNDk2LjU3Ljc0NSAxLjI4Ny43NDUgMi4xNTR2MS4wMjFjMCAuNDcuMDUxLjg1NC4xNTMgMS4xNTIuMTAzLjI5OC4yNTYuNTI1LjQ2MS42ODIuMTkzLjE1Ny40MzcuMjYuNzMyLjMxMi4yOTUuMDUuNjIzLjA3Ni45ODQuMDc2aC45ODVabTE0LjMxNC03LjcwNmgtLjU4OGMtMS4xMDggMC0xLjg4OC4yMjMtMi4zNC42NjktLjQ1LjQ0NS0uNjc3IDEuMTc3LS42NzcgMi4xOTVWMTQuMWMwIDEuMTQ0LS4zNCAyLjAxMy0xLjAyIDIuNjA2LS42OC41OTMtMS42MDUuODktMi43NzQuODloLTIuMzg0di0xLjk4OGguOTg0Yy4zNjIgMCAuNjg4LS4wMjcuOTgtLjA4LjI5Mi0uMDU1LjUzOC0uMTU3LjczNy0uMzA4LjIwNC0uMTU3LjM1OC0uMzg0LjQ2LS42ODIuMTAzLS4yOTguMTU0LS42ODIuMTU0LTEuMTUydi0xLjAyYzAtLjg2OC4yNDgtMS41ODYuNzQ1LTIuMTU1LjQ5Ny0uNTcgMS4xNTgtMS4wMDQgMS45ODMtMS4zMDV2LS4yMTdjLS44MjUtLjMwMS0xLjQ4Ni0uNzM2LTEuOTgzLTEuMzA1LS40OTctLjU3LS43NDUtMS4yODgtLjc0NS0yLjE1NXYtMS4wMmMwLS40Ny0uMDUxLS44NTQtLjE1NC0xLjE1Mi0uMTAyLS4yOTgtLjI1Ni0uNTI2LS40Ni0uNjgyYTEuNzE5IDEuNzE5IDAgMCAwLS43MzctLjMwNyA1LjM5NSA1LjM5NSAwIDAgMC0uOTgtLjA4MmgtLjk4NFYwaDIuMzg0YzEuMTY5IDAgMi4wOTMuMjk3IDIuNzc0Ljg5LjY4LjU5MyAxLjAyIDEuNDYyIDEuMDIgMi42MDZ2MS4zNDZjMCAxLjAxOC4yMjYgMS43NS42NzggMi4xOTUuNDUxLjQ0NiAxLjIzMS42NjggMi4zNC42NjhoLjU4N3oiIGZpbGw9IiNmZmYiLz48L3N2Zz4=)](https://thanks.dev/u/gh/soywod)
[![PayPal](https://img.shields.io/badge/-PayPal-0079c1?logo=PayPal&logoColor=ffffff)](https://www.paypal.com/paypalme/soywod)
