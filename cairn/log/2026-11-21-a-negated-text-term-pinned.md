---
cairn: log
change: a-negated-text-term-pinned
landed: 2026-11-21
---

# A negated text term pinned

search-draft-16, edited in place. vectors/search/queries.json gains `(stand-up or reunion) not nothing`, answering `[home, 2]`: text terms alone, a negated one taking its hits away (SEARCH §8.2), the body of item 1 saying "Nothing to report." No case held a text term negated beside text terms alone, so an implementation counting such a query off the full-text index, without the store, could combine the negated term's hits as a conjunct's and pass every vector: io-pimdir's bitmap count did (cairn/log/2026-11-21-text-counts-off-the-index.md there). The manifest records the file's new digest and its 302 cases; checks/vectors.py checks it.
