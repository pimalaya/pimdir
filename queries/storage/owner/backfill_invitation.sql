-- Writes the invitation re-derived from one held mail body (Annex A.1) into a
-- row written before the column existed, during reconciliation's backfill
-- (§6), a page of list_held_mail at a time. Guarded on IS NULL, so a known
-- invitation is never cleared and a second run changes nothing.
UPDATE mail_summary SET invitation = :invitation
WHERE collection = :collection AND link_id = :link_id AND invitation IS NULL;
