---
cairn: log
change: checks-run-every-statement-and-pin-every-vector
date: 2026-10-31
---

# The checks run every statement and pin every vector

Batch 8 of the release audit (cairn/changes/audit-2026-10-31, lines C1 to C11), with what batches 1 to 7 left for the checks: vector fields added without a `v` bump, scenarios enqueuing payloads the payload schemas refuse, `match_objects` and `match_summaries` run by no scenario, comment lines over 80 columns. storage-draft-08, sync-draft-07 and search-draft-08 stay as batch 1 set them; the sync vector format and queries.json move to `v` 2.

Every check below fails on the seeded fault named on its line and passes on the finished tree; the mutation set at the end seeds the rest, each mutant a copy of the tree with one change, run through the copy's own checks.

## Checks

- **Every statement runs** (C1). checks/invariants.sh records each statement a scenario runs (`run`, `fails`, `isearch`, the flag statements a row write appends, `create_param`; a plan runs none) and, after the last scenario, fails on a statement under queries/ that no scenario ran and checks/waivers.txt does not list as `part/profile/name: reason`, on a waiver naming no statement, and on one naming a statement a scenario runs. On the tree before, 80 of 254 statements ran in no scenario (the reviewer counted 91 of 239 at 9606b43); now all 254 run and the waiver list is empty. 51 scenarios were added: `lookup_objects` over two accounts, a single-account store, an `alt:`, a `hash:`, a `dup:` and a bodiless row; `held_mail_summary` (account, derived key, the row stating its mark first); `link_for_handle` and `handle_for_link`; `delete_binding`; `retained_item` and `revive_item` (the seq and body kept, `retained_by` cleared, the other retained row and collection untouched); the refcount floor; the eight keyset pagers walked by pages of two over tied sort keys with a tombstone among them, and `list_items_page`; the loads by collection and by link of items, bindings and the six summary kinds; the five `get_*` and `component_of`, the three calendar summary deletes; `replace_addresses`, `replace_in_reply_to`, `replace_categories`; a collection's account, kind, generation and policy (`set_conflict` refusing `prefer-remote`), `bump_next_seq`; `bump_attempts`, the parked and pending queue reads; the placements by key, body and domain, the conflicted bindings and items per account, `list_sources`, `object_exists`; `bind_param` and `clear_param`; in the index `hit` over a tombstone, `match_objects` and `match_summaries` (a field filter, two placements of one body, a deleted summary text), `object_indexed`, `objects_gone`, `thread_of`, `thread_members` per account, the flags, `replace_occurrences` and `linked` in both directions. The agenda scenario gained a zero-length occurrence at the range's start, one ending there and a later one of the lower seq, and a plan on `occurrence_by_start`; the purge cutoff now equals a row's retirement instant. Seeds: a statement file added (`stray.sql`), and Q01 to Q14 and N03 to N10 below.
- **Constraints with no scenario** (C2). "handle: a source binds a handle once in a collection, bindings_by_handle refusing a second item under it…" (a third item, so the primary key cannot shadow the index) and "refcount: a release past the pins taken is refused by the statement making it…" (a second release, a pin named twice in one release, an `adjust_refcount` of -2). checks/names.sh compares the tokenizer SEARCH.md §5 states (`unicode61 remove_diacritics 0`, `prefix = '2 3'`) with every `tokenize` and `prefix` of migrations/search/ and every `:tokenizer` the scenarios record in `index_meta`; batch 6 had already moved the harness to `remove_diacritics 0`. The comparison sits in names.sh, the check whose fileset holds SEARCH.md, rather than schema.sh. Seeds: M03, M05, M09, N12.
- **Summaries re-derived** (C3). checks/vectors.py now reads a card's lines by hand for `uid`, `fn`, `kind`, `org`, its `EMAIL` rows and its sort key (A.2); a calendar resource's master for every event, task and journal column (A.3 to A.5: times verbatim with `TZID` and `VALUE`, `recurring` from `RRULE` or `RDATE`, `until`, `status` uppercased, `percent`), its `ORGANIZER` and `ATTENDEE` rows with `mailto:` stripped and `CN` as the name, beside the task columns and `CONTACT` rows it read already; and a message's `From`, `To`, `Cc` and `Bcc` rows by the batch 4 parser. Every column, address row and key of summaries.json is now re-derived. No case held a journal, a card's `KIND` or `ORG` beyond one, or an event's people, so three cases were added over new fixtures: card-kind.vcf (`KIND:GROUP`, an `ORG` with an escaped semicolon), event-people.ics (an organizer and two attendees, an `RDATE` alone, a `DURATION`, escaped `SUMMARY` and `LOCATION`, a `TZID` the IANA database resolves, checked with coreutils `date`) and journal-basic.ics. vectors/README.md now says which values are re-derived and that the sync and search expectations stand as written. Seeds: V14, V18, N13 to N16 with the manifest restated.
- **Object labels** (C4). Every item's `object` and `conflict_object` and every binding's `base_object`, `conflict_object` and `shared_object` are checked in their own loops against the objects the store and the expected store declare; the old check sat in the references loop and read the last item only. Seed: V12 with the manifest restated.
- **JSON and one-word names** (C5). schema.sh reads each statement and migration with its comments dropped (no literal holds `--`) and refuses, in any case, a call of a `json…` function and the `->` and `->>` operators. names.sh checks every backticked one-word lowercase identifier of the documents against the tables, columns, indexes and triggers of both schemas, the statements, the members the vector and payload schemas define, and a list of 124 words in five groups (vocabulary values, kinds, parts and verbs, the query language, platform and protocol names, example values). Seeds: Q15, Q16 (Q17, lower case, was caught before), D02.
- **Strict vector formats** (C6). vectors/schema/ is closed throughout: sync.schema.json has one `$defs` entry per row type (collection, object, item, binding, source, summary with a row per table, address, supersession, reference), each typed and closed, the six mutation kinds with their fields (Add, Edit, Remove, SetFlags, Copy, Move), the four push kinds with what each carries, a member, a page, a head, `fetch` (by handle, Meta or Full, `body`, `revision`, a file's `meta`); summaries.schema.json a row per table, the address and attachment entries, `hint` and `handle` together; the search store, queries (one answer of `hits`, `threads` or `error`, the refusal codes, `temporal`, `cut`), chunks, objects and payloads schemas likewise. checks/vectors.py compares every summary row definition of every schema with its table's columns read off migrations/storage/, list columns as `in_reply_to` and `categories`, and its own column sets too. vectors/README.md documents every field of every format and maps the policy spellings: a collection's `conflict` (manual, prefer-incoming, prefer-existing) between sources, a run's (manual, prefer-remote, prefer-local) as SYNC.md §5's `Manual`, `PreferRemote`, `PreferLocal` between the store and one source. The `v` rule, stated there: a field a runner must read to reproduce a case, removed or given another meaning, or a value added to a closed set, bumps the format's `v` and its schema's `const`. By it, vectors/sync/ (`narrowed`, `enumerated`, `carries`, batch 5) and queries.json (`cut`, batch 6) move to `v` 2, which reverses those batches' reading that a field additive in an open object needed none; SYNC.md §11 and SEARCH.md §11 state the versions, SYNC.md §11 also an upgrade's `tier` and `handles` and each mutation's fields. Seeds: V17, V20, N17 with the manifest restated, and a misspelt summary column, a `level` 3, a `Ful` tier, an object on a Remove, each refused.
- **A manifest** (C7). vectors/manifest.json, `v` 1 with its schema, records the SHA-256 of the 212 files under vectors/ and payloads/ a vendor copies (all but vectors/README.md and the manifest), the length of every list of each case file by JSON pointer, and the number of sync cases; checks/vectors.py compares it with the tree, and `python3 checks/vectors.py . --manifest` writes it. JSON was chosen over a sha256sum list so it carries the counts and conforms to a schema as STORAGE.md §16 asks of every file under vectors/; vectors/README.md and GUIDE §16 give a vendor the check (`jq … | sha256sum -c -`, the manifest compared with this repository's at the revision followed, the cases run counted). vectors/sync/ is checked numbered from 1 with no gap and no number twice, and every fixture named by a case. .gitattributes extends `-text` to vectors/ and payloads/, whose bytes the manifest now pins. Seeds: V06, V08, N21 (with the manifest restated too), N22, and every vector mutant.
- **References** (C8). checks/references.pl, a new flake check (`references`, perl), reads every markdown file outside cairn/: each relative link names a file that exists and each anchor a heading as GitHub slugs it, and each `§n` or `Annex X` a numbered heading of its document: the one named right before it, a link to it included, else the one of the reference a list continues, else the file's own, an annex STORAGE's, a section of another markdown file, an RFC, a BCP, an ISO standard or Unicode outside it. It found STORAGE Annex A.1's `(§3.3)` and `§4.3`, meant as RFC 5322's but read as STORAGE's own by the parts' convention, and vectors/README.md's "the RFC's own §10"; both now name the RFC. The reviewer's checkers reported three false positives here, its sentence rule taking a bare `§` for the last document named. Seeds: N19, N20.
- **Versions match tags** (C9). checks/tags.sh, a CI job on a checkout with its history and tags: for STORAGE, SYNC, SEARCH and conventions/gtd.md, when a tag names the version the Status line states, the document and the files the part owns (its migrations, statements, vectors and schemas, STORAGE the payload schemas, each part the fixtures its vectors name, an unnamed fixture STORAGE's) are the tag's, none added or removed; no tag names today's drafts, so it passes. Seeded read-only through `GIT_DIR` and `GIT_WORK_TREE` on scratch copies: the working tree with its Status lines set to storage-draft-07, sync-draft-06 and search-draft-07 fails on all three, the tree `git archive storage-draft-07` yields passes. names.sh fails when README's Status names another version than a Status line. Seeds: D04, N18.
- **CI hygiene** (C10). actions/checkout pinned at 11d5960a326750d5838078e36cf38b85af677262 (v4.4.0, where v4 points) and cachix/install-nix-action at 75c75c31ebece974e48ebc36b4ad125bd97bd97b (v31.11.3, where v31 points), each tag in a trailing comment, resolved by `git ls-remote`; `permissions: contents: read` and `persist-credentials: false`. schema.sh, names.sh and invariants.sh remove their temporary directory on exit, as floor.sh did. AGENTS.md §4 says `nix flake check` sees the files git tracks and `nix flake check path:$PWD` the working tree, and names the waiver list, the manifest and the tag check. The harness also appended ` PRAGMA user_version …; COMMIT;` to a migration's text with `$(cat …)`, which drops the final newline, so a migration ending in a comment line swallowed both and every check failed confusingly (found by N24); schema.sh, floor.sh and invariants.sh now put a newline between them.
- **Licensing** (C11). README's License covers the documents, the canonical SQL, the payload schemas, the vectors with their fixtures and schemas, the conventions and the checks; vectors/README.md says so for its files. Every JSON Schema (vectors/schema/, payloads/, conventions/gtd/) states `SPDX-License-Identifier: MIT OR Apache-2.0` in its `$comment`, every check script in its header.
- **Scenario payloads are valid**. checks/vectors.py reads every `queue/enqueue_action` of checks/invariants.sh, undoes its shell quoting, stands a well-formed name for each interpolated body, and validates the payload against its action's schema, one under a comment opening `# A malformed payload` being required invalid. Eleven payloads were malformed (an `add` without `flags` or `object`, a `submit` without `from` and `rcpts`); they now carry the members their schemas require, an `add`'s `object` the body its row pins, and the `../x` scenario is marked. 20 payloads are checked. Seed: N11.
- Comment lines over 80 columns: invariants.sh's `ref` helper, vectors.py's chunk comment, and three SQL comments (cancel_action.sql, set_performer.sql, migrations/search/0001_init.sql), rewrapped.

## The mutation score

The reviewer's 50 mutations of 9606b43, each adapted where its target moved (M01 drops `items_by_sort`, `items_by_sort_global` being gone; Q01 and Q09 follow the coalesced cursor and the merged page), and 26 on what batches 1 to 8 added. Columns: the reviewer's snippets on its own 9606b43 tree, rerun by this harness; the tree after batch 7; this tree; this tree with vectors/manifest.json restated after the mutation, as a contributor changing a vector would, so only a check reading what the vector means can catch it. The reviewer reported 18 of 50 at 9606b43.

| mutation | 9606b43 | after batch 7 | now | manifest restated | caught by |
| --- | --- | --- | --- | --- | --- |
| D01-search-field-row-removed | caught | caught | caught | caught | vectors |
| D02-oneword-identifier-typo | missed | missed | caught | caught | names |
| D03-statement-typo-in-guide | caught | caught | caught | caught | names |
| D04-status-line-version | missed | missed | caught | caught | names |
| M01-drop-items_by_sort | caught | caught | caught | caught | invariants, names |
| M02-drop-items_by_link | caught | caught | caught | caught | invariants |
| M03-bindings_by_handle-not-unique | missed | missed | caught | caught | invariants |
| M04-drop-self-reference-check | caught | caught | caught | caught | invariants |
| M05-drop-refcount-check | missed | missed | caught | caught | invariants |
| M06-drop-occurrence_by_start | missed | missed | caught | caught | invariants |
| M07-drop-objects_count_collect | caught | caught | caught | caught | invariants |
| M08-drop-collections_keep_queued | caught | caught | caught | caught | invariants, names |
| M09-search-tokenizer-diacritics | missed | missed | caught | caught | names |
| N01-objects-hash-name-check-dropped | n/a | caught | caught | caught | floor, invariants |
| N02-init_store_meta-older-draft | n/a | caught | caught | caught | invariants, names |
| N03-revive-keeps-retained_by | n/a | missed | caught | caught | invariants |
| N04-delete_binding-every-source | n/a | missed | caught | caught | invariants |
| N05-conflicted-items-any-account | n/a | caught | caught | caught | invariants, names |
| N06-held_mail_summary-derived-keys | n/a | missed | caught | caught | invariants |
| N07-load_items-retained | n/a | missed | caught | caught | invariants |
| N08-thread_members-any-account | n/a | missed | caught | caught | invariants |
| N09-linked-tombstones | n/a | missed | caught | caught | invariants |
| N10-list_items_page-tombstones | n/a | missed | caught | caught | invariants |
| N11-scenario-payload-malformed | n/a | missed | caught | caught | vectors |
| N12-scenario-tokenizer-diacritics | n/a | missed | caught | caught | names |
| N13-summary-card-kind | n/a | missed | caught | caught | vectors |
| N14-summary-event-dtend | n/a | missed | caught | caught | vectors |
| N15-summary-task-status | n/a | missed | caught | caught | vectors |
| N16-summary-event-attendee-name | n/a | missed | caught | caught | vectors |
| N17-sync-narrowed-misspelt | n/a | missed | caught | caught | vectors |
| N18-readme-status-stale | n/a | missed | caught | caught | names |
| N19-anchor-broken | n/a | missed | caught | caught | references |
| N20-section-reference-missing | n/a | missed | caught | caught | references |
| N21-fixture-added-unlisted | n/a | missed | caught | caught | vectors |
| N22-sync-renumbered-gap | n/a | missed | caught | caught | vectors |
| N23-statement-never-run | n/a | caught | caught | caught | invariants, names |
| N24-drop-bindings_by_link | n/a | caught | caught | caught | invariants, names |
| N25-drop-items_bodiless | n/a | caught | caught | caught | invariants, names |
| N26-payload-schema-open | n/a | caught | caught | caught | vectors |
| Q01-page_desc-bound-lt-to-le | missed | missed | caught | caught | invariants |
| Q02-page_asc-order-desc | missed | missed | caught | caught | invariants |
| Q03-count_mail-no-deleted | caught | caught | caught | caught | invariants |
| Q04-pending-actions-desc | caught | caught | caught | caught | invariants |
| Q05-purge_retained-le | missed | missed | caught | caught | invariants |
| Q06-occurrences-order | missed | missed | caught | caught | invariants |
| Q07-hit-no-deleted | missed | missed | caught | caught | invariants |
| Q08-rename-get_mail | caught | caught | caught | caught | invariants, names |
| Q09-page_filtered-no-deleted | caught | caught | caught | caught | invariants |
| Q10-collect_before-drop-user-ref-guard | caught | caught | caught | caught | invariants |
| Q11-list_mail_page_desc-order | missed | missed | caught | caught | invariants |
| Q12-occurrences-zero-length | missed | missed | caught | caught | invariants |
| Q13-lookup_objects-derived-keys | missed | missed | caught | caught | invariants |
| Q14-lookup_objects-no-account-scope | missed | missed | caught | caught | invariants |
| Q15-json-uppercase | missed | missed | caught | caught | schema |
| Q16-json-arrow-operator | missed | missed | caught | caught | schema |
| Q17-json-lowercase-control | caught | caught | caught | caught | schema |
| V01-fold-sort_key-second-instant | missed | caught | caught | caught | vectors |
| V02-full-lowercase-sort_key-simple | missed | missed | caught | caught | vectors |
| V03-mail-date-local-not-utc | missed | caught | caught | caught | vectors |
| V04-sync01-flag-not-pulled | missed | missed | caught | missed | manifest |
| V05-sync01-push-a-flag | missed | missed | caught | missed | manifest |
| V06-delete-sync-vector | missed | missed | caught | caught | vectors |
| V07-search-hit-swapped | missed | missed | caught | missed | manifest |
| V08-search-case-deleted | missed | missed | caught | missed | manifest |
| V09-occurrence-end-shifted | missed | missed | caught | missed | manifest |
| V10-object-digest | caught | caught | caught | caught | vectors |
| V11-chunk-boundary | caught | caught | caught | caught | vectors |
| V12-sync01-expected-item-object-typo | missed | missed | caught | caught | vectors |
| V13-sync-push-key | caught | caught | caught | caught | vectors |
| V14-summary-fn | missed | missed | caught | caught | vectors |
| V15-fixture-byte | caught | caught | caught | caught | vectors |
| V16-search-refusal-span | caught | caught | caught | caught | vectors |
| V17-sync-expected-column-typo | missed | missed | caught | caught | vectors |
| V18-summary-address-position | missed | missed | caught | caught | vectors |
| V19-search-store-fixture-swap | missed | missed | caught | missed | manifest |
| V20-sync-mutation-kind-typo | missed | missed | caught | caught | vectors |
| total | 18 of 50 | 27 of 76 | 76 of 76 | 70 of 76 | |

Of the reviewer's 50: 18 at 9606b43, its own count reproduced; 20 after batch 7; 50 now; 44 with the manifest restated. Of the 26 new: 7 after batch 7, 26 now and with the manifest restated. The six the restated manifest leaves are a sync case's expected rows and pushes, a search case's hits, a case removed, an occurrence row and a store item's fixture: values only an engine or an indexer running the vectors derives, which the manifest now pins against an unnoticed edit. "caught by" names the checks failing with the manifest restated, else the manifest. The harness, adapted from the reviewer's, copied each tree, applied one change and ran its schema, names, invariants, vectors, floor and references checks (those it has).

## Files

- Added: checks/references.pl, checks/tags.sh, checks/waivers.txt, vectors/manifest.json, vectors/schema/manifest.schema.json, vectors/fixtures/card-kind.vcf, vectors/fixtures/event-people.ics, vectors/fixtures/journal-basic.ics, this entry.
- Changed: checks/invariants.sh, checks/vectors.py, checks/names.sh, checks/schema.sh, checks/floor.sh (SPDX, the migration newline); every file of vectors/schema/; vectors/sync/*.json (`v` 2, 117 files); vectors/search/queries.json (`v` 2); vectors/summaries.json (three cases, 53, `v` 3); vectors/README.md; the eleven payloads/*.schema.json and conventions/gtd/writers.schema.json (`$comment` alone); flake.nix (`references`, the waiver file, perl in the shell); .github/workflows/tests.yml; .gitattributes; AGENTS.md §4; README.md (License, layout); GUIDE.md §16; SYNC.md §11; SEARCH.md §11; STORAGE.md Annex A.1 (one citation); queries/storage/owner/cancel_action.sql, set_performer.sql and migrations/search/0001_init.sql (comments); cairn/changes/audit-2026-10-31/tasks.md.
- Deleted: none.

## Followers

- io-pimdir reads vectors/sync/ and queries.json at `v` 2 under the closed schemas, re-vendors vectors/ and payloads/ with manifest.json and checks its copy against it, and passes the three new summaries cases.

## Left

- checks/tags.sh guards nothing until the user tags storage-draft-08, sync-draft-07, search-draft-08 and gtd-draft-03; a tag on another commit than the one the part's files last changed in makes it fail at once, which is the point.
- `nix flake check` without `path:` sees tracked files alone: until the new files are added to git, its `invariants` evaluation misses checks/waivers.txt and `vectors` sees a manifest naming untracked files.
- The sync and search expectations other than the keys, refusals, chunks, title hits and series windows are hand-written; only an engine or an indexer running the vectors checks them (the restated-manifest column).

`nix flake check path:$PWD` passes.
