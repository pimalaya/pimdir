-- The owner's manual eviction of one mail collection below a date (§11.3):
-- every live item whose `date` is older than :before (RFC 3339 Z) and that
-- owes nothing, removed with its bindings, summary and addresses by cascade.
-- An item owes something while no source binds it (the store holds its only
-- copy), it is conflicted, a binding of it is conflicted or has no base (a
-- pending create), a binding of it is a delivered create's, based under a
-- provisional handle no listing has named yet (SYNC.md §5), its flags differ
-- from a binding's base flags, both known (an unpushed flag change), or a
-- person's reference names it, which no relisting restores; such an item
-- stays. The two sets differ by a system flag's bit or by a row either holds
-- and the other lacks, each direction an anti-join on the other's key, so no
-- set is gathered to be compared. An unknown `date` is never older. No
-- tombstone and no push: the remote keeps every member, and a widening
-- relists them. Retained rows are the purge's, not this. The cascade drops
-- pins no statement returns, so recompute_refcounts follows in the same
-- transaction; the delete trigger counts each row in `purges` (§4.5). Returns
-- the seqs evicted.
DELETE FROM items
WHERE collection = :collection AND deleted = 0 AND conflicted = 0
  AND id IN (SELECT item FROM mail_summary WHERE date < :before)
  AND EXISTS (SELECT 1 FROM bindings b
              WHERE b.item = items.id)
  AND NOT EXISTS (SELECT 1 FROM bindings b
                  WHERE b.item = items.id
                    AND (b.conflicted = 1
                         OR b.base_present = 0
                         OR substr(b.handle, 1, 1) = char(1)
                         OR (items.flags_known = 1 AND b.base_flags_known = 1
                             AND (items.marks != b.base_marks
                                  OR EXISTS (SELECT 1 FROM placement_flag f
                                             WHERE f.item = items.id
                                               AND NOT EXISTS (SELECT 1 FROM binding_base_flag g
                                                               WHERE g.item = b.item
                                                                 AND g.source = b.source
                                                                 AND g.flag = f.flag))
                                  OR EXISTS (SELECT 1 FROM binding_base_flag g
                                             WHERE g.item = b.item
                                               AND g.source = b.source
                                               AND NOT EXISTS (SELECT 1 FROM placement_flag f
                                                               WHERE f.item = items.id
                                                                 AND f.flag = g.flag))))))
  AND NOT EXISTS (SELECT 1 FROM item_reference r
                  WHERE r.origin = 'user'
                    AND ((r.from_link_id = items.link_id AND r.from_kind = 'message/rfc822')
                         OR (r.to_link_id = items.link_id AND r.to_kind = 'message/rfc822')))
RETURNING seq;
