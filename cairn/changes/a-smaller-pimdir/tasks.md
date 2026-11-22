---
cairn: tasks
change: a-smaller-pimdir
---

# Tasks

The night of 2026-11-22 to 2026-11-23. P is ~/code/pimalaya/pimdir, I is ~/code/pimalaya/io-pimdir, N is ~/code/pimalaya/.pimdir-night (plain directories on disk, not the tmpfs). Budgets are wall time; a move over one and a half times its budget is rolled back from its checkpoint and listed. journal.md here is appended at every checkpoint.

Commands: io-pimdir through its own shell, `nix develop --command cargo test --all-features` from I, its in-tree target/; pimdir through `nix flake check path:$PWD` from P; python through `nix-shell -p python3`; never perl.

"The gate" is design.md §7, items 1 to 5. "The quick gate" is `cargo test --all-features --test vectors_sync --test engine` and the tests the move touched, run while a move is in progress.

## 0. Before the night (owner present)

- [ ] D1 to D10 of proposal.md confirmed
- [ ] The other session (pimalaya-c1) told that P and I are worked in place until the report
- [ ] journal.md opened: the commits read (P b5b9382, I 00727ba, himalaya a2726f56, neverest 99384ff, cardamum 22c0bd5, calendula 794550c, android c21fb53), the hour
- [ ] First commit in P (this change folder and what-must-hold-and-what-is-used), so a signing prompt shows now
- [ ] Checkpoint 0: P and I copied to N/checkpoints/00-baseline (no target/, no .git)

## 1. The baseline (45 min)

- [ ] I: the full suite once, its result and wall time in N/baseline/io-pimdir.txt; every failing or ignored test listed (a test red here is not a regression)
- [ ] I: clippy, fmt, the no_std build, their result kept
- [ ] P: `nix flake check path:$PWD`, its result kept
- [ ] tools/sizes.sh here: words per document, tables, triggers, indexes and views of a fresh store, statement files, lines under src/ and tests/, public items, tests; run, N/baseline/sizes.txt
- [ ] The authorizer script and its tables copied from the scratchpad to tools/ here (touches.py, touches.tsv, columns.tsv, tables.tsv, triggers.tsv)
- [ ] The bench baseline: the figures of round 4 (I cairn/changes/as-fast-as-notmuch/round-4.md) copied, and one fresh run of the 17 queries with the round-4 binary on .bench-notmuch/runs/x2d on an idle core; the store's file sizes and a dbstat per table and index (bytes held by `collection` text counted apart)
- [ ] The Android reading turned into android.md here: the 130 statements bound and the tables and columns its own statements name (from the report of 2026-11-22), the "became" column empty

## 2. The contract moves (75 min)

No behaviour changes in this step: files move, names stay.

