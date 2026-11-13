-- An intent whose outcome is unknown (§15.2): its performer sent the request
-- and cannot tell whether it took effect. The attempt counted, the row parked
-- under the reserved prefix `unconfirmed: `, which this statement alone
-- writes, then the detail, free text. Never an action the owner applies
-- itself, whose apply commits or does not (§15.3). Answers the id of the row
-- it parked, and nothing for a row that is gone or is such an action.
UPDATE queue SET attempts = attempts + 1, error = 'unconfirmed: ' || coalesce(:detail, '')
WHERE id = :id AND action NOT IN ('add', 'set-flags', 'remove', 'move', 'copy', 'update', 'set-performer')
RETURNING id;
