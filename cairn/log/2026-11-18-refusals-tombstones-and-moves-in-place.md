---
cairn: log
change: the-draft-14-lines
date: 2026-11-18
---

# Refusals, tombstones over a conflict, and moves in place

First lines of cairn/changes/the-draft-14-lines. Version names untouched: the three parts move with the draft-14 bump.

## Rules and their checks

- **What is no refusal** (SYNC §4), owner ruling D34 of 2026-11-16: an HTTP `401`, `407` or `423` is no `Refused`, beside `408`, `409`, `412`, `425` and `429`, and a quota exceeded (an IMAP `NO [OVERQUOTA]`, RFC 9208) is none either, a size exceeded staying one. Each is left unreported, as a transport failure is: a change held by its key (§5) would never be pushed again once the credential is renewed, the lock released or space freed. No vector: the classification is a connector's, and SYNC §12 gives the connector profile none; neverest's and the Android app's connector tests guard it.
- **A deleted and conflicted row** (SYNC §3, §5, §9, STORAGE §10, GUIDE §12), PIM-12 of the CLI family analysis of 2026-11-15: §3 put `Conflict` first while §9 spoke of "a tombstone projected for a conflicted binding". `Tombstone` now comes first, whatever conflict stands, carrying the binding's `conflict_revision` and `conflict_object`, as io-pimdir's hub projects (src/hub.rs, `tombstone_placement`). A binding's conflict names a server edit past its base, which beats the delete: such a tombstone derives no `Remove` whether or not the run lists the member, and is revived or follows the policy. An item conflict holds no delete back: the bodies are the store's, the delete propagates, and the retained item keeps both bodies and its conflict. Vectors 168 (a conflicted binding's tombstone, a delta not listing it: no push, the item revived and still conflicted) and 169 (a delete over an item conflict: the `Remove` pushed, the item retained conflicted with `c2`). Both pass on io-pimdir d6ca71a and on dcf49e2, which projected so already: they pin the reading the old §3 contradicted (under it, 168 would leave the item deleted and 169 push nothing).
- **A move in place** (SYNC §7, STORAGE §15.2, §15.3, §15.4), PIM-14: nothing compared a `move`'s target with the item's own collection, so the item was tombstoned and a create minted beside it, which for a message held without its body never delivers while the tombstone pushes a delete nobody asked for. A `Move` into its own collection is refused staging nothing, a queued `move` there parked naming the collection and never enqueued, and an overlay folds nothing for it. Vector 170, failing on io-pimdir dcf49e2 ("the run failing differs") and passing on d6ca71a (`move-in-place`).
- vectors/manifest.json restated; `checks/vectors.py .` green on the working tree (170 sync cases). checks/tags.sh fails until the draft-14 bump.

## Consumers

io-pimdir passes the three vectors at d6ca71a; its re-vendor follows the bump.
