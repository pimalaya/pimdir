# pimdir-generator

Status: tooling of this repository, no part of the standard

A deterministic generator of pimdir histories, the stores they leave and what every conforming implementation answers over them. It is the generator of cairn/changes/the-freeze-plan (section 2, and the oracle of section 5b), into which cairn/changes/pim-corpus folds. This file is its design note: what it models, what it writes and through what, what its oracle states, how a failure shrinks into a vector, and how io-pimdir takes it as a dev-dependency. scenarios.md beside it is the catalogue of what the consumers do with a store, read once from their sources, from which the profiles draw their events.

## What it makes

`(generator revision, seed, profile)` gives one **history**: a list of events over accounts, collections, sources, items of the four kinds, remote changes, queued actions, sync runs, purges, erasures and crashes. From a history the crate derives, for any event `n`:

- **the store** after event `n`, written into a directory by the canonical statements of queries/ and migrations/ alone, which io-pimdir opens as it opens any store of the current draft;
- **the scripts** of the remote sources, plain data a scripted connector answers from: what each enumerate, fetch and push of a run receives;
- **the oracle**: what every read, count, overlay and search answers after event `n`, and for an engine event, the pushes, the events and the rows it leaves, beside the properties every run holds (no loss, convergence, queue order).

Nothing is stored but the seed: a failing case is the triple above, about 40 bytes, which replays byte for byte on another machine, the bodies and the SQLite instants aside (below).

## Rules it keeps

- **No Pimalaya crate** (D1, 2026-11-20): not io-pimdir, not mime-rs, vcard-rs nor ical-rs. Its dependencies are the ones io-pimdir already pins, so a dev-dependency adds nothing to its lock: rusqlite 0.43 (`bundled`), blake3 1, serde 1 and serde_json 1.
- **The standard writes its own test data.** The writer runs the statements under queries/ and the migrations under migrations/, loaded at run time from the tree the crate sits in (below), bound by the names queries/signatures.json states. Its only SQL text of its own is `PRAGMA`, `BEGIN`, `COMMIT`, `SAVEPOINT`, `RELEASE` and `ROLLBACK`, so checks/schema.sh's rules (no JSON function, no `*`, column lists everywhere) hold of it by construction. The draft a store names is the one init_store_meta.sql writes: the generator never spells a draft's name, so a draft bump in queries/ moves every generated store with it.
- **No parser.** The generator never reads a body to learn what it says. A body is rendered from the model, so its Annex A derivation is the model's value by construction (below), or taken whole from vectors/fixtures/, whose derivation vectors/summaries.json pins and checks/vectors.py proves on a second path.
- **The PRNG is owned and pinned by algorithm**: PCG32 (XSH RR, 64-bit state), checked against its published sequence for seed 42 and stream 54. No `rand`, whose `StdRng` is reproducible within a major only.
- **Closed model.** An event the model cannot predict exactly is not generated. Every class left out is listed under "Limits" with the plan line that will add it, so a passing campaign never claims more than the model covers.
- **Plain names.** The crate is unpublished test tooling, so its public types take no domain prefix and are namespaced by their module (`spec::Spec`, `store::Store`, `rng::Rng`), as the family's toolkit crates are (the owner's call of 2026-11-20, which the owner may still reverse).

## The model

The model is the truth a history moves: plain ordered maps, no SQL, one value per row of STORAGE §4.3 that a reader can observe. It is a second reading of STORAGE, SYNC and SEARCH, written from their text and GUIDE.md's tables, never from io-pimdir; where it and io-pimdir disagree, one of the two misreads a rule, or the rule reads two ways, which is the finding the differential exists for.

### Entities

