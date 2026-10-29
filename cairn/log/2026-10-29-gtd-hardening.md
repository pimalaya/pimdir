---
cairn: log
change: gtd-hardening
date: 2026-10-29
---

# A filed task is never lost, never doubled, and its readers agree

Track A of unfog's cairn/changes/gtd-hardening, with its follow-up of the same day: what the two task clients, unfog and Pimalaya Android, and their sync engine (io-pimdir, neverest) found they needed, and the providers taught (Fastmail keeps one `UID` per account, Google's CalDAV holds events alone and has no `MOVE`).

- **STORAGE §15.3, §4.3, §14** (normative): an `add` MAY carry `supersedes: { collection, seq }`, the item it replaces, a task filed into another collection renamed or not. The owner applies the add and tombstones the item in one transaction and records the pair in `supersessions` (`supersede_item`), each end cascading with its item, `rename_queue_targets` following `supersedes.collection`; the duplicate check reads the store before the tombstone, so a parked add removes nothing. `load` answers the held tombstones (`list_superseded_pending`) and, for a pending create keeping the superseded identity, the binding it may be moved from (`list_superseded_bindings`). Guarded by checks/invariants.sh: the pending supersession, its release on an accepted, withdrawn or purged create, a checkpoint-only source, the cascades and the rename; the superseded binding named for its own identity only, for this source, gone once revived or accepted.
- **SYNC §5, §11** (normative): a tombstone `list_superseded_pending` names derives no `Remove` while the superseding create is pending, so a create its server refuses never costs the item it replaces; once accepted, a plain delete. Guarded by vectors/sync/71 (held) and 72 (released), checks/vectors.py reading `supersessions`.
- **SYNC §3, §4** (normative): a `Created` placement names the member it may be moved from (Superseded), its `Add` carries it as `supersedes`, outside the change key, and a connector able to move delivers it by a `MOVE` then a write of the body, falling back to an upload on `405`, `501` or a `404` for the member; a delete of a member already gone is accepted. Guarded by vectors/sync/73 (fixture todo-inbox-filed.ics), whose push states `supersedes`; checks/vectors.py re-derives its key without it.
- **STORAGE §15.6** (normative): `x-vtodo`, source-wide or per collection, `none` refusing a VTODO landing there, read only where a row states it. Guarded by checks/invariants.sh (the capability scenarios).
- **STORAGE §14.1** (normative): `list_replied(ids)`, the bare message ids a live mail outside `sent` and `drafts` replies to. Guarded by checks/invariants.sh (one reply, one own reply, a deleted one).
- **STORAGE Annex A.4** (wording): the note on `X-` properties no longer names a bucket no client keeps.
- **GUIDE §9, §13, §14, §17** (informative): the projection and the create step name the superseded binding; the drain of a superseding add; capture, clarify and filing as an `add` superseding its source, delivered by a server-side move when the `UID` is kept; the writer rules both clients share (a task already in its state untouched, a plain category edit keeping the state, lines kept byte for byte, `DTSTAMP` restated, `LAST-MODIFIED` only where present, `CONTACT` with `ALTREP`, the category filter folded, Next by due, priority, then oldest captured). Guarded by vectors/gtd/writers.json, 18 cases over 24 fixtures, checks/vectors.py validating their shape; unfog and Android run them.

The draft number stays draft-04: it is not tagged yet. io-pimdir implements it (cairn/changes/gtd-hardening there, 8907303). checks/schema.sh, names.sh, invariants.sh and vectors.py pass (`nix flake check path:.`).
