---
cairn: tasks
change: round-head
---

# Tasks

## 1. pimdir (this repository, in the working tree, not committed)

- [x] SYNC §2: the head in the terminology; a page belongs to a round, a head or a delta
- [x] SYNC §4: `Enumerate` takes a head's position; **Heads.**: delta and band heads, what each carries, rejection (restart), rekey, none; band-head connectors relist the band in every round's last page; delta-head connectors read pages fresh
- [x] SYNC §5: a head's candidates; step 1 of choosing the listing lists the head; **Heads.**: when, which, checked against the run's scope, merged as a page before the last, delta head stamps and lands its checkpoint, band head neither, no cursor move, no `Add`, no absence, one member, rejection restarts; the close lands the latest checkpoint; creates held through a head's write; a band round's heads move its checkpoint; push discipline
- [x] SYNC §10: a head's load (`Handles` and `Links`); `SetRoundCursor` with no cursor
- [x] SYNC §11: `heads`, `head` (`kind`, `from`, `since`, `rejected`), `interrupted_after` not counting the head, `round_started_at` on a source row
- [x] STORAGE §4.3 and §10: `round_checkpoint` the latest a page or a head handed; a head's write
- [x] queries/storage/owner/set_round_cursor.sql: `coalesce(:cursor, round_cursor)`
- [x] checks/invariants.sh: a delta head lands its checkpoint and keeps the cursor (fails on the old statement)
- [x] checks/vectors.py: a head resumes an open round, of a listed kind, from the round's checkpoint or a band round's source's, or from `round_started_at`; a band head states no removal and carries no checkpoint; a head's members carry their meta
- [x] vectors/sync 62 to 69; vectors/README.md
- [x] GUIDE.md §10 and the vectors entry; OVERVIEW.md
- [x] Review of the design (orchestrator, then Clément)
- [x] Commit; log entry `cairn/log/YYYY-MM-DD-round-head.md` once io-pimdir passes 62 to 69

## 2. io-pimdir

- [x] `PimdirRemote::heads()` (delta, band); `PimdirListing::Head` (a delta from a checkpoint, a band from an instant); `PimdirEnumerated` answers a refused head and no head
- [x] `choose`: when resuming, plan a head before the next page from `round_checkpoint`, a band round's source checkpoint, or `PimdirRound::started_at`
- [x] merge a head as a page before the last (candidates, `Handles` load, `holds_creates` true); stamp and `SetRoundCursor { cursor: None, checkpoint }` for a delta head; nothing for a band head
- [x] a refused head restarts the round over `opts.scope`, never a band
- [x] re-vendor `set_round_cursor`; run vectors 62 to 69

## 3. neverest

- [x] IMAP: delta head through `delta_page` from the round's checkpoint (QRESYNC), never falling back to a round page; band head by `UID SEARCH SINCE` without QRESYNC, and the last page relisting it
- [x] Gmail: delta head through the history read once a run, from each collection's round checkpoint; an expired history id refuses the head; page members whose labels no longer hold the collection are left out
- [x] Graph: band head on `/messages` by `receivedDateTime` (`lastModifiedDateTime` left for a measure on a tenant); the whole-folder round's last page relists the head band after the delta link (a delta head from a stored link: not listed, Graph answers NoHead)
- [x] Stalwart test (neverest tests/heads.rs, QRESYNC and band modes): an arrival during an open round shows at the next run and survives the close; heads per collection in the report left for later
- [ ] live: Gmail and Graph test boxes

## 4. Clients

- [ ] MOA: check on a large Gmail box that an arrival shows during the first synchro (`docs/plan/findings.md`)
- [ ] Android: heads in its connectors
