-- Clears the refusal standing on this source's binding under :handle (SYNC.md
-- §5), in the write recording that binding's next accepted push, before the
-- write moves the binding: what the remote refused is no longer what it holds.
-- A binding standing under no refusal, or none under that handle, is left as
-- it is. Seeks bindings_by_handle.
UPDATE bindings SET refusal = NULL, refused_key = NULL, refused_at = NULL
WHERE collection = :collection AND source = :source AND handle = :handle
  AND refusal IS NOT NULL;
