---
cairn: change
id: absence-deletes-only-from-a-complete-round
status: landed
created: 2026-10-30
---

# An absence deletes only from a closed, complete round

## Why

Edit 3 of the pimdir stable-release plan (2026-10-30), from blocker 3 of the consolidated pimdir review, adjusted there: for IMAP without QRESYNC, DAV `PROPFIND` and most collection listings, absence from a complete listing is the only deletion signal, so absences must keep propagating. The defects are that the text contradicts itself and that nothing binds completeness.

- SYNC §5 (SYNC.md:147 at 8b2e8b6) forbids a `Remove` derived from "any absence", while SYNC §9 (:270) and §5 (:192) propagate a round's absences as tombstones.
- The page flags `complete` and `last` (§4, :87), "absence means deleted only in scope" (§5, :143) and the round paragraph (§5, :155) carry no keyword, so by SYNC's own preamble they bind nothing.
- The engine side is unspecified: io-pimdir closes a round on a non-last page with no cursor "whatever it says" (src/sync.rs:572-577).
- No backstop against a connector bug (neverest: a `UIDVALIDITY` change listed as an empty mailbox, a truncated DAV listing, hidden Google calendars) dropping most of a collection.
- SYNC §5 forbids deleting a server collection "from any absence", and neverest does it with `collection.delete` on by default.
- checks/vectors.py:650-663 checks a weaker rule than the prose; no two-source case covers a partial round.

## What

- SYNC §5: the absences that count are those of a closed, complete round, in its scope; they drop the member `Deleted` and propagate to every other source as a tombstone (§9). Nothing else (a page before the last, an interrupted or restarted round, a head, a delta, an out-of-scope member, a band round's undated member, a parked round) is an absence. A `Remove` comes from a tombstone the store holds, the consumer's or one a delete on another source left.
- SYNC §4 and §5: `complete`, `last` and the resume cursor get MUST; an engine MUST refuse a non-last page without a cursor, failing the run before that page's write.
- SYNC §5: the mass-absence guard. A round whose absences would drop more than 50% of its scope's bound members, the scope holding at least 20, parks: it is not closed, nothing is tombstoned, the run reports the counts; a later run relists it and decides again, and a run carrying `accept_absences` closes it.
- SYNC §5: a server collection is never deleted because another source stopped listing it unless the configuration enables it, and then only when the collection is empty or every member was reconciled in the same run.
- vectors/sync 74 to 79; checks/vectors.py checks the prose rule; GUIDE §10, OVERVIEW §5 and §6 follow.

## Decided (2026-10-30)

- The park is not stored: the round is left open with no cursor, nothing tombstoned, the run reports it, and each later run relists and parks again until the caller confirms through the run's `accept_absences` option. STORAGE is untouched.

## Lands in

sync-draft-05.
