---
cairn: log
change: search-part
date: 2026-09-03
---

# Search joins the standard

Search was out of scope, a consumer-private index. Every consumer then paged whole collections into memory and filtered, sorted and searched in its own code, and the index a consumer would build is shared read state: the GTK app, himalaya and pimgate open the same file, and two clients answering `is:unread from:jane` differently is the Annex A divergence one level up.

SEARCH.md is a normative part with a status of its own. index.db sits beside the store with its own `user_version`, so a mismatch is a rebuild and never a migration. FTS5 runs over bodies keyed on the object hash, so a body filed in three collections is tokenised once.

A summary table covers bodiless placements, so a headers-only replica still searches. Occurrences within a horizon give calendar time, threads key on link ids, flags are a derived table, and the language is notmuch-shaped, extended with `kind:`, `with:`, `person:` and `account:`.

The store already answers the structured half through the summary and address tables, so the index carries only text, time and threads.

A hit is `(account, seq)` with its placements, tags follow the union rule, and coverage is part of every answer. migrations/index/0001_init.sql and queries/index/search.sql are canonical, and checks/schema.sh applies them to an index and prepares the statements with the store attached.

vectors/search/ holds the fixture store and fourteen queries every conforming index answers alike: diacritics, a domain token, a digits-only telephone number, a series occurrence and a bodiless hit among them.
