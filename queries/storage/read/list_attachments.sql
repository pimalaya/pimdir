-- The files a message attaches (§14.3): its `attachment` references, each
-- read from a live placement in the account's file collections (:account,
-- NULL for a single-account store), in the order their public ids were drawn,
-- which is document order when the writer walks the parts in it. One row per
-- file: the placement holding no body wins, it being the one standing for the
-- part (`min()` picks the row the bare columns are read from), and
-- `object_hash` is any placement's body, so a file saved to a folder reads
-- as held.
SELECT link_id, collection, seq, name, media_type, size, part, object_hash
FROM (
  SELECT r.to_link_id AS link_id, i.collection, i.seq, s.name, s.media_type, s.size, s.part,
         (SELECT h.object_hash FROM items h JOIN collections hc ON hc.id = h.collection
          WHERE h.link_id = r.to_link_id AND h.deleted = 0 AND h.object_hash IS NOT NULL
            AND hc.kind = 'application/octet-stream'
          LIMIT 1) AS object_hash,
         min(i.object_hash IS NOT NULL)
  FROM item_reference r
  JOIN items i ON i.link_id = r.to_link_id AND i.deleted = 0
  JOIN collections c ON c.id = i.collection AND c.kind = r.to_kind AND c.account IS :account
  LEFT JOIN file_summary s ON s.collection = i.collection AND s.link_id = i.link_id
  WHERE r.from_kind = 'message/rfc822' AND r.from_link_id = :link_id
    AND r.role = 'attachment' AND r.to_kind = 'application/octet-stream'
  GROUP BY r.to_link_id
)
ORDER BY seq, link_id;
