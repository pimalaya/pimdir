-- `handle` is deliberately absent: repointing it is how a source holding one
-- identity twice used to be destroyed, silently, at the write. A write that
-- resolves this binding to another handle is refused instead (§10), the second
-- copy having a key and an item of its own (§9); a legitimate rebind goes
-- through the handle-space rebuild. Each body by its hash, written as
-- insert_item writes it (§4.4).
UPDATE bindings SET base_flags_known = :base_flags_known, base_marks = :base_marks,
       base_object = CASE WHEN :base_object IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :base_object), 0) END,
       base_revision = :base_revision, base_present = :base_present,
       conflicted = :conflicted, conflict_revision = :conflict_revision,
       conflict_object = CASE WHEN :conflict_object IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :conflict_object), 0) END,
       shared_object = CASE WHEN :shared_object IS NULL THEN NULL ELSE coalesce((SELECT id FROM objects WHERE hash = :shared_object), 0) END,
       server_object_id = :server_object_id
WHERE item = (SELECT id FROM items WHERE collection = :collection AND link_id = :link_id) AND source = :source;
