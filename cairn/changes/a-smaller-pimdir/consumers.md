# What the night moves, for each consumer

Read on 2026-11-22 against the design (not against the final tree): a line marked as breaking is a test or call to patch when the consumer moves to the night's io-pimdir. The Android part is the port's cost map.

### Summary

I read the design.md sections you named. Pins today: neverest uses io-pimdir b080e14 (storage-draft-15). himalaya uses dc19b8d (storage-draft-15). cardamum and calendula use 0.19.1 (storage-draft-15, search-draft-15). The io-pimdir working tree is already partway through the flag move: add_flags and retain_flags are deleted under spec/queries, and pimdir's queries/ is already gone from its working tree. So I took the canonical statement list from pimdir b5b9382 with `git show`. I modified nothing and built nothing.

- **neverest: 1 line breaks.** It is the format bump at src/sync/driver/tests.rs:82. `register_syncing` (src/sync/storage.rs:149-180) is safe: `LOAD_CHECKPOINT` and `UPSERT_CHECKPOINT` only touch `sources`, a table the moves keep. Both statements stay reachable as `io_pimdir::sql::NAME`. It does not depend on the `queue` change to `ON DELETE RESTRICT`. The `DROP INDEX placement_by_link` test holds as long as io-pimdir's now-private index keeps that name.
- **himalaya: 4 lines break.** Three are schema: two `UPDATE mail_summary` and one `DROP TABLE item_address`. One is the format bump (`storage-draft-16` expected to read as "upgrade himalaya").
- **cardamum: 0 lines break.** It has no SQL text. Its byte patches use `sql::FORMAT_VERSION` and `sql::search::FORMAT_VERSION` with strings of the same length, so it still holds if the `io_pimdir::sql::search` path stays.
- **calendula: 2 lines break.** One is schema (`UPDATE event_summary`). One is the format bump (`storage-draft-16` expected to read as "upgrade calendula").

The three format-bump failures already fail against 00727ba (storage-draft-16). There, the stamped draft-16 equals the crate's own version, so nothing is refused, and neverest's draft-15 reads as earlier. Under draft-17, draft-16 is earlier, so the message asks to move the store aside instead of asking for an upgrade.

### Android

- **Java binds 130 canonical names:** 124 as string literals, plus 6 through the dynamic `"UPSERT_" + kind + "_SUMMARY"` (PimdirSummary.java:87). 52 of them touch the moves, across 54 call sites.
  - 4 are dropped (the flag statements).
  - 26 are replaced: 6 upserts, 5 `LOAD_*_SUMMARIES_BY_LINK`, 4 `LIST_*_PAGE_ASC`, 4 `SEARCH_*`, `GET_MAIL`, and 6 list writes that become `summary_value`.
  - 15 canonical statements are rewritten in place, keeping their names, and 7 are the app's own forks under owner/.
  - `INSERT_ITEM` (4 call sites) gains a keywords parameter.
- **The app's own SQL that breaks:** 28 of 103 statements in app/, 18 of 39 owner/ forks and 4 of 23 index/ statements name dropped or merged tables. 3 more writers (`SET_FLAGS_KNOWN`, `SET_BASE_FLAGS_KNOWN`, `WRITE_BINDING`) would fail the new keywords CHECK.
- **The Rust side breaks too:**
  - rust/src/search/compile.rs has 15 lines of inline SQL on the old tables.
  - The app still uses 6 of the 7 index statements io-pimdir drops as dead: `FLAGGED`, `ATTACHED`, `HOLDING`, `CATEGORISED`, `OCCURRING_BETWEEN` and `CHUNKS_OF`. compile.rs:541 panics when a name is not served.
  - The app's own index schema keeps the `thread`, `missing` and `chunk` tables. The canonical statements it borrows on those tables will no longer match it.
- **The store schema changes with the crate bump.** The app's store schema is io-pimdir's `sql::MIGRATIONS` (rust/src/offline/shape.rs:51-53), so it changes as soon as the app moves to the new io-pimdir. storage-draft-17 then refuses existing stores.

### 1. Consumers

