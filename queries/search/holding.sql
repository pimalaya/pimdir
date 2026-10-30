-- The placements whose indexed card holds a property (§6): :property is
-- 'phone', 'address', 'birthday' or 'photo', for has:phone, has:address,
-- has:birthday and has:photo. Every other kind records 0, so matches none.
SELECT p.collection, p.seq FROM placement p JOIN object o ON o.hash = p.hash
WHERE CASE :property WHEN 'phone' THEN o.tel WHEN 'address' THEN o.adr
                     WHEN 'birthday' THEN o.bday WHEN 'photo' THEN o.photo END = 1;
