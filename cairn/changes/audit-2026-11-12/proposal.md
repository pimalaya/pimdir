---
cairn: change
id: audit-2026-11-12
status: active
created: 2026-11-12
---

# The audit of 2026-11-12 before version 1: the standard, io-pimdir and its five consumers

## Why

Version 1 is the next step, and it is the last moment a change is free: a draft's store is never migrated, so what the freeze holds wrong costs a migration, a payload version or a table rebuild for ever after. This audit reads the standard, its reference implementation and the five programs built on it (neverest, himalaya, cardamum, calendula, the Android app) from eleven angles, asking of each what would make it safer, faster, more accurate or less verbose, and saying so where nothing would.

It is differential (AGENTS.md §5): every reader started from the open lines of the pimdir and io-pimdir ledgers, and a finding already listed is repeated only where the freeze changes its priority. It is wider than a format audit: the consumers are in scope, because what they forked, skipped or wrote twice is the best evidence of what the standard and io-pimdir make hard.

## Method

- **Read first.** STORAGE.md and SYNC.md end to end, SEARCH.md's index half, the schema, io-pimdir's seams and the open lines of every ledger, before any brief was written.
- **Eleven analysts**, one angle each, read-only: the frozen surface, versioning and the gate, sync safety, store safety, performance, derivations, search, the text and its statements, the three CLIs, neverest, the Android app. At most eight findings each, with the file and line read, a failure scenario or a measured cost, a proposal and its class against the freeze.
- **Eleven skeptics**, one per angle, each told to refute: reopen every citation, look for the rule that already prevents the scenario, grep the ledgers and the logs, check the decisions already made, judge the proposal. Of 85 findings, 56 were confirmed, 28 held in part and are stated here as corrected, 1 was already known, none fell whole. The skeptics added 11 of their own. Two more came from the reading that preceded the briefs (D3, F15). The code behind F1, F2, D1, D4, V2 and Y1 was then reopened by hand, as were the findings a skeptic alone had made (D2, V7, T5, F14 and F2's conflict half), and V1, F11, A1's replay and the plans of P1 and P2 were run a third time.
- **Experiments** on scratch stores built from migrations/storage/0001_init.sql, on SQLite 3.51.2 and on the 3.18.2 floor build: query plans, timings at 60,000 to 200,000 rows, a rebuilding migration, what the schema accepts. Timings are on tmpfs, so they compare variants and hold no fsync cost. bench/ keeps the two worth running again: rebuild.sh, the migration rehearsal behind V1, and statements.sql, the texts timed for P1 and P2.
- **Not done.** No test suite was run, no server contacted, and nothing was changed in any repository but this folder. The analysts' reports, scripts and scratch stores stayed in the session's scratch directory and are not part of the repository; each ledger line carries the files and lines it rests on.

The ledger is tasks.md: 81 lines, one per finding after merging those two angles reached. The line names below (F1, D1, Y1) are its own.

## The verdict

The model holds. Nothing found asks for a different store, a different identity scheme or a different sync algorithm, and the areas the last three audits hardened (the blob store, the push discipline, absence inference, the version refusal, the schema's cost per item) were examined again and came back sound. Storage is close to freezable.

What is left falls in five families, in the order they matter for the freeze:

1. **Three shapes would freeze wrong.** Two payloads carry less than their producers know (`set-flags`, `remove`), and one fact has four witnesses (a base's presence). Each costs a line now.
2. **Identity rests on comparisons whose inputs are not pinned.** The standard both allows a server-decoded subject, date and sender to differ from the body's and mints a message apart when they do; one consumer derives keys with its own parsers; the agreement test stops at the collection's edge. A key is never re-derived, so these outlive any fix.
3. **The second writer is unchecked.** The reference engine passes its vectors, but the Android app's own load and write run none, and they lack two store-side rules. The desktop connectors have never run the seam contract sync-v1 would freeze.
4. **The rules for life after v1 are unrehearsed.** A rebuilding migration under the stated runner deletes every item on the SQLite floor; no program implements the released open rules; the freeze gate holds nothing once the tags exist.
5. **Smaller holes**, each with a cheap answer: an immortal temporary file, a restore answering a recorded incarnation, coverage that reads complete over encrypted mail, an empty collection deleted unseen by the feed.

On the four aims:

| Aim | Where the gain is | Where there is none |
| --- | --- | --- |
| Safer | F1, F2, D1 to D3, Y1, Y2, A1, V1, V2, T1, T4 | the blob write and its verification, the locks, the drain, the push discipline, absence inference |
| Faster | three statement texts (P1, P2, P3), an index decision (F8), batched queue writes (F17) | the schema itself: keys, indexes, triggers and paging measured and kept as they are |
| More accurate | D4 to D8, S1 to S5, F11, X1, X2, V6 | the A.1 header parse, the key grammar, the query parser, OVERVIEW.md |
| Less verbose | a statement cut (F10), one home for two rules (X2), the consumers' duplicated store rules (C5, A6, N2) | the three parts: dense, not redundant; no split, no rewrite |

## What is solid

These were examined and should not be touched.

- **The schema's cost and shape.** The integer placement id with rowid-less children and the system flags as bits are worth what draft-09 claimed: a bare mail placement with one binding costs 472 bytes and a listed message with its summary and addresses about 950, counts are covered by `items_by_sort`, every by-link load is a key seek. 36 of 40 indexes are read by a canonical statement. Renaming 100,000 placements takes 1.7 s against 21.9 s per 250,000 under draft-08, so the text collection ids of decision D4 stand. `bindings` without a rowid would save 1.7% of the bytes and no time.
- **The change feed.** 200,000 inserts drew exactly 200,000 stamps, a restated row draws none, and no writer computes one. The insert trigger costs 6 to 8% of a fill and a variant writing the stamp itself recovers 0 to 3%, inside the noise.
- **Facts the schema holds.** A flag set's three parts cannot disagree (one `CHECK`, two triggers); a body's name is a 52-character shape every pointer reaches by a foreign key; the store's identity cannot move. This is the pattern F3 and F4 extend.
- **The key grammar.** Six reserved prefixes with `esc:`, minting that survives its own collisions, derived keys refused as reference endpoints, FNV-1a 64 where a collision only mints: no ambiguity that changes an outcome was found.
- **The blob store.** A name holds a whole body or nothing, a held name is verified before it is kept, a read verifies through the descriptor it serves, quarantine verifies again under the locks and flushes both directories.
- **The sync core.** A chunk is recorded before the next is pushed and the checkpoint stays behind the pushes; absence comes only from a complete round's last page and a listing dropping most of its scope parks; a delta checks its hints against the whole collection by a second load; only a stated relocation delivers.
- **The version handshake.** Refusal never writes, the index has no migrations (refuse or rebuild), derivation follows its last writer and is tested both ways, vectors are authored from the prose and pinned by a manifest.
- **The checks.** All 258 statements are run by a scenario and none is waived; names.sh and references.pl catch every wrong name and dead reference. Every drift found here is of a kind they cannot see.
- **The implementations' discipline.** io-pimdir makes the profiles types, so a CLI cannot open another draft's store, hold a lock as a reader or serve an unverified body. The Android app never forks the schema, names the digest of each canonical statement it rewrites and runs each fork beside it, on a host build of the 3.18.2 floor. neverest's seam adapter derives `last` from the cursor so a connector cannot mis-state it, and its DAV connector never reads a cut listing as complete.

## What is weak

### 1. Shapes that would freeze wrong

**The queued flag change is a read-modify-write (F1).** `set-flags` carries the whole replacement set. himalaya computes it from a read, and the owner writes it over whatever the placement holds when the row is applied, so a flag another device set, pulled in between, is erased and the erasure pushed. The push seam was made a delta for this on 2026-10-30 and the queued body got `if_match`; the queued flags were left absolute. The window is narrow (a row queued during a run), which is why the skeptic lowered it to medium: the reason to act now is the payload freeze.

**A queued remove says less than its producer knew (F2).** cardamum and calendula accept `--if-match` on delete and check it at the enqueue only. Worse, a remove meeting a conflict is the decision (SYNC §7), and nothing parks it as an `update` is parked since 2026-11-01: a delete queued before a conflict arose removes the server's diverging body unseen.

**One fact, four witnesses (F3), and shapes held by prose (F4).** A scratch store accepts a base that is present and absent at once, an instant spelled "yesterday", a `seq` of -3, an empty collection id that then collides with `NULL` in two key indexes. No conforming writer writes these, but statement text is free (decision D3 of 2026-10-31), and SQLite cannot add a `CHECK` later without rebuilding `items` or `bindings`.

The rest of the family is small: a deleted empty collection the feed never mentions (F5), a receipt deleted with the collection its intent deleted (F6), three indexes nothing reads (F8), eight paged reads that answer an empty page on a `NULL` cursor against §9.3's own rule (F11), a handful of names (F7, F9).

### 2. Identity

**The agreement test and Annex A contradict each other (D1).** Annex A.1 lets a value a server decodes itself stand until the body is read and says it need not agree with the body's derivation. §9 and SYNC §6 land a create, join an item and revive a row only when subject, date and sender agree byte for byte, "which no server rewrites". neverest's Graph connector and the Android app's JMAP and Graph connectors name members from exactly those decoded values. Three readers reached this independently. Where the two derivations differ, a message is minted beside itself, a delivered create waits for ever, or a pending one is uploaded twice. Nobody measured how often they differ on a live server; the standard itself guarantees some cases (a `utf-7` word stays literal under A.1, `iso-8859-1` reads as windows-1252).

**neverest keys with its own parsers (D2).** Its Gmail and IMAP listings derive the Message-ID by stripping one pair of angle brackets and decode through chrono and rfc2047_decoder, where A.1 is stated to the character and io-pimdir implements it. The Android app reads the same Gmail message through io-pimdir's `derive_meta`. Two programs of one family key one message two ways, and a key is frozen once resolved.

**The agreement stops at the collection's edge (D3).** In one mailbox a message reusing a `Message-ID` must agree or is kept apart. Across mailboxes of an account, the body is linked on its size alone, on nothing when the source states none, and the two share one public id. A templated notification reusing its id, one copy archived and the next in the inbox, shows yesterday's body under today's subject and is one hit in a merged view. This is the wrong merge §9 exists to prevent, one statement away.

**What no vector pins (D4 to D8).** No fixture exercises a charset table, and the Android release build links none, so the phone keys and lists legacy-charset subjects as literal encoded words while every vector passes. A repeated header is read first by the summary and last by the search extraction and by JMAP. An empty `UID` is keyed as an identity. A resource of overrides alone has no summary rule. The lowercase mapping names two references that differ on a final sigma.

### 3. The second writer

**The Java write lacks two store rules (A1).** It joins any row holding a bare key, a retained one included, with no agreement test: replayed twice on a scratch database, a message reusing a trashed `Message-ID` takes the trashed row and shows the old body under its new subject. And it never purges a row whose identity moved, so every server-side move fills the trash. Vectors 109 and 110 pin the first rule; the app runs neither, nor any of the 140 (A2). The pimdir ledger ticks both rules as followed by the app (V8).

**The desktop connectors lag the seam (Y2, Y1, Y4).** neverest pins sync-draft-08, so `relocated`, which sync-v1 would freeze, has been run by vectors and the Android app only; it also misses two older rules, one from 2026-09-04. Its Graph mail pass hands as vanished whatever a fresh delta did not list, which the engine applies outside every absence guard. And no connector can say `capped`.

**Why it happens (A6, X1).** The store-side rules of §14 live in io-pimdir behind rusqlite, so the platform SQLite forced a second copy: about 1,270 Java lines, 14 write statements the standard does not name. §4.4 and §17 bind every implementation to the canonical names; neither implementation runs them all. What a name binds has to be said before names freeze.

### 4. Life after v1

**A rebuild under the stated runner loses the store (V1).** §6 foresees migrations that rename or drop a column. On SQLite these rebuild the table; in one transaction with foreign keys on, as §6 step 3 runs them, the rebuild of `collections` commits on 3.18.2 with every item cascaded away and `integrity_check` clean, and fails on a current SQLite. Both analyst and skeptic reproduced it. The skeptic found the other route (editing a `CHECK` under `writable_schema` keeps every row) and that the defensive mode §18 recommends refuses it. Nothing rehearses either.

**The released rules exist on paper (V2, V3, V6).** Version 1 binaries will be the old readers and producers of every later store, yet no program reads `read_version` or `produce_version`: io-pimdir calls any other `user_version` damaged. The rule for a payload version an owner does not know has no vector, and the reference broke on it on 2026-11-01. checks/tags.sh passes while two of the three current drafts are untagged, and names.sh reads nothing from a `storage-v1.0.0` Status line.

**The freeze order has a cost nobody chose (V4).** With STORAGE frozen first, sync state stays exact per sync draft: each sync draft after the storage freeze still costs a new store and what no source restores. sync-draft-09 itself changed STORAGE.md and four owner statements.

### 5. The store

A writer killed between its link and its unlink leaves a second link to a whole body that the collector is ordered to leave alone, which also falsifies the erase guarantee (T1). Restoring one backup twice answers the same incarnation (T3). The backup, restore and self-check §7 and §8 specify have no tool, and `pimdir check` prints consistent without hashing a body (T4). The owner fence can wait for a migration, but removing a held lock file lets a second owner in today, and a sentence forbids it (F16).

### 6. Search

Coverage counts items without a body and nothing else, so an answer over encrypted, unparseable or unreadable bodies reads complete (S2). A re-expansion wipes the occurrences of an item whose body it cannot read (S3). The reference HTML reduction joins adjacent cells into one token, so an order number in an HTML-only receipt is not found (S1). The index records no revision of its extraction, so after search-v1 a fix never reaches indexed bodies, as happened on 2026-11-02 (V7). SEARCH is derived and rebuilt, so none of this gates storage-v1.

### 7. Performance

The schema needs nothing. Three statement texts do, and a text keeps its name, so they are patches: two statements about supersessions walk a whole collection on every engine load, 25 to 30 ms each time at 60,000 items for a table that is nearly always empty, about 10 s over a 100,000-message fill by extrapolation against 3.5 s of writes (P1); the delta's owing statement spends most of its time in temporary b-trees, 120 to 140 ms where two anti-joins take 24 to 25 (P2); a drain reads every binding of a collection per action to name one or two sources (P3). Before P2's rewrite, the scenarios it relies on must exist: nothing runs the keyword branches of `collect_before`, where a wrong comparison deletes an item holding an unpushed keyword.

### 8. Verbosity

The fair answer on the documents is: little. Each rule stated twice was compared, and one copy had drifted (X2); OVERVIEW.md agrees with the parts; the density of §9's table and §14's batch carries cases vectors pin. A reader owes 45% of STORAGE.md and a producer 65%; a reading path per profile serves them better than a split (X4). Cutting GUIDE.md's procedures to citations would remove what it is for.

The verbosity worth cutting is in the code around the standard. The three CLIs restate store rules three times, and the copies differ (C5). The Android app carries a second copy of the write (A6). neverest's driver is 13,810 lines of which 7,268 are tests and only 110 are a second drive loop (N2): its size is not the problem its line count suggests.

## Where no improvement was found

Stated so the next audit does not look again without new evidence: the blob rules of §5 and the name `CHECK`; the flag encoding and its base twin; the key grammar and FNV-1a 64 in both its uses; `level` beside `object_hash` (a claim beside a fact, by design); the version carriers (none removable); the `_by_link` twins and the per-kind statement families (no fold without losing a plan); the sync concept count (40 engine identifiers, 12 batch operations, two agreement points, two conflict records: nothing removable without losing a recorded guarantee); the two conflict policies (two axes); the query parser against §8.3 and operator injection in both index shapes; erasure through `optimize_text`; the per-connection pragmas of every profile; the drain's transaction boundaries; file modes; the dead-column question (every summary column is read by a canonical statement); the hash key over raw bytes; the Unicode 15.0.0 pin.

## Decisions asked (answered below)

Each is the owner's; the recommendation is the first option.

- **Q1, the queued flag change.** An optional `base` beside `flags` (absent keeps today's replace, a `base` met by an unknown set parks), or an `add` and `remove` form, which cannot express himalaya's `flag set` over a set never synced.
- **Q2, the queued remove.** Optional `if_match`, and parked when it meets a conflict its `resolves` does not name, as `update`; or left as it is, the CLIs dropping `--if-match` on delete.
- **Q3, the agreement's inputs.** The raw read of subject, date and sender a MUST where the source serves them, read only on a disagreement with a held row (no schema moves, connectors change); or §6 compares only values both sides derived by A.1, which changes the rule and its vectors.
- **Q4, identity across collections.** The agreement asked of linking, of the shared `seq` and of the held-elsewhere purge; or accepted as a known cost, written in §9.
- **Q5, the freeze order.** STORAGE and SYNC's state-bearing sections freeze together, since they do not move apart in practice (sync-draft-09 changed STORAGE.md and four owner statements); or the standard defines discarding one source's sync state in place, and must then say what an unpushed edit becomes when no engine of the old draft is left to push it.
- **Q6, statement names.** A name binds the text run under it and an effect may be reached by statements of an implementation's own, or the Android app takes the canonical names for its 14 writes. Cut `hit`, `component_of` and `match_objects_ranked` or give each a caller. Columns bind by position alone, or by name too (then 13 need one).
- **Q7, three unread indexes.** Keep `items_unread` and make `count_unread` use it, with a plan assert on the floor, or drop it; land readers for `items_by_seq_global` and `placement_flag_by_flag` or drop them.
- **Q8, names.** Rename `collect_before` and the handful of F7, or leave them and fix the prose.
- **Q9, the fence and the unconfirmed send.** The owner epoch after v1 as a migration, one sentence on lock files now; the unconfirmed state as a reserved `error` prefix, no schema.
- **Q10, a fifth kind.** The lock-out of older readers stated as a known cost, or an unknown-kind reading defined for every store-wide read.
- **Q11, owner files in the store directory.** A reserved name for owner state, or neverest's three files moved out.
- **Q12, search-v1.** Tagged after the index-schema items of the performance ledger, with S2, S4 and V7; nothing in it gates storage-v1.
- **Q13, batches in the queue.** Two MAY sentences now; a plural payload later as `v` 2.

## Decided

The user decided on 2026-11-12, taking the first option of each question:

- **Q1.** `set-flags` gains an optional `base` beside `flags`: with it the owner applies the current set plus what `flags` adds to `base` less what it removes; without it, today's replace; a `base` met by an unknown set parks.
- **Q2.** `remove` gains an optional `if_match` and an optional `resolves`, on `update`'s rules: parked when the item holds another body, parked when it meets a conflict `resolves` does not name.
- **Q3.** A connector MUST read subject, date and sender raw where its source serves them, at least when its decoded summary disagrees with a held row. An own create minted on a disagreement is reported. No schema moves.
- **Q4.** The agreement of §9 guards a hint across the collections of an account too: body linking, the shared `seq` and the held-elsewhere purge of a bodiless row each need a holder that agrees.
- **Q5.** storage-v1.0.0 and sync-v1.0.0 are tagged together. README's Status follows.
- **Q6.** A canonical name binds the text run under it, and an effect may be reached through statements of an implementation's own, bound by §7, the column rule and the vectors; a removal after v1 costs a minor. `component_of` is cut, `hit` becomes io-pimdir's placements read under that name, `match_objects_ranked` is cut unless the search planner runs it. Columns bind by position; the 13 unnamed ones are aliased all the same, and queries/signatures.json is generated in CI.
- **Q7.** `items_unread` stays and `count_unread` uses it, its plan asserted on the floor too. `placement_flag_by_flag` stays for the flag reads the performance ledger moves to the store, with a waiver until then. `items_by_seq_global` was to go; it stays, since io-pimdir, the Android app and the canonical `hit` read a `seq` without its collection (found 2026-11-12). A check fails an index named by no plan and no waiver.
- **Q8.** `collect_before` becomes `evict_before` and §11.3 "Evicting below a date". `mail_in_reply_to.msg_id` becomes `message_id`, `items_retained` becomes `items_deleted`. Proposed and still the user's to overrule: `:before` for every time ceiling, `:hash` for a body bound outside a column's name.
- **Q9.** The owner epoch waits for after v1, a migration raising neither floor; §8 says now that a lock file is never removed nor replaced while the store exists. An unconfirmed send is a reserved prefix of `queue.error`, no schema, which neverest and the Android app both write.
- **Q10.** A kind added later raises `read_version` and older readers and producers refuse the store: stated in OVERVIEW and §13 as a known cost.
- **Q11.** The store directory reserves one name for an owner's own state, and neverest's three files move under it. The name is to settle in the draft.
- **Q12.** search-v1.0.0 is tagged after the index-schema items of the performance ledger, with S2, S4 and V7. Nothing in it gates storage-v1.
- **Q13.** Two MAY sentences now (several actions in one enqueue transaction, a bounded run applied under savepoints); a plural payload later as `v` 2.

## Plan

One breaking batch, then proof, then tags. The standard's own rule applies: batch related rules into one entry, each with the check that fails without it.

### Phase 0: decide

Done on 2026-11-12 (Decided, above). V8 first: close the stale ledger lines and reopen the two ticked for Android, so the checklist read off the ledgers is true.

### Phase 1: the last breaking drafts

storage-draft-10 and sync-draft-10, one batch in pimdir, io-pimdir following in one commit that pimdir's CI pins.

- **Payloads:** F1, F2, with their payload and sync vectors; V6's three-state payloads.json.
- **Schema:** F3, F4, F5, F6, and what Q7, Q8 and Q11 decide (F7, F8, F9, F14).
- **Statements:** F10, F11, F12, F15; the text-only P1, P2, P3 with their scenarios and plan asserts, P2's missing scenarios before its rewrite; T3; S5.
- **Identity:** D1 and D3 as rules; D4 to D9 as fixtures and sentences, the checks following.
- **Text:** X1, X2, X4, F13, F16, F17, T1 with T2's sentence, T5, Y1's sentence, Y3's give-up, Y5 with its vector, S7.

### Phase 2: proof

- **The gate:** V1 (two rehearsal migrations, on the floor too), V2 (the released judgement implemented and tested on a synthetic version 2 store), V3 (digests of the frozen bytes, the signatures file, a freeze dry run on a scratch copy).
- **The second writer:** A2, the runner replaying vectors/sync through the Java owner, each failure triaged as an app bug or an underspecified rule; the second kind returns to phase 1.
- **The tools:** T4.

### Phase 3: the consumers follow

- **neverest:** D2, Y1, then Y2 (the two old rules on the current pin, then the port), Y4, F16's one form, N1.
- **The Android app:** A1, A3, A4, D4's manifest line, D1's raw reads.
- **The CLIs:** C1 (calendula's branch before anything else), C2, C3, F1's and F2's producers.
- **io-pimdir:** T1, T2, T5, Y6, S1, S3.

### Phase 4: tags

Every consumer pinned on one io-pimdir commit, that commit pinned by pimdir's CI, the live suites run once on the test accounts (the user's command), then the tags: storage-v1.0.0, and sync-v1.0.0 with it or after as Q5 decides. search-v1.0.0 later, per Q12. Before them, the note a draft user needs: sync until nothing is pending with the last draft binary, since the new one refuses the store.

### After v1

The migrations already decided (the purge log, the pending bit, the counters), the owner epoch, A6's core coroutine with A5's re-derivation pass, C5's hoists, and the lines marked any.

### Sizes

Where an analyst or a skeptic estimated one, none measured: V1 one to two days, V2 about a day, V3 about two days, Y2 one to two days, A2 about 500 Java lines and a scripted connector, then days of triage. Most of phase 1 is a line of schema or a sentence each, with its scenario or vector; its cost is the batch landing whole in pimdir, io-pimdir and the Android app's forks at once. Phase 3 is the long one: neverest and the app each carry four to six lines of real code.

## Not covered

No suite was run and no fsync was timed. SQLite 3.18 was exercised for the plans, the fork tests and the rebuild, not for every refusal of F4. No live server was asked how often its decoded fields differ from A.1 (D1): the pim-corpus change would answer it. conventions/gtd.md, the contents of most vector files, himalaya-tui, unfog, journal and the GTK app were not read. io-pimdir's own search performance is the open phase of performance-audit-2026-11-05 and was left to it.
