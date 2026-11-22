-- SPDX-License-Identifier: MIT OR Apache-2.0
--
-- A released version 1 store holding at least one row in every table, for the
-- rehearsal migrations of this directory (STORAGE.md §6). Plain SQL, no
-- canonical statement, so the 3.18.2 floor runs it too. The last queue row,
-- the last item and the last object are deleted again, so the three
-- AUTOINCREMENT sequences stand above every id their tables still hold.
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

INSERT INTO objects(id, hash, size, refcount) VALUES
    (1, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 10, 3),
    (2, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 20, 1),
    (3, 'cccccccccccccccccccccccccccccccccccccccccccccccccccc', 30, 0);
DELETE FROM objects WHERE id = 3;

INSERT INTO items(collection, link_id, seq, flags_known, marks, keywords,
    object, sort_key, level)
VALUES
    ('INBOX', 'a@x', 1, 1, 1, '$label', 1, '2026-08-01T10:00:00Z', 2),
    ('INBOX', 'b@x', 2, 1, 0, '', NULL, '2026-08-02T10:00:00Z', 1),
    ('Archive', 'a@x', 1, 0, 0, '', NULL, '2026-08-01T10:00:00Z', 1),
    ('Cal', 'ev', 3, 0, 0, '', NULL, '2026-09-01T09:00:00Z', 1),
    ('Cal', 'td', 4, 0, 0, '', NULL, '', 1),
    ('Cal', 'jn', 5, 0, 0, '', NULL, '', 1),
    ('Cards', 'c1', 6, 0, 0, '', 2, 'alice', 2),
    ('Files', 'f1', 7, 0, 0, '', NULL, 'notes.txt', 1),
    ('INBOX', 'gone@x', 8, 0, 0, '', NULL, '', 1),
    ('INBOX', 'last@x', 9, 0, 0, '', NULL, '', 1);
UPDATE items SET deleted = 1, retained_at = '2026-11-01T00:00:00.000Z',
    retained_by = 'imap'
WHERE link_id = 'gone@x';
DELETE FROM items WHERE link_id = 'last@x';

INSERT INTO bindings(item, collection, source, handle, base_flags_known,
    base_marks, base_keywords, base_object, base_revision, base_present,
    shared_object, round)
SELECT id, collection, 'imap', '10', 1, 1, '$label', 1, NULL, 1, NULL, 1
FROM items WHERE collection = 'INBOX' AND link_id = 'a@x';
INSERT INTO bindings(item, collection, source, handle)
SELECT id, collection, 'imap', char(1) || 'b@x'
FROM items WHERE collection = 'INBOX' AND link_id = 'b@x';
INSERT INTO supersessions(item, by_item)
SELECT (SELECT id FROM items WHERE collection = 'Cal' AND link_id = 'td'),
       (SELECT id FROM items WHERE collection = 'Cal' AND link_id = 'jn');

INSERT INTO summary(item, component, uid, title, sender, date, size)
SELECT id, 'mail', link_id, 'hello', 'alice@example.org', '2026-08-01T10:00:00Z', 10
FROM items WHERE link_id IN ('a@x', 'b@x');
INSERT INTO summary_value(item, role, position, value)
SELECT id, 'in-reply-to', 0, 'parent@x' FROM items
WHERE collection = 'INBOX' AND link_id = 'b@x';
INSERT INTO summary(item, component, uid, title, dtstart, dtstart_value)
SELECT id, 'event', 'ev', 'Stand-up', '20260901T090000Z', 'date-time'
FROM items WHERE link_id = 'ev';
INSERT INTO summary(item, component, uid, title)
SELECT id, 'task', 'td', 'File the report' FROM items WHERE link_id = 'td';
INSERT INTO summary_value(item, role, position, value)
SELECT id, 'category', 0, 'work' FROM items WHERE link_id = 'td';
INSERT INTO summary(item, component, uid, title)
SELECT id, 'journal', 'jn', 'Notes' FROM items WHERE link_id = 'jn';
INSERT INTO summary(item, component, uid, title)
SELECT id, 'contact', 'c1', 'Alice Example' FROM items WHERE link_id = 'c1';
INSERT INTO summary(item, component, title, media_type, size)
SELECT id, 'file', 'notes.txt', 'text/plain', 12 FROM items WHERE link_id = 'f1';
INSERT INTO summary_value(item, role, position, value, name)
SELECT id, 'from', 0, 'alice@example.org', 'Alice' FROM items
WHERE collection = 'INBOX' AND link_id = 'a@x';
INSERT INTO item_reference(from_kind, from_link_id, to_kind, to_link_id, role,
    origin, created_at)
VALUES ('message/rfc822', 'a@x', 'text/vcard', 'c1', 'sender', 'auto',
    '2026-11-13T00:00:00.000Z');
INSERT INTO item_property(seq, key, value)
SELECT seq, 'pimdir/label', 'Receipts' FROM items
WHERE collection = 'INBOX' AND link_id = 'a@x';

INSERT INTO queue(created_at, producer, collection, action, payload,
    target_collection, object, attempts, error)
VALUES
    ('2026-11-13T00:00:01.000Z', 'p', 'INBOX', 'move',
     '{"v":1,"seq":1,"to":"Archive"}', 'Archive', NULL, 0, NULL),
    ('2026-11-13T00:00:02.000Z', 'p', 'INBOX', 'submit',
     '{"v":1,"source":"smtp","from":"a@example.org","rcpts":["b@example.org"]}',
     NULL, 1, 1,
     'unconfirmed: the connection dropped'),
    ('2026-11-13T00:00:03.000Z', 'p', 'Cal', 'remove', '{"v":1,"seq":4}',
     NULL, NULL, 0, NULL);
DELETE FROM queue WHERE id = 3;
INSERT INTO receipts(id, applied_at, collection, seq) VALUES
    (90, '2026-11-12T00:00:00.000Z', 'INBOX', 1),
    (91, '2026-11-12T00:00:00.000Z', NULL, NULL);
