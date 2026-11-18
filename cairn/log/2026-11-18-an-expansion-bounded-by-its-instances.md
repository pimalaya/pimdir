---
cairn: log
change: the-draft-14-lines
date: 2026-11-18
---

# An expansion bounded by its instances

The owner's rulings of 2026-11-18 on cairn/changes/the-draft-14-lines: D6 (a), the refused offered create bound as the source's pending create, stands as landed (cairn/log/2026-11-18-a-refused-offered-create-is-bound.md); D7 (a), folded into search-draft-14 before its tags, which no part has yet, so no version name moves.

## Rules and their checks

- **The instances an expander walks** (SEARCH §7, §11, GUIDE §15): at most 10,000,000 instances of a recurrence rule, each start it yields in turn from its `DTSTART`, before the horizon or in it, an `EXDATE` notwithstanding, whatever `COUNT` it states beyond them; the cut is the earliest of the 10,001st occurrence, the first period not examined and the first instance not walked. A `VTIMEZONE` observance's rule stays on the period bound alone. PIM-15 of the CLI family analysis of 2026-11-15: a 570-byte event walked every instance a `COUNT` named, 22 s in release.
- Vector: search store item 35 (fixtures/event-dense.ics), every second from 2025-04-26T19:13:20Z under `COUNT=4000000000`, cut at 2025-08-20T13:00:00Z, its 10,000,001st instance, having written the horizon's first 3,600 seconds; the window 12:59:58Z to 13:00:02Z lists two rows, where the occurrence bound alone writes four (cut 14:46:40Z), and the case `kind:event date:2025-08-20` counts it cut. The four existing `cut` cases count it too, and `changed:..1000000000` lists it.
- checks/vectors.py reads the third bound from the prose and expands a rule whose `BYxxx` parts only expand each period into the same instants, a `COUNT` or none beside them, by arithmetic; the window fails it with the bound at 20,000,000 in the prose, and a row past 13:00:00Z fails it.
- vectors/manifest.json restated; `checks/vectors.py .` green (221 search cases, 8 windows).

## Consumers

io-pimdir follows in its working tree: the bound in its expander, the vendored copy at this commit, then the pin, before the owner tags draft-14.
