---
cairn: log
change: system-flags-from-the-store
landed: 2026-11-21
---

# System flags from the store

search-draft-16 and storage-draft-15, neither tagged, so both are edited in place and no number moves. The owner's decision of 2026-11-21, recorded in io-pimdir's cairn/changes/as-fast-as-notmuch/proposal.md ("Decided"), on finding F6 of cairn/changes/performance-audit-2026-11-05: `is:unread`, `is:read`, `is:flagged`, `is:answered` and `is:draft` are answered from the store's `items.marks` as it stands, keywords still from the index. Expected at 517k Enron messages: the unread count from about 583 ms to about 45 ms (notmuch 14). This lands the spec side; io-pimdir follows.

## Rules and the check guarding each

- **A system flag term reads the store** (SEARCH §1, §8's `tag:` `flag:` and `is:` rows, §10): `is:` and a `tag:` or `flag:` naming `\Seen`, `\Answered`, `\Flagged`, `\Draft` or `\Deleted` (exact bytes) read `items.marks`, never the index; any other flag, a keyword, reads the index's `flag` table (`flagged`). Two new query client statements, `unread` (no parameter, answers `collection`, `seq`: the live rows whose `marks & 1 = 0`, on `items_unread` named by `INDEXED BY`) and `marked(mark)` (answers `collection`, `seq`: the live rows holding the bit, on `items_by_sort`, which covers `marks`). Guard: checks/invariants.sh "flags: unread answers the live rows lacking \Seen, an unknown set among them, from the store with no flag row in the index", "flags: marked answers the live rows holding a bit, for each of the five", and "flags: a flag changed and a row deleted since the last refresh answer as the store holds them" (the store written by `update_item`, no refresh between); vectors/search/refresh.json, case "a system flag is read from the store as it stands"; checks/vectors.py, which now re-derives every queries.json and refresh.json query made of system flag terms beside `kind:mail`, `kind:contact`, `kind:file` or `collection:` from the store's flags (7 queries.json cases, 9 refresh queries).
- **Their seeks** (SEARCH §8, STORAGE §4.3's index list): `unread` walks `items_unread` and `marked` `items_by_sort` alone, never the whole table. Guard: invariants "flags: unread walks items_unread, marked items_by_sort alone, neither the whole table".
- **Per hit** (SEARCH §8.2, Tags): `is:read` matches when any placement holds `\Seen`, `is:unread` when none does, as `tag:x` and `not tag:x` already read; a hit of which `unread` answers one placement is left out when another holds the bit. This states what io-pimdir already compiles (`is:unread` as `not` `\Seen`). Guard: refresh.json's new case, step 1 (a message filed twice, read in one collection: no hit of `is:unread`), and vectors.py's per-hit re-derivation.
- **Freshness** (SEARCH §4's lag paragraph, §8.2's new bullet "Flags are as fresh as the store"): a system flag term answers the store as it stands while a text term, a keyword and every other index term answer the store as the index last folded it, so with a lag the flag terms are fresher; completeness still needs a zero lag, whatever the terms read. Guard: refresh.json v 4's `lagging` step (SEARCH §11, vectors/README.md, vectors/schema/search-refresh.schema.json), whose queries are answered before the refresh, the index one write behind, each holding only terms the store answers; vectors.py requires at least two lagging queries answering otherwise than the index's flags one write behind would (six do), and every lagging query to be one it re-derives from the store.
- **The index holds no system flag** (SEARCH §3, §4, migrations/search/0001_init.sql): the `flag` table holds keywords alone, by a `CHECK (flag NOT IN ('\Seen', '\Answered', '\Flagged', '\Draft', '\Deleted'))`, and the indexer writes the flags `load_changed_items` answers but those five (`replace_flags`, `insert_flag`); `load_changed_items` keeps its columns. Guard: invariants "flag: the index refuses a system flag, each of the five, by its exact bytes"; the two `flagged` and `replace_flags` scenarios now use keywords (`todo`, and `\seen`, a keyword by its case).

Signatures: two added, `search/unread` and `search/marked`, queries/signatures.json restated; no existing statement's parameters or columns moved. checks/names.sh passes (SEARCH §3's table names both). vectors/manifest.json restated for refresh.json, its schema and vectors/README.md. checks/waivers.txt: `placement_flag_by_flag`'s reason restated (below). GUIDE §15 (refresh step 5, query step 3) and OVERVIEW §10 follow.

## Proof that each check fails without its rule

Each rule was disabled in a scratch copy of the tree under /tmp/claude-1000/, never through git, and the check run there:

- `unread` and `marked` reading the index's `flag` table (the old reading): the three answer expectations and the plan expectation fail (4 broken);
- `unread` spelled `NOT (marks & 1)` with no `INDEXED BY`: the plan expectation answers `0110`, the walk on `items_by_sort`;
- the index's `flag` table without its CHECK: "the index refuses a system flag" answers `00000|Work|2`;
- refresh.json's lagging `is:read` stating the index's answer, `[home, 2]`: vectors.py fails on the store's re-derivation;
- refresh.json with no `lagging` step: vectors.py fails "a lagging step answers a system flag term otherwise than the index's flags, one write behind, would".

## Chosen here, for the owner

- **The `flag` table stays, keywords only, and the indexer stops writing system flags into it**, enforced by a CHECK rather than a statement filtering them silently. A refresh still restamps on a mark read and rewrites the keywords of that placement; dropping that rewrite, and the summary text rewrite of F6, are not decided and stay open on the performance-audit ledger.
- **`tag:\Seen` and the other four** read the store too, as the decision's "keywords (`tag:`, `flag:` on a non-system flag)" implies; `tag:\Deleted` reads bit 16, though `is:` names no value for it.
- **Completeness is unchanged**: an answer whose terms all read the store is still complete only at zero lag, the conservative reading, though its hits are exact.
- **No new store index**: `is:flagged`, `is:answered` and `is:draft` as a driving set walk `items_by_sort`'s live entries (a covering scan, not a seek); a probe on a row the store walk already holds tests its `marks`. A partial `items_flagged` would make `is:flagged` a seek at a write cost; not taken.
- **`unread` and `marked` answer placements, not hits**, as `flagged`, `attached` and the other set statements do, the client applying the per-hit rule.
- **`placement_flag_by_flag` stays waived**: no statement reads it now that keywords stay on the index; whether to drop it from the store schema is the owner's call.
- **refresh.json moved to `v` 4** for `lagging`, a key a runner must act on.

## What io-pimdir must change

- `src/client/search/compile.rs`, `PimdirQueryPredicate::Flag`: for a system flag, read `store.items.marks` (the set as `unread` or `marked` answers it, the estimate on the same, the probe as `{j}.marks & bit`) instead of `flag`; `is:unread` driven by `unread` rather than the complement of `\Seen`'s rows. `src/search/plan.rs`'s `PimdirPlanEstimate::Flag` follows.
- The refresh (`src/search/refresh.rs`, `ReplaceFlags`): write only the flags but the five system flags into `flag`; the canonical schema now refuses them, so the current refresh fails on the first `\Seen`.
- The vector runner: read refresh.json `v` 4 and answer a `lagging` step's queries before its refresh.
- Bump checks/io-pimdir.rev here to the commit that does.
