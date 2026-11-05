INSERT INTO journal_summary(item, uid, summary, dtstart, dtstart_tzid, dtstart_value)
VALUES((SELECT id FROM items WHERE collection = :collection AND link_id = :link_id), :uid, :summary, :dtstart, :dtstart_tzid, :dtstart_value)
ON CONFLICT(item) DO UPDATE SET
    uid = excluded.uid, summary = excluded.summary, dtstart = excluded.dtstart,
    dtstart_tzid = excluded.dtstart_tzid, dtstart_value = excluded.dtstart_value;
