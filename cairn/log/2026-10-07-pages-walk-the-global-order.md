---
cairn: log
change: pages-walk-the-global-order
date: 2026-10-07
---

# Pages across collections walk one store-wide order

`list_mail_page_filtered` and `search_mail` order a set of collections by `(sort_key, seq, collection)`, which `items_by_sort` cannot give: it leads with the collection. SQLite read every live row of the set through `items_by_seq` and sorted it in a temporary b-tree to return one page.

- **`items_by_sort_global`** on `items(sort_key, seq, collection) WHERE deleted = 0`, beside `items_by_sort` (STORAGE §9.3). Measured by MOA on a 50k-mail store with statistics (SQLite 3.53): two folders 49 ms → 0.6 ms, one folder unread 37 → 0.6 ms, the worst case (a 10-mail folder older than everything) 6.4 → 5.6 ms.
- **The statements keep their collection test off `items_by_seq`** (`+i.collection IN …`). Without `sqlite_stat1`, which no Pimalaya writer produces, the planner still picks `items_by_seq` and the temporary sort even with the new index present; with the `+` it walks `items_by_sort_global` with or without statistics, and on a store lacking the index it scans and sorts as before, so an unreconciled store reads correctly. Measured on a fresh 50k store without statistics: two folders 15 ms → 0.3 ms, one large folder 10 → 0.3 ms, the 10-mail folder older than everything 0.3 → 4.8 ms (the whole order walked).
- Guarded by invariants.sh "page: list_mail_page_filtered walks items_by_sort_global over two collections, sorting nothing" and the same for `search_mail` (`EXPLAIN QUERY PLAN` on two collections: the index used, no `TEMP B-TREE FOR ORDER BY`); both fail without the change.

`count_mail`, `count_mail_by_day` and `count_unread` order nothing and keep their per-collection seek. Folded into 0001; draft-04 is not tagged yet, so the number stays. io-pimdir reconciles the index on open.
