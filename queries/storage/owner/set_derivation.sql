-- Records the Annex A revision an owner re-derived the store's rows under
-- (§6), in the transaction finishing the re-derivation. Never lowers it: an
-- owner at an earlier revision leaves the store's as it is.
UPDATE store_meta SET derivation = :derivation WHERE id = 1 AND derivation < :derivation;
