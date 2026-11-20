---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# A hostile zone is indexed within bounds

io-pimdir's generated suite found that event-zoned-hostile.ics, whose zone's DAYLIGHT rule steps every second from 1970, exhausts the indexer's memory through ical-rs's zone transitions (G8). Its summary vector pinned the store's reading (Annex A.3); no search vector indexed it.

- **vectors/search/refresh.json**, a fourth case: the event filed alone and indexed, a coverage written, then its title (`stepping`) and its kind (`kind:event`) answer it, a canonical index holding its one body. Decided by the lead: the case requires termination and the item's presence by the fields it states, never the instant a zone this hostile resolves to, which is the implementation's own.
- No rule moves: SEARCH §7 and STORAGE Annex A.3 bound what an expansion and a zone walk follow; the case is the check that an indexer honours them.

io-pimdir lists the case pending, and runs none of it, until it takes the ical-rs that bounds the walk (ical-rs "fix(tz): read a zone through a bounded walk", unreleased), moving its `EXTRACTOR` revision then; checks/implementation.sh fails while the case is listed, which is the freeze gate's.
