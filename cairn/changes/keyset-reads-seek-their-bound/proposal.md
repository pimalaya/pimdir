---
cairn: change
id: keyset-reads-seek-their-bound
status: active
created: 2026-10-30
---

# Keyset reads seek their bound, counts read what they filter on

## Why

Moved out of reads-proportional-to-what-they-ask on 2026-10-30, which landed its two decisions (a flag set has one spelling, `json()`'s; no store-side FTS5) and left the statement rewrites to this change. The findings, measurements and the four plan asserts are that change's proposal.md, items 1, 2 and 4, and its delta.md, re-verified against the statements on 2026-10-18.

No schema moves: every edit is to a statement's text, keeping its name, parameters and result columns, so it lands as a patch of STORAGE (§4.4) in whichever draft or release is current.

## What

1. Every keyset statement bounds its leading key beside the exact row-value cursor (list_mail_page_filtered, search_mail, list_mail_page_desc, list_items_page_desc, search_contacts, search_calendar, search_files, list_attachments_by_account; the oldest-first pages where their plan lacks it); STORAGE §9.3.
2. count_mail, count_mail_by_day, count_unread and sum_mail read `mail_summary` through `EXISTS` only when `:attachment` is bound, and test `\Seen` with `instr(i.flags, '"\\Seen"') > 0`, which the `json()` spelling makes exact; the same seen test in list_mail_page_filtered and search_mail; STORAGE §14.1.
3. search_mail under the bound and a page cap.
4. The audit's plan asserts 1 to 4 in checks/invariants.sh, each failing on the statements before the rewrite.

## Lands in

The next STORAGE text after the rewrite, as a patch.
