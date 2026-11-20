---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator writes a collection's parent and presentation

The generator's side of e9d285b (`set_collection_parent`, `set_collection_presentation`, STORAGE §14's forest rule), of cairn/changes/the-freeze-plan. No part of the standard moves.

- **The model** (generator/src/model.rs): a collection holds its `parent` and its `Presentation` (color, description, sort order).
- **The writer** (generator/src/writer.rs): once every collection is declared, each one's parent is set with `set_collection_parent` and its presentation with `set_collection_presentation`; a parent the statement refused would leave the row as it was, which the oracle reads as a disagreement.
- **The oracle** (generator/src/oracle.rs): `list_collections` and `list_collections_by_account` state the parent, color, description and sort order, in the order the statements give, those with a sort order first.
- **The profiles**: the count profile's hierarchy is now its parents, each mailbox under the one its path nests under, six deep at the most, within one account; its special mailboxes carry a sort order, its calendars a color, its address books a description. The structure profile files work/Archive under work/INBOX and gives work/INBOX, work/calendar and work/holidays a presentation.
- **Checks**: the count profile's test holds a hierarchy at least five deep by parent, each parent in its child's account, and presentations present; every store written is self-checked. Broken by hand to see each fail: a parent unwritten, a color unwritten, the oracle ignoring the sort order.
