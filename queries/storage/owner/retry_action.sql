-- A parked row put back among the pending ones, on a person's request and
-- never of the owner's own accord (§15.5): the error cleared, the id and the
-- attempts kept, so the next drain lists it in its place in the append order.
-- The one way an intent parked `unconfirmed: ` is performed again (§15.2).
-- Answers the id of the row it put back, and nothing for a row that is
-- pending or gone.
UPDATE queue SET error = NULL WHERE id = :id AND error IS NOT NULL RETURNING id;
