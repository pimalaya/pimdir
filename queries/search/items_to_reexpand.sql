-- What a horizon roll re-expands (§7), bound to the horizon it replaces: a
-- recurring series whose bound the old horizon had not reached, or that
-- states none, and a single calendar item whose start the new window covers
-- and the old one did not. The bound is compared on its calendar day, the
-- first eight characters of any UNTIL form against the date of the old end,
-- so a local or date-only UNTIL still compares.
SELECT i.collection, i.seq FROM store.items i
JOIN store.collections c ON c.id = i.collection
LEFT JOIN store.event_summary e ON e.collection = i.collection AND e.link_id = i.link_id
LEFT JOIN store.task_summary t ON t.collection = i.collection AND t.link_id = i.link_id
WHERE c.kind = 'text/calendar' AND i.deleted = 0
  AND (
    (coalesce(e.recurring, t.recurring) = 1
      AND (coalesce(e.until, t.until) IS NULL
           OR substr(coalesce(e.until, t.until), 1, 8) >= replace(substr(:old_end, 1, 10), '-', '')))
    OR (coalesce(e.recurring, t.recurring) IS NOT 1
      AND ((i.sort_key >= :old_end AND i.sort_key < :new_end)
           OR (i.sort_key >= :new_start AND i.sort_key < :old_start)))
  );
