INSERT INTO task_summary(collection, link_id, uid, summary, dtstart, dtstart_tzid,
                         dtstart_value, due, due_tzid, due_value, status, completed,
                         percent, recurring, until)
VALUES(:collection, :link_id, :uid, :summary, :dtstart, :dtstart_tzid,
       :dtstart_value, :due, :due_tzid, :due_value, :status, :completed,
       :percent, :recurring, :until)
ON CONFLICT(collection, link_id) DO UPDATE SET
    uid = excluded.uid, summary = excluded.summary, dtstart = excluded.dtstart,
    dtstart_tzid = excluded.dtstart_tzid, dtstart_value = excluded.dtstart_value,
    due = excluded.due, due_tzid = excluded.due_tzid, due_value = excluded.due_value,
    status = excluded.status, completed = excluded.completed,
    percent = excluded.percent, recurring = excluded.recurring, until = excluded.until;
