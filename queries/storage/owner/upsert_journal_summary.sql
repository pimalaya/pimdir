INSERT INTO journal_summary(collection, link_id, uid, summary, dtstart, dtstart_tzid, dtstart_value)
VALUES(:collection, :link_id, :uid, :summary, :dtstart, :dtstart_tzid, :dtstart_value)
ON CONFLICT(collection, link_id) DO UPDATE SET
    uid = excluded.uid, summary = excluded.summary, dtstart = excluded.dtstart,
    dtstart_tzid = excluded.dtstart_tzid, dtstart_value = excluded.dtstart_value;
