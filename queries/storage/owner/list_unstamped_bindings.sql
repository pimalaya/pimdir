-- The deletes a round infers when its last page lands (SYNC.md §5): the
-- based bindings of this source that no page of the open round stamped,
-- whose item's `date` falls in the round's scope, or is unknown and the
-- round lists its whole scope. A band round lists by a date filter, which
-- never returns an undated member, so its absence there proves nothing. A
-- round whose listing a date filter narrowed (:narrowed 1, SYNC.md §4) proves
-- the absence only of what its filter could list: a member dated before the
-- round opened. An undated member, or one dated at or after that instant, is
-- absent there only when the connector enumerated the collection's handles
-- unfiltered (:enumerated 1, the enumeration in the `handles` slot) and that
-- enumeration lacks its handle. A pending create is no member of the remote
-- and is never listed here, nor is a delivered one (SYNC.md §2), based under a
-- provisional handle no listing names; a placement out of scope is not either,
-- absence meaning deleted only in scope. Read after the last page's own
-- stamps, in its write.
SELECT b.handle, i.link_id
FROM bindings b
JOIN items i ON i.id = b.item
JOIN sources r ON r.collection = b.collection AND r.source = b.source
LEFT JOIN mail_summary s ON s.item = b.item
WHERE b.collection = :collection AND b.source = :source
  AND r.round_started_at IS NOT NULL
  AND b.round IS NOT r.round
  AND substr(b.handle, 1, 1) != char(1)
  AND b.base_present = 1
  AND CASE WHEN s.date IS NULL THEN r.round_band = 0
           ELSE (r.round_since IS NULL OR s.date >= r.round_since)
                AND (r.round_until IS NULL OR s.date < r.round_until) END
  AND (:narrowed = 0
       OR s.date < r.round_started_at
       OR (:enumerated = 1
           AND NOT EXISTS (SELECT 1 FROM temp.param p
                           WHERE p.slot = 'handles' AND p.value = b.handle)))
ORDER BY b.handle;
