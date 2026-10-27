---
cairn: tasks
change: reads-proportional-to-what-they-ask
---

# Tasks

From the 2026-10-11 performance audit (p1p2-report #4, #5, #6 and §2.10 asserts 1 to 4), re-verified on 2026-10-18.

## #4 keyset bound

- [ ] queries/storage/read: the leading-key bound in list_mail_page_filtered, search_mail, list_mail_page_desc, list_items_page_desc, search_contacts, search_calendar, search_files, list_attachments_by_account
- [ ] The oldest-first pages (list_items_page_asc, list_contacts_page_asc, list_events_page_asc, list_tasks_page_asc, list_journals_page_asc, list_files_page_asc): check their plan carries the bound, add it where it does not
- [ ] STORAGE §9.3

## #6 counts

- [ ] count_mail, count_mail_by_day, count_unread, sum_mail: the chip through `EXISTS`, no join; the seen test by `instr` (or a `seen` column, decided with STORAGE §13's spelling)
- [ ] The same seen test in list_mail_page_filtered and search_mail
- [ ] STORAGE §13: one spelling of a flag set; STORAGE §14.1

## #5 search

- [ ] Choose: store-side FTS5 trigram over `mail_summary`, or `LIKE` kept and the text left to SEARCH.md's index (proposal.md, item 3)
- [ ] If store-side: migrations/storage (the table and its triggers), search_mail and a count through `MATCH`, STORAGE §4.1 (FTS5 required, its floor), §14.1

## Checks and followers

- [ ] checks/invariants.sh: plan asserts 1 to 4 of the audit, each failing on today's statements
- [ ] checks/names.sh if a statement is added
- [ ] GUIDE.md: the reads' plans
- [ ] Bump the draft number if `draft-04` is tagged before this lands
- [ ] Log entry
- [ ] io-pimdir: re-vendor the statements; android: drop `MailStore.below` and `MailStore.unjoined` (store-performance L1, L2, L4)
