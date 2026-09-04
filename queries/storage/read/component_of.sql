-- Which calendar table holds the item (Annex A.3); no row for a component
-- the format has no table for.
SELECT 'VEVENT' AS component FROM event_summary WHERE collection = :collection AND link_id = :link_id
UNION ALL
SELECT 'VTODO' FROM task_summary WHERE collection = :collection AND link_id = :link_id
UNION ALL
SELECT 'VJOURNAL' FROM journal_summary WHERE collection = :collection AND link_id = :link_id;
