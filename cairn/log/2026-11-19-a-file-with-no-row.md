---
cairn: log
change: two-silent-losses-fold-into-draft-08
landed: 2026-11-19
---

# A file with no row

The last open line of two-silent-losses-fold-into-draft-08: vectors/sync/ could not state a file under an object's name with no row, the state a crash in the middle of an exclusive create and copy leaves (the file written, the transaction storing its row never committed), and vector 130 stood for it with a row. The owner ruled on 2026-11-19 to land it before the draft-14 tags as one optional schema field.

- **SYNC §11**: an object of `store` or `expect.store` may state `row` false, a blob file under its name and no row, which nothing names; beside `corrupt` it is that file holding other bytes. Guarded by vector 172 and by checks/vectors.py.
- **vectors/schema/sync.schema.json**: the `blob` definition gains `row` (boolean); the sync format moves from 7 to 8, as vectors/README.md has a format move for a field a runner reads, and every case under vectors/sync/ states `v` 8.
- **Vector 172**: vector 130 in the crash's own state, c2 a partial file with no row; the Full fetch finds the name held whatever the rows say, sets the file aside and files the fetched bytes with their row (STORAGE §5, §7).
- **checks/vectors.py**: an object stated with `row` false has a file (not `blob` false), no item or binding of its side names it, and no push carries it. The rule was seen to fail on a copy of vector 172 whose item named c2.
- vectors/README.md, GUIDE.md (the runner's steps), vectors/manifest.json restated.

No draft number moves: storage-, sync- and search-draft-14 are untagged, and AGENTS.md §2 bumps a part's number only for a change after its tag; the store's schema, statements and payloads are untouched, so a store any draft-14 program wrote is the same store. What moves is the sync vectors' own format, which a runner reads first (vectors/README.md, Rules for a consumer): io-pimdir v0.17.0 (e78ef92), which checks/io-pimdir.rev names, refuses format 8, so checks/implementation.sh fails at that pin until it names the io-pimdir commit carrying the runner at format 8 (io-pimdir cairn/log/2026-11-19-the-crate-follows-draft-14.md), which passes every case, 172 included, with no engine change.

Checks: `nix flake check path:$PWD`, checks/tags.sh, and checks/implementation.sh against the io-pimdir working tree with the pin pointed at it on a scratch copy.
