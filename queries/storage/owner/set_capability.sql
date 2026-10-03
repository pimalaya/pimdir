-- One row of a source's declaration (§15.6), after delete_capabilities in the
-- same transaction. `account` is the one the source syncs for, NULL in a
-- single-account store. `collection` NULL is the source-wide row; a collection
-- overrides it there alone. `support` is 'full', 'partial' or 'none', `detail`
-- what a human reads about it, or NULL.
INSERT INTO capabilities(account, source, collection, capability, support, detail)
VALUES(:account, :source, :collection, :capability, :support, :detail)
ON CONFLICT(source, ifnull(collection, ''), capability)
DO UPDATE SET account = excluded.account, support = excluded.support, detail = excluded.detail;
