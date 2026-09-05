---
cairn: log
change: deletes-and-the-trash
date: 2026-09-05
---

# A local edit survives a remote delete, the engine decides a refused delete, and the trash shows every tombstone

SYNC §5 said new content beats a delete on both sides and dropped a vanished member whatever its placement held, so a contact edited offline and deleted on the server went to the trash under a `Vanished` event, its edit with it. A vanished member holding a body its base does not is re-staged as a pending create under a provisional handle and added on the next run (vector 16); a remote edit over a tombstone that also holds a local edit follows the policy rather than pulling blind.

The delete policy was an option, `Revert` or `Keep`, with a MUST on the caller to pick `Keep` beside other sources; a source configured alone and joined later looped between a revert and a re-add. The engine decides per item from the bindings it loaded: held when another binding exists, reverted when this one is the last. The option and its vector fields are gone. A rejected relocation is a rejected push, pending, not a refused right under the policy, so a move whose connector cannot relocate no longer becomes a copy. A tombstone with no base derives no `Remove` against a provisional handle: the binding is dropped and the item retained. A tombstone held by a source that may not remove it was in neither the live view nor the trash, unpurgeable and invisible; the trash lists every deleted row, `retained_at` saying whether a source still binds it, on `items_retained` re-keyed to `deleted = 1`. SYNC §3, §5, §7; STORAGE §11, §14.1; GUIDE §7, §9, §10, §14; OVERVIEW §7. The trash view is guarded by checks/invariants.sh.
