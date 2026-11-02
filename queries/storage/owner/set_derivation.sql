-- Records the Annex A revision the store's rows stand under (§6): a later
-- one in the transaction finishing its re-derivation, an earlier one in the
-- transaction an owner at that revision first writes a summary in, so the
-- next owner at a later revision re-derives what it wrote.
UPDATE store_meta SET derivation = :derivation WHERE id = 1;
