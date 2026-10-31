-- A placement whose body the indexer could not read (§4), gone from the blob
-- directory or failing its name: each pass reads it again.
INSERT OR IGNORE INTO missing(collection, seq) VALUES(:collection, :seq);
