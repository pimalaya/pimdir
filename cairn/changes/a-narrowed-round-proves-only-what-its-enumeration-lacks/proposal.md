---
cairn: change
id: a-narrowed-round-proves-only-what-its-enumeration-lacks
status: draft
created: 2026-11-15
---

# A narrowed round proves only what its enumeration lacks

## Why

The live campaign of 2026-11-15 lost data on the replica. After `neverest sync --since 30d`, the unscoped sync's widening round (a band ending 2026-10-16) unbound 13 Gmail messages and 24 Graph messages the servers still hold: CI messages whose `Date` is 2026-01-01 but which the provider received or stamped in November. The connectors narrowed the band by the provider's date filter (Gmail's `before:` reads the arrival, Graph's `sentDateTime` the submission), so the band's pages did not list them, and the last page handed the unnarrowed enumeration, which did list them. They were dropped all the same.

What the prose said, and the statement with it, sync-draft-11 and storage-draft-11:

- SYNC §5 "A narrowed listing proves only what its filter could list": a round whose last page is `narrowed` MUST find absent only a member whose `date` is known and earlier than `round_started_at`, "which its filter, taken with its margin, could list"; an undated member, or one dated at or after that instant, only when `enumerated` lacks its handle.
- queries/storage/owner/list_unstamped_bindings.sql wrote exactly that: `:narrowed = 0 OR s.date < r.round_started_at OR (:enumerated = 1 AND handle missing)`.

So the SQL matched the prose, and the prose contradicted itself. Its own premise is false: a filter on another instant than the `Date` lists no superset of a scope by the `Date`, whatever its margin. The same section says a received-date filter misses "one whose `Date` runs ahead of its arrival", and §4 tells a connector to hand `enumerated` precisely so the engine finds an absence "in scope, counted and parked as any other"; yet a member dated before the round opened was found absent whatever the enumeration said. Two classes of member are exposed:

- **A `Date` behind its arrival past a ceiling.** A band, or any scope with an `until`, narrowed by `received < until + margin` misses every message received after that ceiling whose `Date` lies before `until`: a message appended or imported (IMAP `APPEND` stamps the arrival now), delivered late, resent with its old `Date` (the CI messages). This is common, not an edge, and no margin covers it, the gap between the `Date` and the arrival being unbounded.
- **A `Date` ahead of its arrival past a floor.** A scope narrowed by `received >= since - 2 days` misses a message dated in the scope but received before the window (a sender's clock running weeks fast). S4 of audit-2026-10-31 recorded it as "still the margin's assumption"; the assumption holds for most mail and fails silently for the rest.

Neverest avoids the first class for now by not narrowing band rounds by their ceiling; the Android app does narrow them (Graph `sentDateTime lt until`, JMAP `before:`), and both build on the same statement, vendored by io-pimdir.

## What

1. **A member the enumeration holds is never absent** (SYNC §5): a round whose last page is `narrowed` finds absent only a member in its scope whose handle the `enumerated` list that page hands lacks, whatever its `date`. The enumeration is the source stating what it holds, read with no filter; the filter's silence says only that the filter's own date fell outside its window.
2. **A narrowed round handing no enumeration finds no member absent** (SYNC §5): a removal is applied there only when the source states it; the round closes as any round does, and an engine SHOULD report the based bindings it left unlisted, as a capped round does. This is the decision below.
3. **The statement** (queries/storage/owner/list_unstamped_bindings.sql): `:narrowed = 0 OR (:enumerated = 1 AND NOT EXISTS (handle in the slot))`. `round_started_at` no longer decides an absence; it still dates a band head (SYNC §4, §5). Parameters and columns unchanged, its effect changed.
4. **The prose around it**: §5 "A narrowed listing says so" names the two classes a filter misses and asks a connector to hand `enumerated` on a band round's last page too, saying that a narrowed round handing none deletes nothing by absence; the margin paragraph no longer calls a received-date narrowing "a superset of the scope"; §5's list of what is no absence names a member the enumeration holds. STORAGE §10's round bullet, GUIDE §9 to §11 and OVERVIEW §5 follow.

## Decision (the owner's)

Item 2 changes what a tagged draft infers, beyond restoring what the prose meant: under sync-draft-11 a narrowed round without an enumeration dropped a dated member it did not list (vector 107 dropped 14). Three readings:

- **(a) Nothing absent without an enumeration** (recommended, implemented). A filter's silence proves nothing whichever bound it narrows, and the format never knows which bound, nor which instant, a connector's filter read. Every connector the guide names can enumerate cheaply: IMAP `UID SEARCH ALL`, JMAP `Email/query` by `inMailbox`, Graph's ids with `$select=id`, Gmail's `messages.list` by label. A connector that hands none loses only the inference, never a message: deltas and stated removals still delete. It is the rule a capped round already follows, and the owner's standing one: a silent loss is never acceptable, report instead.
- **(b) Keep the old inference for a scope with no `until`.** A floor-only narrowing misses only a `Date` ahead of its arrival by more than the margin; the engine could keep dropping a dated member there. It keeps vector 107 as it was, but rests on an assumption the format cannot check, and on the engine trusting that a connector narrowing an open scope used no ceiling.
- **(c) Change item 1 alone.** Leaves every connector that does not enumerate (neverest's IMAP and Gmail band rounds today) exposed to both classes.

Taking (a) rewrites vector 107 (its 14 now kept and reported) and costs the connectors that narrow without enumerating their band-round deletes until they hand `enumerated`: neverest's IMAP and Gmail connectors hand it only off a band (`narrowed && !band`), the Android app on every narrowed last page.

## Versions

Both parts changed after their tags: SYNC.md and vectors/sync/ (sync-draft-11), and two statements of queries/storage/ with STORAGE.md (storage-draft-11, the other change of this day, a-pending-create-is-withdrawn-whatever-the-rights, included). checks/tags.sh fails until the owner bumps them (sync-draft-12, storage-draft-12, their Status lines, README, AGENTS.md and the version texts of SYNC §10, STORAGE §4.2 and §17) and tags them. Left undone here, as asked. A bump refuses every store and sync state of draft-11 (STORAGE §4.2, SYNC §10): the apps rebuild their stores, as at every draft so far. An engine on the new statement and an engine on the old one infer different deletes from one store, which is what the sync bump is for.

## Lands in

The working tree of 2026-11-15, uncommitted: SYNC.md, STORAGE.md, GUIDE.md, OVERVIEW.md, queries/storage/owner/list_unstamped_bindings.sql, vectors/sync/107 (rewritten), 160 and 161 (new), 47 (note), vectors/README.md, vectors/manifest.json, checks/invariants.sh, checks/vectors.py. io-pimdir follows in its working tree (its cairn/changes/a-narrowed-round-proves-only-what-its-enumeration-lacks); checks/io-pimdir.rev moves once both are committed.
