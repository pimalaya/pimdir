-- How much of a collection a reader cannot list yet.
SELECT count(*) FROM probes WHERE collection = :collection;
