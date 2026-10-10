---
cairn: log
change: reconcile-by-schema-text
date: 2026-10-10
---

# Reconciliation compares the schema's own text, and held mail is paged

Two asks from the Android owner.

- **The reconciliation test is the canonical schema** (§6, GUIDE §3). Owners detected each change by its own literal (`'attachments'` in a `CHECK`, `role` in a trigger body), one test per change, each a chance to miss one. Now an owner applies the canonical migrations to an empty database and compares every table, index and trigger with the store's by `sqlite_schema` text, `--` comments dropped and whitespace collapsed: a differing table is rebuilt from the canonical text, a differing index or trigger recreated, a missing one created, an extra one dropped. `PRAGMA table_info` cannot see a `CHECK`, so the text is the only witness of a constraint; normalising comments and whitespace keeps an edited comment from forcing a rebuild. The rebuild renames the stored table aside with `legacy_alter_table` on, so neither triggers nor foreign keys elsewhere are rewritten to the old name, creates the canonical table under its own name, so its stored text becomes the canonical one and the next open finds it current, and carries an `AUTOINCREMENT` counter over, so a queue id is never reused against a receipt. `ALTER TABLE … ADD COLUMN` stops being the reconciliation, the text it leaves never equalling the canonical one. Guarded by invariants.sh "reconcile: a store the canonical migrations created is current", "a table whose constraint moved differs, a comment does not", "rebuilt from the canonical text, nothing differs and no key dangles", "the rebuilt table takes the new constraint, its triggers back" and "an AUTOINCREMENT counter carries over, no id reused" (it fails with `INSERT OR REPLACE` into `sqlite_sequence`, which holds no key and keeps both rows).
- **`list_held_mail(after_collection, after_link_id, limit)`** pages the mail rows holding a body, store-wide and live or not, on the key, for a backfill re-deriving a column from the bodies such as §6's invitation. Guarded by "reconcile: list_held_mail pages the rows holding a body".

draft-04 is not tagged yet, so the number stays.
