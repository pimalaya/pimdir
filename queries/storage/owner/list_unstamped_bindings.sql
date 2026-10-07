-- The deletes a round infers when its last page lands (SYNC.md §5): the
-- based bindings of this source that no page of the open round stamped,
-- whose item's `date` falls in the round's scope, or is unknown and the
-- round lists its whole scope. A band round lists by a date filter, which
-- never returns an undated member, so its absence there proves nothing. A
-- pending create is no member of the remote and is never listed here; a
-- placement out of scope is not either, absence meaning deleted only in
-- scope. Read after the last page's own stamps, in its write.
SELECT b.handle, b.link_id
FROM bindings b
JOIN sources r ON r.collection = b.collection AND r.source = b.source
LEFT JOIN mail_summary s ON s.collection = b.collection AND s.link_id = b.link_id
WHERE b.collection = :collection AND b.source = :source
  AND r.round_started_at IS NOT NULL
  AND b.round IS NOT r.round
  AND (b.base_present = 1 OR b.base_flags IS NOT NULL
       OR b.base_object IS NOT NULL OR b.base_revision IS NOT NULL)
  AND CASE WHEN s.date IS NULL THEN r.round_band = 0
           ELSE (r.round_since IS NULL OR s.date >= r.round_since)
                AND (r.round_until IS NULL OR s.date < r.round_until) END
ORDER BY b.handle;
