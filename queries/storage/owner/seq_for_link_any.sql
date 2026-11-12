-- The public id a link id already has in a collection of the kind of
-- :collection, so one identity's placements of one kind share one (§9.1) and
-- a Message-ID spelling an event's UID draws its own. Unscoped by account
-- (§9.2), whatever the row's state. A key the writer derives (alt:, hash:,
-- dup:) states nothing and never shares (§9), so the caller runs this for none.
-- A message shares only with a row it agrees with (§9): one whose summary
-- states the :subject, :date and :sender being named, byte for byte, NULL
-- matching NULL. A row stating another, or holding no summary, is another
-- message reusing the Message-ID, and the caller draws a seq of its own. The
-- three are read for mail alone: a row of another kind agrees with anything.
-- The lowest seq, should rows that agree hold several.
SELECT held.seq FROM items AS held
JOIN collections AS there ON there.id = held.collection
JOIN collections AS here ON here.id = :collection
LEFT JOIN mail_summary AS m ON m.item = held.id
WHERE held.link_id = :link_id AND there.kind = here.kind
  AND (here.kind != 'message/rfc822'
       OR (m.item IS NOT NULL AND m.subject IS :subject AND m.date IS :date AND m.sender IS :sender))
ORDER BY held.seq
LIMIT 1;
