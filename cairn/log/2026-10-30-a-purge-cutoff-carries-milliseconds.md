---
cairn: log
change: a-purge-cutoff-carries-milliseconds
date: 2026-10-30
---

# A purge cutoff carries milliseconds

STORAGE §11.2 now says a `purge_retained_before` cutoff MUST be written as the stamps are (`%Y-%m-%dT%H:%M:%fZ`): the comparison is textual and a second-precision cutoff sorts after every stamp of its own second. Closes the algorithm-audit-2026-09-04 ledger line on millisecond stamps. Lands in storage-draft-05.
