-- The same page descending; a NULL cursor is the first page, so a caller
-- never invents a key above every representable one.
SELECT seq, link_id, flags, object_hash, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0
  AND (:after_key IS NULL OR (sort_key, seq) < (:after_key, :after_seq))
ORDER BY sort_key DESC, seq DESC LIMIT :limit;
