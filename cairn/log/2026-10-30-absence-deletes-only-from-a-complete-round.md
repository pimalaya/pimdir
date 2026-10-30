---
cairn: log
change: absence-deletes-only-from-a-complete-round
date: 2026-10-30
---

# An absence deletes only from a closed, complete round

Edit 3 of the pimdir stable-release plan. SYNC §5 forbade a `Remove` from "any absence" while §5 and §9 propagated a round's absences as tombstones, the page flags and the round paragraph carried no keyword, and nothing stopped a connector's empty or truncated listing from deleting a collection.

- **SYNC §5, which absences delete** (normative): an absence is a delete only when a closed, complete round of the source did not list a member in its scope; it drops the member `Deleted` and propagates as a tombstone every other source pushes (§9). A page before the last, an interrupted or restarted round, a head, a delta, an out-of-scope member, a band round's undated member and a parked round are none. A `Remove` comes from a tombstone the store holds and nothing else. Guarded by vectors 74 (two sources, a partial round deletes nothing anywhere), 75 (a closed round's absence tombstones the item, jmap keeping it) and 76 (jmap pushes the `Remove`), and by checks/vectors.py, which now fails any case dropping a based binding of the run's source other than for a stated removal, a tombstone, a rekey or an absence from a round the run closed, in scope and not parked.
- **SYNC §4 and §5, completeness** (normative): MUST on `complete`, `last` and the cursor; an engine refuses a page neither last nor carrying a cursor, failing the run before that page's write; a round reconciles its scope alone. Guarded by vector 79.
- **SYNC §5, the mass-absence guard** (normative): more than half of at least 20 based bindings in scope absent parks the round: nothing dropped, no `CloseRound`, the last page landed with no cursor, the counts reported; the next run relists from the first page; `accept_absences` closes it. Not stored. Guarded by vectors 77 and 78 and by checks/vectors.py.
- **SYNC §5, server collections** (normative): an engine mirroring collections deletes one on a server because another source stopped listing it only when its configuration enables it, and then only when it is empty or fully reconciled in the run. No check can hold it: the vectors run one collection.
- **SYNC §11, checks/names.sh**: the vector fields `accept_absences`, `parked`, `failed`.
- **GUIDE §10, OVERVIEW §5 and §6** (informative) follow.

The new check was run on copies of 74, 77 and 79 broken as the rule forbids (74 and 79 dropping binding 10, 77 without its `parked`): it reports "binding 10 leaves only for a stated removal or a closed round's absence in scope" and "a mass absence parks", where the check of 8b2e8b6 reported only 79's missing cursor. `nix flake check path:$PWD` passes. io-pimdir (src/sync.rs:572-577, the park, `accept_absences`) and neverest (UIDVALIDITY, DAV truncation, `collection.delete` default false) follow in their own cairns.
