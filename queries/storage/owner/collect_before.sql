-- The owner's manual collection of one mail collection below a date (§11.3):
-- every live item whose `date` is older than :before (RFC 3339 Z) and that
-- owes nothing, removed with its bindings, summary and addresses by cascade.
-- An item owes something while it is conflicted, a binding of it is
-- conflicted or has no base (a pending create), or its flags differ from a
-- binding's base flags, both known (an unpushed flag change), or a person's
-- reference names it, which no relisting restores; such an item stays. An
-- unknown `date` is never older. No tombstone and no push: the remote keeps
-- every member, and a widening relists them. Retained rows are
-- the purge's, not this. The cascade drops pins no statement returns, so
-- recompute_refcounts follows in the same transaction; the delete trigger
-- counts each row in `purges` (§4.5). Returns the seqs collected.
DELETE FROM items
WHERE collection = :collection AND deleted = 0 AND conflicted = 0
  AND link_id IN (SELECT link_id FROM mail_summary
                  WHERE collection = :collection AND date < :before)
  AND EXISTS (SELECT 1 FROM bindings b
              WHERE b.collection = items.collection AND b.link_id = items.link_id)
  AND NOT EXISTS (SELECT 1 FROM bindings b
                  WHERE b.collection = items.collection AND b.link_id = items.link_id
                    AND (b.conflicted = 1
                         OR NOT (b.base_present = 1 OR b.base_flags IS NOT NULL
                                 OR b.base_object IS NOT NULL OR b.base_revision IS NOT NULL)
                         OR (items.flags IS NOT NULL AND b.base_flags IS NOT NULL
                             AND items.flags IS NOT b.base_flags)))
  AND NOT EXISTS (SELECT 1 FROM item_reference r
                  WHERE r.origin = 'user'
                    AND ((r.from_link_id = items.link_id AND r.from_kind = 'message/rfc822')
                         OR (r.to_link_id = items.link_id AND r.to_kind = 'message/rfc822')))
RETURNING seq;