```tsv
repo	file:line	names	after the moves	breaks
neverest	src/sync/storage.rs:160	io_pimdir::sql::LOAD_CHECKPOINT (SELECT on sources), in register_syncing 149-180	unchanged: sources kept, statement kept as io_pimdir::sql::LOAD_CHECKPOINT	no
neverest	src/sync/storage.rs:167	io_pimdir::sql::UPSERT_CHECKPOINT (upsert on sources), register_syncing	unchanged, same path	no
neverest	src/sync/driver.rs:352	io_pimdir::sql::FORMAT_VERSION (own in PimdirFormatRefusal)	storage-draft-17	no
neverest	src/sync/driver/tests.rs:50	UPDATE store_meta SET format_version = 'storage-draft-99'	store_meta kept; store_meta_identity guarded only store_id/incarnation	no
neverest	src/sync/driver/tests.rs:75-81	storage-draft-07..13 asserted earlier	still earlier than 17	no
neverest	src/sync/driver/tests.rs:82	!written_earlier(storage-draft-15)	draft-15 is earlier than own draft-17 (already fails at 00727ba draft-16)	yes
neverest	src/sync/driver/tests.rs:535 (callers 551, 568)	DROP TABLE receipts; DROP TABLE queue / bindings (foreign_keys OFF)	both tables kept; queue gains FK RESTRICT, harmless with FKs off	no
neverest	src/sync/index.rs:208	DROP INDEX placement_by_link on index.db	index private to io-pimdir; placement kept, name presumably kept	no (unknown if renamed)
neverest	src/sync/index.rs:230	UPDATE index_meta SET format_version	index_meta kept	no
neverest	src/sync/index.rs:241	search-draft-99	later than 17	no
neverest	src/sync/index.rs:263	search-draft-11	earlier than 17	no
neverest	src/cli/sync.rs:1062	SELECT count(*) FROM capabilities	unchanged table	no
neverest	tests/queue.rs:305	UPDATE queue SET payload	queue kept	no
neverest	tests/queue.rs:370	UPDATE store_meta SET format_version	kept	no
neverest	tests/queue.rs:383	storage-draft-99	later	no
neverest	tests/queue.rs:403	storage-draft-11	earlier	no
neverest	cairn/spec/sync.md:1488	mail_summary, contact_summary, event_summary, task_summary, journal_summary, item_address	summary + summary_value (spec text goes stale)	no (doc)
neverest	13 lines in src/imap/backend.rs, src/kind/mail.rs, src/msgraph/client.rs, src/sync/driver/gmail_bodies.rs, src/sync/remote.rs, src/sync/storage.rs, src/sync/driver/tests.rs, tests/attachments.rs	public Pimdir*Summary types	unchanged if the public API holds	no
himalaya	src/error.rs:451	io_pimdir::sql::FORMAT_VERSION	storage-draft-17	no
himalaya	src/pimdir/index.rs:940	UPDATE mail_summary SET size = 'x' WHERE item = (SELECT id FROM items WHERE seq = ?1)	UPDATE summary SET size = 'x' WHERE item = ... (component 'mail')	yes
himalaya	src/pimdir/index.rs:1256	UPDATE index_meta SET tokenizer = 'porter'	index_meta kept (tokenizer column exists today)	no (unknown if the private index drops the column)
himalaya	src/pimdir/index.rs:1275,1291,1295,1299	index_meta.format_version = search-draft-11	earlier, refused, unchanged	no
himalaya	src/pimdir/backend.rs:2256	UPDATE queue SET payload	queue kept	no
himalaya	src/pimdir/backend.rs:2842,2858-2859,2865	storage-draft-11; SELECT format_version, count(*) FROM queue / store_meta	kept	no
himalaya	src/pimdir/backend.rs:2902	UPDATE store_meta SET format_version WHERE id = 1	kept	no
himalaya	src/pimdir/backend.rs:2913	(storage-draft-11, "move its directory aside")	still earlier	no
himalaya	src/pimdir/backend.rs:2914	(storage-draft-16, "upgrade himalaya")	draft-16 earlier than 17: message says move aside (already fails at 00727ba)	yes
himalaya	src/pimdir/backend.rs:2933	io_pimdir::sql::FORMAT_VERSION in message	storage-draft-17	no
himalaya	src/pimdir/backend.rs:2972	DROP TABLE item_address (corrupt-store test)	table gone; drop summary_value (or summary) instead	yes
himalaya	src/pimdir/backend.rs:3926	UPDATE items SET sort_key WHERE link_id	items kept (gains keywords)	no
himalaya	tests/pimdir_search.rs:218	UPDATE mail_summary SET size = 'x' WHERE subject = 'Report 2'	UPDATE summary SET size = 'x' WHERE component = 'mail' AND title = 'Report 2'	yes
himalaya	cairn/spec/search.md:128	index_meta.format_version search-draft-11	unchanged	no (doc)
himalaya	19 lines in src/pimdir/backend.rs (15, incl. mail.subject at 704 and 710), src/pimdir/index.rs (2), src/pimdir/attachment/mod.rs (2)	PimdirMailSummary and its fields	unchanged if the public API holds	no
cardamum	src/pimdir/client.rs:11,102	sql::FORMAT_VERSION	storage-draft-17	no
cardamum	src/pimdir/backend.rs:1116,2524,2535-2536	FORMAT_VERSION byte-patched to storage-draft-11 (same length)	same length as storage-draft-17	no
cardamum	src/pimdir/backend.rs:2551	byte-patched to storage-draft-99	later	no
cardamum	src/pimdir/index.rs:354,1133,1145	sql::search::FORMAT_VERSION byte-patched to search-draft-11	same length as search-draft-17	no (if the io_pimdir::sql::search path stays)
cardamum	src/error.rs:538,544,570	storage-draft-11; VersionMismatch.store_meta field; search-draft-11 (error values only)	unchanged	no
cardamum	src/pimdir/index.rs:355 (4 lines)	summary::{contact, mail::PimdirMailSummary}	unchanged if the public API holds	no
calendula	src/pimdir/client.rs:26,216	sql::FORMAT_VERSION	storage-draft-17	no
calendula	src/pimdir/client.rs:316,322,359	storage-draft-07, store_meta field, search-draft-07 (error values)	unchanged	no
calendula	src/pimdir/client.rs:393-406	version_message with literal own versions (storage-draft-14, storage-v1)	independent of io-pimdir	no
calendula	src/pimdir/queue.rs:605	UPDATE queue SET payload	queue kept	no
calendula	src/pimdir/index.rs:872	UPDATE event_summary SET recurring = 'x' WHERE item = (SELECT id FROM items WHERE seq = ?1)	UPDATE summary SET recurring = 'x' WHERE item = ...	yes
calendula	src/pimdir/index.rs:1339-1351	sql::search::FORMAT_VERSION spelled once in index.db, patched to search-draft-08	same length	no (unknown if the private index spells it twice)
calendula	src/pimdir/backend.rs:3207	sql::FORMAT_VERSION spelled once in pimdir.db (byte patch)	store_meta only; the dropped trigger never held it	no
calendula	src/pimdir/backend.rs:3221	storage-draft-12 as earlier	earlier	no
calendula	src/pimdir/backend.rs:3222	storage-draft-16 as newer, expects "upgrade calendula"	draft-16 earlier than 17 (already fails at 00727ba)	yes
calendula	src/pimdir/backend.rs (6), src/pimdir/index.rs (2)	public Pimdir*Summary types	unchanged if the public API holds	no
```

