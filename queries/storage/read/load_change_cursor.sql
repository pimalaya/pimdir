-- What a consumer records beside what it derived (§4.5): the last stamp drawn,
-- so the next look asks for every stamp above it, and purges, which says
-- whether a row left without one.
SELECT next_change - 1 AS changed, purges FROM store_meta WHERE id = 1;
