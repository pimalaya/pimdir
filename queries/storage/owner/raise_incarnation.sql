-- Run on a restored copy before anything else opens it (§8): above the copy's
-- own incarnation and, when the store it replaces could still be read, above
-- that one's (:replaced, NULL when it could not), so no consumer of either
-- takes the copy for what it followed (§4.5).
UPDATE store_meta SET incarnation = max(incarnation, ifnull(:replaced, 0)) + 1 WHERE id = 1;
