---
cairn: change
id: a-read-body-is-verified
status: landed
created: 2026-10-18
---

# A body read is checked against its name

## Why

Borrowed from an external engine's blob store: a content-addressed body is verified against its hash on read, and a mismatch is a cache miss, never corruption served.

Most of that store is already this one, so it is not redone: a body is named by the hash of its bytes (STORAGE §5), written to a writer-unique temporary file, synced, renamed and the directory synced, and deduplicated by name. Two of the external design's other ideas are already here too:

- **Bodies outside the sync state, re-derivable caches**: blobs are immutable and live beside the database, a rebuild (§12) re-keys the spine and keeps the items and their bodies, and index.db is derived, droppable and hides stale rows by joining the live store at query time (SEARCH §3, `hit`).
- **Derivation off the store lock**: the search indexer is a store reader (SEARCH §3). The owner's own derivations still run inside its write transaction; that is io-pimdir's derivation-before-the-write.

What is not here: a read trusts the file. §7 makes a store "self-checking" by recomputing hashes on request, and puts blob bytes above the row, but nothing says what a reader does with a body whose bytes no longer hash to its name (a bad sector, a truncated copy of the directory, a writer bug). io-pimdir's `PimdirBlobs::get` and `reader` return whatever the file holds, so a corrupt body is parsed, displayed, pushed to another source or indexed as if sound.

## What

- STORAGE §5: a reader handed a body by hash SHOULD verify it once read whole, and MUST treat a mismatch as the body being absent: the item reads as holding none, and the owner's next upgrade fetches it again from a source that has it. A streamed read verifies at its end and fails the stream.
- STORAGE §7: what an owner does with the bad file (moved aside under a period-prefixed name the collector leaves alone, or unlinked), and that the row is repaired from what the source hands back.
- No body is pushed to another source without having been verified in the same run.

## Decided (2026-10-30)

The pimdir stable-release plan (edit 7): no new column. A read verifies only what it reads whole or streams to its end; a body read in part (an attachment opened by range) is not verified, and no verified mark is kept per object, so the schema does not move for it.

## Decided (2026-10-30)

- A missing file and a wrong one are the same state for every reader, the item holding no body. An owner unlinks a wrong file under the staging lock taken exclusively, as the collector would, rather than moving it aside under a period-prefixed name the collector would then leave for ever; the row stays and the next `Full` upgrade fetches the body again.

## Lands in

storage-draft-05 if done before its tag, else the next draft.
