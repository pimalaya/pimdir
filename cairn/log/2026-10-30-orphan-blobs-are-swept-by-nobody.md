---
cairn: log
change: orphan-blobs-are-swept-by-nobody
date: 2026-10-30
---

# The orphan sweep's grace period is superseded by the staging lock

A correction to cairn/log/2026-08-25-orphan-blobs-are-swept-by-nobody.md, written at ledger-housekeeping-2026-10-30 since log entries are immutable. That entry made the orphan sweep skip files younger than a grace period, so a blob a producer had written and not yet referenced was not unlinked under it. The grace period is no longer the rule: since owner-lock-must (2026-08-25) a producer holds the staging lock on objects.lock shared across its blob write and the enqueue that pins it, and the collector takes that lock exclusively (STORAGE §5, §8), which proves no process is between a body and its row; STORAGE §14 says the writer's lock, not the file's age, keeps a collector out of the window. Only a period-prefixed temporary file is still left alone. An implementation keeping a grace period as well loses nothing but disk.
