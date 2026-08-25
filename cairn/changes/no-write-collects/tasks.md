---
cairn: tasks
change: no-write-collects
---

# Tasks

- [x] §5: an object at refcount zero is unreferenced, not deleted; a write MUST NOT delete the row or unlink the blob, with the streamed-body pattern it broke named.
- [x] §5: the refcount sweep and the orphan sweep become one collector, holding the owner lock and taking the staging lock exclusively; the grace period goes, and a period-prefixed temporary file is stated as not-an-orphan.
- [x] §14: steps 3 and 5 leave `write`; the commit is step 3, and the batch reclaims nothing.
- [x] §14: `collect_garbage()` named as an operation; §11.2 purge reports rows retired, not bytes.
- [x] queries/objects.sql: the garbage statements are the collector's; `list_object_hashes` added for the directory diff.
- [x] Log entry.
- [ ] **Downstream, Android**: no collector exists there, so those stores grow without bound; and the write path must stop sweeping if it does.
