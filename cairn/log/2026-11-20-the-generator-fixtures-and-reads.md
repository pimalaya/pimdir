---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator files the fixtures and states 44 reads

The third code step of the generator of cairn/changes/the-freeze-plan (section 2). No part of the standard moves.

- **The fixture layer** (generator/src/fixture.rs): every body vectors/summaries.json pins a row for, once each, checked against its stated name, filed with that row. The model keys each by its own rules, and the profile fails unless it reaches the key summaries.json pins, so the escape and the `alt:` and `hash:` fallbacks are held to the vectors (a model skipping the escape fails on card-reserved-uid.vcf).
- **Row states** (generator/src/model.rs): a tombstone a source still binds and a retained row, with and without a body, written with `insert_item` and `retain_item` (STORAGE §11).
- **The structure profile** gains a reply, a reply filed in the sent mailbox, an address named twice in one role, a tombstone and three retained rows, so each rule the oracle states has a case it decides.
- **The oracle** (generator/src/oracle.rs) covers 44 read statements: the collections by account, their kinds, accounts, generations and coverage, the sources; per collection the live and deleted counts, every listing and the trash page by page, the reply ids and categories; per row `get_mail_row`, `list_item_bindings`, `handle_for_link`; the identities and bodies held in several places (`list_link_placements`, `list_object_placements`), `describe_endpoint`, `retained_bytes`; each account's mail and the whole store's counted (`count_mail`, `count_unread`) and merged (`list_mail_page_filtered`) under five filters; `list_replied`; every address's placements by role, page by page, and every domain's. A statement ordering by part of a row compares as a multiset, an instant SQLite stamps by its shape.
- **Checks**: the flake's `generator` check runs it on four seeds. Each new rule was broken by hand and the self-check seen to fail: unread counting read mail, a body's placements counting a retained row, retained bytes counting a tombstone, a merged page ignoring `since`, the endpoint taken from the last collection, a retained row with no instant, an address's second position listed, a reply in the sent mailbox counted. Two of those passed until the profile gained the case deciding them, which is why it did.
