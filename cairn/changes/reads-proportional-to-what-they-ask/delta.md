---
cairn: delta
change: reads-proportional-to-what-they-ask
---

## ADDED Requirements

### Requirement: STORAGE §14.1 A count reads what it filters on
A count over a set of collections (`count_mail`, `count_mail_by_day`, `count_unread`, `sum_mail`) SHALL read `mail_summary` only when `:attachment` is bound, and SHALL test `\Seen` without expanding `flags`.

#### Scenario: a count with no chip
- GIVEN a mail store and every chip `NULL`
- WHEN `count_mail` is planned with no `ANALYZE`
- THEN the plan reads `items_by_sort` covering and touches no `mail_summary` index (checks/invariants.sh)

## MODIFIED Requirements

### Requirement: STORAGE §9.3 The sort key
Paging is a seek on `items_by_sort`, not a scan. A keyset page SHALL bound its leading key in the statement itself, `sort_key <= coalesce(:after_key, x'')` newest first and `sort_key >= coalesce(:after_key, '')` oldest first, beside the exact row-value cursor, so the bound reaches the index whatever the planner knows. A page over a set of collections walks `items_by_sort_global` the same way, its collection test kept off `items_by_seq` (`+i.collection`); a substituted statement SHOULD keep that plan.

#### Scenario: a page deep in a large store
- GIVEN three mail collections and a cursor at 98 % of their order
- WHEN `list_mail_page_filtered` is planned with that cursor bound
- THEN the plan reads `items_by_sort_global (sort_key>? AND sort_key<?)` (checks/invariants.sh)

### Requirement: STORAGE §13 Encodings
`flags`, `base_flags` (TEXT): a JSON array of raw flag strings sorted by code point, written as `json()` writes it, so one flag set has one spelling and `\Seen` is found by its bytes. `NULL` is unknown, `'[]'` is known-empty.
