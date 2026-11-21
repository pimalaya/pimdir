---
cairn: change
id: the-query-serves-every-client
status: landed
created: 2026-11-21
---

# The query serves every client

## Why

Calendula and Cardamum already parse their unified search with the SEARCH query language (§8) through io-pimdir. Himalaya, the client with the oldest and widest query system, still has its own grammar (chumsky, `from alice and after 2026-01-01 order by date desc`), so the family speaks two search languages. Moving Himalaya onto §8 needs three things §8 lacks, and SEARCH is frozen with STORAGE and SYNC (the-freeze-plan, D3, 2026-11-20), so they land before the freeze or not before v2:

- a message's `Message-ID`: `id:` names a pimdir item, not the header;
- times of day: a point is a year, a month or a day, and a relative amount counts days, weeks or years, where Himalaya takes `5 hours ago` and RFC 3339 date-times (himalaya #528, closed as fixed on 2026-11-21);
- an order: §8 has none, the index's `search` takes date, name or relevance, where Himalaya orders by date, sender, recipient or subject, either direction.

## What

Notmuch is the model (notmuch-search-terms(7), notmuch-search(1), 0.40), as the owner decided on 2026-11-21.

- **`mid:` field.** `mid:<message-id>`, notmuch's name, matched whole against `mail_summary.message_id`, the value read with or without its angle brackets; a contact, an event, a task, a file never match. No generic `header:` field, as notmuch has none: a header beyond `Message-ID` is not searched, and `In-Reply-To` is reached through `thread:`. A field a client does not serve stays `unknown-field` in the index (§8.4 unchanged) and the client's own refusal elsewhere.
- **Instants.** `point` gains `instant = day "T" 2DIGIT ":" 2DIGIT [ ":" 2DIGIT ] [ offset ]`, its span its own minute or second, read in the stated zone when it carries no offset; `relative` gains `%s"min"`, `%s"h"` and `%s"mo"` (calendar months). Mail still compares `sort_key`.
- **Orders.** Outside the grammar, as notmuch's `--sort`: §8.2 names five orders, each one value with its direction, `newest-first` (the default), `oldest-first`, `title` (A to Z, folded as Annex A.2 folds `fn`), `sender` (A to Z over the first `From` mailbox's address; any other kind holds none and sorts last) and `relevance` (best first), ties broken by `(sort_key, seq)`. A thread list sorts by its newest member under `newest-first` and its oldest under `oldest-first`, so the two are not reverses. A recipient order is not added: the index holds no single recipient per message.
- **Vectors** for each: `mid:` with and without brackets, instants with and without offset across a zone transition, `h`, `min` and `mo` amounts, each order.

Nothing else moves: the fields of §8, the text semantics (§8.5, tokens, never substrings), the limits and the refusals stay.
