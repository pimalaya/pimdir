---
cairn: log
change: fallback-keys-mint
date: 2026-09-05
---

# One key procedure for hints and fallbacks, byte order for handles, a namespace for provisional handles

STORAGE §9 returned a fallback key (`alt:`, `hash:`) from its first branch and never asked whether the collection already held it, while admitting two messages may share an `alt:` key: two `Message-ID`-less alerts in one second, or two byte-identical UID-less cards, collided on the primary key at the second insert. The hint or the fallback in its place now goes through the same free and minted branches, so the second becomes `dup:alt:...#handle`; a hint is usable when non-empty after trimming, which an empty `UID:` line no longer passes. vectors/summaries.json pins the `alt:` key on mail-no-message-id.eml, checks/vectors.py re-derives it, and sync vector 31 pins the mint over it.

Handle order decided minted keys and rekey pairing and was never defined; IMAP `"9"` and `"10"` sort differently as bytes and as numbers. SYNC §4 states byte order. A rekey meeting two old copies under one hint pairs by body hash first and handle order last, so a renumbering that swapped two resources under one `UID` no longer carries one meeting's flags and pending edit onto the other. A provisional handle is `U+0001` followed by the link id, a name no protocol hands out and one two engines derive alike, which the `Add` key then shares; the vectors write it escaped and checks/vectors.py checks it against `base_present`. A mutable resource stating another hint under its handle is keyed afresh, on the terms a changed `hash:` key already had, rather than ignored by the resolve-once rule. STORAGE §9, Annex A.1; SYNC §2, §4, §6, §8; GUIDE §11.
