-- Ordered by sort_order then id, the ones carrying no sort order last. The
-- merged view reads exactly this and groups on `account`.
SELECT id, account, kind, name, parent, color, description, sort_order, generation
FROM collections ORDER BY sort_order IS NULL, sort_order, id;
