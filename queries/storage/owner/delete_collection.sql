-- Removes a collection with everything under it: items, bindings, summaries,
-- addresses, probes, sources and queue rows cascade (§14). Retention does not
-- apply, the operator having removed the collection itself, and the pins the
-- cascade drops are settled by recompute_refcounts in the same transaction,
-- the one write that cannot know its net change. Children keep their rows
-- with `parent` set NULL.
DELETE FROM collections WHERE id = :collection;
