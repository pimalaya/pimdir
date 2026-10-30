---
cairn: change
id: reads-proportional-to-what-they-ask
status: landed
created: 2026-10-18
---

# Store reads proportional to what they ask

## Why

The P1/P2 performance audit of 2026-10-11 (synthetic stores of 10k, 100k and 1M messages, no `ANALYZE`, the plans a phone gets) found three canonical reads whose cost grows with the store rather than with the page. Android works around the first and the third in its own SQL (android cairn/changes/store-performance, `MailStore.below` and `MailStore.unjoined`) and lists the canonical fixes as library proposals L1, L2 and L4. Re-verified against the statements on 2026-10-18: all three are as the audit read them.

- **#4, keyset pages do not seek.** STORAGE §9.3 says paging is a seek, but `:after_key IS NULL OR (i.sort_key, i.seq, i.collection) < (...)` keeps the bound out of the index, so a page walks `items_by_sort_global` from the top down to its own position: 216 ms at 98 % of a 1M store against 0.4 ms with a redundant `AND i.sort_key <= coalesce(:after_key, x'')`, and a whole walk of 500 a page 229 s against 2.4 s. The same `IS NULL OR` form is in list_mail_page_filtered, search_mail, list_mail_page_desc, list_items_page_desc, search_contacts, search_calendar, search_files and list_attachments_by_account.
- **#5, search is `LIKE` over every summary.** search_mail matches subject, sender and display name by `LIKE`, a scan: a no-hit page costs 1.6 s at 1M, and the list runs it with its count and its per-day count, about 4.8 s per keystroke. An FTS5 trigram table (LIKE's substring semantics) answers in 0.06 to 0.6 ms for a rare word, 13 s to build at 1M.
- **#6, counts join a summary no chip asks for.** count_mail, count_mail_by_day and count_unread `LEFT JOIN mail_summary` whatever `:attachment` holds, and test `\Seen` through a correlated `json_each`: count 845 to 112 ms at 1M without the join, unread 135 to 87 ms at 100k with `instr`. sum_mail has the same shape.
- **Plan asserts 1 to 4** (audit §2.10) are missing from checks/invariants.sh, so nothing fails when a statement stops seeking.

## What

1. **Every keyset statement bounds its leading key**: newest first `AND i.sort_key <= coalesce(:after_key, x'')`, oldest first `AND i.sort_key >= coalesce(:after_key, '')`, beside the row-value test that stays the exact cursor. STORAGE §9.3 says the bound is part of the statement.
2. **Counts read the summary only for the chip**: `AND (:attachment IS NULL OR EXISTS (SELECT 1 FROM mail_summary s WHERE s.collection = i.collection AND s.link_id = i.link_id AND s.attachment = :attachment))`, no join; the seen test `instr(i.flags, '"\\Seen"') > 0`, which needs STORAGE §13's flag spelling to be byte-exact (written through `json()`), else a `seen` column the writer keeps. count_mail, count_mail_by_day, count_unread, sum_mail and the two page statements.
3. **Search over a text index.** Two forms, to choose before the edit:
   - a store-side FTS5 external-content table over `mail_summary(subject, sender, sender_name)`, trigram tokenizer, kept by triggers, with search_mail and a count through `MATCH`. It makes FTS5 a store requirement (STORAGE §4.1 asks for none today) and puts text in the store, which SEARCH §1 leaves to the index;
   - or the store keeps `LIKE` under the sargable bound and a page cap, and the text half moves to SEARCH.md's index once io-pimdir implements it (search-milestones, M4).
4. **The plans are asserted** in checks/invariants.sh, bound to a three-collection list, a mid keyset and a floor, no `ANALYZE`: a cursor page reads `items_by_sort_global (sort_key>? AND sort_key<?)`; every page statement carries its bound in the index constraint; the counts with every chip null plan no `mail_summary` access and `items_by_sort` covering; search_mail scans no `items_by_sort_global` once item 3 lands.

## Decided (2026-10-30)

The pimdir stable-release plan (edit 7) settled the two choices this change waited on:

- **Flag spelling**: a flag set is written as `json()` writes it, sorted by code point (delta.md, STORAGE §13), so `\Seen` is found by its bytes and no `seen` column is added.
- **No store-side FTS5**: item 3 takes its second form. The store keeps `LIKE` under the sargable bound, FTS5 stays no store requirement, and text search is SEARCH.md's index.

The statement rewrites and the plan asserts moved to keyset-reads-seek-their-bound on 2026-10-30, so this change lands the two decisions alone: they are what the store's text fixes, and the rewrites change no name, parameter or result column, a patch (STORAGE §4.4).

## Consequence

Android drops `MailStore.below` and `MailStore.unjoined` and re-vendors the statements. io-pimdir re-vendors them; its reads keep their signatures.
