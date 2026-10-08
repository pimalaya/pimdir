---
cairn: log
change: a-move-beside-a-held-copy
date: 2026-10-08
---

# A move beside a held copy pairs with its minted create

A `Copy` or a `Move` into a collection already holding the identity keys its create by the identity minted over the provisional handle it derives (`dup:<hint>#` then `U+0001` and the hint). The origin, the destination and the landing matched the exact key only, so the minted create had no origin, the tombstone no destination, and the remove went out as a plain delete. A source holding no body left nothing to deliver the create: the message was gone from the server. Seen on Pimalaya Android, a move to Trash of a message Trash already held under the same `Message-ID`, its body never downloaded. draft-04 is not tagged, so the number stays.

## Rules

- **SYNC §3, the same identity.** An origin and a destination pair a key with itself or with the key minted over the provisional handle it derives, the bare key preferred; a destination is named by the create's handle. `origin_for_link` and `destination_for_link` match both forms, the bare one first, and the destination statement returns the create's handle. Guarded by vectors/sync/48 (destination) and 49 (origin), both failing on the previous statements.
- **SYNC §4 and §5, the remove's `link_id`.** A remove whose destination is a minted create carries no `link_id`: the target held the identity before the move, and a connector checking that `to` holds it would delete. A copy the target held before is not the move's delivery. Guarded by vector 48, which expected a plain delete under the previous text.
- **SYNC §6, landing.** A hint lands a pending create keyed by the hint or by the hint minted over its provisional handle, the bare key first. io-pimdir already did (2eb6d42); the text did not say so. Guarded by vector 50, which an engine matching the bare key alone fails by minting `dup:<hint>#4`.
- **SYNC §7.** States the key a `Copy` or a `Move` takes beside a live holder.

GUIDE §9, §10 and §11 mirror the four.

## Left open

- A target holding both the identity and its once-minted key mints the create twice (`dup:dup:<hint>#…`), a key none of the rules above pair. It takes two earlier copies of one identity in one collection; the pairing would need a recursive match.
- A rekey of the target while a relocated arrival is not landed yet mints the arrival rather than landing the create, pending creates being outside the rekey (§8). Same for the bare key, so not specific to the mint; nothing is lost, the create stays pending.
