-- The probes of a Handles load (§14): :handles is a JSON array of the handles
-- asked for, so an upgrade over a freshly enumerated mailbox reads its batch
-- and not every unnamed handle the source holds.
SELECT handle, flags FROM probes
WHERE collection = :collection AND source = :source
  AND handle IN (SELECT value FROM json_each(:handles));
