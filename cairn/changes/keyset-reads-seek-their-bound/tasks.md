---
cairn: tasks
change: keyset-reads-seek-their-bound
---

# Tasks

- [ ] queries/storage/read: the leading-key bound in list_mail_page_filtered, search_mail, list_mail_page_desc, list_items_page_desc, search_contacts, search_calendar, search_files, list_attachments_by_account
- [ ] The oldest-first pages (list_items_page_asc, list_contacts_page_asc, list_events_page_asc, list_tasks_page_asc, list_journals_page_asc, list_files_page_asc): their plan checked, the bound added where missing
- [ ] count_mail, count_mail_by_day, count_unread, sum_mail: the chip through `EXISTS`, no join; the seen test by `instr`; the same test in list_mail_page_filtered and search_mail
- [ ] search_mail under the bound and a page cap
- [ ] STORAGE §9.3 and §14.1; GUIDE.md: the reads' plans
- [ ] checks/invariants.sh: plan asserts 1 to 4, each failing on the statements before
- [ ] Log entry
- [ ] Followers: io-pimdir re-vendors; android drops `MailStore.below` and `MailStore.unjoined` (store-performance L1, L2, L4)
