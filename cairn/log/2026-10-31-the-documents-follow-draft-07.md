---
cairn: log
change: the-documents-follow-draft-07
date: 2026-10-31
---

# The documents follow draft-07

Editorial: no rule, statement or vector moved, and no part's version with them, two stale column names in SEARCH.md aside, corrected to what search-draft-07 already meant. The gtd convention takes gtd-draft-02 for the versions it requires.

- README.md: "Using the standard" became "Usage", one subsection per way of using the standard (the documents, io-pimdir's I/O-free core, its std client), each saying what it suits.
- OVERVIEW.md: §1 names the shapes and STORAGE §4.1; §8 counts seven action kinds, `set-performer` included; §10 lists the temporal coverage among the answer's and says an index may be written another way; §11 says the vectors bind every implementation and the canonical schema and statements the canonical shape. Two paragraphs compacted.
- STORAGE.md: §4.1 no longer says the canonical shape needs `DROP COLUMN`, which no canonical text runs (the reconciliation rebuilds a table); §4.4's two paragraphs on what a statement binds are one; §6 says a reader and a producer refuse a shape they do not implement, as §4.1 already required; §13 points at §4.4 for a set's spelling rather than restating it; §15 no longer counts "six kinds"; §16 states the model vectors once and what checks/ binds. "Shape" now means a way of writing the store alone, a summary's and a page's columns named as such. migrations/storage/0001_init.sql's leading comment drops `DROP COLUMN` likewise, a comment the reconciliation ignores.
- SYNC.md: §3's no-base test names `base_flags_known` beside `base_present`, and its flag test reads the sets without naming the canonical tables; §6 and §10 write a summary's list rows with it; §11 compares flag sets and lists as arrays whichever tables hold them; "a coroutine form" and "each case's structure" where "shape" meant neither.
- SEARCH.md: §9 read a bodiless message's parent from `mail_summary.in_reply_to`, a column draft-07 removed: it reads the first `mail_in_reply_to` id; §6 read a task's categories on `task_summary`, now `task_category`, and says chunk offsets index the text before §5's fold, as io-pimdir cuts them; §8 refuses any full-text engine's raw syntax, not FTS5's alone; §2's two bullets on the schema text are one, and §11 names the fold among what the cases pin.
- GUIDE.md: §2 runs `create_param` on every connection, the reader's read-only one included (a temporary table, checked on SQLite 3.50: the main database stays unwritable), and has the reader refuse an unimplemented shape and read a subquery over an absent table as answering none; §3's shape check joins step 1's paragraph; §9's no-base test and unknown flag set follow SYNC §3; §13's drain reads a move's target from `target_collection`; §15 cuts chunks before the fold and merges step 1's two bullets on the schema text, and §16 compares a `relevance` case as a set on a shape without bm25; "schema text" and "structure" where "shape" meant neither.
- conventions/gtd.md, bumped to gtd-draft-02: its Status line required storage-draft-05 and search-draft-05 while §1 reads `task_category`, so it now requires storage-draft-07 and search-draft-07; §3 pointed the writer cases at vectors/schema/gtd-writers.schema.json, which never existed, now conventions/gtd/writers.schema.json, the file checks/vectors.py validates against; a capture derives its categories with `insert_category`; §1's opening no longer restates the document's. No rule moved. AGENTS.md names gtd-draft-02.

Guarded by checks/names.sh, every backticked identifier still resolving; `nix flake check` green.
