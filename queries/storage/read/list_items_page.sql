-- A keyset page in link-id order, riding the primary key with no extra index;
-- the empty string starts from the beginning, a link_id never being empty. That
-- order means nothing to a reader: it is the page for a sweep that must see
-- every item exactly once, and a listing wants a sort-key page below.
SELECT seq, link_id,
       CASE WHEN items.flags_known = 1
            THEN coalesce((SELECT group_concat(f.flag, ' ') FROM placement_flag f
                           WHERE f.collection = items.collection AND f.link_id = items.link_id), '') END AS flags,
       object_hash, sort_key, level FROM items
WHERE collection = :collection AND deleted = 0 AND link_id > :after
ORDER BY link_id LIMIT :limit;
