-- Run on a restored copy before anything opens it (§8): above the copy's own
-- incarnation and, when the store it replaces could still be read, above
-- that one's (:replaced, NULL when it could not), so no consumer of either
-- takes the copy for what it followed (§4.5). The stride is random, 1 to
-- 2^31, so two restores of one backup, the replaced store unread, answer two
-- incarnations: a consumer compares for equality and reads no order in it.
UPDATE store_meta
SET incarnation = max(incarnation, ifnull(:replaced, 0)) + 1 + (random() & 2147483647)
WHERE id = 1;
