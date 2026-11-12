-- Resolve link ids (the `links` slot) to a hydrated body hash, scoped to the
-- caller's account, the only axis a link id is trustworthy on: two unrelated
-- servers may mint the same vCard UID (§9.2), and answering across accounts
-- hands one account's body to the other's sync. A single-account store binds
-- NULL and dedups whole-store.
-- Keyed on the assigned link id, never on the identity hint it was assigned
-- from, so a minted key (§9) finds no body here and fetches its own: a missed
-- dedup rather than a wrong merge. A writer-derived key (alt:, hash:, dup:)
-- claims no identity, so two items carrying one may be two bodies, and it is
-- excluded outright (§9).
-- The size and the row's subject, date and sender ride along as the witnesses
-- a link needs (§9, SYNC.md §6): a body is adopted only from a row agreeing
-- with the member on the three, and on the size where the member states one,
-- since a message reusing a Message-ID in another collection is another
-- body. The three are NULL together for a row with no mail summary, which a
-- message agrees with never. One row per holder, so the caller picks one
-- that agrees.
SELECT i.link_id, i.object_hash, o.size, m.subject, m.date, m.sender FROM items i
JOIN collections c ON c.id = i.collection
JOIN objects o ON o.hash = i.object_hash
LEFT JOIN mail_summary m ON m.item = i.id
WHERE i.object_hash IS NOT NULL
  AND i.link_id IN (SELECT value FROM temp.param WHERE slot = 'links')
  AND NOT (i.link_id GLOB 'alt:*' OR i.link_id GLOB 'hash:*' OR i.link_id GLOB 'dup:*')
  AND c.account IS :account;
