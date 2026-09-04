-- Every source's binding of one item: where it lives and what each agreed to.
SELECT link_id, source, handle, base_flags, base_object, base_revision, base_present,
       conflicted, conflict_revision, conflict_object, shared_object
FROM bindings WHERE collection = :collection AND link_id = :link_id
ORDER BY source;
