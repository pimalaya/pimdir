-- What a consumer records beside what it derived (§4.5): the last stamp
-- drawn, so the next look asks for every stamp above it; purges, which says
-- whether a row left without one or a collection was renamed or deleted; and
-- the store's id and incarnation, a mismatch of either being a reset.
SELECT next_change - 1 AS changed, purges, store_id, incarnation FROM store_meta WHERE id = 1;
