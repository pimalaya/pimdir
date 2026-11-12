-- What a horizon roll or a change of time zone re-expands (§7), bound to the
-- horizon it replaces, the new one (the same twice when only a zone moved),
-- the version of the time zone database in use and the zone floating times
-- are read in: every live calendar item when either is not the one
-- index_meta records, since any zoned or floating time may move with it;
-- else a recurring series whose bound the old horizon had not reached, or
-- that states none, and a single calendar item whose start the new window
-- covers and the old one did not. The bound is compared on its calendar day,
-- the first eight characters of any UNTIL form against the date of the old
-- end, so a local or date-only UNTIL still compares. A journal's summary does
-- not say whether it recurs (STORAGE.md Annex A.5), so a horizon that moved
-- answers every live journal, a recurring one among them. Read from the
-- calendar collections to their items (the CROSS JOIN), so no item of another
-- kind is walked.
SELECT i.collection, i.seq FROM store.collections c
CROSS JOIN store.items i ON i.collection = c.id
LEFT JOIN store.event_summary e ON e.item = i.id
LEFT JOIN store.task_summary t ON t.item = i.id
LEFT JOIN store.journal_summary j ON j.item = i.id
WHERE c.kind = 'text/calendar' AND i.deleted = 0
  AND (
    :tzdb_version IS NOT (SELECT m.tzdb_version FROM index_meta m WHERE m.id = 1)
    OR :floating_zone IS NOT (SELECT m.floating_zone FROM index_meta m WHERE m.id = 1)
    OR (coalesce(e.recurring, t.recurring) = 1
      AND (coalesce(e.until, t.until) IS NULL
           OR substr(coalesce(e.until, t.until), 1, 8) >= replace(substr(:old_end, 1, 10), '-', '')))
    OR (j.item IS NOT NULL
      AND (:new_start IS NOT :old_start OR :new_end IS NOT :old_end))
    OR (coalesce(e.recurring, t.recurring) IS NOT 1
      AND ((i.sort_key >= :old_end AND i.sort_key < :new_end)
           OR (i.sort_key >= :new_start AND i.sort_key < :old_start)))
  );
