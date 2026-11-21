-- Records a public id as split when its placements name two or more
-- documents (§3), a placement's body or, while it has none, its own summary:
-- run after split_forget for each public id a batch placed or dropped (§4).
INSERT INTO split(seq) SELECT :seq
WHERE (SELECT count(DISTINCT coalesce(object, -id)) FROM placement WHERE seq = :seq) > 1;
