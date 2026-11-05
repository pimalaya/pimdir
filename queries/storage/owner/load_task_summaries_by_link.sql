-- The task summaries, on load_mail_summaries_by_link's terms.
SELECT i.link_id, s.uid, s.summary, s.dtstart, s.dtstart_tzid, s.dtstart_value, s.due, s.due_tzid, s.due_value,
       s.status, s.completed, s.percent, s.recurring, s.until, s.priority, s.parent, s.mid, s.created
FROM items i JOIN task_summary s ON s.item = i.id WHERE i.collection = :collection
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links');
