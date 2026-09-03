-- pimdir summaries: what a reader lists an item from without its body, one
-- table per kind (STORAGE.md §4.4, Annex A), written with the item and read
-- joined onto its page.
--
-- Reference statements for the store operations (STORAGE.md §4.4, §14); column
-- encodings in §13, named parameters `:name`.

-- Writes: an upsert per kind, so a later tier replaces the row. A row moved
-- without its item stamps it with stamp_item (§4.5). A component rewritten as
-- another deletes its old row explicitly; everything else cascades.

-- name: upsert_mail_summary
INSERT INTO mail_summary(collection, link_id, message_id, in_reply_to, subject,
                         sender, sender_name, date, size, attachment)
VALUES(:collection, :link_id, :message_id, :in_reply_to, :subject,
       :sender, :sender_name, :date, :size, :attachment)
ON CONFLICT(collection, link_id) DO UPDATE SET
    message_id = excluded.message_id, in_reply_to = excluded.in_reply_to,
    subject = excluded.subject, sender = excluded.sender,
    sender_name = excluded.sender_name, date = excluded.date,
    size = excluded.size, attachment = excluded.attachment;

-- name: upsert_contact_summary
INSERT INTO contact_summary(collection, link_id, uid, fn, kind, org)
VALUES(:collection, :link_id, :uid, :fn, :kind, :org)
ON CONFLICT(collection, link_id) DO UPDATE SET
    uid = excluded.uid, fn = excluded.fn, kind = excluded.kind, org = excluded.org;

-- name: upsert_event_summary
INSERT INTO event_summary(collection, link_id, uid, summary, location, dtstart,
                          dtstart_tzid, dtstart_value, dtend, recurring, until)
VALUES(:collection, :link_id, :uid, :summary, :location, :dtstart,
       :dtstart_tzid, :dtstart_value, :dtend, :recurring, :until)
ON CONFLICT(collection, link_id) DO UPDATE SET
    uid = excluded.uid, summary = excluded.summary, location = excluded.location,
    dtstart = excluded.dtstart, dtstart_tzid = excluded.dtstart_tzid,
    dtstart_value = excluded.dtstart_value, dtend = excluded.dtend,
    recurring = excluded.recurring, until = excluded.until;

-- name: upsert_task_summary
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

-- name: upsert_journal_summary
INSERT INTO journal_summary(collection, link_id, uid, summary, dtstart, dtstart_tzid, dtstart_value)
VALUES(:collection, :link_id, :uid, :summary, :dtstart, :dtstart_tzid, :dtstart_value)
ON CONFLICT(collection, link_id) DO UPDATE SET
    uid = excluded.uid, summary = excluded.summary, dtstart = excluded.dtstart,
    dtstart_tzid = excluded.dtstart_tzid, dtstart_value = excluded.dtstart_value;

-- name: delete_event_summary
DELETE FROM event_summary WHERE collection = :collection AND link_id = :link_id;

-- name: delete_task_summary
DELETE FROM task_summary WHERE collection = :collection AND link_id = :link_id;

-- name: delete_journal_summary
DELETE FROM journal_summary WHERE collection = :collection AND link_id = :link_id;

-- The client read surface (§14.1): the kind's page in its natural direction,
-- cursor (sort_key, seq) as in queries/items.sql. A LEFT JOIN, since a probed
-- item has a row and no summary yet.

-- name: list_mail_page_desc
-- Newest first, the usual mail listing.
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.message_id, s.in_reply_to, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM items i LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) < (:after_key, :after_seq)
ORDER BY i.sort_key DESC, i.seq DESC LIMIT :limit;

-- name: get_mail
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.message_id, s.in_reply_to, s.subject, s.sender, s.sender_name, s.date, s.size, s.attachment
FROM items i LEFT JOIN mail_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;

-- name: list_contacts_page_asc
-- A to Z on the normalised name.
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.fn, s.kind, s.org
FROM items i LEFT JOIN contact_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) > (:after_key, :after_seq)
ORDER BY i.sort_key, i.seq LIMIT :limit;

-- name: get_contact
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.fn, s.kind, s.org
FROM items i LEFT JOIN contact_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;

-- name: list_events_page_asc
-- Chronological on the first occurrence (§9.3); a series is expanded above
-- the store (SEARCH.md).
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.summary, s.location, s.dtstart, s.dtstart_tzid, s.dtstart_value,
       s.dtend, s.recurring, s.until
FROM items i LEFT JOIN event_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) > (:after_key, :after_seq)
ORDER BY i.sort_key, i.seq LIMIT :limit;

-- name: get_event
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.summary, s.location, s.dtstart, s.dtstart_tzid, s.dtstart_value,
       s.dtend, s.recurring, s.until
FROM items i LEFT JOIN event_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;

-- name: list_tasks_page_asc
-- Soonest due first (§9.3, Annex A.4).
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.summary, s.dtstart, s.dtstart_tzid, s.dtstart_value,
       s.due, s.due_tzid, s.due_value, s.status, s.completed, s.percent, s.recurring, s.until
FROM items i LEFT JOIN task_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) > (:after_key, :after_seq)
ORDER BY i.sort_key, i.seq LIMIT :limit;

-- name: get_task
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.summary, s.dtstart, s.dtstart_tzid, s.dtstart_value,
       s.due, s.due_tzid, s.due_value, s.status, s.completed, s.percent, s.recurring, s.until
FROM items i LEFT JOIN task_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;

-- name: list_journals_page_asc
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.summary, s.dtstart, s.dtstart_tzid, s.dtstart_value
FROM items i LEFT JOIN journal_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.deleted = 0
  AND (i.sort_key, i.seq) > (:after_key, :after_seq)
ORDER BY i.sort_key, i.seq LIMIT :limit;

-- name: get_journal
SELECT i.seq, i.link_id, i.flags, i.object_hash, i.sort_key, i.level,
       s.uid, s.summary, s.dtstart, s.dtstart_tzid, s.dtstart_value
FROM items i LEFT JOIN journal_summary s ON s.collection = i.collection AND s.link_id = i.link_id
WHERE i.collection = :collection AND i.seq = :seq AND i.deleted = 0;

-- name: component_of
-- Which calendar table holds the item (Annex A.3); no row for a component
-- the format has no table for.
SELECT 'VEVENT' AS component FROM event_summary WHERE collection = :collection AND link_id = :link_id
UNION ALL
SELECT 'VTODO' FROM task_summary WHERE collection = :collection AND link_id = :link_id
UNION ALL
SELECT 'VJOURNAL' FROM journal_summary WHERE collection = :collection AND link_id = :link_id;
