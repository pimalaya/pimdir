---
cairn: log
change: mail-reads-take-a-floor
date: 2026-10-10
---

# The mail reads take a floor, and a range sums

A reader listing mail down to a date (the Android app's list floor, soon its download window) wrapped `count_mail`, `count_mail_by_day` and `list_mail_page_filtered` in a subquery cutting `sort_key >= floor` after the fact, so every count read every stored row of the shown collections: with 100,000 headers that was the common path. Its footer also needs to say what moving the date back would download, which no statement answered.

- **`:since`** on `count_mail`, `count_mail_by_day`, `count_unread` and `list_mail_page_filtered` (§14.1). A floor on the sort key, bound as `i.sort_key >= coalesce(:since, '')`: `NULL` sets none, and an undated row (`''`) lies below any other, as it does for a scope's band. `search_mail` takes none, a search reaching past any list. Guarded by invariants.sh "since: NULL is no floor, the undated row counted", "a floor leaves out the rows below it and the undated, and keeps a key equal to it", "per day above the floor, no undated day", "unread above the floor" and "the page ends at the floor".
- **The floor is a seek** (§14.1). The three counts seek `items_by_sort` on `(collection, sort_key)` and the page seeks `items_by_sort_global` from the top down to the floor. Guarded by "since: the page seeks the floor on items_by_sort_global" and "since: <statement> seeks the floor on items_by_sort" for each count.
- **`sum_mail`** (§14.1), a new read: `count_mail`'s set and chips over `[:since, :until)`, answering the rows, the summed `size` of those knowing it and the count of those that do not. An open `:until` binds as the empty blob, above every text in SQLite's order, so both bounds stay seeks. Guarded by "sum: rows, known bytes and unknown sizes above a floor", "a range open below holds the undated", "the range is half-open", "under the chips across collections", "nothing in range sums to zero" and "both bounds seek items_by_sort, open or not"; names.sh by STORAGE §14.1 and GUIDE §14 naming it.

An existing caller binding no `:since` reads `NULL` and is unchanged. draft-04 is not tagged yet, so the number stays.
