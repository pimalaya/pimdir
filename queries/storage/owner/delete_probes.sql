-- A handle-space rebuild (§12) voids every unnamed handle at once.
DELETE FROM probes WHERE collection = :collection AND source = :source;
