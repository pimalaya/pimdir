---
cairn: tasks
change: keyset-reads-seek-their-bound
---

# Tasks

- [x] queries/storage/read: the leading-key bound in list_mail_page_filtered, search_mail, list_mail_page_desc, list_items_page_desc, search_contacts, search_calendar, search_files, list_attachments_by_account. Closed by cairn/log/2026-10-31-keyset-reads-seek-their-bound.md: the cursor coalesced into its row value, the five pages over a set merged from each collection's seek; list_attachments_by_account's leading key is the message's, which no index of the stand-ins holds, so its page reads the account's stand-ins, found by role.
- [x] The oldest-first pages (list_items_page_asc, list_contacts_page_asc, list_events_page_asc, list_tasks_page_asc, list_journals_page_asc, list_files_page_asc): their plan checked, the bound added where missing. Closed by the same entry: each already seeks `(sort_key,seq)>(?,?)`, now asserted.
- [x] count_mail, count_mail_by_day, count_unread, sum_mail: the chip through `EXISTS`, no join; the seen test by `instr`; the same test in list_mail_page_filtered and search_mail. Closed by the same entry: the three counts read the summary through `EXISTS` for the chip alone; sum_mail keeps the join its sizes need; flags being rows, the seen test is a seek on placement_flag's key in every read, asserted.
- [x] search_mail under the bound and a page cap. Closed by the same entry: a merge, each collection's walk capped at the page.
- [x] STORAGE §9.3 and §14.1; GUIDE.md: the reads' plans. Closed by the same entry.
- [x] checks/invariants.sh: plan asserts 1 to 4, each failing on the statements before. Closed by the same entry ("page: …", "since: …", "count: …").
- [x] Log entry: cairn/log/2026-10-31-keyset-reads-seek-their-bound.md.
- [ ] Followers: io-pimdir re-vendors; android drops `MailStore.below` and `MailStore.unjoined` (store-performance L1, L2, L4)
