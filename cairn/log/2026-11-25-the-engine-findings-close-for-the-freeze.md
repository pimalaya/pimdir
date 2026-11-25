---
cairn: log
change: the-freeze-plan
landed: 2026-11-25
---

# The engine findings close for the freeze

The sync and storage findings that stood before the freeze, read against storage-draft-18 and sync-draft-16. No rule moves and no number with it: vectors 231 and 232 are new, 114 and 115 state more of what they already held, and io-pimdir follows (its cairn/log/2026-11-25-the-engine-findings-close-for-the-freeze.md). Two readings are left for the owner.

## Pinned

- **SYNC §3, §5, §9: an edit beats a delete only by a body the deleting server never held.** io-pimdir's hub property (tests/engine/hub_property.rs) found a case it read as a lost edit: a source pushed an edit, its server then deleted the member, and a second source, which had not synced the edit, staged the very same body. The first source's absence drops a placement holding its base's body (§5) and the item is deleted; the second projects a `Tombstone` (§3, rule 1) and pushes the delete, its remote unchanged so no remote edit revives it. Nothing is lost: the body it staged is the one the server deleted. The property was wrong, not the engine. Vector 231 pins the second source's run; it passes on io-pimdir unchanged, and fails on an engine reviving the item for the staged body.
- **SYNC §9, STORAGE §11, §11.1: a body a bodiless revive sets aside keeps its own summary and sort key.** Vector 232: a card retained as Jane Doe, restored at Meta as Jane A. Doe, keeps `c1` under `jane doe`. It failed on io-pimdir 55d2702, which gave the kept body the reviving member's sort key (finding G12 of its replay, left standing on 2026-11-21).
- **SYNC §9: a fill settling an item conflict leaves the adopted body's summary and sort key on the item, and its own on the body it keeps.** Vectors 114 and 115 now state the summary the emptying pull left before and both rows' summaries and sort keys after; io-pimdir passes both unchanged.

## Left for the owner

- **G29, STORAGE §5, §11.4 and §14 disagree.** §11.4 releases a binding's `base_object` naming the released body and says nothing of `shared_object`; §5 has `shared_object` outlive the item's body until every binding reconciled against what replaced it; §14 ("A body two members stating one hint would share") releases a body "as §11.4 releases one", naming each binding's `base_object` and `shared_object`. io-pimdir clears both (release_bases_before, as cairn/log/2026-10-30-a-merge-keeps-every-body.md decided: a message has no cross-source merge to read the ancestor for); the generator's upkeep clears the base alone. Read literally, §5 keeps the body pinned and a release frees nothing a synced binding agreed on. Proposed: §11.4 names `shared_object` beside `base_object`, and §5 carves out a release of a message's body, an immutable kind never diverging (SYNC §9); a vector can then pin it and the generator follows. A text change, so storage-draft-19.
- **A mutable revival whose member carries another body.** tasks.md "Left on 2026-11-20" reads it as keeping the old body; STORAGE §11.1 reads the other way: "A revive adopts the incoming body when there is one", the retained body kept apart only "when the incoming placement carries none", and "the pins the retained row held are released only for what the revive replaced". io-pimdir releases it (a draft vector stating the keep failed there: no `Overruled`, no retained `c1`); the generator keeps it (spec/generator/src/engine.rs, `revive`, keeping whenever the row's body differs from the carried one). The body such a row holds is one a person deleted or a server's earlier version, so releasing loses nothing anyone chose to keep; keeping it costs a trash row per restore. No vector until ruled: if the text stands, the generator follows it; if the owner wants the keep, STORAGE §11 and §11.1 and SYNC §6 move, and io-pimdir with them.

## Guards

- vectors 231 and 232, 114 and 115 (checks/vectors.py, `nix flake check path:$PWD`); io-pimdir's tests/vectors_sync.rs runs all four, 232 failing on 55d2702.
- vectors/README.md and vectors/manifest.json restated.
