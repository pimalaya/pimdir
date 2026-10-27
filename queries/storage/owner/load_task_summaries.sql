-- The task summaries, on load_mail_summaries's terms.
SELECT link_id, uid, summary, dtstart, dtstart_tzid, dtstart_value, due, due_tzid, due_value,
       status, completed, percent, recurring, until, priority, categories, parent, mid
FROM task_summary WHERE collection = :collection
  AND (:links IS NULL OR link_id IN (SELECT value FROM json_each(:links)));
