-- The source the user chose for an intent capability of an account, if any
-- (§15.6). A producer still checks it is among list_capability_sources: a
-- choice outlives a source that stopped declaring the capability.
SELECT source FROM performers WHERE account IS :account AND capability = :capability;
