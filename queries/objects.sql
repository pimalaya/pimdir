-- pimdir objects: the content-addressed body index and its reference counting.
-- The bytes live in blob files (SPEC.md §5); these rows are the index.
--
-- Reference statements for the store operations (SPEC.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- name: store_object
-- The bytes are in the blob file already, written by this batch or streamed
-- there beforehand; the refcount is settled later in the batch (§14).
INSERT INTO objects(hash, size, refcount) VALUES(:hash, :size, 0)
ON CONFLICT(hash) DO UPDATE SET size = excluded.size;

-- name: lookup_objects
-- Resolve link ids (a JSON array) to a hydrated body hash, scoped to the
-- caller's account, the only axis a link id is trustworthy on: two unrelated
-- servers may mint the same vCard UID (§9.2), and answering across accounts
-- hands one account's body to the other's sync. A single-account store binds
-- NULL and dedups whole-store.
SELECT i.link_id, i.object_hash FROM items i
JOIN collections c ON c.id = i.collection
WHERE i.object_hash IS NOT NULL
  AND i.link_id IN (SELECT value FROM json_each(:links))
  AND c.account IS :account;

-- name: recompute_refcounts
-- Recount from the four pointers that pin an object, in one grouped pass, so
-- O(items+bindings+queue). The correlated-subquery form is O(objects x items),
-- since the OR across object_hash and conflict_object is a disjunction no index
-- serves: on twenty thousand items it took 80 seconds against this one's 121 ms.
-- The left join is what settles an object no pointer names any more, counting
-- zero rather than leaving it unvisited (§5).
UPDATE objects SET refcount = counted.n
FROM (
  SELECT o.hash AS hash, count(r.hash) AS n FROM objects o
  LEFT JOIN (
    SELECT object_hash AS hash FROM items WHERE object_hash IS NOT NULL
    UNION ALL SELECT conflict_object FROM items WHERE conflict_object IS NOT NULL
    UNION ALL SELECT base_object FROM bindings WHERE base_object IS NOT NULL
    UNION ALL SELECT object_hash FROM queue WHERE object_hash IS NOT NULL
  ) r ON r.hash = o.hash
  GROUP BY o.hash
) AS counted
WHERE counted.hash = objects.hash AND objects.refcount != counted.n;

-- name: adjust_refcount
-- The O(changes) alternative to recompute_refcounts, for an implementation that
-- diffs its writes (§14).
UPDATE objects SET refcount = refcount + :delta WHERE hash = :hash;

-- name: list_garbage_objects
-- What the collector takes (§5), and no write's business: the batch that
-- attaches a body may not be the one that indexed it. `<= 0` matches the
-- partial index objects_garbage, so neither statement scans, and it keeps the
-- read-only reader honest, since it cannot apply the refcount floor (§7).
SELECT hash FROM objects WHERE refcount <= 0;

-- name: delete_garbage_objects
-- The blob files go after the commit, so a crash leaves at worst an orphan and
-- never a row without a body.
DELETE FROM objects WHERE refcount <= 0;

-- name: object_exists
-- Asked once per file as the collector walks the blob directory, after
-- delete_garbage_objects has committed, so one pass reclaims the collected and
-- the orphaned together. A point lookup rather than list_object_hashes, which
-- would hold the whole index in memory to answer about one file (§5).
SELECT 1 FROM objects WHERE hash = :hash;

-- name: list_object_hashes
-- For the diagnosis that visits every row anyway (§7: an object row whose blob
-- is missing is a read that will fail), never for the collector.
SELECT hash FROM objects;

-- name: release_pins
-- adjust_refcount at -1, set-based, for a caller settling many at once. A hash
-- listed twice releases twice, which is what makes it the same operation as the
-- loop it replaces: that loop costs a hundred thousand statements in one
-- transaction on a fifty-thousand-item purge.
UPDATE objects SET refcount = refcount -
  (SELECT count(*) FROM json_each(:hashes) WHERE value = objects.hash)
WHERE hash IN (SELECT value FROM json_each(:hashes));
