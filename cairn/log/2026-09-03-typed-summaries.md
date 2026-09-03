---
cairn: log
change: typed-summaries
date: 2026-09-03
---

# The summary is a typed row per kind, and `items.meta` is gone

`items.meta` was an opaque, versioned JSON blob the store never parsed, with Annex A as an informative convention for its shape. Three writers read that convention three ways: io-pimdir's scanner decoded no RFC 2047 and split a vCard property on its first colon, neverest kept its own readers to get both right, and the Android store wrote a calendar meta holding only an ETag.

The vectors were ASCII throughout and every one of those passed them. A summary a reader cannot render fails nowhere, which is the failure §16 was written about, one column further in.

The set of kinds is closed and named by the spec, so a dynamic column preserved nothing anyone could read. It is replaced by five `STRICT` tables, `mail_summary`, `contact_summary`, `event_summary`, `task_summary`, `journal_summary`, named by domain rather than media type (one contact table serves vCard 3.0, 4.0 and a JSContact body) and keyed on the item, cascading with it, referencing no object.

A calendar resource is one component (RFC 4791 §4.1), so it is one row in the table of that component, and a component with no table (`VFREEBUSY`) is an item with a body and no summary.

Annex A is now normative and derives the rows, with an A.0 that says what decoded and verbatim mean and how a property splits, which is where the three writers diverged. `mail_summary` gains `sender_name` and `attachment`; `to` leaves the row for the address table (item-address).

The queue's `add` and `update` carry no summary: the owner derives it from the body it already holds. vectors/meta.json becomes vectors/summaries.json, each case a row plus its addresses, and two fixtures pin what split the writers: an RFC 2047 subject and display name, and a card with an escaped comma, a quoted parameter around a colon and a folded line.

Every reader of `meta` in the eight repositories that carry one migrates with this; it lands before the freeze or not at all.
