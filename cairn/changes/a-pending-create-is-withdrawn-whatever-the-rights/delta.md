---
cairn: delta
change: a-pending-create-is-withdrawn-whatever-the-rights
---

## MODIFIED Requirements

### Requirement: STORAGE §15.6 The sources concerned by an action on one item
For a `remove`, a `move` or a `copy`, a source binding the item as a pending create alone (`load_item_capabilities` answering `held` 0) SHALL NOT be among the item's sources concerned: the remove withdraws that create and pushes nothing (SYNC §7), so it needs neither the source's remove nor its move; a move or a copy meets that source in the target alone, as a source of the target binding nothing of the item. Every source of the target binding nothing of the item, or binding it as a pending create alone, is asked what an `add` of the item carrying its flags needs there. A `set-flags` and an `update` still read every source binding the item. Replaces: every source binding the item, a pending create included, for every action.

#### Scenario: removing a create its source rejected
- GIVEN a message added to a Graph folder, applied by the drain and rejected by every sync, so a pending create of `graph`, and `graph` declaring `mail.message.remove` and `mail.message.move` `none`
- WHEN a producer gates a `remove` of it
- THEN it passes, while a `remove` and a `move` of a message `graph` holds are refused naming the capability (io-pimdir tests/capabilities.rs)

#### Scenario: moving it to the trash
- GIVEN the same pending create, and `graph` syncing the target
- WHEN a producer enqueues a `move` of it and the owner drains it
- THEN the gate asks `graph` an `add` into the target, the drain applies it, nothing is parked, and the target holds the message (io-pimdir tests/capabilities.rs)

## ADDED Requirements

### Requirement: STORAGE §14.1 `load_item_capabilities` answers `held`
`load_item_capabilities(collection, seq)` SHALL answer, after `source`, `capability`, `support` and `detail`, a fifth column `held`: the source's `bindings.base_present` for the item, 0 for a pending create, 1 for a based binding, a delivered create included.

#### Scenario: a pending create and a delivered one
- GIVEN an item `graph` binds under a provisional handle with no base, and another it binds under a provisional handle with a base naming nothing
- WHEN `load_item_capabilities` runs for each
- THEN the first answers `held` 0 and the second 1 (checks/invariants.sh, "capability: a pending create is bound unheld …")
