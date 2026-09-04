-- One source's unnamed handles, read beside the named ones (SYNC.md §3).
SELECT handle, flags FROM probes WHERE collection = :collection AND source = :source;
