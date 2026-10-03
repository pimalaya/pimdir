-- Records the source the user chose to perform an intent capability for an
-- account, applying a `set-performer` action (§15.6). The conflict target is the
-- expression index, so NULL is the account of a single-account store.
INSERT INTO performers(account, capability, source)
VALUES(:account, :capability, :source)
ON CONFLICT(ifnull(account, ''), capability) DO UPDATE SET source = excluded.source;
