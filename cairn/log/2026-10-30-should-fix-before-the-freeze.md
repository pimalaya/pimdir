---
cairn: log
change: should-fix-before-the-freeze
date: 2026-10-30
---

# What should be fixed before STORAGE freezes

Edit 10 of the pimdir stable-release plan, the should-fix list of the consolidated pimdir review. None lost data alone; each is cheaper in a draft than after a release.

Store:

- **STORAGE §14, 0001_init.sql** (normative, schema): `delete_collection` is refused while the collection holds a pending or parked queue row, by the new trigger `collections_keep_queued`; the operator cancels first. Refusal was chosen over parking: a parked row of a deleted collection has nothing to apply to. Guarded by checks/invariants.sh ("collection: a collection holding a parked action is not deleted", which on the schema without the trigger reports "expected [refused|1], got [|0]").
- **STORAGE §13, §15.2, §15.3** (normative): a row whose payload `v` the owner does not know for a kind it knows is skipped, as an unknown kind is. No check here runs a drain.
- **STORAGE §9, §13, §16, Annex A** (normative): `alt:`, `hash:`, `dup:`, `part:`, `file:` and the escape `esc:` are reserved; a hint beginning with one is keyed `esc:` and the hint, so a vCard `UID` stating `hash:` keeps its `seq`, its links and its references; a connector strips the one `esc:` before naming the identity to a server. Guarded by summaries.json's case card-reserved-uid.vcf and checks/vectors.py, which now checks every stated identity's key ("link_id of a stated identity: hash:0123456789abcdef is not esc:hash:0123456789abcdef" on a copy keyed the old way, which the old check passed).
- **STORAGE Annex A.2** (normative): case mapping is Unicode 15.0.0's; a later version agrees on every character 15.0.0 assigns, and one assigned later may map as the writer's version says. Not checkable beyond the existing case-fold vector.
- **STORAGE §4.4, OVERVIEW §11**: a statement's name, parameters and result columns bind, its text is reference; a fix keeping the three is a patch. New canonical statements for what io-pimdir wrote by hand: `backfill_invitation`, `backfill_task_organisation` (STORAGE §6), guarded by a reconcile scenario of checks/invariants.sh and by checks/names.sh.
- **STORAGE §1, README, OVERVIEW §1**: "Rebuildable" became what re-sync restores and what it cannot (un-pushed edits, the queue and receipts, references, capabilities, performers, retained rows, local collections); a rebuild is never automatic.
- **STORAGE §2**: a collection may be a folder, an item a file.
- The draft shims stay where they are: moved to the-draft-shims-gather-in-one-annex, to be done once the last draft schema edit has landed.

Sync:

- **SYNC §6, §9, STORAGE §9** (normative): a member stating a `Message-ID` the collection holds under another source's item whose summary disagrees on subject, date or sender is another message and is minted apart. Guarded by vector 93 (fixture mail-reused-message-id.eml) and checks/vectors.py ("member 77 names another message under basic-1@example.org and is minted apart" on a copy joining it, which the old check passed).
- **SYNC §5** (normative): an event is reported only once the write recording it committed, and every committed one is reported. No vector format reports a failing write.
- **SYNC §4, §5, §11** (normative): an add accepted with no handle (IMAP without UIDPLUS) stays a pending create, not pushed again in the run, landed by the next listing; `assigned` `null` in a vector. Guarded by vector 92 and checks/vectors.py ("an add accepted without a handle keeps its provisional binding" on a copy that superseded it).

Wording and checks:

- **STORAGE, SYNC, SEARCH**: the BCP 14 boilerplate of RFC 8174, SHALL and RECOMMENDED now declared; keywords added where a binding rule carried none (SYNC §5 rounds and restart, STORAGE §11 and §11.1). The untestable "MUST NOT raise a page past these" left with the page table (conventions-leave-the-core).
- **Contradictions**: AGENTS.md now points the freeze gate at README's Status; GUIDE §11's rekey match order names the base revision first (a-rekey-parks-a-mass-absence); GUIDE §12's purge needs the same body or none, as STORAGE §11 says.
- **vectors/**: every file states `v`, sync/* and gtd/writers.json gaining `"v": 1`; vectors/schema/ holds a JSON Schema (draft 2020-12) per format, which checks/vectors.py validates (flake.nix adds python `jsonschema`). A copy of vector 01 without `v` and with an unknown key fails it.

Search:

- **queries/search/occurring_between.sql** (normative): a zero-length occurrence at the range's start falls in it, so a `DUE;VALUE=DATE` task answers `date:` its day. Guarded by checks/invariants.sh ("expected [Cal|1|], got [|]" on the old statement) and search case `date:2027-01-15` over the new item 22 (fixtures/todo-due-date.ics).
- **SEARCH §8.1** (normative): a range leaves the horizon only in a query that can reach a calendar item, which the vectors already said (`collection:work/INBOX date:2026-07..`). checks/vectors.py re-derives `horizon_left` for every plain query and fails a case either way.
- **SEARCH §6, §8** (normative): `has:attachment` is the mark for mail and a non-empty `attachment` field for a calendar item, that field holding each `ATTACH`'s `FILENAME` (RFC 8607) and `FMTTYPE`; cases `has:attachment` and `has:attachment kind:task` over the new item 23 (fixtures/event-attach.ics) and item 16. Chunk offsets index the indexer's own extraction, so a client of another implementation re-chunks; `id:` with digits alone names the `seq` and the link id both; `linked:` reads a role before the first colon only when it is one.
- Items 22 and 23 joined the search fixture store, so the cases `date:today..`, the two task-status and priority ones, the Next view, `changed:..`, `folder:home/Calendar` and `has:attachment` gained them.

`nix flake check path:$PWD` passes. io-pimdir vendors migrations/ (the trigger), queries/ (`backfill_invitation`, `backfill_task_organisation`, `occurring_between`, `delete_collection`'s comment) and reads vectors/ (two new sync vectors, two new search items, `v` everywhere, vectors/schema/), and follows in its cairn.
