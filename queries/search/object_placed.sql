-- Whether a placement still names a body, read once a placement left it or
-- moved off it: a body none names goes with its last placement (§4).
SELECT EXISTS (SELECT 1 FROM placement WHERE hash = :hash) AS placed;