- [ ] I: sql/storage/{read,queue,owner}/ and sql/search/ receive P's queries/; sql/migrations/search/ receives the index schema; build.rs reads them there; `io_pimdir::sql` unchanged for a caller
- [ ] I: the signature listing and its script follow (sql/signatures.json, sql/signatures.py); the generator moves to I/generator (out of spec/), reading I/sql
- [ ] I: spec/ keeps migrations/storage, vectors, payloads; tests/spec_drift.rs compares those three byte for byte and the statements against I/sql alone
- [ ] P: queries/, migrations/search/, generator/, checks/names.sh, checks/signatures.py, checks/waivers.txt, checks/references.pl removed; flake.nix, checks/schema.sh, checks/floor.sh, checks/implementation.sh, checks/vectors.py follow
- [ ] P: checks/invariants.sh, a sub-agent in parallel: invariants.tsv here, one line per scenario with the io-pimdir test or generated property holding its rule, or `none`; the script is removed from the flake's checks now and deleted in step 6, once every `none` is a test in I or a line of the report
- [ ] P: vectors/search/refresh.json loses `objects` and `split`; manifest restated; I's runner follows
- [ ] P: AGENTS.md §4 and "Everything else", README.md: what a change must land with, restated for what is left
- [ ] The gate; clippy; checkpoint 1; commits (P then I, spec/REVISION naming P's)

## 3. Storage: flags as columns (75 min)

design.md §3.1.

- [ ] P: 0001_init.sql: `items.keywords`, `bindings.base_keywords`, their checks; `placement_flag`, `binding_base_flag`, their 12 triggers and `placement_flag_by_flag` out; `binding_owes` on the two columns; `items_stamp_update` and `items_owes_update`, `bindings_owes_update` watch the new columns; format `storage-draft-17`
- [ ] I: sql/: `insert_item`, `update_item`, `insert_binding`, `update_binding` carry the sets; the four flag statements out; every read naming a flag table (32 by the authorizer) reads the column
- [ ] I: src/client/write.rs `write_flags` and the hub's read; reader, producer; `sql::FORMAT_VERSION`
- [ ] I: the search half: src/client/search/compile.rs, src/sql/search.rs, `load_changed_items`
- [ ] Sub-agents in parallel once the schema is fixed: the generator's writer; tests/vectors_sync.rs seed and `actual_rows`; the schema-bound tests naming a flag table (owing_load, roundtrip, flag_rows)
- [ ] A property test: a set written in any order reads back sorted and equal, and a restated set stamps nothing
- [ ] The gate; checkpoint 2; commits

## 4. Storage: one summary, one list table (180 min)

design.md §3.2 and §3.3. The longest move; its quick gate runs after each sub-step.

- [ ] P: 0001_init.sql: `summary` and `summary_value` with every check the nine tables carry; the nine tables and their indexes out; the three partial indexes and `summary_value_by_value` in
- [ ] I: sql/: `get_summary`, `upsert_summary`, `load_summaries`, `load_summaries_by_link`; `load_values`, `load_values_by_link`, `load_values_by_collection`, `replace_values`, `insert_value`; the kind pages and the four `search_*` on the one table; the ten `link_*` rules; `lookup_objects`, `held_mail_summary`, `list_attachments*`, `describe_endpoint`, `list_replied`, `list_address_placements`, `list_domain_placements`; the mail pages and counts
- [ ] I: `PimdirSummaryTable` and `write_summary` in src/client/write.rs; `read_hub`; reader; attachments; producer. The public summary types (`PimdirMailSummary` and the five others) do not change
- [ ] I: the search half: compile.rs (kind, status, mid, priority, category, `has:attachment`, addresses), src/sql/search.rs, `hit`, `items_to_reexpand`, the refresh's summary reads (src/client/search/summary.rs)
- [ ] P: vectors/summaries.json restated if a field's name is stated there; manifest
- [ ] Sub-agents in parallel once the schema is fixed: the generator's writer and oracle columns; tests/vectors_sync.rs; the schema-bound tests (attachments, rederivation, scoped_sync, store_text, search_plan, search_scale, generated/replay)
- [ ] Each of the 23 direct readers of `mail_summary` and the 10 of `item_address` (tools/touches.tsv) accounted for in the journal
- [ ] The plans of the mail page, the unread page and the address lookup read with `EXPLAIN QUERY PLAN`: the same index, no scan
- [ ] The gate; clippy, fmt, no_std; checkpoint 3; commits

## 5. Storage: the guards (30 min)

design.md §3.4.

- [ ] `store_meta_identity` out; `collections_keep_queued` out, `queue.collection` `ON DELETE RESTRICT`, `delete_collection` checking first and keeping its error code
- [ ] The 4 statements nothing references out (`deliver_binding`, `link_senders_of_by_link`, `list_garbage_objects`, `set_store_version`)
- [ ] The gate; checkpoint 4; commits

No storage move starts after 03:00. If step 4 is not checkpointed by then, step 5 is skipped and listed.

## 6. Search: what nothing reads (45 min)

design.md §5. No move starts after 04:00; the refactor ends at 04:30 whatever is left.

- [ ] I: `chunk` and `thread` out of the index schema with their statements; `missing` a column of `placement`; the seven dead statements out; `search-draft-17`
- [ ] I: refresh and compile follow; index.hits and `pimdir_fields` untouched
- [ ] The answers of vectors/search/queries.json unchanged; refresh equal to rebuild under the generated tests
- [ ] invariants.tsv: every `none` ported as a test in I, or listed; P/checks/invariants.sh deleted
- [ ] The gate; checkpoint 5; commits

## 7. The documents (a lane beside steps 3 to 6, read at 05:00)

One sub-agent per document, from design.md and the schema as each checkpoint leaves it; the lead reads every diff before it lands.

- [ ] rules.tsv here: each of STORAGE.md's 212 requirement sentences and SEARCH.md's 50, marked kept, moved or dropped (design.md §6)
- [ ] STORAGE.md rewritten to the schema of checkpoint 4 or the last one reached: at most 18,000 words, storage-draft-17 on its Status line
- [ ] SEARCH.md: §2 to §4 out, §5 to §10 kept, its references to statements out: at most 8,000 words, search-draft-17
- [ ] SYNC.md: each reference to a statement or to a retired section restated as the rows it names; no rule moves; its Status requires storage-draft-17
- [ ] OVERVIEW.md, README.md, AGENTS.md, conventions/gtd.md follow; GUIDE.md retired
- [ ] I: cairn/spec/store.md, search.md, spec-fidelity.md folded; CHANGELOG.md under Unreleased; no version bump
- [ ] P: cairn/log/2026-11-23-a-smaller-pimdir.md, one entry naming each rule touched and the check guarding it; I: its own log entry
- [ ] Every `dropped` line of rules.tsv carries a reason a reader can judge without the old text

## 8. The consumers (beside step 9, a sub-agent, no port)

- [ ] consumers.md here: for neverest, himalaya, cardamum and calendula, every table, column, statement name, public item and format string each names (sources and tests) that the night moved, with its file and line and what it became; none is built
- [ ] android.md: the "became" column filled for every statement, table and column

## 9. The measures after the refactor (04:30 to 05:15, no build running)

- [ ] The 1M store rebuilt in the new format from .bench-notmuch/corpus/x2 (`pimbench sync`, then `index`), wall, CPU and bytes written kept; the 517k tier as well, the performance pass prototyping on it
- [ ] The 17 queries, count, page and threads, new binary and new store against the round-4 binary and store and notmuch (`vs.sh`, `ab.sh`), one run on an idle core; answers compared (`cmp.sh`)
- [ ] A run with nothing to do, and a delta of one message with its index refresh (the rewrite of index.hits timed apart)
- [ ] Sizes: pimdir.db and index.db, dbstat per table and index, against the baseline
- [ ] tools/sizes.sh again; the table of proposal.md filled with what was reached

## 9b. The performance pass (05:15 to 08:30)

- [ ] perf/README.md here: the table of 9, each measure where pimdir is not ahead of both round 4 and notmuch, and the import, no-op and index-build figures
- [ ] Independent agents, one per lead (the measures they own named), each on its own scratch copy of I under N/perf/<lead>, pinned to its own idle core, builds off-tree one at a time per agent; each prototypes on the 517k store and returns a patch, its measure before and after, and the answers compared
- [ ] Each patch re-measured by the lead head to head (old binary, new binary, notmuch in one hyperfine run on the reference core); kept only when better beyond noise and every answer is identical; applied to I, the gate run, committed
- [ ] A change of the index format confirmed with one 1M index rebuild; a change of the store format only if its gain pays a re-import before 08:00
- [ ] The final table at 1M: every measure, round 4, notmuch, the night; ties within noise said as ties

## 10. The report (08:30 to 09:00)

- [ ] report.md here, one page: the table before and after; each move with its checkpoint, or why it was rolled back or skipped; every test deleted and why; the decisions of decisions.md in one line each; consumers.md and android.md in one line each; the bench table; what was not verified (live servers, a phone, the ignored suites); the doubts left for the owner
- [ ] P/checks/io-pimdir.rev names I's last commit; both trees' status clean but for what the report names
- [ ] The last checkpoint and commits; nothing pushed
- [ ] A memory note pointing at report.md

## Stretch, only if step 6 is checkpointed before 02:30

- [ ] `supersessions` as `items.supersedes`; `performers` into `capabilities`
- [ ] Statement twins folded where the plan stays the same: the `_by_link` loads, the six `set_collection_*`
- [ ] Public items no consumer and no test names, listed (not removed) for the owner

## If the night is cut short

The last line of journal.md names the last checkpoint and the step in progress. Whoever resumes restores both trees from that checkpoint's copy under N if the step in progress left them red, never through git, and goes on from the step named.