### 2. Android

(a) Canonical names Java binds that the moves drop, replace or rewrite. "fork" means the app serves its own text from rust/pimdir/queries/owner/. Rows marked "rust" are run by the app's Rust search, not by Java.

```tsv
name	change	served from	call sites	count
ADD_FLAGS	dropped (items.keywords written by insert_item/update_item or the app's own writer)	fork owner/	pimdir/PimdirItems.java:201	1
RETAIN_FLAGS	dropped	canon	pimdir/PimdirItems.java:201	1
ADD_BASE_FLAGS	dropped (bindings.base_keywords)	fork owner/	pimdir/PimdirItems.java:231	1
RETAIN_BASE_FLAGS	dropped	canon	pimdir/PimdirItems.java:230	1
UPSERT_{MAIL,CONTACT,EVENT,TASK,JOURNAL,FILE}_SUMMARY	replaced by one kind-agnostic summary upsert (component, title, uid, card_kind)	fork owner/ (all 6)	pimdir/PimdirSummary.java:87 (dynamic)	1 site, 6 names
LOAD_MAIL_SUMMARIES_BY_LINK	replaced (kind-agnostic load)	canon	pimdir/DeletedItems.java:203	1
LOAD_CONTACT_SUMMARIES_BY_LINK	replaced	canon	pimdir/DeletedItems.java:206	1
LOAD_EVENT_SUMMARIES_BY_LINK	replaced	canon	pimdir/DeletedItems.java:211	1
LOAD_TASK_SUMMARIES_BY_LINK	replaced	canon	pimdir/DeletedItems.java:212	1
LOAD_JOURNAL_SUMMARIES_BY_LINK	replaced	canon	pimdir/DeletedItems.java:213	1
LIST_EVENTS_PAGE_ASC	replaced (kind-agnostic page)	canon	calendar/EventStore.java:415	1
LIST_TASKS_PAGE_ASC	replaced	canon	calendar/EventStore.java:413	1
LIST_JOURNALS_PAGE_ASC	replaced	canon	calendar/EventStore.java:416	1
LIST_FILES_PAGE_ASC	replaced	canon	file/FileStore.java:337	1
SEARCH_MAIL	replaced (kind-agnostic search)	canon	mail/MailStore.java:1188	1
SEARCH_CONTACTS	replaced	canon	pimdir/ItemLinks.java:263	1
SEARCH_CALENDAR	replaced	canon	pimdir/ItemLinks.java:264	1
SEARCH_FILES	replaced	canon	pimdir/ItemLinks.java:265	1
GET_MAIL	replaced (kind-agnostic get)	canon	file/FileStore.java:406	1
INSERT_ADDRESS	replaced (summary_value insert)	canon	pimdir/PimdirSummary.java:163	1
INSERT_IN_REPLY_TO	replaced (summary_value, role in-reply-to)	canon	pimdir/PimdirSummary.java:187	1
INSERT_CATEGORY	replaced (summary_value, role category)	canon	pimdir/PimdirSummary.java:187	1
REPLACE_ADDRESSES	replaced (summary_value delete by role)	canon	pimdir/PimdirSummary.java:150	1
REPLACE_IN_REPLY_TO	replaced	canon	pimdir/PimdirSummary.java:182	1
REPLACE_CATEGORIES	replaced	canon	pimdir/PimdirSummary.java:182	1
COUNT_MAIL	rewritten in place (reads summary)	canon	mail/MailStore.java:837	1
COUNT_MAIL_BY_DAY	rewritten in place	canon	mail/MailStore.java:873	1
COUNT_UNREAD	rewritten in place	canon	mail/MailStore.java:899	1
SUM_MAIL	rewritten in place	canon	mail/MailStore.java:940	1
GET_MAIL_ROW	rewritten in place (subject becomes title; column list may move)	canon	mail/MailStore.java:1066	1
LIST_MAIL_PAGE_FILTERED	rewritten in place (keywords, summary)	canon	mail/MailStore.java:964,1122,1186	3
LIST_ATTACHMENTS	rewritten in place	canon	file/FileStore.java:241	1
LIST_ATTACHMENTS_BY_ACCOUNT	rewritten in place	canon	file/FileStore.java:286	1
LIST_LINK_PLACEMENTS	rewritten in place (keywords)	canon	file/FileStore.java:396	1
LIST_RETAINED_PAGE	rewritten in place (keywords)	canon	pimdir/DeletedItems.java:157	1
LIST_UNSTAMPED_BINDINGS	rewritten in place	canon	pimdir/PimdirStorage.java:490	1
LIST_REPLIED	rewritten in place (summary_value in-reply-to)	canon	task/TaskStore.java:203	1
DESCRIBE_ENDPOINT	rewritten in place (one summary join for six)	canon	pimdir/ItemLinks.java:243	1
HELD_ELSEWHERE	rewritten in place	canon	pimdir/PimdirStorage.java:1363	1
SEQ_FOR_LINK_ANY	rewritten in place	canon	pimdir/PimdirItems.java:164	1
EVICT_BEFORE	rewritten (mail_summary, placement_flag, binding_base_flag)	fork owner/	mail/MailStore.java:1625	1
LINK_INVITATIONS_OF	rewritten (summary.invitation)	fork owner/	mail/MailStore.java:1239	1
LINK_INVITATIONS_TO	rewritten	fork owner/	pimdir/PimdirSummary.java:123,125	2
LINK_MAIL_FROM	rewritten (summary_value)	fork owner/	pimdir/PimdirSummary.java:121	1
LINK_SENDERS_OF	rewritten (summary_value)	fork owner/	pimdir/PimdirSummary.java:119	1
LINK_SOURCES_OF	rewritten (summary.mid)	fork owner/	pimdir/PimdirSummary.java:125	1
LINK_SOURCES_TO	rewritten (summary.mid)	fork owner/	pimdir/PimdirSummary.java:119	1
INSERT_ITEM	parameters change: gains :keywords	canon	pimdir/PimdirStorage.java:1538,1824; file/FileStore.java:681; contact/PimdirContacts.java:814	4
rust: FLAGGED, ATTACHED, HOLDING, CATEGORISED, OCCURRING_BETWEEN	dropped from io_pimdir::sql::search but live in the app (compile.rs:541 panics when absent); fork into queries/search/	canon	rust/src/search/compile.rs:313,325,333,391,420	5
rust: CHUNKS_OF	dropped from io-pimdir, live in the app (reads its own chunk table, fed by index/put_chunk)	canon	rust/src/search/find.rs:353	1
rust: GET_MAIL, GET_CONTACT, GET_EVENT, GET_TASK, GET_JOURNAL, GET_FILE	replaced (kind-agnostic get)	canon	rust/src/search/refresh.rs:369-374	6
rust: LIST_ADDRESS_PLACEMENTS, LIST_DOMAIN_PLACEMENTS	rewritten over summary_value	canon	rust/src/search/compile.rs:266,259	2
rust: INSERT_MISSING, DELETE_MISSING, LOAD_MISSING_ITEMS, COVERAGE	io-pimdir's text will read placement.missing; the app's index keeps a missing table, so fork or adopt	canon	rust/src/search/refresh.rs:806,809,136; coverage.rs:458	4
rust: DELETE_THREAD	io-pimdir drops thread; the app keeps it (own upsert_thread), so fork or drop	canon	rust/src/search/refresh.rs:833	1
rust: LOAD_CHANGED_ITEMS, ITEMS_TO_REEXPAND	text follows the new store (keywords, summary) for free; check the answered columns	canon	rust/src/search/refresh.rs:133,116	2
```

