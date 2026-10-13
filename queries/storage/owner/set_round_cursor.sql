-- Lands a page's resume cursor, and the checkpoint the page carries when it
-- carries one (the first page for a source giving it up front, the last for
-- Graph), in the page's write (SYNC.md §5). A NULL :checkpoint keeps the one
-- an earlier page or head landed. A delta head lands the checkpoint it
-- carries with a NULL :cursor, which keeps the cursor a page landed: a head
-- never moves the round's cursor.
UPDATE sources SET round_cursor = coalesce(:cursor, round_cursor),
                   round_checkpoint = coalesce(:checkpoint, round_checkpoint)
WHERE collection = :collection AND source = :source AND round_started_at IS NOT NULL;
