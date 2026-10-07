-- One collection's coverage per source, and the round each has under way
-- (`round_started_at` NULL is none), for a reader saying "mail since" per
-- account or showing a first sync filling in (§14.1).
SELECT source, covered_since, covered_until, covered_at,
       round_started_at, round_since, round_until
FROM sources WHERE collection = :collection ORDER BY source;
