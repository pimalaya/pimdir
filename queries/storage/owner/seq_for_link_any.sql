-- The public id this link id already has, so all its placements share one.
-- Unscoped by account (§9.2): the seq restates what the content states. A
-- writer-derived key states nothing and never shares (§9), so the caller runs
-- this for a stated hint only.
SELECT seq FROM items WHERE link_id = :link_id LIMIT 1;
