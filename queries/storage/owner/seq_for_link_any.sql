-- The public id a link id already has in a collection of the kind of
-- :collection, so one identity's placements of one kind share one (§9.1) and
-- a Message-ID spelling an event's UID draws its own. Unscoped by account
-- (§9.2), whatever the row's state. A key the writer derives (alt:, hash:,
-- dup:) states nothing and never shares (§9), so the caller runs this for none.
SELECT held.seq FROM items AS held
JOIN collections AS there ON there.id = held.collection
JOIN collections AS here ON here.id = :collection
WHERE held.link_id = :link_id AND there.kind = here.kind
LIMIT 1;
