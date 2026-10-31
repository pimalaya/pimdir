-- The time zone floating times and dates now stand under (§7), an IANA name
-- or UTC.
UPDATE index_meta SET floating_zone = :floating_zone WHERE id = 1;
