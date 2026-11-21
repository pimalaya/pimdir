-- The live placements whose system flags hold :mark (§8), one bit of the
-- store's items.marks (STORAGE §13): 1 `\Seen` for is:read, 2 `\Answered`, 4
-- `\Flagged`, 8 `\Draft`, 16 `\Deleted`, for is: or a tag: or flag: naming
-- one. Read from the store as it stands, never from the index, so it answers
-- a flag the index has yet to fold (§8.2). items_by_sort holds the bits of
-- every live row, so the walk reads that index alone, never the table.
SELECT i.collection, i.seq FROM store.items i INDEXED BY items_by_sort
WHERE i.deleted = 0 AND i.marks & :mark = :mark;