- **Accounts**: `NULL` (a single-account store) or ids from the catalogue's shapes (`work`, `personal`, a mail address as himalaya and the Android app use), never holding the namespace separator (STORAGE §9.2).
- **Collections**: an id namespaced by account where the store holds several (`work/INBOX`, `carddav/default`, the Android app's shapes), a kind of the four or `''` undeclared, a display name, a role of its kind's vocabulary, a parent, a conflict policy, a generation. The attachments collection of an account (`<account>/\u0001attachments`, role `attachments`) when the profile records stand-ins (STORAGE §14.3).
- **Sources**: per collection, with a checkpoint, a coverage, a round and its stamps; a source id names one remote store-wide.
- **Items**: link id, seq, flag set (known or not, its system flags as `marks`), body or none, level, sort key, the cross-source state (`deleted`, `conflicted`, `conflict_object`), retention, the kind's summary row with its list rows, address rows. Mail, contacts, the three calendar components and files, the files being stand-ins of attachments or members of a file source.
- **Bindings**: per item and source, handle (a provisional one `\u0001` and the link id), the base (flags, object, revision, presence), `shared_object`, the binding's conflict, its round, the refusal standing on it.
- **Objects**: hash, size, refcount as STORAGE §5 settles it, and whether the blob file is held, missing or corrupt, or held with no row (the states vectors/sync names).
- **The queue**: rows with their producer, collection, action, payload (as the bytes a producer wrote), target collection, object, attempts and error; receipts; supersessions; capabilities and performers; references.
- **The remotes**: per source, its members by handle (flags, revision, body), its checkpoint counter, its handle space and validity epoch, its rights, what it accepts, refuses or answers with no handle, and the server-side quirks the catalogue lists (a cap, a date filter, a rejected cursor).
- **The feed**: the event at which each item and collection last moved, the purge count, the store id and incarnation, so the oracle states what a consumer folds above a cursor (STORAGE §4.5).

### Bodies and their derivation

Two layers, as pim-corpus proposed:

- **Surface**, sampled: plausible names, subjects, words, addresses, dates and times, from small word lists in the crate. Each body is rendered in a form whose Annex A derivation is the value the model drew: a message with ASCII header fields written once, unfolded, a `Date` in UTC at whole seconds, an addr-spec already canonical, `Message-ID` and `In-Reply-To` in angle brackets; a vCard 4.0 and an iCalendar object whose properties are unescaped text; an attachment, an invitation, an encrypted part or a calendar time zone only through a template whose derivation is stated beside it. The words of the text fields are known too, which is what the search oracle matches.
- **Structure**, enumerated and never sampled: every fixture under vectors/fixtures/ is a body the generator files as it stands, with the link id, summary, addresses, sort key, mark and stand-ins vectors/summaries.json gives it. That is where the hard cases of Annex A live (encoded words, folding, broken dates, 8-bit headers, bare LF, charsets, time zones, override-only series, the walk's bounds), already derived twice.

Every generated body carries a run-scoped mark (an `X-Generator-Run` header for mail, an `X-GENERATOR-RUN` property for the others, never in the `X-PIMDIR-` space a producer strips, STORAGE §18), so a body in a store or a remote can be traced to its seed; the mark is part of the bytes, so the `hash:` key the model computes (FNV-1a 64, Annex A.2) covers it.

### Structure cases

What the generator files for each case pim-corpus enumerates, and for the store's own:

| Case | In the store or the script |
| --- | --- |
| a missing `Message-ID` | an `alt:` key (mail-no-message-id.eml and generated twins) |
| a `Message-ID` twice in one collection | a second copy minted `dup:<key>#<handle>` |
| a `Message-ID` reused across collections by another message | a row that does not agree: its own `seq`, its own body, never linked |
| a never-written mailbox (`HIGHESTMODSEQ` 0) | a source whose first checkpoint is the zero one and a delta that lists nothing |
| modified UTF-7, a separator inside a name, names differing by case, a name a prefix of another | collection ids and names of those shapes, each its own row |
| an empty collection | a declared collection with no item, synced and deleted |
| 100k UIDs with holes | handles drawn with gaps, sorted by byte order, never by number |
| a `UIDVALIDITY` bump | a rekey: the handle space renumbered, from 1 again |
| system flags, keywords, `$Important`, `$Junk`, `\seen` | marks and flag rows, `\seen` a row of its own (STORAGE §13) |
| 8-bit headers, absurd folding, a broken or missing `Date`, CRLF beside bare LF | the fixtures pinning each, `NULL` date and `''` sort key included |
| thread graphs with broken `References` | `In-Reply-To` chains with gaps, cycles and ids nothing holds |
| reserved prefixes in a hint | `esc:` keys (card-reserved-uid.vcf and twins) |
| a card or an event with no usable `UID` | a `hash:` key, two byte-identical ones in one collection |
| attachments, invitations, encrypted mail | stand-ins and references, `invitation` and its reference, a body the search part counts `encrypted` |
| tasks with a parent, a mail they came from, categories | `parent`, `mid`, `task_category`, the references the owner records |
| recurring, all-day, floating and zoned events, overrides | the fixtures of A.3, generated series with `RRULE`, `RDATE`, `EXDATE` and `RECURRENCE-ID` |

## Events and histories

An event is one of:

- **Configuration**, the owner's: declare a collection (kind, account, name, role, policy), rename one, delete one, declare a source's capabilities, restore the store from a copy (`raise_incarnation`).
- **Remote**, on one source: a member added, edited, flagged, removed (stated or silently), renumbered, a refusal armed for a push, an add answered with no handle, a cursor or a head rejected.
- **Producer**: one or several actions enqueued in one transaction, every action and intent of STORAGE §15.3 and Annex B.2 that a consumer issues, with the options the catalogue shows each issuing (`base`, `if_match`, `resolves`, `supersedes`, `copy`, `recurrence_id`, a performer), and the malformed and unknown payloads of vectors/payloads.json.
- **Engine**: a verb of SYNC (sync with its options and scope, upgrade, mutate, rekey) or a drain of the queue, as the catalogue's run shapes order them.
- **Owner upkeep**: purge, purge before an instant, evict, release, erase, collect, cancel, retry, acknowledge, prune receipts.
- **Crash**: the next engine event cut after its `k`-th commit, the store reopened and the verb run again.

A history is a list of events drawn by its profile. The catalogue gives each event its weight and its preconditions (a `move` needs a target of the same kind, a `resolves` a conflict shown), so a sampled history is one a consumer could have caused.

## Profiles

- **structure**: every structure case and every catalogue scenario once, in a fixed order, the seed choosing only the surface. Small enough to run on every `nix flake check`.
- **quirks**: about 500 items in about 30 collections with hostile ids and names, every reserved prefix, every key shape of STORAGE §9, the queue's malformed and unknown rows.
- **count**: 100k to 200k small items, hundreds of collections, a hierarchy 5 deep or more, for listing, merge and scale tests (task 3, line 5) and the Android and io-pimdir benches.
- **bytes**: a few hundred items, large bodies, one past 25 MB and one past 100 MB, rendered as a stream from the seed and never held whole, for the blob store, fetch and append paths.
- **campaign**: sampled histories mixing every event class by the catalogue's weights, the profile campaigns run (plan section 7).

## The writer

The writer turns the model into a store, through two doors only:

- **As the owner**: GUIDE §2 and §3 (`flock` on owner.lock through `std::fs::File::try_lock`, the pragmas, 0001_init.sql, `init_store_meta`, `create_param`), then GUIDE §5's statements in its order for every row the model holds: `store_object`, `ensure_collection`, `set_collection_*`, `seq_for_link_any` or `bump_next_seq`, `insert_item` with its flag rows, the kind's summary, addresses and lists, `insert_binding` with its base flags, the round and checkpoint statements, `retain_item`, `supersede_item`, `add_reference`, `set_capability`, `set_performer`, `refuse_binding`, `adjust_refcount`. A blob is written as GUIDE §4 writes it, through a temporary and a link that never replaces.
- **As a producer**: GUIDE §13's enqueue under a shared lock on objects.lock, `store_object`, `pin_object`, `enqueue_action`; parked rows by `park_action`, unconfirmed ones by `unconfirm_action`, receipts by `record_receipt`.

It can write the state after any event (**materialise**), so a reader test opens a store at event `n` without running an engine, and a shrunk case states its `store` rows. Owner upkeep events run their own statements (`purge_item`, `evict_before`, `release_before`, `rename_collection` with `rename_queue_targets`, `delete_collection`, `cancel_action`, `raise_incarnation`).

Three things a writer cannot choose: the store id and the instants SQLite stamps (`created_at`, `retained_at`, `covered_at`, `applied_at`, `refused_at`). The oracle leaves the first and those instants out, as vectors/sync does, and an event taking a cutoff instant (`purge_retained_before`) takes it between the instants the writer observed around the events it separates, the writer leaving at least a millisecond between them.

A state the model reaches and no canonical statement writes is a finding (the store's statements cannot build what its rules lead to), reported with the event that reached it. The writer records which statements a profile ran: a statement no profile runs is an input to checks/waivers.txt's review, never a reason to add SQL of the generator's own.

**Where it reads the statements.** The crate finds migrations/, queries/ and vectors/ in the directory above its own manifest (`env!("CARGO_MANIFEST_DIR")/..`), which is this repository's root here and io-pimdir's spec/ once vendored there (below), or in a directory the caller names. It refuses a tree whose statements disagree with queries/signatures.json.

## The scripted remote

A source's script is what SYNC §4's three requests answer, per run: the pages of a round or the one page of a delta (members with handle, flags, revision, meta, `carries`; `vanished`, `complete`, `last`, `cursor`, `checkpoint`, `narrowed`, `enumerated`, `capped`), the head, the fetches by handle and tier, and the outcome of each push (accepted with or without a handle and a revision, rejected, refused with a reason, a relocation). It is plain data in the shape of vectors/sync's `remote` and `outcomes`, so a scripted connector written once in io-pimdir's tests answers both, and a shrunk case moves into a vector unchanged. The generator states what the connector receives and is to answer, never how io-pimdir calls it: no trait, no callback, the connector being io-pimdir's.

A remote holds its own state between runs (the model's), so a script is derived per run from it: what changed since the checkpoint the run presents, a round's pages cut where the profile says, a delta's stated removals.

## The oracle

For every event `n` the oracle states:

- **Reads**: for each statement under queries/storage/read/, the rows it answers at parameter points the model draws from the state (every collection and account, every `seq`, a listing's first page and the page after each cursor, a page past the end, every address and domain, every link id and hash held twice, the trash, the queue rows), compared as typed values, in order where the statement orders, the store id and SQLite's instants left out. A consumer whose API wraps the statements (io-pimdir's reader) maps its calls onto these points.
- **The overlay**: what a reader shows with the pending rows folded as GUIDE §13 ends, per listing and per item, including a row that would park (folded into nothing) and an unknown one (listed, folded into nothing).
- **The feed**: the set of items and collections a consumer folds above a cursor recorded after any earlier event, the order across events, and whether `purges` moved (STORAGE §4.5, plan section 4's seam).
- **Engine events**: the pushes in order with the idempotency key SYNC §4 derives, the events reported, a park and its counts, a failure, and the rows after in vectors/sync's `expect.store` form; and the properties a run holds whatever the model predicts: no body ever written lost (reachable from a row, retained, or quarantined), a second run changing nothing, queue rows applied in append order, a run cut after any commit and run again leaving the rows a clean run leaves.
- **Search** (plan 5b): for each query the vectors ask, and each form of SEARCH §8.3's grammar, the hits as `(account, seq)`, threads, the coverage counts, `complete`, `horizon_left`, `zone_differs`, `cut` and the temporal coverage, from the model's own reading of SEARCH §6 to §9 over the words it rendered.

**The self-check.** On every profile the crate runs, the canonical read statements answer, on the store the writer wrote, what the model predicts. That holds the writer to the statements and the model to the store, and is the check `nix flake check` runs (below). A disagreement fails it and is a finding before any implementation is involved.

## Shrinking

A failure is a history, an event index and a predicate the caller states (a read disagreeing, a property failing). The shrinker reduces it deterministically: events dropped by halves then one at a time, then items, flags, bodies and pages made fewer and smaller, each candidate replayed and kept while the predicate still fails. The result is written as:

- a **sync vector** when the failing event is one engine verb: `store` the materialised state before it, `run` the verb, `remote` its script, `expect` the oracle's; a generated body becomes a fixture under vectors/fixtures/ named by its digest;
- a **search vector** case (store.json items and a queries.json case) when the failure is a query's answer;
- otherwise a **scenario** text for checks/invariants.sh, with its statements in order, for the lane owning checks/ to land.

A failure needing several engine events (a crash and its rerun, a drain then a sync) does not fit one sync case: sync vector format 8 holds one run. Such a failure is reported with its history until the format grows (a finding for the vectors lane, below).

## How io-pimdir consumes it

- **Vendored like the vectors.** checks/implementation.sh copies migrations/, queries/, vectors/ and payloads/ into io-pimdir's spec/; it copies generator/ too, and io-pimdir declares `pimdir-generator = { path = "spec/generator" }` under `[dev-dependencies]`. The crate then finds the statements one directory up, the same tree io-pimdir's suite runs over, so the generator and the vectors never come from two revisions.
- **Its API is data.** `Profile::generate(seed)` gives a `History`; `History::store_at(n, dir)` writes the store; `History::script(n)` the remote's answers for an engine event; `History::oracle(n)` the expectations; `shrink(history, n, predicate)` the minimal case and its vector. io-pimdir's tests own the scripted connector, the comparison of its reader's answers with the oracle's read points, and the crash injection.
- **Its tests**: readers against the oracle on every profile's stores, queued rows of every producer included (plan 3.1); the engine replaying the scripts (3.2); a crash at every commit (3.3); the index refreshed after each event against a rebuild and against the search oracle (3.4); the count and bytes profiles under the scale tests (3.5). Campaign seeds live in a file of io-pimdir's tests, run by its CI.

## Determinism and the revision

`REVISION` is an integer in the crate, raised whenever a `(seed, profile)` gives another history. generator/digests.json pins, for a fixed set of seeds per profile, the BLAKE3 of the history's canonical serialisation, and the crate's tests compare them: an accidental change fails, an intended one raises `REVISION` and restates the file, logged in cairn/log/ like any change here. The bodies are part of the history; the store's bytes are not, since its id and instants are SQLite's.

## Checks

`nix flake check` runs the `generator` check, which builds the crate with `rustPlatform.buildRustPackage` from its Cargo.lock and runs its tests: the PCG32 sequence, the base32 cases and object names of vectors/objects.json, every statement prepared against a fresh store to the parameters and columns queries/signatures.json states, the fresh store's `store_meta`, pragmas, modes and lock, and the Annex A revision STORAGE.md states; as the steps land, the digests of digests.json and the self-check on the structure and quirks profiles at the pinned seeds, with a sample of the count profile. The development shell carries cargo, rustc, clippy and rustfmt (`nix develop --command cargo test` in generator/). The crate holds no `//` comment but `// SAFETY:` and follows the family's layout rules.

## Limits

Left out at first, each with the plan line adding it:

- engine events (sync, upgrade, mutate, rekey, drain) and the scripted remote: plan 2, "The scripted remote states", once the model of SYNC lands, in this order: one source, deltas then rounds, refusals and deliveries, several sources and policies, rekey;
- the search oracle: plan 5b, "The generator's oracle answers every search the vectors ask";
- crashes inside the generator's own writes: never, the writer being the test's fixture, not its subject;
- the index file itself: the generator never writes index.db, which is the implementation's to build.

Where it stands (2026-11-20): the structure profile holds the surface layer of the four kinds and the cases its model keys so far (a message filed in two mailboxes sharing a `seq` and a body, a `Message-ID` reused by another message, one held twice in a mailbox, none, an undated message, an attachment, a listed message holding no body and no known flags, keywords beside `\Seen` and `\seen`, a card with no `UID` and one with a reserved prefix, UTC, floating, all-day and recurring events, tasks, a journal, files, an undeclared collection, an empty one). Still to come before its line is ticked: the fixtures of vectors/fixtures/, tombstones, retained rows, conflicts, the queue, references and stand-ins. The self-check compares the store's answers with the model's, so a value both take from the model (a sort key, a summary column) is held to Annex A by another test: the renderers derive, for bodies stating a fixture's fields, the rows vectors/summaries.json pins for that fixture.

## Build order

1. The model and the structure profile's entities (plan 2, "The model").
2. The scenario catalogue (scenarios.md, plan 2).
3. The writer, materialising any state, and the self-check over the read statements (plan 2, "The writer").
4. The oracle of reads, overlay and feed (plan 2, "The oracle").
5. The scripted remote and the model of the engine (plan 2, "The scripted remote states").
6. Profiles count, bytes, quirks, campaign (plan 2, "Profiles").
7. Shrinking into vectors (plan 2, "Shrinking").
8. The flake check (plan 2, last line).
9. The search oracle (plan 5b).
