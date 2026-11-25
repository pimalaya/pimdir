---
cairn: log
change: the-oracle-follows-search-draft-19
landed: 2026-11-25
---

# The oracle follows search-draft-19

search-draft-19, requiring storage-draft-18. io-pimdir's SEARCH oracle (cairn/log/2026-11-25-the-oracle-answers-search.md) was written before search-draft-18 landed and disagreed with four of queries.json's cases since; it now follows the text, and the two readings it found (io-pimdir G27, G28) are settled or put to the owner. io-pimdir follows in its change of the same name.

## Rules and their checks

- **SEARCH §7: a calendar item holding no body yields no occurrence** (io-pimdir G27). io-pimdir dated such an item at its sort key (`kind:event date:2026-06` answering the hostile-zone fixture its generated suite leaves bodiless). The text reads one way: §8.1 has an event, a task or a journal compare occurrences and nothing else, §7 expands them from the resource alone, §6 lists all a bodiless placement is matched on (its title, people and role fields, no date), §4 keeps occurrences only for a body once read, and §8.2 classes `date:` over calendars as a term reading a body, counting a `bodiless` item against it. A bullet of §7 now says so: such an item, and one whose body the index never read, yields none, its sort key standing for none, a date term matching neither, the coverage counting it. For a person: an event whose body the store released or never fetched is not found by `date:` or `when:` until its body is read, and the answer says it is incomplete. OVERVIEW.md §10 follows. Check: vectors/search/extraction.json's new last case, "a calendar item holding no body" (`kind:event` a hit and complete; `kind:event date:2026-06-01` and `date:2026-06` no hit and incomplete, the item counted `bodiless`; `summary:planning` a hit matched on its summary), which fails on io-pimdir before (both date queries answered the item).
- **vectors/search/extraction.json `v` 2**: a store's bodiless item may state an `event_summary` row, beside `mail_summary` and `file_summary` (vectors/schema/search-extraction.schema.json, its `const` and the row's shape as summaries.json's); SEARCH §11 and vectors/README.md name it. The case list is appended to, nothing else moves.
- **SEARCH §8.3: the reserved forms**, reworded to what queries.json, checks/vectors.py and io-pimdir already did: a text or a value beginning with `~`, `~` alone included; one of two characters or more beginning with `/`; a value beginning with `{`. "Anywhere else, or alone, `~`, `/` and `{` are characters" contradicted the case refusing `~` alone; `/` alone stays a character (the case `/`, no hit). Checks: queries.json's `~` (refused 0-1) and `/` cases, unchanged.
- **The oracle answers the vectors where it decides** (io-pimdir spec/generator/src/query.rs and query/): `subject:""` a text term yielding no token, no hit; `thread:` over the threads of the whole store, its members in every account holding one (the owner's ruling of 2026-11-25, which it read per account); a relative amount closing a range spanning its instant alone (`2w..2w` empty); `linked:<role>:` with no id refused `invalid-value`; every refusal's span, `dangling-operator`'s first operator of a run missing its term among them; what each hit matched on, where every text term of the query stands unnegated. It holds all 353 cases of queries.json, spans and `matched` included, and the 83 queries of extraction.json, none disagreeing (162 of the 436 agreeing wholly, 166 on what the oracle decides, 108 left to fixture bodies or a threaded listing); refresh.json is not asked, the model following none of its owner writes. Four cases failed it before (`subject:""`, the two `thread:reply-1@example.org` cases, `linked:sender:`).

## For the owner: io-pimdir G28

A series every recurrence rule of which states an `UNTIL` on a day before its `DTSTART` (the generated suite's `DTSTART:20261122T143216Z`, `RRULE:FREQ=WEEKLY;UNTIL=20260512T181043Z`): does it occur at its `DTSTART`?

- RFC 5545 §3.8.5.3 says yes, unconditionally: "The "DTSTART" property defines the first instance in the recurrence set", and again "The "DTSTART" property specified within the iCalendar object defines the first instance of the recurrence"; §3.3.10's "The UNTIL rule part defines a DATE or DATE-TIME value that bounds the recurrence rule in an inclusive manner" bounds the rule, not the set, and "The "DTSTART" property value always counts as the first occurrence" is said of `COUNT`. Only a `DTSTART` "not synchronized with the recurrence rule" makes the set undefined, which a rule stating no `BYxxx` part cannot be.
- ical-rs, which io-pimdir expands with, says no, deliberately (ical-rs 0.7.3 src/recur/set.rs `is_cut_before_start`, its cairn/log/2026-10-29-timeline-oracle-second-round.md, settled toward recurring-ical-events): such a series is the shape a client leaves when it deletes a series from its first instance on, so its `DTSTART` is no instance either.
- SEARCH §7 says neither.

Recommended: ical-rs's reading, written into SEARCH §7 as a stated departure from RFC 5545 §3.8.5.3, because the family's calendars (calendula, the Android app) expand with ical-rs, so search then finds exactly the instances a person's calendar shows. Consequence for a person: a series deleted from its first instance on is not found by date (with RFC's reading it would come back as one ghost occurrence at its old start, which no calendar of the family shows); an event mistakenly written with an `UNTIL` before its start is not found by date either. The RFC's reading means changing ical-rs and every consumer of it. Either way the ruling lands with a fixture under vectors/fixtures and an appended extraction.json case, and the oracle's `Readings::start_counts` becomes the rule.

## Versions

search-draft-19 on SEARCH.md's Status line, §2 and §12, README.md and AGENTS.md; storage and sync unchanged. vectors/manifest.json restated.

## Left

- G28, above.
- checks/io-pimdir.rev and io-pimdir's spec/REVISION move with the commits of this change.

Checked: `nix flake check path:$PWD`; io-pimdir's suite over this tree's migrations, vectors and payloads, and its generator's tests (cairn/log/2026-11-25-the-oracle-follows-search-draft-19.md there).
