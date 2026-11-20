---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The engine seams the generator found

The sync cases the generator's engine model read from SYNC (cairn/log/2026-11-20-the-generator-engine-several-sources.md, the-generator-engine-scopes.md) and no vector pinned, landed in sync-draft-15, no number moving. Sync vector format 11, every case restated.

## What moved

- **SYNC §5, the events** (normative, clarified): `Added` names a member joining an item other sources bind, never `Created`, which names this source's own create; `ContentChanged` names a body the item took, a joining member's a collection policy adopted included, never one a policy kept apart, the item keeping its own. Vectors 182 (a `prefer-existing` fold reports `Overruled` alone), 184 (a mail join reports `Added` alone, its flags folded with no base, b's missing flag pushed) and 185 (a card joining with a diverging carried body is settled by the collection's `prefer-incoming`, reported `Added`, `ContentChanged`, `Overruled`).
- **SYNC §9, a `PreferRemote` pull over an item another source changed** (no rule moves, pinned): the fold finds a divergence the collection's policy settles, and the body another source folded is kept once by that policy, never as the pulling source's dropped edit (§9, "over an item that had not changed for it"). Vectors 181 (`prefer-incoming`), 182 (`prefer-existing`), 183 (`manual`, the item conflicted and nothing kept).
- **SYNC §5, creates wait for the page that lands them** (no rule moves, pinned): vector 186, a pending create beside a round a mass absence parks derives no `Add` while the round stays open.
- **SYNC §5, the report of a capped round and of a narrowed one handing no enumeration** (normative, promoted): the run MUST report how many based bindings it left unlisted, counted as the deletes are; it was a SHOULD, kept as one by cairn/log/2026-11-20-the-shoulds-and-mays-reviewed.md, and no vector could state it. io-pimdir reports it (`PimdirSyncReport::unlisted`) and neverest shows it. SYNC §11 adds `unlisted` to `expect`, none stated being none, which moves the sync format to 11 (vectors/schema/sync.schema.json); vectors 107 (3) and 134 (1) state it.
- checks/vectors.py derives `unlisted` for a closing capped round or narrowed one handing no enumeration (the based bindings of the source in scope that no page listed, stamped or vanished, a held tombstone aside), refuses it on any other case, and counts the rule as held. vectors/README.md and GUIDE §10 follow.

## Guards

- Vectors 182, 184 and 185 fail on io-pimdir edbcf0b ("events differ": `ContentChanged` under `prefer-existing`, `Created` for a join, the source's `Manual` recording a join's diverging body) and pass on the io-pimdir following this entry (its cairn/log/2026-11-20-a-join-is-added.md); 181, 183 and 186 pass on both.
- checks/vectors.py fails on 107 and 134 without their `unlisted` ("0 is not 3", "0 is not 1"); io-pimdir's runner compares the count.

## Left

- A member joining an item without carrying its body, the usual DAV listing at `Meta` (draft vector set aside, not landed): SYNC §9 records it as an item conflict whatever the policy, and §6's upgrade under `manual` lands the fetched body in `items.conflict_object` even when it equals the item's, which no rule clears. Joining a second address book would leave every identical card conflicted. For the owner, with a recommendation in the lane's report.
- Whether a run pushes what its own fold leaves owed (182: the source's base moves to the refused body, so it owes the item's): the generator's model pushes it in the same run, io-pimdir on the next one; 182 runs with `push` false. For the owner.