(b) The app's own statements naming dropped or merged tables or columns. The renames these rows refer to:
- `placement_flag.flag` becomes `items.keywords`; `binding_base_flag.flag` becomes `bindings.base_keywords`.
- `mail_summary.subject` and `message_id` become `summary.title` and `uid`.
- `contact_summary.fn` and `kind` become `title` and `card_kind`.
- The calendar summaries' `summary` column becomes `title`; `file_summary.name` becomes `title`.
- `item_address.address`, `mail_in_reply_to.message_id` and `task_category.category` all become `summary_value.value`.

```tsv
file	tables	columns hit	after the moves
rust/pimdir/queries/app/base_flags.sql	binding_base_flag	flag	bindings.base_keywords
rust/pimdir/queries/app/copy_addresses.sql	item_address	address, name	summary_value(value, name)
rust/pimdir/queries/app/copy_mail_summary.sql	mail_summary	subject, message_id	summary(title, uid)
rust/pimdir/queries/app/copy_summary.sql	all 6 summaries, item_address, mail_in_reply_to, task_category	subject, fn, kind, summary, message_id, uid, name, address	one summary copy and one summary_value copy
rust/pimdir/queries/app/count_owing.sql	placement_flag, binding_base_flag	flag	keywords <> base_keywords (anti-joins become a text compare)
rust/pimdir/queries/app/held_message_object.sql	mail_summary	subject	summary.title
rust/pimdir/queries/app/held_object.sql	mail_summary	subject	summary.title
rust/pimdir/queries/app/in_reply_to_of.sql	mail_in_reply_to	message_id	summary_value role in-reply-to
rust/pimdir/queries/app/item_flags.sql	placement_flag	flag	items.keywords
rust/pimdir/queries/app/item_object_flags.sql	placement_flag	flag	items.keywords
rust/pimdir/queries/app/items_without_summary.sql	contact_summary	item	summary
rust/pimdir/queries/app/key_of_another_message.sql	mail_summary	subject	summary.title
rust/pimdir/queries/app/list_cards.sql	contact_summary, item_address	fn, kind, uid, address	summary(title, card_kind, uid), summary_value
rust/pimdir/queries/app/list_live_mail.sql	mail_summary	subject	summary.title
rust/pimdir/queries/app/list_task_categories.sql	task_category	category	summary_value role category
rust/pimdir/queries/app/list_task_rows.sql	task_summary, item_address	summary, uid, address, name	summary, summary_value
rust/pimdir/queries/app/load_placements.sql	placement_flag, binding_base_flag, mail_summary, file_summary	flag, subject, name	keywords, base_keywords, summary(title)
rust/pimdir/queries/app/load_placements_by_handle.sql	same 4	same	same
rust/pimdir/queries/app/load_placements_by_link.sql	same 4	same	same
rust/pimdir/queries/app/mail_of_message_id.sql	mail_summary	message_id	summary.uid
rust/pimdir/queries/app/mail_pins_dated_before.sql	mail_summary	date	summary.date
rust/pimdir/queries/app/mail_unjoined.sql	mail_summary	item, attachment	summary
rust/pimdir/queries/app/mail_witnesses.sql	mail_summary	subject	summary.title
rust/pimdir/queries/app/message_id_of.sql	mail_summary	message_id	summary.uid
rust/pimdir/queries/app/names_another_message.sql	mail_summary	subject	summary.title
rust/pimdir/queries/app/overruled_state.sql	placement_flag	flag	items.keywords
rust/pimdir/queries/app/pending_creates_by_message_id.sql	mail_summary	message_id	summary.uid
rust/pimdir/queries/app/search_mail_indexed.sql	mail_summary, placement_flag	subject, message_id, flag	summary, keywords
rust/pimdir/queries/app/set_flags_known.sql	(items)	marks only	must also write keywords ('' when unknown, else the sorted set) or the new CHECK fails
rust/pimdir/queries/app/set_base_flags_known.sql	(bindings)	base_marks only	same for base_keywords
rust/pimdir/queries/app/write_binding.sql	(bindings)	base_marks reset when unknown	must reset base_keywords too (bindings_forget_base_flags trigger gone)
rust/pimdir/queries/owner/add_flags.sql	placement_flag	flag	delete (statement dropped)
rust/pimdir/queries/owner/add_base_flags.sql	binding_base_flag	flag	delete
rust/pimdir/queries/owner/evict_before.sql	mail_summary, placement_flag, binding_base_flag	date, flag	summary.date, keywords, base_keywords
rust/pimdir/queries/owner/link_invitations_of.sql	mail_summary	invitation	summary.invitation
rust/pimdir/queries/owner/link_invitations_to.sql	mail_summary	invitation	summary.invitation
rust/pimdir/queries/owner/link_mail_from.sql	item_address	address	summary_value
rust/pimdir/queries/owner/link_parents_of.sql	task_summary	parent	summary.parent
rust/pimdir/queries/owner/link_parents_to.sql	task_summary	parent	summary.parent
rust/pimdir/queries/owner/link_senders_of.sql	item_address	address	summary_value
rust/pimdir/queries/owner/link_senders_of_by_link.sql	item_address	address	summary_value (io-pimdir drops this name as unreferenced)
rust/pimdir/queries/owner/link_sources_of.sql	task_summary	mid	summary.mid
rust/pimdir/queries/owner/link_sources_to.sql	task_summary	mid	summary.mid
rust/pimdir/queries/owner/upsert_mail_summary.sql	mail_summary	subject, message_id	one summary upsert
rust/pimdir/queries/owner/upsert_contact_summary.sql	contact_summary	fn, kind, uid	one summary upsert
rust/pimdir/queries/owner/upsert_event_summary.sql	event_summary	summary, uid	one summary upsert
rust/pimdir/queries/owner/upsert_task_summary.sql	task_summary	summary, uid	one summary upsert
rust/pimdir/queries/owner/upsert_journal_summary.sql	journal_summary	summary, uid	one summary upsert
rust/pimdir/queries/owner/upsert_file_summary.sql	file_summary	name	one summary upsert
rust/pimdir/queries/index/agenda_occurrences.sql	store.event_summary, journal_summary, task_summary	summary	store.summary.title
rust/pimdir/queries/index/item_addresses.sql	store.item_address	address, name	store.summary_value
rust/pimdir/queries/index/item_categories.sql	store.task_category	category	store.summary_value
rust/pimdir/queries/index/item_in_reply_to.sql	store.mail_in_reply_to	message_id	store.summary_value
rust/pimdir/migrations/search/0001_init.sql	chunk, thread, missing (app's own index shape)	-	not forced (the app's shape); must match whatever search statements it borrows
rust/pimdir/queries/index/put_chunk.sql	chunk (app index)	-	not forced
rust/pimdir/queries/search/upsert_thread.sql	thread (app index)	-	not forced
rust/src/search/compile.rs:327,345-347,362,375,403,494,497,601-606	inline SQL: store.mail_summary, event/task/journal_summary, task_category, item_address, all 6 summaries	attachment, status, category, address	summary, summary_value (15 lines)
```

