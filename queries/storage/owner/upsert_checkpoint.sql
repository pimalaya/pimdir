INSERT INTO sources(collection, source, checkpoint) VALUES(:collection, :source, :checkpoint)
ON CONFLICT(collection, source) DO UPDATE SET checkpoint = excluded.checkpoint;
