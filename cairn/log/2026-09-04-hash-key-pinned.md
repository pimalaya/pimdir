---
cairn: log
change: hash-key-pinned
date: 2026-09-04
---

# The hash: key is pinned

Annex A.2 fixed the hash: fallback as FNV-1a 64 of the bytes while the one vector for it carried `null`, on the argument that an implementation would fail on its own vectors. It would not: nothing else checks a derived key, and two writers disagreeing on it never share a seq. event-no-uid.ics now pins the key, checks/vectors.py re-derives it, and STORAGE §16 counts it among what summaries.json binds.
