---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The SHOULDs and MAYs reviewed

The second and third lines of the freeze plan's section 4: every SHOULD and MAY of STORAGE, SYNC and SEARCH at draft-15 (86 obligations on 78 lines, the key-word boilerplate aside) read with what io-pimdir does and which consumer's correctness rests on it, from the sources of io-pimdir, himalaya, cardamum, calendula, neverest and the Android app, read and never run. None needs a spec break. Four lines are documented in draft-15, no rule moving; two promotions wait on the owner; the rest stay optional, for the reason given.

## Documented (no rule moves)

- **STORAGE §15.4, the overlay (decided).** It stays MAY for a reader and SHOULD for how a row folds: an overlay is a prediction the drain can contradict (a body it cannot read, a capability declared since), so it cannot be a MUST, and no store loses anything by a wrong fold, the owner checking `base` and `if_match` again. The rows it folds into nothing are now every row the owner would park (§15.2, §15.3, §15.6), the listed ones among them, with an action on an item no source binds added, and a producer gating a write on what it shows states `base` or `if_match`. himalaya takes a flag change's `base` from the folded set, cardamum and calendula their `if_match` from the folded body, each through io-pimdir's `PimdirReader::with_pending`; Android and neverest overlay nothing.
- **STORAGE §14, the sync seam's selection.** "A store MAY return more than the selection names" now says never a retained item (§11.1), which §11.1's MUST on `load_items` and SYNC §3 already held: neverest and Android would re-upload a retained row. This is the plan's "retained items `load_items` leaves out": a MUST already, only the MAY read against it.
- **STORAGE Annex A.1, the hint read raw.** Its SHOULD now names SYNC §4's MUST on the three compared fields, so the two levels read as one rule (the hint SHOULD, the compared fields MUST).
- **SEARCH §4, refreshing after each batch.** A client relies on `behind`, never on the one-batch bound: neverest refreshes after a whole run or drain under a deadline, or not at all, which the SHOULD allows, and the frontends print `behind` already.

## For the owner

- **STORAGE §14.3, the attachments collection's id** (`account/\u0001attachments`): promote SHOULD to MUST (spec minor, recommended). Two owners of one store declaring it differently file stand-ins twice; io-pimdir and Android both write it, and sync vector 70 and the search store pin it already.
- **SYNC §5, a narrowed round handing `enumerated`**: promote SHOULD to MUST for a connector offering an enumeration (spec minor, optional). Without it a narrowed round finds no absence; neverest's IMAP, Graph and Gmail connectors and Android's Gmail one hand it.

## Kept, by reason

- **The implementation's choice** (a profile omitted, the canonical text or its own, statements of its own, several statements under one name, `*` on `store_meta`, the exclusive-create fallback, a write cut in chunks, references recorded or ignored, further intents, an index of another shape, flattening, a page answered): no consumer depends on which way it goes.
- **Performance** (`incremental_vacuum`, a merge statement's plans, a blob written before `BEGIN`, the refcount settle skipped, `recompute_refcounts` skipped, a run of actions in one transaction, a batch recording its stamp, extraction in parallel, fetching concurrently, paging a round, lowering a page size): correctness is the same either way.
- **The platform or the deployment** (`FILE_SHARE_DELETE` on Windows, `fullfsync` on macOS, a lease on a network filesystem, the SQLite 3.31 defences): each where it applies.
- **A person's or a producer's choice** (the account id, refusing a shared store or asking, asking before an intent, the zone a client states, `base` and `if_match` where a producer read something, showing a `partial` detail, resolving capabilities before enqueuing, which the owner's backstop decides again).
- **Reports an engine owes the person** (unlisted bindings of a narrowed or capped round, a pending create out of scope, delivered creates waiting, a resumed run listing its head): io-pimdir reports each and neverest shows them; promoting changes no store.
- **Freedoms the parts state on purpose** (a DAV member carrying its body, naming members from decoded values, a band round, a superseding create delivered by a server move, recording a create delivered early, a mail scope and a received-date filter, an `Edit` restating its sort key, a `Full` fetch streamed, a receipt dropped after seven days, a later Unicode version's mapping, a scheduling intent's two forms, a rename followed by `rename_collection`, bm25 recommended and `relevance` refusable, an HTML reduction's token boundaries and skipped elements, a WHATWG decode, a vendor re-checking digests, `trusted_schema` and `DEFENSIVE`).

## Findings by door

- **Implementation (io-pimdir):** its overlay (src/client/reader.rs `fold`) folds rows the owner parks: an action on an item no source binds in a synced collection, a `move` or `copy` of an unbound item, the §15.6 backstop, a `move` to an undeclared target or one of another kind; and an `update` it folds repoints the body and level but leaves the summary and sort key as committed, which calendula works around. A wrong fold shows an edit the drain then parks; nothing is lost.
- No spec break.

Checked: `nix flake check path:$PWD`. A doc-only change lands no new check (AGENTS.md §4 binds a rule); the overlay's cases go to the generator's oracle (the freeze plan, section 2).
