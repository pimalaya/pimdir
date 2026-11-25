---
cairn: log
change: the-empty-span-matches-nothing
landed: 2026-11-25
---

# The empty span matches nothing

Live night 3 (calendula on microsoft-pimdir, 2026-11-25 21:47Z) found SEARCH §8.1 reading two ways: `date:2w..2w` is "the empty span", yet the overlap rule (an occurrence starts before the range ends and ends after it starts) holds for an occurrence running across that instant, so the query answered a yearly all-day event whose occurrence contained it. io-pimdir d5f2b89 and its generator's oracle both followed the overlap rule; the only vector was `kind:mail`, where an empty span already matched nothing.

The lead of the night took the recommended reading under the owner's rule of 2026-11-25 (take the recommended spec decisions, report them in the morning for confirmation): a span whose end is not after its start is empty, holds no instant and matches nothing, whatever the kind. The other reading, an empty span asking which occurrences are under way at its instant, would give `2w..2w` a meaning for calendar kinds and none for mail, and a range ending before it starts (`1d..2d`) one too.

## Rules and their checks

- SEARCH §8.1, "Every span is half-open": an empty span (end not after start) matches nothing, whatever the kind. Guarded by vectors/search/queries.json `collection:home/Agenda date:1d..1d` and `collection:home/Agenda date:1d..2d` (now 2027-01-02T12:00:00Z, in UTC): io-pimdir d5f2b89 answered the all-day event of 1 January to the first.

search-draft-20 has no tag and is edited in place (AGENTS.md §2). io-pimdir follows (its cairn/log/2026-11-25-the-empty-span-matches-nothing.md).
