---
cairn: log
change: null-cursor-first-page
date: 2026-09-04
---

# A NULL cursor is the first descending page

The two descending pages, list_items_page_desc and list_mail_page_desc, started by binding a key above every representable one, which every implementation had to invent, and the reference implementation substituted a NULL-cursor form for exactly that reason. The statements now bind a NULL cursor as the first page, so the reference copy is verbatim and the substitution allowance goes unused.
