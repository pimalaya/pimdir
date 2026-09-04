-- Recurring series whose bound the horizon has outrun, or that state none
-- (§7): the rest keep the occurrences they have.
SELECT i.collection, i.seq FROM store.event_summary e
JOIN store.items i ON i.collection = e.collection AND i.link_id = e.link_id
WHERE e.recurring = 1 AND (e.until IS NULL OR e.until > :horizon_end) AND i.deleted = 0;
