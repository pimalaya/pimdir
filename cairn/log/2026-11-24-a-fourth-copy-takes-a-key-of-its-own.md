---
cairn: log
change: a-fourth-copy-takes-a-key-of-its-own
landed: 2026-11-24
---

# A fourth copy takes a key of its own

Found by the live test night of 2026-11-23 (.lanes/live/report.md of the workspace, §4): himalaya copying one message from INBOX into a folder and trashing it, again and again through its pimdir queue, drained by neverest on Stalwart. The fourth copy into one collection was parked for good, "binding … dup:dup:nv-abs-10@example.org#…#… holds handle 4 and this write carries …: a binding pins one handle": the key staged for it was the third copy's. Nothing was lost (parked, server untouched). Reproduced on a copy of the scratch store, the parked row retried and drained.

The rule stood: SYNC.md §7 keys the create by the identity minted over the provisional handle it derives, minted again over a held key, and STORAGE §9 has minting yield a free key. io-pimdir read the target for the bare key and its first mint alone, so the second mint was taken unread. No part's text moves; sync-draft-15, storage-draft-17 and search-draft-17 stay as they are.

## SYNC.md §7, a copy or a move beside held copies

- A `Copy` into a collection holding the identity three times, under the bare key, its mint over the provisional handle it derives and that key minted again, takes the key minted a third time, its own `seq` and a pending create under the provisional handle that key derives. Vector 215 (the engine took the third copy's key and the write refused the rebind).

io-pimdir follows in the commit checks/io-pimdir.rev names.
