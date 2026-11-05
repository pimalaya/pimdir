ALTER TABLE items ADD COLUMN marks INTEGER NOT NULL DEFAULT 0;
UPDATE items SET marks = (EXISTS (SELECT 1 FROM placement_flag f WHERE f.collection = items.collection AND f.link_id = items.link_id AND f.flag = '\Seen'))
  | ((EXISTS (SELECT 1 FROM placement_flag f WHERE f.collection = items.collection AND f.link_id = items.link_id AND f.flag = '\Flagged')) << 1);
CREATE INDEX items_by_sort_marks ON items(collection, sort_key, seq, marks) WHERE deleted = 0;
CREATE INDEX items_unread ON items(collection, sort_key) WHERE deleted = 0 AND marks & 1 = 0;
ANALYZE;
.timer on
.print === count seen=0 by EXISTS (canonical)
SELECT count(*) FROM items i WHERE i.collection IN ('acct/INBOX') AND i.deleted = 0
  AND 0 = EXISTS (SELECT 1 FROM placement_flag f WHERE f.collection = i.collection AND f.link_id = i.link_id AND f.flag = '\Seen')
  AND i.sort_key >= '';
.print === count seen=0 by marks, covering index
SELECT count(*) FROM items i WHERE i.collection IN ('acct/INBOX') AND i.deleted = 0 AND i.sort_key >= '' AND (i.marks & 1) = 0;
.print === count unread by the partial unread index
SELECT count(*) FROM items i WHERE i.collection IN ('acct/INBOX') AND i.deleted = 0 AND i.marks & 1 = 0;
.print === count by day, marks covering index
SELECT count(*) FROM (SELECT date(nullif(sort_key, ''), '0 minutes') AS day, count(*) FROM items WHERE collection IN ('acct/INBOX') AND deleted = 0 AND sort_key >= '' GROUP BY day);
.print === unread page by the partial unread index (walk)
SELECT count(*) FROM (SELECT seq FROM items WHERE collection = 'acct/INBOX' AND deleted = 0 AND marks & 1 = 0 ORDER BY sort_key DESC LIMIT 50);
.timer off
EXPLAIN QUERY PLAN SELECT count(*) FROM items i WHERE i.collection IN ('acct/INBOX') AND i.deleted = 0 AND i.sort_key >= '' AND (i.marks & 1) = 0;
EXPLAIN QUERY PLAN SELECT count(*) FROM items i WHERE i.collection IN ('acct/INBOX') AND i.deleted = 0 AND i.marks & 1 = 0;