(c) Java readers that depend on those statements. The ordinal readers stay valid if the rewritten app/ statements keep their column order. The canonical ones depend on io-pimdir's new column lists.

```tsv
class	lines	reads	statements
pimdir/PimdirStorage.java	195-235	ordinals 0, 2, 5, 13	LOAD_PLACEMENTS* (app) via scoped() 537-570
pimdir/PimdirStorage.java	616-724 (placementOf)	ordinals 0-26: flags 1, base flags 6, mail 16-22 (date, subject, sender, size, attachment, invitation), file 23-26 (name, media_type, size, part), kind 15	LOAD_PLACEMENTS, _BY_LINK, _BY_HANDLE (app)
pimdir/PimdirStorage.java	741-780 (statusOf), 3209-3257 (folded, hasBase)	ordinals 5, 10, 13, 14 and the base columns	LOAD_PLACEMENTS* (app)
pimdir/PimdirStorage.java	485-510	ordinal 0	LIST_UNSTAMPED_BINDINGS (canon)
pimdir/PimdirStorage.java	1103-1139	row presence	HELD_OBJECT, HELD_MESSAGE_OBJECT (app)
pimdir/PimdirStorage.java	1348-1370	3 ordinals	HELD_ELSEWHERE (canon)
pimdir/PimdirStorage.java	1430-1475	2 ordinals	OVERRULED_STATE (app)
pimdir/PimdirStorage.java	1483-1503	flags text	ITEM_FLAGS, COPY_SUMMARY (app)
pimdir/PimdirStorage.java	2122-2138	2 ordinals	BASE_FLAGS (app)
pimdir/PimdirStorage.java	2733-2748	2 ordinals	PENDING_CREATES_BY_MESSAGE_ID (app)
pimdir/PimdirStorage.java	2790-2800	exec	COPY_MAIL_SUMMARY, COPY_ADDRESSES (app)
pimdir/PimdirStorage.java	2817-2837	ordinals 0-3 (subject, date, sender, size)	MAIL_WITNESSES (app)
pimdir/PimdirSummary.java	54-114, 144-190	derive JSON keys put as named params (subject, fn, kind, summary, message_id, uid, name)	UPSERT_*_SUMMARY, INSERT_/REPLACE_ lists, LINK_* rules (rulesOf 116-129)
pimdir/PimdirItems.java	155-233	writes flags (SET_*_FLAGS_KNOWN, RETAIN_/ADD_), PimdirDb.changedSharing	flag statements, SEQ_FOR_LINK_ANY
pimdir/DeletedItems.java	150-181	by column name (flags, size)	LIST_RETAINED_PAGE (canon)
pimdir/DeletedItems.java	184-234	by column name: subject, sender_name, sender, date, fn, org, summary, dtstart	LOAD_*_SUMMARIES_BY_LINK (canon): renamed columns break by name
pimdir/ItemLinks.java	239-248	ordinals 0-2	DESCRIBE_ENDPOINT (canon)
pimdir/ItemLinks.java	256-300	title at ordinal 8 / 8 / 7	SEARCH_CONTACTS, SEARCH_CALENDAR, SEARCH_FILES (canon)
pimdir/PimdirCollections.java	322-333	ordinal 0	COUNT_OWING (app)
mail/MailStore.java	1073-1105 (row)	ordinals 0-13	LIST_MAIL_PAGE_FILTERED, SEARCH_MAIL (canon), SEARCH_MAIL_INDEXED (app), GET_MAIL_ROW (canon)
mail/MailStore.java	1107-1145, 954-973	8 and 2 ordinals	LIST_MAIL_PAGE_FILTERED (canon)
mail/MailStore.java	832-946	1 ordinal each (aggregates)	COUNT_MAIL, COUNT_MAIL_BY_DAY, COUNT_UNREAD, SUM_MAIL (canon)
mail/MailStore.java	527-545	3 ordinals	MESSAGE_ID_OF, IN_REPLY_TO_OF (app)
mail/MailStore.java	1741-1756	2 ordinals	ITEM_FLAGS (app)
mail/MailStore.java	1606-1635, 1231-1244	exec	MAIL_PINS_DATED_BEFORE (app), EVICT_BEFORE, LINK_INVITATIONS_OF (fork)
mail/Outbox.java	239-281	3 ordinals	LIST_LIVE_MAIL (app)
calendar/EventStore.java	485-515 (page)	ordinal 7 = "the kind's NOT NULL summary text", plus 0, 1, 3, 4	LIST_TASKS, EVENTS, JOURNALS_PAGE_ASC (canon, replaced)
calendar/EventStore.java	409-460 (loadTasks)	ordinals 0-4; PimdirDb.table to the Rust bridge by column name	LIST_TASK_ROWS, LIST_TASK_CATEGORIES (app)
file/FileStore.java	237-258, 276-318, 329-360, 393-419	8, 14, 9, 4 ordinals	LIST_ATTACHMENTS, LIST_ATTACHMENTS_BY_ACCOUNT, LIST_FILES_PAGE_ASC, LIST_LINK_PLACEMENTS, GET_MAIL (canon)
contact/PimdirContacts.java	210-244, 653-697, 788-818	8, 1, 2 ordinals	LIST_CARDS, ITEMS_WITHOUT_SUMMARY, ITEM_OBJECT_FLAGS (app), INSERT_ITEM
task/TaskStore.java	185-214, 232-242	1 ordinal each	LIST_REPLIED (canon), MAIL_OF_MESSAGE_ID (app)
```

