-- SPDX-License-Identifier: MIT OR Apache-2.0
--
-- A released version 1 store holding at least one row in every table, for the
-- rehearsal migrations of this directory (STORAGE.md §6). Plain SQL, no
-- canonical statement, so the 3.18.2 floor runs it too. The last queue row
-- and the last item are deleted again, so both AUTOINCREMENT sequences stand
-- above every id their tables still hold.
INSERT INTO store_meta(id, format, format_version, version, read_version,
    produce_version, store_id, incarnation, hash_algo, created_at, derivation)
VALUES (1, 'pimdir', 'storage-v1', 1, 1, 1, '0123456789abcdef0123456789abcdef',
    1, 'blake3', '2026-11-13T00:00:00.000Z', 3);

INSERT INTO collections(id, account, kind, name, parent, role) VALUES
    ('INBOX', 'work', 'message/rfc822', 'INBOX', NULL, 'inbox'),
    ('Archive', 'work', 'message/rfc822', 'Archive', 'INBOX', NULL),
    ('Cal', 'work', 'text/calendar', 'Calendar', NULL, 'default'),
    ('Cards', 'work', 'text/vcard', 'Contacts', NULL, NULL),
    ('Files', 'work', 'application/octet-stream', 'Files', NULL, NULL),
    ('Later', NULL, '', 'Later', NULL, NULL);

INSERT INTO sources(collection, source, checkpoint, covered_since, covered_at,
    round)
VALUES ('INBOX', 'imap', x'6331', '2026-01-01T00:00:00Z',
    '2026-11-12T10:00:00.000Z', 1);
INSERT INTO capabilities(account, source, collection, capability, support,
    detail)
VALUES ('work', 'imap', NULL, 'mail.message.move', 'full', NULL),
    ('work', 'imap', 'INBOX', 'mail.message.remove', 'none', 'read-only');
INSERT INTO performers(account, capability, source)
VALUES ('work', 'mail.submit', 'smtp');

INSERT INTO objects(hash, size, refcount) VALUES
    ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 10, 3),
    ('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 20, 1);

INSERT INTO items(collection, link_id, seq, flags_known, marks, object_hash,
    sort_key, level)
VALUES
    ('INBOX', 'a@x', 1, 1, 1,
     'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
     '2026-08-01T10:00:00Z', 2),
    ('INBOX', 'b@x', 2, 1, 0, NULL, '2026-08-02T10:00:00Z', 1),
    ('Archive', 'a@x', 1, 0, 0, NULL, '2026-08-01T10:00:00Z', 1),
    ('Cal', 'ev', 3, 0, 0, NULL, '2026-09-01T09:00:00Z', 1),
    ('Cal', 'td', 4, 0, 0, NULL, '', 1),
    ('Cal', 'jn', 5, 0, 0, NULL, '', 1),
    ('Cards', 'c1', 6, 0, 0,
     'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'alice', 2),
    ('Files', 'f1', 7, 0, 0, NULL, 'notes.txt', 1),
    ('INBOX', 'gone@x', 8, 0, 0, NULL, '', 1),
    ('INBOX', 'last@x', 9, 0, 0, NULL, '', 1);
UPDATE items SET deleted = 1, retained_at = '2026-11-01T00:00:00.000Z',
    retained_by = 'imap'
WHERE link_id = 'gone@x';
DELETE FROM items WHERE link_id = 'last@x';

INSERT INTO placement_flag(item, flag)
SELECT id, '$label' FROM items WHERE collection = 'INBOX' AND link_id = 'a@x';
INSERT INTO bindings(item, collection, source, handle, base_flags_known,
    base_marks, base_object, base_revision, base_present, shared_object, round)
SELECT id, collection, 'imap', '10', 1, 1,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', NULL, 1, NULL, 1
FROM items WHERE collection = 'INBOX' AND link_id = 'a@x';
INSERT INTO bindings(item, collection, source, handle)
SELECT id, collection, 'imap', char(1) || 'b@x'
FROM items WHERE collection = 'INBOX' AND link_id = 'b@x';
INSERT INTO binding_base_flag(item, source, flag)
SELECT id, 'imap', '$label' FROM items
WHERE collection = 'INBOX' AND link_id = 'a@x';
INSERT INTO supersessions(item, by_item)
SELECT (SELECT id FROM items WHERE collection = 'Cal' AND link_id = 'td'),
       (SELECT id FROM items WHERE collection = 'Cal' AND link_id = 'jn');

INSERT INTO mail_summary(item, message_id, subject, sender, date, size)
SELECT id, link_id, 'hello', 'alice@example.org', '2026-08-01T10:00:00Z', 10
FROM items WHERE link_id IN ('a@x', 'b@x');
INSERT INTO mail_in_reply_to(item, position, message_id)
SELECT id, 0, 'parent@x' FROM items
WHERE collection = 'INBOX' AND link_id = 'b@x';
INSERT INTO event_summary(item, uid, summary, dtstart, dtstart_value)
SELECT id, 'ev', 'Stand-up', '20260901T090000Z', 'date-time'
FROM items WHERE link_id = 'ev';
INSERT INTO task_summary(item, uid, summary)
SELECT id, 'td', 'File the report' FROM items WHERE link_id = 'td';
INSERT INTO task_category(item, position, value)
SELECT id, 0, 'work' FROM items WHERE link_id = 'td';
INSERT INTO journal_summary(item, uid, summary)
SELECT id, 'jn', 'Notes' FROM items WHERE link_id = 'jn';
INSERT INTO contact_summary(item, uid, fn)
SELECT id, 'c1', 'Alice Example' FROM items WHERE link_id = 'c1';
INSERT INTO file_summary(item, name, media_type, size)
SELECT id, 'notes.txt', 'text/plain', 12 FROM items WHERE link_id = 'f1';
INSERT INTO item_address(item, role, position, address, name)
SELECT id, 'from', 0, 'alice@example.org', 'Alice' FROM items
WHERE collection = 'INBOX' AND link_id = 'a@x';
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role,
    origin, created_at)
VALUES ('message/rfc822', 'a@x', 'text/vcard', 'c1', 'sender', 'auto',
    '2026-11-13T00:00:00.000Z');

INSERT INTO queue(created_at, producer, collection, action, payload,
    target_collection, object_hash, attempts, error)
VALUES
    ('2026-11-13T00:00:01.000Z', 'p', 'INBOX', 'move',
     '{"v":1,"seq":1,"to":"Archive"}', 'Archive', NULL, 0, NULL),
    ('2026-11-13T00:00:02.000Z', 'p', 'INBOX', 'submit',
     '{"v":1,"source":"smtp","from":"a@example.org","rcpts":["b@example.org"]}',
     NULL, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1,
     'unconfirmed: the connection dropped'),
    ('2026-11-13T00:00:03.000Z', 'p', 'Cal', 'remove', '{"v":1,"seq":4}',
     NULL, NULL, 0, NULL);
DELETE FROM queue WHERE id = 3;
INSERT INTO receipts(id, applied_at, collection, seq) VALUES
    (90, '2026-11-12T00:00:00.000Z', 'INBOX', 1),
    (91, '2026-11-12T00:00:00.000Z', NULL, NULL);
