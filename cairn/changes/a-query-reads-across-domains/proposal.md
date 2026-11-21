---
cairn: change
id: a-query-reads-across-domains
status: draft
created: 2026-11-21
---

# A query reads across domains

## Why

compared-with-notmuch found notmuch fast, exact and composable, with well-chosen features; the owner (2026-11-21) wants pimdir to take that and extend it to every domain, the domains linked: a person's card, the mail they sent and the meetings they attend are already one answer (SEARCH §1), and a query should be able to select mail by what the contacts in the store say. The store holds what that needs: `item_address` across every kind (Annex A.6), references (§14.2), categories, threads (SEARCH §9). What the language lacks is a way to say "the values of this field, taken from the items another query matches". notmuch has one case of it, `thread:{query}`, and the general form in its sexp syntax, `(matching …)`.

`person:` is today's hard-coded instance (contacts whose title matches, expanded to `with:` over their `email` rows).

## What

Designed here, specified as each lands after v1 (every spelling reserved by the-query-reserves-its-later-forms, so each is a minor version):

- **Subqueries, `field:{query}`.** The field's values taken from the items the subquery matches, then matched as the field matches a value:
  - `thread:{from:jane}`: every member of the threads holding a hit;
  - `from:{category:family}`, `with:{collection:work-contacts}`: mail by the addresses of the contacts matched;
  - `attendee:{kind:contact category:client} date:2026-12`: the meetings of December with clients;
  - `linked:{subject:"offer 42"}`: the items at the other end of those messages' references;
  - `person:x` restated as `with:{kind:contact title:x}`.
  The subquery is scoped as a query is (§8.2), its coverage folded into the answer's, nesting bounded by §8.3's limits.
- **A thread summary.** A statement answering, per thread of a page: its id, matched and total members, the senders split matched and unmatched in date order, the subject of its first hit in the query's order, its first and last dates, the union of its members' flags. A second statement answering the reply tree (`message.parent`). Both on SEARCH §9's tables.
- **A `list:` field.** The message's `List-Id` (RFC 2919), the identifier between its angle brackets, matched whole and case-insensitively; one extraction revision (§6).
- **Address harvesting.** A canonical statement answering the distinct addresses of a role across every kind with how often and how lately each appears, deduplicated by address, case-insensitively, the most frequent display name kept: completion and "people I write to" for every app.
- **Recursive collections.** `folder:Lists/**`, a collection and every collection below it by STORAGE's parent links.
- **Proximity.** `NEAR(a b, n)`-style terms, FTS5's own, the grammar's spelling to choose.
- **Regular expressions.** `field:/re/` on the raw value of the subject, the senders, the Message-ID, a collection id, a flag, as notmuch matches them (lib/regexp-fields.cc): a filter over the candidates of the query's other terms, a scan of the field when alone, an expansion over the distinct values for a closed field (flags, collections); ERE; evaluated in the implementation, never as a registered SQL function (§5).
- **Stemming.** `~word`, in a stated language, on terms the index stems at extraction; the plain word stays exact.

## Order

After io-pimdir's planner (cairn/changes/as-fast-as-notmuch): a subquery, a regex and a thread summary are driver sets and residual filters, and on today's compiled query, which reads every live item, each would cost the store twice.
