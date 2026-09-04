INSERT INTO thread(id, first, last, count) VALUES(:id, :first, :last, :count)
ON CONFLICT(id) DO UPDATE SET first = excluded.first, last = excluded.last, count = excluded.count;
