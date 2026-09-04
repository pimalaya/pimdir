-- What a consumer records beside what it derived (§4.5): every stamp below
-- next_change is drawn, and purges says whether a row left without one.
SELECT next_change, purges FROM store_meta WHERE id = 1;
