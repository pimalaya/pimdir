-- The same page descending. Start by binding the largest key the store can
-- hold; an implementation SHOULD expose that as "no cursor" rather than make a
-- caller invent a sentinel.
SELECT seq, link_id, flags, object_hash, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0
  AND (sort_key, seq) < (:after_key, :after_seq)
ORDER BY sort_key DESC, seq DESC LIMIT :limit;
