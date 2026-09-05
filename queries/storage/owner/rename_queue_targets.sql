-- Runs beside rename_collection (§14): a pending move or copy names its target
-- inside its payload, which no foreign key cascades.
UPDATE queue SET payload = json_set(payload, '$.to', :new_id)
WHERE error IS NULL AND action IN ('move', 'copy')
  AND json_extract(payload, '$.to') = :collection;
