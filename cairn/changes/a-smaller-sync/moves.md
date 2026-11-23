# A smaller sync: the changes, one by one

Written on 2026-11-23 after a second reading, line by line, of the code each move of design.md §3 touches (io-pimdir 176e0b7, pimdir fb56c83, android c21fb53, neverest 99384ff). Nothing was built or run for it: every claim below is from reading, and each names its lines.

The second reading does not confirm the first plan. Of the eight moves it listed, three hold as written, two hold in a smaller form, and four change an outcome or the wire and so cannot be made under "behaviour frozen". The duplicated code is real, but most duplicates do not decide alike: merging them is a change of rule, not a refactoring. This file says, for each change, what exists, what would change, what must stay, how it is guarded, and where it stops.

## 0. Four levels of sameness

A change is classed by the strongest claim it can honestly make:

- **L0, same yields.** Every yield but `WantsLoad` has the same `Debug` text, in the same order, and every row is the same after each run. The Android store and neverest see nothing.
- **L1, same rows.** Pushes, events, requests and rows are the same; a write batch differs in ops or fields the write does not read. The Rust store is unaffected; the Android Java store, a second implementation of the write, must be re-run on the 200 vectors before it can be trusted with the new batches.
- **L2, wire addition.** A selection, a loaded field or a write op is added. The Android Java and JSON mirror follow, and SYNC §10 where it names the load.
- **L3, another outcome.** A rule changes. It needs the owner's ruling, a sentence in SYNC.md, a vector that fails without it, and both consumers.

The night lands L0 only. Everything else is measured on scratch copies and reported (§3), or listed with what it needs (§4, §5).

| First plan | Verdict | Level | Tonight |
| --- | --- | --- | --- |
| Move 1, dead arms and duplicates | holds, smaller (the `Resolved` map and the `Parked` arm stay) | L0 | T1 |
| Move 2, the status | does not hold: batches change | L1 | measured, K2 |
| Move 3, one policy settle | holds as one verdict function; the effects stay two | L0 | T2 |
| Move 4, one load a page | not expressible in the wire | L2 | listed, W2 |
| Move 4, round closed without the whole collection | no channel for the count, no answer for a one-page round, Android answers no `unstamped` | L2 and L3 | measured first, W1 |
| Move 5a, the no-op's fixed cost | holds for three of five items | L0 | T3 |
| Move 5b, skipping | holds as an allow-list with stated conditions | addition | T4 |
| Move 6, one landing | does not hold: the two landings follow different rules | L3 | measured, K1 |
| Move 7, rekey through the merge | does not hold: 14 of 22 cases differ | L3 | reproduced, K3 |
| Move 8, the drain | does not hold: one site cannot, one is no duplicate, one changes a key | L3 | reproduced, K4 |

## 1. What lands tonight (L0)

### T1. Dead arms and duplicates

About 35 lines, 30 minutes.

