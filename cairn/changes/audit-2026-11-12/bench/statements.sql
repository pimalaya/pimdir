-- SPDX-License-Identifier: MIT OR Apache-2.0
--
-- The statement texts the audit of 2026-11-12 timed against the canonical
-- ones (lines P1 and P2 of its ledger), each keeping its name, its parameters
-- and its columns. Candidates, not canonical text: P2's needs the scenarios
-- the ledger names before it replaces anything.

-- list_superseded_bindings (P1): the canonical text with its joins written
-- CROSS JOIN, so the plan starts from supersessions, nearly always empty,
-- rather than from every item of :collection. 23 to 32 ms against under
-- 0.1 ms at 60,000 items.
SELECT n.link_id, t.collection, b.handle, b.base_revision
FROM supersessions s
CROSS JOIN items n ON n.id = s.by_item
CROSS JOIN items t ON t.id = s.item
CROSS JOIN bindings b ON b.item = s.item AND b.source = :source AND b.base_present = 1
WHERE n.collection = :collection AND t.link_id = n.link_id
  AND n.deleted = 0 AND t.deleted = 1
  AND NOT EXISTS (SELECT 1 FROM bindings h
                  WHERE h.item = n.id AND h.source = :source AND h.base_present = 1)
ORDER BY n.link_id;

-- list_superseded_pending (P1): the same change. 4 ms against under 0.1 ms.
SELECT t.link_id
FROM supersessions s
CROSS JOIN items t ON t.id = s.item
CROSS JOIN items n ON n.id = s.by_item
WHERE t.collection = :collection AND t.deleted = 1 AND n.deleted = 0
  AND (EXISTS (SELECT 1 FROM bindings b WHERE b.item = n.id AND b.base_present = 0)
       OR (n.object_hash IS NOT NULL
           AND EXISTS (SELECT 1
                       FROM (SELECT source FROM sources WHERE collection = n.collection
                             UNION
                             SELECT source FROM bindings WHERE collection = n.collection) c
                       WHERE NOT EXISTS (SELECT 1 FROM bindings b
                                         WHERE b.item = n.id AND b.source = c.source))))
ORDER BY t.link_id;

-- list_owing_bindings (P2): the two flag sets compared by two anti-joins on
-- the keys of placement_flag and binding_base_flag, where the canonical text
-- builds a temporary b-tree per binding for each EXCEPT. 120 to 140 ms
-- against 24 to 25 ms at 59,691 bindings, the same handles, on SQLite 3.51.2
-- and on the 3.18.2 floor. collect_before holds the same compound.
SELECT b.handle FROM bindings b JOIN items i ON i.id = b.item
WHERE b.collection = :collection AND b.source = :source
  AND (b.conflicted = 1 OR i.conflicted = 1 OR i.deleted = 1
       OR NOT (b.base_present = 1 OR b.base_flags_known = 1
               OR b.base_object IS NOT NULL OR b.base_revision IS NOT NULL)
       OR (i.flags_known = 1 AND b.base_flags_known = 1
           AND (i.marks != b.base_marks
                OR EXISTS (SELECT 1 FROM placement_flag f
                           WHERE f.item = i.id
                             AND NOT EXISTS (SELECT 1 FROM binding_base_flag g
                                             WHERE g.item = b.item AND g.source = b.source
                                               AND g.flag = f.flag))
                OR EXISTS (SELECT 1 FROM binding_base_flag g
                           WHERE g.item = b.item AND g.source = b.source
                             AND NOT EXISTS (SELECT 1 FROM placement_flag f
                                             WHERE f.item = i.id AND f.flag = g.flag))))
       OR (i.object_hash IS NOT NULL AND i.object_hash IS NOT b.base_object))
ORDER BY b.handle;
