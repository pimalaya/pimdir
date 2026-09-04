-- Unknown markers (NULL) never erase known ones (§13).
INSERT INTO probes(collection, source, handle, flags)
VALUES(:collection, :source, :handle, :flags)
ON CONFLICT(collection, source, handle) DO UPDATE SET
    flags = coalesce(excluded.flags, probes.flags);
