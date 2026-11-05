---
cairn: change
id: storage-draft-09
status: draft
created: 2026-11-05
---

# storage-draft-09: an integer placement id, the system flags as columns, deltas loading what owes a push

> Cross-repo: io-pimdir and the Android app follow, every store is recreated (README, Status). The content is settled by cairn/changes/performance-audit-2026-11-05 (The draft-09 bench, and the Android session's measurement of the app's path recorded there): on the app's write path −45% a page in statements and 28 to 16 statement runs a message; on the canonical writer −53% SQL and −49% bytes a message; unread counts 8 to 18 times faster.

## Why

storage-draft-08 (tagged at 8fd5c69) keys every child of an item by `(collection, link_id)`, two texts repeated in each row and index entry, and keeps every flag as a row whose insert requests its item's restamp. Those two choices are most of what a listed message costs to write, most of its 2.1 KB in pimdir.db, and every count a full pass. A delta load reads the whole collection because what owes a push is answered by no statement (io-pimdir cairn/changes/a-delta-loads-what-it-names). The three parts are tagged, so this lands as one bump of each, the apps reinstalling once.

## What

### 1. An integer placement id (STORAGE §4.3, §13, migrations/storage)

- `items.id INTEGER PRIMARY KEY AUTOINCREMENT`, never reused and never shown: a consumer keeps `(collection, seq)`, a writer `(collection, link_id)`, which stays unique (`UNIQUE (collection, link_id)`).
- `placement_flag`, `bindings`, `binding_base_flag`, the six summaries, `item_address`, `mail_in_reply_to`, `task_category` and `supersessions` keyed by `item` (`REFERENCES items(id) ON DELETE CASCADE`), their indexes restated on it (`placement_flag_by_flag(flag)`, `item_address_by_address(address, role)`).
- `bindings` keeps `collection` for `bindings_by_handle (collection, source, handle)`, held equal to its item's by a foreign key `(item, collection) REFERENCES items(id, collection) ON UPDATE CASCADE`, so a rename moves it with the item. `bindings_by_link` goes: `items_by_link` and the binding's key serve `origin_for_link` and `destination_for_link`.
- A rename (`rename_collection`) updates `items.collection` and what references collections, no longer every child row.

### 2. The system flags as columns (STORAGE §4.3, §4.4, §4.5, §13)

- `items.marks` and `bindings.base_marks`, INTEGER: `\Seen` 1, `\Answered` 2, `\Flagged` 4, `\Draft` 8, `\Deleted` 16, each by its exact bytes. Every other flag, `\seen` and `$Important` among them, stays a row of `placement_flag` or `binding_base_flag`. `CHECK (flags_known = 1 OR marks = 0)` and its base twin.
- A set is the bits and the rows together: reads answer `flags` and `base_flags` as one text as now (§4.4), the bits rendered by their names.
- `marks` is observable: items_stamp_update stamps its change, so a system flag set moves one stamp, and a fresh item carrying them draws one stamp from its insert.
- `items_by_sort (collection, sort_key, seq, marks) WHERE deleted = 0`, so a count or a page filtering on a system flag reads the index alone, and `items_unread (collection, sort_key, seq) WHERE deleted = 0 AND marks & 1 = 0`.

### 3. The statements' interface (STORAGE §4.4, queries/storage)

- Every statement keeps its name, its key parameters and the columns it answers; its text reaches the children through the item's id. Changes: `insert_item` and `update_item` take `:marks`, `insert_binding` and `update_binding` `:base_marks`; the `flags` slot of `retain_flags`, `add_flags` and their base twins holds the set's other flags alone, so a writer whose set holds none runs neither for a fresh row.
- Reads testing a system flag test the bit: `count_mail`, `count_mail_by_day`, `count_unread`, `sum_mail`, `list_mail_page_filtered`, `search_mail`, `collect_before`'s flag comparison.
- §4.4 states that a list parameter's value column carries no affinity (checks/floor.sh since 2026-11-05).

### 4. Deltas load what owes a push (STORAGE §14, SYNC §10)

- `list_owing_bindings(collection, source)`: the handles of the source's bindings whose placement may not be `Clean` (SYNC §3): a binding or its item conflicted, the item deleted, no base, the flags known on both sides and differing (the bits compared, then the rows), an object other than the base's.
- `list_lacking_items(collection, source)`: the link ids of the live items holding a body that the source binds not, its `Created` projections.
- SYNC §10: a delta loads the `Handles` it lists and finds vanished, the `Links` of the hints it carries, and those the two statements name, never `All`. A round's last page keeps `All`: what it finds absent and whether a mass absence parks it are counted over every based binding in scope (§5). A superset is safe, a subset loses a push, so the statements read SYNC §3 conservatively, and a sync vector pins each status.

### 5. The sender rule once per page (STORAGE §14.2)

- `link_senders_of_by_link`: `link_senders_of` over the `links` slot, so a page of mail runs the rule once.

### 6. Versions

- storage-draft-09, sync-draft-08 (§10, requiring storage-draft-09), search-draft-09 (its statements reading the store's children rewritten, requiring storage-draft-09; the index's own changes stay the audit's later step): Status lines, README, `init_store_meta`, `init_index_meta`, every check naming a version.

## Not in this draft

- The pending stamp (io-pimdir a-page-lands-in-few-statements, step 2): nothing left to save once the flags are columns.
- The index without its `flag` table, the occurrence bound, the planner: search changes of the audit's phase 1, a later search draft.
- Bits for keywords (`$Junk`, `$Important`, `$Forwarded`): Annex B.1 reads them by row, and none was measured.

## Followers

- io-pimdir: re-vendor spec/; the write path encodes the system flags into `:marks` and `:base_marks` and binds the other flags alone; delta and last-page loads by §4's statements; the projection reads flags as before.
- android: the `pimalaya-android` shape's forks of the changed statements; PimdirStorage's upsert without `SET_FLAGS_KNOWN` and the flag statements for a set of system flags; then the phone run the audit waits for.
- Every app reinstalls over a new store.

## Open points

- `AUTOINCREMENT` writes `sqlite_sequence` per insert; the bench measured it so. A plain `INTEGER PRIMARY KEY` may reuse the largest id after a purge, which a consumer keyed on it (a later search draft) would have to reconcile.
