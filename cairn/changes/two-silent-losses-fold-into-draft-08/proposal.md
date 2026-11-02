---
cairn: change
id: two-silent-losses-fold-into-draft-08
status: landed
created: 2026-11-01
---

# Two silent losses fold into draft-08

## Why

Two of the items cairn/changes/the-consumers-gaps-fold-into-draft-08/tasks.md left open lose a body nobody chose to lose:

- A queued `update` states no `overrule`, so its `Edit` is a person's settle (SYNC §7). One queued before an item conflict arose, its `if_match` naming the body the item keeps under `manual`, passes that guard and settles the conflict on drain, discarding the diverging body silently. The same holds for a binding's conflict, which the `Edit` resolves by pushing over the server's diverging body.
- STORAGE §5 keeps any file already holding a final name. The Android app's fallback move, an exclusive create then a copy (android cairn/log/2026-11-01-the-shape-follows-storage-draft-08.md, "Re-pin to 09d2d1c"), leaves part of a body under the name when a crash cuts the copy; a later write of the same body keeps the part, and once a read quarantines it the body only that device held is gone. STORAGE §5 named no such move, so the app's reading was its own.

## What

1. SYNC §7 and STORAGE §15.2, §15.3: an `Edit` without `overrule` settles a conflict only as a person's resolution stating `resolves`, the `conflict_object` of each conflict it meets; otherwise it is refused and the drain parks the `update`, as it parks one stating `resolves` over no conflict. payloads/update.v1.schema.json defines `resolves`, a non-empty array of distinct object names.
2. STORAGE §5 and §7: a writer finding its name held verifies the file there; an owner quarantines one that fails and writes again, a producer fails its write. The exclusive create and copy is named as the one non-atomic no-replace move, allowed only where no atomic one is offered or allowed, with its crash caveat; the Android note follows the app's API 30 gate.

## Decided

The user decided on 2026-11-01 both rules and to fold them into storage-draft-08 and sync-draft-07 without a new draft number, as the-consumers-gaps-fold-into-draft-08 did: neither is tagged and no schema moves. Choices made here, within that decision:

- **`resolves` names bodies, not a flag.** A boolean says a resolution happened but not of which conflict, so a resolution decided over a conflict since settled would settle the next one. Naming the diverging body, the `conflict_object` the person was shown, ties the decision to the conflict it was made over; a conflict nobody has read (`conflict_object` `NULL`) can be named by none, as an overrule cannot settle it either (SYNC §7). It is an array because an item and the binding an edit runs through may both be conflicted with different bodies, and a single name would leave such an item unresolvable by any update; the producer cannot know which binding the drain runs through, so it names every conflict it showed, a superset passing. A resolution meeting no conflict parks, the conflict it decided being settled already.
- **The gate is on the `Edit`, not only the drain.** A frontend embedded in the owner calls `Edit` directly and meets the same race, an edit form saved over a conflict that arose while it was open. Stating the rule at SYNC §7 binds both and lets vectors/sync/ pin it.
- **MUST for the held name.** STORAGE §7 already makes every whole read verify before any use; the write finding a name held is the one moment the good bytes exist beside the failing ones, and keeping the failing file discards them where no later read recovers them. SHOULD would leave that loss conformant. The cost is one whole read of the held file when a name is found held, the read §7 owes before the body is used anyway.
- **A producer does not quarantine.** STORAGE §7 keeps quarantine the owner's, under the staging lock taken exclusively and serialised against its own writers, which is what keeps it from moving a file another writer is still copying in. A producer holds the lock shared across its write and its enqueue and cannot take it exclusively without releasing it over a body it may have written unpinned, so it fails its write instead: its bytes stay with its caller, nothing is lost, and the owner frees the name.
- **A payload member at v 1.** STORAGE §15.3 has a member added take the next `v`; while the part is a draft, a payload's shape is now said to be edited in place as version 1 of the schema is (§4.2), the schemas being closed so a program of the draft before parks a `resolves` it does not define rather than ignore it.
- **The sync vectors move to format 3.** vectors/README.md bumps a format when a runner reads a field it did not; an `Edit`'s `resolves` is one. The draft numbers do not move.

## Lands in

storage-draft-08 and sync-draft-07 as they stand, untagged.
