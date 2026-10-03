-- Clears one source's declaration, its collection rows included, the first
-- half of declaring it (§15.6): a declaration replaces the whole set in one
-- transaction, so a capability the source lost does not linger.
DELETE FROM capabilities WHERE source = :source;
