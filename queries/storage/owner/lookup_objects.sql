-- Resolve link ids (a JSON array) to a hydrated body hash, scoped to the
-- caller's account, the only axis a link id is trustworthy on: two unrelated
-- servers may mint the same vCard UID (§9.2), and answering across accounts
-- hands one account's body to the other's sync. A single-account store binds
-- NULL and dedups whole-store.
-- Keyed on the assigned link id, never on the identity hint it was assigned
-- from, so a minted key (§9) finds no body here and fetches its own: a missed
-- dedup rather than a wrong merge. A writer-derived key (alt:, hash:, dup:)
-- claims no identity, so two items carrying one may be two bodies, and it is
-- excluded outright (§9).
SELECT i.link_id, i.object_hash FROM items i
JOIN collections c ON c.id = i.collection
WHERE i.object_hash IS NOT NULL
  AND i.link_id IN (SELECT value FROM json_each(:links))
  AND i.link_id NOT LIKE 'alt:%' AND i.link_id NOT LIKE 'hash:%' AND i.link_id NOT LIKE 'dup:%'
  AND c.account IS :account;
