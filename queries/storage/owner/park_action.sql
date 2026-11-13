-- A permanently failing action: the attempt counted, the error recorded, the
-- row skipped and visible to operators instead of blocking the collection's
-- queue for ever. A failure is never an unknown outcome: a text beginning
-- with the reserved prefix `unconfirmed: ` is recorded behind `failed: `,
-- whole, the prefix being unconfirm_action's alone to write (§15.2).
UPDATE queue SET attempts = attempts + 1,
                 error = CASE WHEN :error GLOB 'unconfirmed: *' THEN 'failed: ' || :error ELSE :error END
WHERE id = :id;
