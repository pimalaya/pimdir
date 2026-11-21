-- The placements holding a keyword (§8, §10): tag: or flag: naming a flag
-- other than the five system flags, which the index holds no row of and
-- `marked` and `unread` read from the store.
SELECT collection, seq FROM flag WHERE flag = :flag;
