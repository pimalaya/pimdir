-- When the handle is named, dropped by its source, or superseded.
DELETE FROM probes WHERE collection = :collection AND source = :source AND handle = :handle;
