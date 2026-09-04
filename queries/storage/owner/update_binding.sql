-- `handle` is deliberately absent: repointing it is how a source holding one
-- identity twice used to be destroyed, silently, at the write. A write that
-- resolves this binding to another handle is refused instead (§10), the second
-- copy having a key and an item of its own (§9); a legitimate rebind goes
-- through the handle-space rebuild.
UPDATE bindings SET base_flags = :base_flags, base_object = :base_object,
       base_revision = :base_revision, base_present = :base_present,
       conflicted = :conflicted, conflict_revision = :conflict_revision,
       conflict_object = :conflict_object, shared_object = :shared_object
WHERE collection = :collection AND link_id = :link_id AND source = :source;
