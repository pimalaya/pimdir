-- The owner's release of the bodies of a set of mail collections
-- (:collections, a JSON array) below a sort key (§11.4): every live item whose
-- sort_key is below :until (RFC 3339 Z, NULL for none), the undated ('')
-- below any, that holds a body and needs it, back to Meta with its summary,
-- addresses, flags and bindings kept. It needs it while it is conflicted, a
-- binding of it is conflicted, has no base (a pending create) or names
-- another body as its base (a local edit), it has no binding, or a source of
-- the collection does not bind it (a propagation the body delivers); such an
-- item keeps it. release_bases_before runs first, recompute_refcounts after,
-- in the same transaction; the bodies fall to the collector. Returns the
-- seqs released.
UPDATE items SET object_hash = NULL, level = 1
WHERE items.collection IN (SELECT value FROM json_each(:collections))
  AND items.deleted = 0 AND items.conflicted = 0 AND items.object_hash IS NOT NULL
  AND items.sort_key < coalesce(:until, x'')
  AND (SELECT kind FROM collections c WHERE c.id = items.collection) = 'message/rfc822'
  AND EXISTS (SELECT 1 FROM bindings b
              WHERE b.collection = items.collection AND b.link_id = items.link_id)
  AND NOT EXISTS (SELECT 1 FROM bindings b
                  WHERE b.collection = items.collection AND b.link_id = items.link_id
                    AND (b.conflicted = 1
                         OR NOT (b.base_present = 1 OR b.base_flags IS NOT NULL
                                 OR b.base_object IS NOT NULL OR b.base_revision IS NOT NULL)
                         OR (b.base_object IS NOT NULL AND b.base_object != items.object_hash)))
  AND NOT EXISTS (SELECT 1 FROM sources s
                  WHERE s.collection = items.collection
                    AND NOT EXISTS (SELECT 1 FROM bindings b
                                    WHERE b.collection = items.collection
                                      AND b.link_id = items.link_id AND b.source = s.source))
RETURNING seq;
