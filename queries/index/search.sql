-- pimdir search index: the statements over index.db with the store attached
-- as `store` (SEARCH.md §3). Named parameters `:name`.

-- name: init_index_meta
INSERT INTO index_meta(id, version, tokenizer) VALUES(1, :version, :tokenizer);

-- name: load_index_meta
SELECT version, tokenizer, store_change, store_purges, horizon_start, horizon_end
FROM index_meta WHERE id = 1;

-- name: set_index_cursor
-- Written in the transaction that folded the changes it names (§4).
UPDATE index_meta SET store_change = :store_change, store_purges = :store_purges WHERE id = 1;

-- name: set_horizon
UPDATE index_meta SET horizon_start = :horizon_start, horizon_end = :horizon_end WHERE id = 1;

-- The refresh (§4): what the store changed, what the index still holds.

-- name: load_changed_items
-- The store's feed, joined to what the index needs to fold a row: its
-- collection's kind and account, and whether it holds a body now.
SELECT i.collection, i.link_id, i.seq, i.object_hash, i.flags, i.deleted, i.retained_at, c.kind, c.account
FROM store.items i JOIN store.collections c ON c.id = i.collection
WHERE i.changed > :since ORDER BY i.changed LIMIT :limit;

-- name: placements_gone
-- Placements the index holds and the store no longer does: purged rows, or a
-- renamed collection's old id. Run when store_meta.purges or a collection
-- stamp moved.
SELECT p.collection, p.seq FROM placement p
LEFT JOIN store.items i ON i.collection = p.collection AND i.seq = p.seq
WHERE i.seq IS NULL;

-- name: objects_gone
-- Bodies the collector took (STORAGE.md §5): their text goes with them.
SELECT o.hash FROM object o LEFT JOIN store.objects s ON s.hash = o.hash WHERE s.hash IS NULL;

-- name: object_indexed
SELECT rowid, status FROM object WHERE hash = :hash;

-- name: insert_object
INSERT INTO object(hash, status) VALUES(:hash, :status) RETURNING rowid;

-- name: insert_object_text
INSERT INTO object_text(rowid, title, people, body, attachment, place, org, note)
VALUES(:rowid, :title, :people, :body, :attachment, :place, :org, :note);

-- name: delete_object
-- The FTS row is deleted by rowid first (contentless_delete), then the row.
DELETE FROM object_text WHERE rowid = :rowid;

-- name: delete_object_row
DELETE FROM object WHERE hash = :hash;

-- name: upsert_placement
INSERT INTO placement(collection, seq, link_id, hash) VALUES(:collection, :seq, :link_id, :hash)
ON CONFLICT(collection, seq) DO UPDATE SET link_id = excluded.link_id, hash = excluded.hash
RETURNING rowid;

-- name: delete_placement
DELETE FROM placement WHERE collection = :collection AND seq = :seq RETURNING rowid;

-- name: insert_summary_text
INSERT INTO summary_text(rowid, title, people) VALUES(:rowid, :title, :people);

-- name: delete_summary_text
DELETE FROM summary_text WHERE rowid = :rowid;

-- name: replace_flags
DELETE FROM flag WHERE collection = :collection AND seq = :seq;

-- name: insert_flag
INSERT INTO flag(flag, collection, seq) VALUES(:flag, :collection, :seq);

-- name: replace_occurrences
DELETE FROM occurrence WHERE collection = :collection AND seq = :seq;

-- name: insert_occurrence
INSERT INTO occurrence(collection, seq, start, end) VALUES(:collection, :seq, :start, :end);

-- name: items_to_reexpand
-- Recurring series whose bound the horizon has outrun, or that state none
-- (§7): the rest keep the occurrences they have.
SELECT i.collection, i.seq FROM store.event_summary e
JOIN store.items i ON i.collection = e.collection AND i.link_id = e.link_id
WHERE e.recurring = 1 AND (e.until IS NULL OR e.until > :horizon_end) AND i.deleted = 0;

-- name: upsert_thread
INSERT INTO thread(id, first, last, count) VALUES(:id, :first, :last, :count)
ON CONFLICT(id) DO UPDATE SET first = excluded.first, last = excluded.last, count = excluded.count;

-- name: upsert_message
INSERT INTO message(link_id, thread, parent) VALUES(:link_id, :thread, :parent)
ON CONFLICT(link_id) DO UPDATE SET thread = excluded.thread, parent = excluded.parent;

-- name: thread_of
SELECT thread FROM message WHERE link_id = :link_id;

-- The query side (§8): the primitives a compiled query joins. Each yields
-- placements; the compiler intersects and orders them.

-- name: match_objects
-- Every placement whose body matches, ranked. :match is the compiled FTS5
-- expression, never the user's text (§8).
SELECT p.collection, p.seq, bm25(object_text) AS rank
FROM object_text
JOIN object o ON o.rowid = object_text.rowid
JOIN placement p ON p.hash = o.hash
WHERE object_text MATCH :match;

-- name: match_summaries
SELECT p.collection, p.seq, bm25(summary_text) AS rank
FROM summary_text
JOIN placement p ON p.rowid = summary_text.rowid
WHERE summary_text MATCH :match;

-- name: flagged
SELECT collection, seq FROM flag WHERE flag = :flag;

-- name: occurring_between
-- Every calendar placement with an occurrence overlapping [:start, :end).
SELECT DISTINCT collection, seq FROM occurrence WHERE start < :end AND end > :start;

-- name: thread_members
SELECT p.collection, p.seq FROM message m
JOIN placement p ON p.link_id = m.link_id
WHERE m.thread = :thread;

-- name: hit
-- One hit's presentation row (§8), joined out of the store.
SELECT i.collection, c.account, c.kind, i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level
FROM store.items i JOIN store.collections c ON c.id = i.collection
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;

-- name: coverage
-- What a result set could not see (§8): live items with no body, per kind.
SELECT c.kind, count(*) FROM store.items i JOIN store.collections c ON c.id = i.collection
WHERE i.object_hash IS NULL AND i.deleted = 0 AND i.retained_at IS NULL
GROUP BY c.kind;
