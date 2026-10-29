-- Runs beside rename_collection (§14): a pending move or copy names its target
-- inside its payload, and a pending add the item it supersedes, neither of
-- which a foreign key cascades.
UPDATE queue SET payload = CASE action
    WHEN 'add' THEN json_set(payload, '$.supersedes.collection', :new_id)
    ELSE json_set(payload, '$.to', :new_id)
END
WHERE error IS NULL
  AND ((action IN ('move', 'copy') AND json_extract(payload, '$.to') = :collection)
       OR (action = 'add' AND json_extract(payload, '$.supersedes.collection') = :collection));
