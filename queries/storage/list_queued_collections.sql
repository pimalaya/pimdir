-- The collections with pending work, for the owner's drain loop.
SELECT DISTINCT collection FROM queue WHERE error IS NULL;
