---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's model, writer and first self-check

The second code step of the generator of cairn/changes/the-freeze-plan (section 2). No part of the standard moves.

- **The model** (generator/src/model.rs): collections, items, bindings, objects and checkpoints as plain values, an item keyed as STORAGE §9 assigns a key (the hint, `esc:` before a reserved prefix, the `alt:`, `hash:` or `file:` fallback, minted over the handle while held) and numbered as §9.1 draws a `seq` (shared with a row of the same kind holding the key, a message's only with one agreeing on subject, date and sender, drawn for a derived key).
- **The surface bodies** (generator/src/body.rs): a message, a card, an event, a task, a journal and a file, each rendered so that its Annex A row is the one the model drew, with the FNV-1a 64 of the `hash:` key. A test holds the renderers to vectors/summaries.json: bodies stating the fields of mail-basic.eml, card-basic.vcf, event-utc.ics, event-date-only.ics, event-floating.ics and todo-due-only.ics derive the rows pinned for them (size aside, the bytes differing), so a derivation error fails there rather than passing a self-check that reads the same model on both sides.
- **The writer** (generator/src/writer.rs): a model written into a store through the canonical statements alone, in GUIDE §5's order, each body through a temporary and a link that never replaces (GUIDE §4); every `seq` the store draws (`seq_for_link_any`, else `bump_next_seq`) is held to the model's, so the model and the statements cannot read §9.1 two ways unnoticed.
- **The oracle** (generator/src/oracle.rs): from the model alone, the rows of `list_collections`, `list_accounts`, `count_items`, every listing statement walked page by page under its keyset cursor (`list_items_page`, `list_items_page_asc`, `list_items_page_desc`, `list_mail_page_desc`, `list_contacts_page_asc`, `list_events_page_asc`, `list_tasks_page_asc`, `list_journals_page_asc`, `list_files_page_asc`), `get_item` and the kind's `get_` for every live item, `seq_by_link` and `load_addresses` for every row; a flag set compared as a set (STORAGE §4.4).
- **Checks**: the flake's `generator` check now also runs the self-check, four seeds of the structure profile each written, read and compared, every blob hashing to its name, and the renderers against summaries.json. Shown to bite by hand: a model not sharing a `seq` fails the writer, a card's sort key left unfolded fails the renderers' test.
