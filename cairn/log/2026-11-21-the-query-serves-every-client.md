---
cairn: log
change: the-query-serves-every-client
landed: 2026-11-21
---

# The query serves every client

search-draft-16. SEARCH §8 gains `mid:`, a message's `Message-ID` matched whole with or without its brackets, in place of the proposed generic `header:` (the owner's ruling of 2026-11-21, after notmuch: notmuch-search-terms(7) has `id:`/`mid:` and no generic header term, `In-Reply-To` reached through threads); §8.1 instants (`day T hh:mm[:ss][Z|±hh:mm]`, a minute or a second, a skipped local time read at the offset before the transition, a repeated one as its first) and the relative units `min`, `h` and `mo` (a month counted on UTC's calendar, a day the month lacks landing on its last); §8.2 five orders, each one value with its direction, after notmuch's `--sort`: `newest-first` (the default), `oldest-first`, `title` (was `name`), `sender`, `relevance`, a thread standing by its first hit. §8.4 is unchanged: a field a client does not serve stays `unknown-field` in the index.

Rules and their checks: the field table, §8.1 and §8.3's ABNF by the new cases of vectors/search/queries.json (now `v` 5, `sort` taking the five names) and checks/vectors.py's re-derivation of their refusals and of the zoned instants over mail and Agenda; the orders by a case each, answered by io-pimdir. The skipped-time rule has no vector: checks/vectors.py re-derives a zoned case over single events only, and no such fixture stands in a gap; io-pimdir's compile tests pin it.

Draft names moved: SEARCH's Status line and §2, §12, STORAGE §17's example, README, AGENTS.md, conventions/gtd.md, init_index_meta.sql, checks/invariants.sh. checks/io-pimdir.rev moves with the io-pimdir commit that follows.
