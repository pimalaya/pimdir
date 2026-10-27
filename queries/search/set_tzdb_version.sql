-- The time zone database version the occurrences now stand under (§7).
UPDATE index_meta SET tzdb_version = :tzdb_version WHERE id = 1;
