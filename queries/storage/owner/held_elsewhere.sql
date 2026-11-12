-- Whether another collection of the same account holds an identity live with
-- the same body, so the drop of its last binding here is a move, not a loss
-- (§11). A retiring row with a body needs a holder carrying that body, else
-- the holder is bodiless or diverged and the row is retained. One with no
-- body is held by any live holder, a message only by one it agrees with
-- (§9): a holder whose summary states the retiring row's subject, date and
-- sender, byte for byte, NULL matching NULL. A holder stating another, or
-- either row holding no summary, is another message reusing the Message-ID,
-- and the row is retained.
SELECT 1 AS found FROM items AS held
JOIN collections AS there ON there.id = held.collection
JOIN collections AS here ON here.id = :collection
WHERE held.link_id = :link_id AND held.collection != :collection
  AND held.deleted = 0
  AND there.account IS here.account
  AND CASE
        WHEN :hash IS NOT NULL THEN held.object_hash = :hash
        WHEN here.kind != 'message/rfc822' THEN 1
        ELSE EXISTS (
          SELECT 1 FROM items AS mine
          JOIN mail_summary AS own ON own.item = mine.id
          JOIN mail_summary AS theirs ON theirs.item = held.id
          WHERE mine.collection = :collection AND mine.link_id = :link_id
            AND theirs.subject IS own.subject AND theirs.date IS own.date
            AND theirs.sender IS own.sender)
      END
LIMIT 1;
