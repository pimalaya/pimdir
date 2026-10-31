# 📁 Pimdir [![Matrix](https://img.shields.io/badge/chat-%23pimalaya-blue?style=flat&logo=matrix&logoColor=white)](https://matrix.to/#/#pimalaya:matrix.org) [![Mastodon](https://img.shields.io/badge/news-%40pimalaya-blue?style=flat&logo=mastodon&logoColor=white)](https://fosstodon.org/@pimalaya) [![Sponsor](https://img.shields.io/badge/sponsor-pink?style=flat&logo=github-sponsors&logoColor=white)](https://pimalaya.org/sponsor/)

Pimdir is **local-first standard** for **personal information**: mail, contacts, calendars, tasks and files in **one portable store**, kept **a replica of every source**, and **searchable** through one query language.

The canonical part is the schema, the reference statements and the test vectors, so every implementation agrees on the same store. [io-pimdir](https://github.com/pimalaya/io-pimdir) is the reference implementation.

## Table of contents

- [Features](#features)
- [Specification](#specification)
- [Usage](#usage)
- [Layout](#layout)
- [Status](#status)
- [AI policy](https://github.com/pimalaya/.github/blob/master/AI_POLICY.md)
- [License](#license)
- [Social](#social)
- [Contributing](https://github.com/pimalaya/.github/blob/master/CONTRIBUTING.md)
- [Sponsoring](#sponsoring)

## Features

- **Cross-domain**: mail, contacts, events, tasks, journals and files, in one store
- **Multi-account**: several accounts in one store, *in merged views*
- **Portable**: one SQLite file plus a blob directory, identical on every OS and architecture
- **Scalable**: real indexes, a change feed, and keyset pages that cost the same at any depth
- **Transactional**: a flag change or a multi-item move is one atomic commit
- **Deduplicated**: a body is stored once, by content hash
- **Retentive**: an upstream expunge never erases the local copy; only an explicit purge does
- **Offline-first**: every edit is staged locally and reconciled by a three-way merge
- **Searchable**: a full-text index over bodies, occurrences and threads

## Specification

Three normative parts (BCP 14), each versioned apart:

- [STORAGE.md](./STORAGE.md), the **store**: schema, blobs, summaries, change feed, retention and action queue.
- [SYNC.md](./SYNC.md), the **sync** layer: sources reconciled through the store, merge rules, connector seam.
- [SEARCH.md](./SEARCH.md), the **search** layer: the derived index and the query language.

Two informative documents around them:

- [OVERVIEW.md](./OVERVIEW.md), the **model**: entities, identifiers and how the parts fit. Read it first.
- [GUIDE.md](./GUIDE.md), the **implementation guide**: procedures, decision tables and a conformance checklist.

[conventions/gtd.md](./conventions/gtd.md) holds the task conventions Pimalaya's apps share. It builds on the standard but is not part of it.

Sync and search are optional, but neither stands without the store. Where the overview or the guide disagrees with a part, the part wins.

Two things to know first: removal is a **soft delete** (only an explicit purge erases), and the **action queue** is how any process other than the store's owner writes to it.

## Usage

There are three ways to use the standard, from the most work to the least. They mix: an app can write its reader from the documents and take the sync engine from io-pimdir.

###   Implement the documents

Write the store yourself, in any language with a SQLite binding, from the three parts and the guide. Run the canonical schema and statements verbatim (the recommended shape, on SQLite 3.37 or newer), or a shape of your own on an older SQLite, named in `store_meta.shape` (STORAGE §4.1). The test vectors say when you are done: the model vectors bind every shape, checks/ the canonical one.

This suits the small profiles: readers, producers and query clients.

### Use io-pimdir's I/O-free core

Take the hard parts from [io-pimdir](https://github.com/pimalaya/io-pimdir) without its SQLite or its I/O: the summaries are pure functions, and the sync engine and the index refresh are coroutines that yield what they need to read and what they write, and your program answers them over its own database and transport. Build it without default features, with `search` for the query language, the extraction and the refresh.

This suits an owner bound to a database of its own, such as an Android app on the platform's SQLite.

### Use io-pimdir's std client

Take the whole store from io-pimdir: with its `client` feature (the default) it opens pimdir.db through rusqlite and drives the coroutines itself, one handle per profile, with the connector seam for your sources and, with `search`, the index.

This suits a desktop program or a CLI. Owning, syncing and indexing a store are large: io-pimdir exists so nobody writes them twice.

## Layout

```
OVERVIEW.md     the model (informative, read first)
STORAGE.md      the store, the base (normative)
SYNC.md         the sync layer (normative, optional)
SEARCH.md       the search layer (normative, optional)
GUIDE.md        the implementation guide (informative)
migrations/     canonical schema migrations: storage/ and search/
queries/        the reference statements, one file each
vectors/        the normative test data
checks/         schema, statement, name and vector checks (nix flake check)
conventions/    Pimalaya's own conventions, outside the standard (gtd.md)
cairn/          the dated history (log/) and audit ledgers (changes/)
```

The history follows [Cairn](https://github.com/pimalaya/cairn), the documents themselves being the living spec (see [AGENTS.md](./AGENTS.md)).

## Status

Draft: **storage-draft-07**, **sync-draft-06** and **search-draft-07**, each named by a git tag. An implementation states the version of each part it conforms to.

A released part is versioned `<part>-vX.Y.Z`: STORAGE's major is the store schema version, SEARCH's the index schema version, SYNC's a breaking change to the connector seam or the engine.

STORAGE freezes first, once the reference implementation passes every check and vector and a real store survives one upgrade cycle. Until then, schema version 1 is edited in place and an older draft store is reconciled on open; after it, every schema change is a migration.

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
