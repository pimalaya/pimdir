---
cairn: change
id: search-milestones
status: draft
created: 2026-10-18
---

# Search, from the draft part to a running index

## Why

PIMDIR_REPORT §2.14 (2026-09-03) planned search in six milestones. The first, the spec, has landed: search-part, change-feed, companion-files, derived-keys-carry-no-identity, zulu-designator, typed-summaries and item-address on 2026-09-03, then search-roles-threads-horizon on 2026-09-05. SEARCH.md is a normative part at `draft-04`, with its schema, its statements and 21 query vectors, and no implementation has ever run them: io-pimdir has no `search` feature.

The rest is deferred to the 2027 NLnet plan, Task 2 "pimdir Notmuch": an index keyed on the object hash, tags that are the store's flags, one query grammar across mail, contacts and calendar. This change records what is left so the plan starts from it rather than from the report.

## What

What is already in SEARCH.md and is not redone: the index keyed on `objects.hash` (§3), tags as flags through the queue (§10), the cross-domain fields (§8), the change feed as the refresh (§4), the horizon (§7), threads (§9).

What is left, by milestone, each a change in its repository when it starts:

- **M1, the index** (io-pimdir, cairn/changes/search-feature): refresh from the feed, mail extraction with chunk boundaries, `object_text` and `summary_text`, the AST and its compiler, `index`, `search`, `count`, `show`, and their output contract (JSON Schema for hits, coverage and errors).
- **M2, cross-domain** (io-pimdir): vCard and iCalendar extraction, `kind:`, `with:`, `person:`, occurrences within the horizon.
- **M3, threads and dates** (io-pimdir): `thread:`, the threaded listing, relative dates.
- **M4, writes** (io-pimdir): `tag` through the queue, `thread`.
- Consumers are not in Task 2: himalaya, cardamum, calendula and the GTK app move onto the library afterwards, and `search_mail`, `search_contacts`, `search_calendar` and `search_files` stay for consumers built without the index (they say "until SEARCH.md's index").
- Decrypted indexing (old M6) is dropped, and M5 (the gateway's `SEARCH` and `Email/query`) is not carried over: pimgate is retired.

## Decided (2026-10-27)

The aim: Task 2 prepares Task 1 "Pimalaya CLI: REPL and MCP". MCP over search is a milestone MOA needs, and the direction is a domain reliable enough for AI to consume. So:

- **An unknown `field:` is refused**, never read as free text, with a structured error: its position, what was expected, the fields that exist. An agent invents fields; MOA's agent once passed `query` to a tool expecting `text`, the tool ignored it and answered the inbox, and the model took it for results (moa docs/decisions.md).
- **The output contract is a deliverable of M1**, not of the consumers: a JSON Schema for hits, coverage and errors, so the MCP tools of Task 1 only wrap it. A hit carries a snippet and an address `show`, `thread` and `tag` accept as is; no client rebuilds an id from display fields.
- **Extraction records chunk boundaries** per object hash: snippets need them now, and the embedding index (cairn/changes/embedding-index) embeds the same chunks later without extracting again.
- **Measured targets** for the grant: index throughput on a 50k-mail store, query p95 at 1M items, against the `LIKE` baseline of 1.6 s for a no-hit page at 1M (reads-proportional-to-what-they-ask).

What is left here, in the standard:

- **A formal grammar.** §8 is prose. Two parsers must agree on the precedence of `or` against the implicit `and`, on `not` before a parenthesis, on a quote inside a phrase, on an unknown `field:` (refused, as decided above), and on `*` inside a word. An ABNF in §8, a vector per rule, and the error shape a refused query answers.
- **Vectors for what no case pins.** The 21 queries use no `or`, `not`, parentheses or `*`, no relative date (`2w`, `today`), no `has:attachment`, `is:encrypted` or `changed:`, no `name` or `relevance` sort, no threaded listing and no range leaving the horizon (the coverage flag).
- **The time zone database version.** An occurrence of a zoned series resolved through the database (§7) moves when the database does. `index_meta` records the version the occurrences were expanded under, and a change re-expands as a horizon roll does. ical's tzdb-pinned-and-versioned change is what exposes the version.
- **Leaving draft.** SEARCH.md freezes only once an implementation answers every case; until then its schema is edited in place on the terms STORAGE §6 sets.

## Not in scope

The store-side search of reads-proportional-to-what-they-ask (audit item 5): it makes today's `LIKE` reads fast, and those reads stay for consumers without the index.

The embedding index: cairn/changes/embedding-index, after M1.
