-- Every placement of every split public id (§3), by public id then
-- collection, with the hash of its body, NULL while bodiless or once the
-- body's row is gone: what a count matching whole documents evaluates per
-- placement instead (§8.2), each body probed by match_object and each
-- summary by match_summary. CROSS JOIN walks the few split rows and seeks
-- each one's placements, never every placement.
SELECT split.seq, p.collection, o.hash FROM split
CROSS JOIN placement p ON p.seq = split.seq
LEFT JOIN object o ON o.id = p.object
ORDER BY split.seq, p.collection;
