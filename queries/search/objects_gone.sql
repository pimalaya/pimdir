-- Bodies the collector took (STORAGE.md §5): their text goes with them.
SELECT o.hash FROM object o LEFT JOIN store.objects s ON s.hash = o.hash WHERE s.hash IS NULL;
