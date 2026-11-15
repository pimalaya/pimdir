---
cairn: log
change: a-narrowed-round-proves-only-what-its-enumeration-lacks
date: 2026-11-15
---

# A narrowed round proves only what its enumeration lacks

Found by the live campaign of 2026-11-15: a widening band round, narrowed by Gmail's `before:` and Graph's `sentDateTime`, unbound 13 Gmail and 24 Graph messages their servers still held, CI messages dated 2026-01-01 and received in November, which the last page's enumeration listed. The prose (SYNC §5) and `list_unstamped_bindings` agreed with each other: a narrowed round found absent any member dated before `round_started_at`, whatever the enumeration. The rule's premise, that a received-date filter with its margin lists every dated member of the scope, is false for a ceiling (a `Date` behind its arrival is common: appends, imports, late deliveries) and for a floor once a `Date` runs ahead of its arrival past the margin. Proposal, with the owner's decision still open: cairn/changes/a-narrowed-round-proves-only-what-its-enumeration-lacks (status draft). The tree holds its recommended reading (a).

## Rules and their checks

- **A member the enumeration holds is never absent** (SYNC §5, STORAGE §10): a narrowed round finds absent only a member in scope whose handle `enumerated` lacks, whatever its date. Vectors 160 (a band narrowed by arrival, an old `Date` received late) and 161 (a `Date` ahead of its arrival), both failing on io-pimdir with the old statement; checks/invariants.sh "narrowed: a member the enumeration holds is never absent …" and "narrowed: a band whose upper bound read the arrival …", failing on the old statement.
- **A narrowed round handing no enumeration finds nothing absent** (SYNC §5), closing as any round and reporting what it left unlisted: the decision. Vector 107 rewritten (its 14, dated 5 October and unlisted, kept), failing on io-pimdir with the old statement; checks/invariants.sh "narrowed: a narrowed one handing no enumeration finds none absent …", failing on the old statement; checks/vectors.py's `provable` reads the enumeration alone and requires a case of each, failing on the old 107.
- **What a filter misses** (SYNC §5): no margin makes a filter on another instant than the `Date` a superset of the scope; a connector hands `enumerated` on a band round's last page too. Prose; GUIDE §10 names Gmail's `before:` and Graph's `sentDateTime lt` among the narrowings.
- `list_unstamped_bindings`: `:narrowed = 0 OR (:enumerated = 1 AND handle missing)`, parameters and columns unchanged. STORAGE §10, GUIDE §9 to §11, OVERVIEW §5, vectors/README.md and vectors 47's note follow; vectors/manifest.json restated.
- Checked on the working tree (2026-11-15): `nix flake check path:$PWD`, nine checks (161 sync cases, 259 of 259 statements). checks/tags.sh fails, SYNC.md and STORAGE.md having changed after their draft-11 tags: the bump and the tags are the owner's.

## Consumers

io-pimdir follows in its working tree (its log of 2026-11-15, same id): the spec re-vendored, the engine reading every unstamped binding of the scope and applying the page's proof itself, which keeps the empty-listing guard exact. The Android app runs io-pimdir's engine and the canonical statement it vendors, so it takes the fix with the crate; it narrows band rounds by a ceiling on Graph and JMAP and loses data today. neverest hands no enumeration on its IMAP and Gmail band rounds, which under this rule infer no delete until it does.
