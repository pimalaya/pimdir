---
cairn: change
id: trash-disposal-is-a-move
status: landed
created: 2026-10-08
---

# A delete that ends in a trash is staged as a move

## Why

SYNC §4 leaves the disposal of a plain delete (expunge, trash) to the consumer. A consumer that disposes into the server's trash at push time, as the Pimalaya Android app did, stages a `Remove` and pushes a move: the store records the item gone while the server holds it in the trash, and the trash collection learns of it only when next listed. The user deletes, opens the trash, and finds nothing. Nothing in the spec is wrong; it only does not say which mutation fits.

## What

A non-normative note for implementers, in SYNC §7 (Mutate) and GUIDE.md beside the mutations:

> A delete the consumer means to land in a trash collection is a relocation, not a delete: stage it as `Move` into that collection, so the trash shows it before any sync and the push relocates it (§4). Keep `Remove` for a delete meant to be final, as from the trash itself. A `Remove` pushed as a move leaves the store unaware of the copy it made until that collection is listed again.

No normative change, no vector.
