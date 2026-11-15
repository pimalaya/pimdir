---
cairn: change
id: a-pending-create-is-withdrawn-whatever-the-rights
status: active
created: 2026-11-15
---

# A pending create is withdrawn whatever the rights

## Why

The live campaign of 2026-11-15: `himalaya -a microsoft-pimdir message add` into a Graph folder other than Drafts was queued, applied by `neverest drain`, then rejected by every sync (Graph appends to Drafts only), so it stays a pending create. Deleting it, which himalaya stages as a move to the trash, is refused at the enqueue: "Source microsoft/msgraph does not support mail.message.move: item.create or item.delete is disabled". The message exists nowhere but in the store, and the user cannot get rid of it while deletes are off.

The root is in STORAGE §15.6 and its statement: the sources concerned by an action on one item are "every source binding it" (`load_item_capabilities`, its `holders` reading every binding). A pending create is a binding, under a provisional handle with no base, so the source that refused the add is asked for its delete right to withdraw it. Yet SYNC §3 and §7 say a tombstone over a binding with no base is a create withdrawn: it derives no `Remove`, the binding goes and the item is retained. Nothing is pushed, so no right is used. A move is the same withdrawal in its source collection plus a create in its target, which the target's sources push as an `Add`.

## What

1. **`load_item_capabilities` answers `held`** (queries/storage/read/load_item_capabilities.sql, a fifth column): the source's `bindings.base_present`, 0 when it binds the item as a pending create alone, its server holding nothing yet. A delivered create is based (SYNC §2) and answers 1: its server holds the member, and the remove staged on it is pushed once it lands.
2. **The sources concerned** (STORAGE §15.6): for a `remove`, a `move` or a `copy`, a source answering `held` 0 is left out of the item's sources. A remove of it withdraws the create (SYNC §7) and needs nothing of it, its delete right included. A move or a copy meets it in the target alone, as a source of the target binding nothing of the item, asked there what an `add` of the item carrying its flags needs, the change it pushes being an `Add` (SYNC §2's table). A `set-flags` and an `update` still ask it: what they change rides on the add it will push.
3. The paragraph on the target's sources says what they are asked, an `add`'s capabilities, which io-pimdir already reads and which the table left implicit.
4. STORAGE §14.1 names the column; GUIDE §12's gate leaves out `held` 0 for the three actions.

## Decided

- **A column, not a filter in the statement.** Leaving pending creates out of `holders` for every action would also let a `set-flags` adding a flag the source cannot carry, or an `update` turning a pending event into a scheduled one, pass ungated, though both reach the server with the add. The statement answers the fact, and the gate reads it per action. Appended last, so a reader taking the first four columns by position reads what it read.
- **`base_present`, not the provisional handle.** A delivered create keeps the provisional handle and its server holds the member: removing it is a delete the source pushes once the member lands, which its delete right governs.
- **No new capability, no new action.** Withdrawing a create is the store's own business, as STORAGE §15.3 already says of an item no source binds.

## Versions

storage-draft-11 changed after its tag (a statement's columns, STORAGE.md), as did sync-draft-11 by the change of the same day, a-narrowed-round-proves-only-what-its-enumeration-lacks, whose proposal states the bump the owner owes. This change is a fix: no reading of the tagged draft refuses a withdrawal on purpose.

## Lands in

The working tree of 2026-11-15, uncommitted: STORAGE.md, GUIDE.md, queries/storage/read/load_item_capabilities.sql, queries/signatures.json, checks/invariants.sh. io-pimdir follows in its working tree (its cairn/changes/a-pending-create-is-withdrawn-whatever-the-rights), where tests/capabilities.rs `a_pending_create_is_withdrawn_whatever_its_source_may_delete` fails on the old gate with the live refusal.