(d) Cost estimate.

**Facts:**
- 50 of the app's own SQL files name a dropped or merged table: 28 in app/, 18 in owner/, 4 in index/. 3 more writers (set_flags_known, set_base_flags_known, write_binding) must start writing keywords to satisfy the new CHECK.
- 52 Java-bound canonical names are affected (54 call sites); 26 of them are replaced by statements io-pimdir has not named yet.
- About 13 Java classes read these cursors (table c).
- On the Rust side: 15 lines of inline SQL in rust/src/search/compile.rs, 6 io-pimdir-dropped index statements the app still uses (they need forks), 5 canonical search statements on the app's own `missing` and `thread` tables (fork or adopt io-pimdir's shape), and 6 per-kind GET_* in refresh.rs.
- The derive bridge (`SummaryJson`, rust/src/ffi/offline.rs) hands Java the old column names keyed by kind.
- Tests: 13 Java test files name the old tables (64 lines; SyncVectorsTest 9, Draft09Measure 23). Rust tests: offline/shape/tests.rs 6 lines, ffi/offline.rs:639-656 3 lines, search/tests.rs 4.
- The store schema follows the io-pimdir bump automatically, so existing stores are refused at storage-draft-17 (reinstall).
- The `collections_keep_queued` mentions at PimdirCollections.java:80 and MailStore.java:177 are only comments. Foreign keys are on (PimdirDb.java:355), so `ON DELETE RESTRICT` keeps the same behaviour.

**Opinion:**
- **Mostly mechanical:** most of the SQL work is renames (table to `summary` with a `component` filter, columns to `title`/`uid`/`card_kind`, address and list tables to `summary_value.value`). Flag joins become plain column reads, so count_owing and overruled_state get simpler.
- **Real work:**
  - Writing the sorted keywords: SQLite 3.18 has no ordered group_concat, so Java should compute the text, in one place (PimdirItems.writeFlags and writeBaseFlags).
  - The summary write path: PimdirSummary plus 6 upsert forks plus 6 list writes become one upsert plus `summary_value`.
  - The 26 replaced canonical names, which wait on io-pimdir fixing the kind-agnostic names and column lists. EventStore.page's ordinal-7 trick and ItemLinks' title ordinals depend on them.
- **Size:** if keeping the column order on the app's own statements leaves placementOf and the other ordinal readers untouched, I'd put the port at one to two focused days plus the test fixtures. Fixing io-pimdir's final statement names first is the gate.
