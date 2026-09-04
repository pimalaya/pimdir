-- For the diagnosis that visits every row anyway (§7: an object row whose blob
-- is missing is a read that will fail), never for the collector.
SELECT hash FROM objects;
