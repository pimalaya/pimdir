-- The bindings' half of release_before (§11.4), run first in its transaction:
-- a base naming the item's own body lets go of it with the item. The binding
-- stays based (base_present 1) whatever witnessed its base before. The
-- predicate is release_before's, which this statement leaves true.
UPDATE bindings SET base_object = NULL, base_present = 1
FROM items i
WHERE bindings.collection = i.collection AND bindings.link_id = i.link_id
  AND bindings.base_object = i.object_hash
  AND i.collection IN (SELECT value FROM json_each(:collections))
  AND i.deleted = 0 AND i.conflicted = 0 AND i.object_hash IS NOT NULL
  AND i.sort_key < coalesce(:until, x'')
  AND (SELECT kind FROM collections c WHERE c.id = i.collection) = 'message/rfc822'
  AND EXISTS (SELECT 1 FROM bindings b
              WHERE b.collection = i.collection AND b.link_id = i.link_id)
  AND NOT EXISTS (SELECT 1 FROM bindings b
                  WHERE b.collection = i.collection AND b.link_id = i.link_id
                    AND (b.conflicted = 1
                         OR NOT (b.base_present = 1 OR b.base_flags IS NOT NULL
                                 OR b.base_object IS NOT NULL OR b.base_revision IS NOT NULL)
                         OR (b.base_object IS NOT NULL AND b.base_object != i.object_hash)))
  AND NOT EXISTS (SELECT 1 FROM sources s
                  WHERE s.collection = i.collection
                    AND NOT EXISTS (SELECT 1 FROM bindings b
                                    WHERE b.collection = i.collection AND b.link_id = i.link_id
                                      AND b.source = s.source));
