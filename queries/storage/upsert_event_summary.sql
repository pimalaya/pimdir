INSERT INTO event_summary(collection, link_id, uid, summary, location, dtstart,
                          dtstart_tzid, dtstart_value, dtend, recurring, until)
VALUES(:collection, :link_id, :uid, :summary, :location, :dtstart,
       :dtstart_tzid, :dtstart_value, :dtend, :recurring, :until)
ON CONFLICT(collection, link_id) DO UPDATE SET
    uid = excluded.uid, summary = excluded.summary, location = excluded.location,
    dtstart = excluded.dtstart, dtstart_tzid = excluded.dtstart_tzid,
    dtstart_value = excluded.dtstart_value, dtend = excluded.dtend,
    recurring = excluded.recurring, until = excluded.until;