| Site | Today | After |
| --- | --- | --- |
| src/sync.rs:2888, src/upgrade.rs:874 | two `is_mutable(placement)`, the same body | one `pub(crate)` function in src/placement.rs (not a public method: the seam's public items stay as they are) |
| src/sync.rs:1463-1481, src/upgrade.rs:840-852 | sync's `store_body` splits a fetched body by hand, upgrade's `stored_body` does the same split | sync's `store_body` calls the one `stored_body`, then pushes its `StoreObject` as today |
| src/rekey.rs:445 | `old.object.is_some() && old_base.is_none_or(\|b\| b.object != old.object)` | `old.staged_edit().is_some()` (src/placement.rs:431, the same predicate, base-less included) |
| src/sync.rs:2009-2013, src/rekey.rs:264-268 | the same five assignments re-staging a body as a pending create | one pure `restaged(placement) -> PimdirPlacement` in src/placement.rs (`pub(crate)`); each caller keeps its own handle and drop rule, which differ (sync drops `Superseded` only when the handle moves, rekey hoists its drops) |

Left as they are, on purpose:

- **rekey's `Resolved` map** (src/rekey.rs:84, 648-658, 740). The first plan called it a copy of `self.items`. It is not: `items.dedup_by` keeps the first of a repeated handle (src/rekey.rs:172) while `resolved.insert` keeps the last (:650), so a listing repeating a handle carries the first item with the last one's link id, summary and sort key. Removing the map changes that outcome. It goes to K3 as finding R0 (SYNC §4 says the engine keeps the first).
- **`PageKind::Parked` in take_page's selection match** (src/sync.rs:835). It is assigned only at :993, after the load, so the arm is dead; but the match is exhaustive, and the only edit is a panicking arm in its place. Not an improvement.
- `LastPage.narrowed` and `enumerated` (bound to `false` and `None` at src/sync.rs:828), `PimdirArg::Write`, `PimdirOpen`: public, mirrored by the Android JSON.

Guard: the gate (design.md §7). No oracle weighting.

Stop: any difference the oracle reports. These four edits have no reason to produce one, so a difference means the reading was wrong and the edit is reverted alone.

### T2. One policy verdict

Net lines about zero, 45 minutes. The gain is one table in one place, the one SYNC §5 will print (design.md §5, table A).

Today the source's conflict policy is decided twice:

- src/sync.rs:2135-2152, `resolve_conflict`: `Manual` records; `PreferRemote` pulls; `PreferLocal` and `KeepLocal` record when the run may not push content, else keep the observed body when the member carried one, else record.
- src/upgrade.rs:492-526, `settle`: the same downgrade (`PreferLocal` and `KeepLocal` without content pushes read as `Manual`), then the same three arms, the body always read since the upgrade fetched it.

After: one pure function beside `PimdirConflictPolicy`, `pub(crate)`:

```rust
enum Verdict { Record, Keep, Adopt }

fn verdict(policy: PimdirConflictPolicy, pushes_content: bool, body_read: bool) -> Verdict
```

| Policy | `pushes_content` | `body_read` | Verdict |
| --- | --- | --- | --- |
| `Manual` | any | any | `Record` |
| `PreferRemote` | any | any | `Adopt` |
| `PreferLocal`, `KeepLocal` | false | any | `Record` |
| `PreferLocal`, `KeepLocal` | true | false | `Record` |
| `PreferLocal`, `KeepLocal` | true | true | `Keep` |

Both callers match on the verdict and keep their own effects, because the effects differ and each difference is an outcome:

| | sync (src/sync.rs) | upgrade (src/upgrade.rs) |
| --- | --- | --- |
| `Record` | `mark_conflict` :2206: upsert, `conflicts += 1`, `Conflicted` event; the diverging body is the carried one or none | upsert of the diverged placement :500, no event, no counter |
| `Keep` | `keep_observed` :2160: diverged upsert, `Overrule`, adopted upsert with status `Dirty` always, base flags `Unknown` when there is no base, `flush`, then the `Update` gated on the observed revision | diverged upsert, `Overrule`, final upsert with status computed (:530-536), base flags the placement's own when there is no base (:482-486), no push |
| `Adopt` | `pull_content` :2522: meta, body or none, base at the revision, `ContentChanged`, `refreshed += 1` | a clearing upsert first when the binding recorded a conflict (:516-522), then the fetched body as body and base |

What must stay, each a way to break L0 while "only moving code":

- In sync, `body_read` is asked without side effect (`self.metas.get(handle)` holding a body). Today `carried_body` (:2218) is called inside the `PreferLocal` arm and pushes a `StoreObject`; calling it early for every policy would add an op to a `Manual` batch before `mark_conflict` adds its own.
- `KeepLocal` on a remote-only change (src/sync.rs:2067-2072) and the tombstone holding an edit (:1804-1820) keep calling `resolve_conflict`; only its inside changes.
- A base-less conflicted binding reaches upgrade's `settle` (a create collision, src/sync.rs:2026-2028, fetched at src/upgrade.rs:276), so the two base-flag fallbacks are both live and stay apart.

One small helper rides along: the diverged placement (`status = Conflict`, `conflict_revision`, `conflict_object`) is built at src/sync.rs:2172-2175 and :2207-2210 and src/upgrade.rs:487-490; one `pub(crate)` constructor serves the three.

Guard: the gate, the oracle weighted to conflicts: each of the four policies, content pushes allowed and not, the member carrying its body and not, a remote-only change under `KeepLocal`, a tombstone holding an edit, a create collision fetched by an upgrade, a conflict's body fetched equal and not.

### T3. The no-op's fixed cost

60 minutes. Three edits in the store layer, each measured alone on the 517k store and kept only beyond noise.

| Edit | Site | Saves | Why it is L0 |
| --- | --- | --- | --- |
| `read_hub` asked for no link answers the empty hub at once | src/client/write.rs:1045-1112, called from `load` at :139 | 7 of the 21 statements a no-op folder runs (LOAD_CONFLICT, LOAD_KIND, CLEAR_PARAM, four by-link reads) | nothing is projected from no link; `conflicted`, `offered` and `folded` come from the hub in memory, empty either way; no later statement of the load reads the param slot before binding its own. `apply` is not touched: a batch holding a hub op always names links |
| BEGIN and COMMIT of a load through cached statements | src/client/write.rs:78-80 (`unchecked_transaction`, which goes through rusqlite's `execute_batch` and parses each time) | about 3% of the store's share | the same transaction; a guard rolls back on an early return, as rusqlite's `Transaction` does on drop |
| statements prepared from their text without the comment header | build.rs:165-168 bakes each file whole, so the cache hashes and compares the header at every use (src/client.rs:1664-1703) | up to 15% of the store's share | the public `sql::*` constants keep their value (the Android Java binds them by name); a second, private text is baked for preparing |

Dropped from the first plan, with the reason:

- **"Load 2 does not re-read what load 1 read."** What a load answers is public: neverest calls `store.load` itself (src/sync/driver/spine.rs:215, 548), and another handle of the same process can commit between two loads (the owner lock excludes processes, not handles: src/client/lock.rs:52-59).
- **"`collection_sources` once a run."** Its only effect is `beside_others` (src/sync.rs:2304); read once, it is stale when another handle binds the collection during the run. T4 removes its cost from the no-op anyway.

Expected: 87 ms to about 60 to 65 ms with every folder synced. That is above notmuch new (50 ms): the first plan's "about 50" counted the two items dropped. At or under notmuch is T4's.

Guard: the gate; the load battery of the oracle (design.md §4) compares what `store.load` answers for five selections after every run, since this move edits `load`; the three measures of design.md §7.

### T4. The collections a run may skip

90 minutes. One public addition, no type changed, nothing in the engine.

A store read on `PimdirSourceStore` (name settled when written; `settled_collections` here) answers the collections of this source where a run that lists nothing new derives nothing, each with its coverage. A collection is settled when all of these hold:

1. its `sources` row holds a checkpoint and a coverage (else the next run opens a round, src/sync.rs:597-613);
2. no round is open (`round_started_at IS NULL`);
3. no binding of the source owes (`owes = 1`, the partial index bindings_owing);
4. no binding of the source holds a refusal (a held refusal is reported every run, src/sync.rs:1654-1667; such a binding owes, so this arm is a second fence);
5. no item of the collection lacks this source (`lacks = 1` and no binding of the source, the partial index items_lacking);
6. no supersession names an item of the collection.

The read checks `sync_version` once, as every load does (src/client/write.rs:91), so a skip hides no refusal of the store.

A caller may skip a settled collection only when all of these hold too, which are its own to know:

- its source states nothing changed since the checkpoint the store holds (for pimbench: the folder's mtimes are those it recorded);
- the scope it would ask is the coverage's scope, not narrower (a narrower scope writes `SetCoverage` on an empty delta, src/sync.rs:1037-1045) and not wider (a round);
- `full` is off.

Anything else is run as today. The list is an allow-list on purpose: a condition missed makes a run that was not needed, never a skip that was.

Guard, in the oracle: after every generated scenario, for each source and each collection the read calls settled, a sync is run anyway with the coverage's scope, `full` off, and a remote answering an empty delta with the stored checkpoint. It must yield no push, no write, no event and a default report. The run counts how many states were settled, so the check cannot pass by being vacuous.

Measure: the read's plan on the 1M store (arms 3 to 5 scan partial indexes that are empty at rest; arms 1 and 2 scan `sources` for the source, one small row a collection). An index is added to storage-draft-17 only if the read is over 1 ms there. pimbench skips what is settled and unchanged; the no-op is measured both ways.

Expected: about 18 ms, 10 of them pimbench's own folder walk.

Written with it: the statement under io-pimdir spec/queries/storage/read, an ADDED requirement in io-pimdir cairn/spec/sync.md, a line under Added in CHANGELOG.md, a test in tests/ (settled after a clean sync; not settled after each of: a local flag edit, a staged create, a refusal, a second source's new item, an open round, a missing checkpoint). SYNC.md is not touched: the standard binds no statement.

### T5. SYNC.md

The lane beside T1 to T4; design.md §5 holds the method, the owner map and the tables. No rule moves, so no vector and no engine line depends on it.

## 2. The order and what each step proves

| Step | Proves | If it fails |
| --- | --- | --- |
| baseline | the suite, the measures and neverest's port at the base | the night goes on without the port (D4) |
| oracle built, old against old | the oracle is deterministic | fix the mask or the model before anything else |
| three planted bugs caught | the oracle can fail | no move is gated by it until it does |
| T1 | the reading of the small duplicates | revert the one edit |
| T2 | the policy table is one table | revert T2; T3 and T4 do not depend on it |
| T3 | the three store edits change no answer | each edit kept or dropped alone |
| T4 | a settled collection derives nothing | the read lands without pimbench's skip, or not at all |
| K1 to K4 | what each rule change would cost and move | reported as not measured |

T1 to T4 are independent: none needs another to land.

## 3. Measured tonight, never landed

Each candidate is built in a copy of the tree under .pimdir-night/candidates, run through the oracle in report mode (the relaxed comparison of design.md §4: per run, the concatenated write ops, pushes, fetches, enumerates, the report and the rows), and reported with its lines saved and the classes of scenario it changes, one shrunk example each. 40 minutes each, in this order, until 04:00. Nothing of it reaches the tree.

### K1. One landing (first plan's move 6)

The two landings follow different rules today:

| | sync, a page or a head (src/sync.rs:1317-1460) | upgrade, a fetch (src/upgrade.rs:550-658) |
| --- | --- | --- |
| Which create a hint lands | key is the hint or the one minted over its provisional handle (`landed_hint`), bare key first | key equals the hint exactly |
| Delivered creates | landed | not landed: `status == Created && base.is_none()` only |
| Another message under the hint | minted apart (`same_message`), `Disagreed` reported | not tested |
| Offered copies | joined, flags united | not seen |
| Base flags | the listed flags | the flags of the row being named |
| A diverging body | base names no revision and no body, the content axis decides | base keeps the fetched revision, then `settle` by the policy |
| A tombstoned delivered create | lands as a tombstone | not reachable |
| Drop of the provisional handle | pushed by the merge loop, before the upsert (:1648) | pushed by `land` itself (:587) |

What is shareable at L0 is the tail both run alike (handle moved, summary and sort key filled when unset, level from the body, status from base against flags and body): about 25 lines, not worth a move of its own.

K1 builds upgrade's landing on sync's predicate and reports what moves. The question for the owner: should a fetch land a delivered create, a create under a minted key, and refuse another message, as a page does? SYNC §6 states the page's rule; the upgrade path is reachable only when a mutable resource restates its hint at a fetch, or a row was named by no listing.

### K2. The status derived (first plan's move 2)

The first plan said the write keeps only `Tombstone` and a conflict's revision. Corrected: the write reads `Tombstone` (src/hub.rs:736, PimdirStorage.java:1684) and `status != Conflict` (src/hub.rs:186, PimdirStorage.java:1751). `Clean`, `Dirty` and `Created` are read by no write.

They are read by the engine itself during a run, on placements it has already rewritten. `pull_content` leaves the status as it was (src/sync.rs:2520), so a `Dirty` placement pulled under `PreferRemote` reaches `reconcile_flags` still `Dirty`; `settled` is then true (:2250) and a second upsert is pushed by `rebase`. A derived status would read `Clean` there and push one upsert. The rows are the same, the batch is not: L1.

K2 derives the status at the one place a placement is built for the write and reports how many batches differ, and whether any row does. If none does, it is an L1 change waiting on one thing: the Android store re-run on the 200 vectors with the new batches.

### K3. Rekey's own rules (first plan's move 7)

`carry` (src/rekey.rs:429-553) is not sync's merge with small differences: of 22 cases read side by side, 8 write the same placement. Replacing it by sync's axes needs a dozen switches for about 155 lines removed. It is not proposed.

What the reading found instead is a list of behaviours only a rekey has, with no vector and no test, some of which read as defects. K3 writes one test for each on a scratch copy, so the morning holds "reproduced" or "not reproduced", not a reading:

| | Case | A rekey today | A page today |
| --- | --- | --- | --- |
| R0 | a listing repeats a handle | first item, last item's link id, summary and sort key (:172, :650) | first kept (SYNC §4) |
| R1 | a binding conflict, the member listed with no revision | `conflict_revision` cleared, the diverging body dropped, the op still says `Conflict` (:500-506) | untouched |
| R2 | a tombstone, revision unchanged | flags merged into it, its divergence reset (:473-474, :522-524) | nothing written |
| R3 | a tombstone holding a staged edit, the remote edited | revived, the staged body dropped from the placement (:512 matches before :525) | the both-changed case, by the policy |
| R4 | a carried row, the listed flags unknown | the base takes the unknown set (:476) | a base keeps its flags while a push is owed |
| R5 | a delivered create matched | flags united, no `same_message` test, dropped `Rekeyed`, no event (:487-492) | landed by `land`, `Created` |
| R6 | a pending create or an offered copy whose hint a member states | left; the member minted apart (:405-415) | landed or joined |
| R7 | a base-less conflict | given a base when matched, re-staged when not (:250-253) | left untouched |
| R8 | a listing carrying bodies | ignored: no `StoreObject`, level `Meta` | stored, level `Full` |

R3 is the one to read first: whether the write keeps the dropped body as a retained item (SYNC §9) decides between a rule and a silent loss, and the test says which. neverest runs a rekey on `Renumbered` (src/sync/driver/reconcile.rs:69-83) and its remote can carry bodies (src/sync/remote.rs:1080), so R8 may be reachable in the field.

Each row reproduced becomes a line for the owner: keep (then SYNC §8 states it and a vector pins it) or change (then a vector that fails today).

### K4. The drain against `mutate` (first plan's move 8)

Of the three sites, one cannot use mutate's Add (a queued add may hold no body, `PimdirMutation::Add` requires one; its duplicate check is store-wide where mutate's sees one source), one is no duplicate (src/client/producer.rs:2052-2075 chooses which source's conflicted binding a mutation runs through, which mutate cannot), and one changes a key.

That last one is a disagreement between two paths of the same crate. The drain hands mutate the hub's projection of the target (src/client/producer.rs:2203-2214), which includes the copy the store offers a source for an item it lacks; `store.mutate` hands it `load(Links)`, which drops that copy (src/client/write.rs:158-166). A Copy or Move into a collection where another source already holds the identity therefore mints a second copy through the queue and joins the item through `store.mutate`. No test covers the case. K4 writes it both ways and reports which key each takes.

Also corrected: vectors 141 to 146 and 176 to 179, which the first plan named as the drain's guard, are `"verb": "mutate"` and run through `store.mutate` (tests/vectors_sync.rs:1020-1028). They do not guard producer.rs.

## 4. Wire changes, listed with what each needs

### W1. A round closed without the whole collection (L2 and L3)

Why it does not fit the wire, each read in the code:

- **No channel for the count.** `bound` (src/sync.rs:979-983) is an outcome when the round parks (`report.parked`). No field of `PimdirLoaded` can carry a count.
- **A one-page round has no answer.** The round opens in the page's own write (`OpenRound` at :917, after the load), so at load time `unstamped` is empty and LIST_UNSTAMPED_BINDINGS requires an open round. Answering it means writing `OpenRound` and `Stamp` before the load: one write batch becomes two, with a crash point between.
- **Android answers no `unstamped` to `Owing`** (PimdirStorage.java:188-190): an engine asking `Owing` at a last page would infer no absence there, silently.
- **Four more uses of the whole set**: delivered creates at rest are reported `Delivered` by a last page and are not owing (vector 139, src/sync.rs:1757-1766); an absent clean binding needs its placement to be dropped; `claimed` (:1151) sees every link id, where `Owing` plus `Links` misses a key minted twice and a restated mutable member; `stamped` (:1131) needs the same count.

What it would take: a selection (or a loaded count) added to the wire, SYNC §10's sentence changed (SYNC.md:623), the Java `loadCollection` following, and one-page rounds kept on today's load.

Whether it is worth that is unmeasured. A round lists every member of its scope, so the listing is O(collection) before the load is; only a band round or a narrowed one lists less than it loads. The baseline measures a round's close over a 30k-message folder against the listing that precedes it (tasks.md step 1). If the load is a small part of the round, W1 is dropped, not deferred.

### W2. One load a page (L2)

A page before the last and a head load twice, `Handles` then `Links` (src/sync.rs:861, :2731). The wire's selection is one tagged variant, so "both at once" needs a new one. Folding the hints into `Handles` is not the same load: `Links` drops the copies the store offers (src/client/write.rs:158-166), `Handles` does not, and an offered copy in `local` changes where a join happens. Two read transactions a page beside a network round trip: not proposed.

### W3. The status (L1)

K2 above. Lands when its report shows no row moved and the Android store has re-run the vectors.

## 5. Rule changes, for the owner

One line each; K1, K3 and K4 bring the evidence.

- **C1, one landing rule** for a page and a fetch (K1).
- **C2, rekey's own rules** R0 to R8, each kept and pinned or changed (K3).
- **C3, the drain and `store.mutate` agree** on a Copy or Move beside another source's item (K4).
- **C4, `item_lacks` and `hash:` items**: a multi-source collection holding one never reads as settled (T4's arm 5), and every delta loads it to project nothing. A view change that moves a storage mark and vector rows.
- **C5, supersessions pruned** once the add is accepted, or indexed by collection.
- **C6, features with few users**, kept: band heads and band rounds, narrowed rounds with `enumerated`, capped listings, `supersedes`, `Abandon`. A cut names the consumer it breaks.
- **C7, the dead wire**: `LastPage.narrowed` and `enumerated`, `PimdirArg::Write`, `PimdirOpen`.

The Android store served by io-pimdir (design.md §8) turns W1, W2, W3 and C7 into internal changes. It is the one change that makes the next ones cheap.

## 6. What this does to the targets

| | First plan | After the second reading |
| --- | --- | --- |
| Engine code | 12,500 to at most 10,500 lines | 12,500 to about 12,450 tonight. The 2,000 lines are behind C1, C2, C3 and W3, which are rulings |
| Places deciding a conflict policy | 3 to 1 | one verdict; two sets of effects, on purpose |
| Places landing a pending create | 2 to 1 | 2, with the table of how they differ and what merging them moves |
| Collection loaded whole | a rekey only | unchanged; measured, then W1 or nothing |
| No-op, every folder synced | at or under notmuch new | about 60 to 65 ms (notmuch new 50) |
| No-op, settled folders skipped | about 18 ms | about 18 ms |
| SYNC.md | at most 12,000 words | at most 14,000, every requirement kept (design.md §5) |
| New | | the oracle, kept; nine rekey behaviours and one drain disagreement reproduced or refuted; each rule change with what it moves |
