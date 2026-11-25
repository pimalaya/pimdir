---
cairn: log
change: the-freeze-plan
landed: 2026-11-25
---

# The oracle answers search

io-pimdir's test generator gains an oracle of SEARCH §8 (io-pimdir cairn/log/2026-11-25-the-oracle-answers-search.md), written from SEARCH.md's text alone, and io-pimdir's suite asks it one query per form of §8.3's grammar over generated stores, after each owner write of a run, beside the fixed store of vectors/search/. Nothing in this repository's documents, vectors or checks moved.

## Lines of cairn/changes/the-freeze-plan/tasks.md this closes

- Section 2, "The oracle: search answers": io-pimdir spec/generator/src/query.rs answers a query's hits as `(account, seq)`, their order in the four orders that are not the index's own, and the coverage §8.2 states, three-valued per hit, a hit it cannot place (a fixture body, which the generator never parses) left undecided rather than guessed.
- Section 5b, "Query vectors: every form of the grammar, run over generator stores, not one fixed store": io-pimdir tests/generated/search.rs, per seed of the generated suite and after each of the twenty writes of its index run, about 176 queries drawn from the model (every field of §8's table, every value of the closed fields, every `date-value` shape, phrases, the wildcard, `or`, `and`, `not`, `-`, groups), compared as hit sets, as ordered lists, page by page, by count and by coverage.
- Section 5b, "The generator's oracle answers every search the vectors ask": the oracle renders vectors/search/store.json and answers each of queries.json's 302 cases; none disagrees with what it decides (123 wholly, 126 on what it decides, 53 left to a fixture body or a threaded listing).

## What the standard's text left open, found on the way

- SEARCH §8.3, "Reserved forms": "a text or a value beginning with `~`" and "Anywhere else, or alone, `~`, `/` and `{` are characters as others" read two ways for `~` alone; queries.json refuses it `reserved-form`, which reads the two-character qualifier as the slash's alone. A sentence for the search lane.
- SEARCH §7 and §8.1: whether a calendar item whose body the index holds none of answers `date:` (io-pimdir dates it at its sort key; §7 expands bodies alone), and how a series whose `UNTIL` falls before its `DTSTART` expands (io-pimdir to nothing; RFC 5545 counts `DTSTART` as the first occurrence of a rule bounded by `COUNT`, and is silent for `UNTIL`). io-pimdir G27 and G28; no vector pins either.
- STORAGE §11.4 releases a binding's `base_object` and says nothing of its `shared_object`, which §5 has outlive the item's body; io-pimdir clears both. io-pimdir G29, outside search.
