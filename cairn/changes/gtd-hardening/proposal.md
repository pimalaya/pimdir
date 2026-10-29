---
cairn: change
id: gtd-hardening
status: landed
created: 2026-10-28
---

# A move that cannot lose the capture, collections that refuse tasks, and the writer rules as vectors

## Why

The review of the GTD work on 2026-10-28 (unfog cairn/changes/gtd-hardening, the umbrella for this track) found three seams in what this repository states.

- **H4, a move stages the remove before the add is performed.** GUIDE §17 says "a `remove` of the source item once the `add` was performed", and nothing in the queue can say so: both consumers stage the two at once. A parked add (a live duplicate link id) or a refused push (an events-only calendar, a server enforcing UID uniqueness) still lets the remove through, and the capture is gone from every server.
- **M6, nothing says a calendar refuses VTODO.** A consumer offers every `text/calendar` collection as a task list, Google's CalDAV calendars included, and learns from a rejected push.
- **M1, the two writers of one convention disagree** on a task already in the target state, a plain category edit, `CONTACT` and `CREATED`. The decided rules are the umbrella's table; they are informative here (GUIDE §17) and checked by data both consumers run.

## What

- **`add` carrying `supersedes: {collection, seq}`** (STORAGE §15.3): applied with the superseded item's tombstone in one owner transaction, recorded in a new `supersessions` table (§4.3); the tombstone's push is held while the superseding item is a pending create (SYNC §5, `list_superseded_pending`), so a refused create keeps the source on its server. `rename_queue_targets` follows the field. invariants.sh runs the statements; vectors/sync 71 and 72 run the hold and its release.
- **`x-vtodo`** (STORAGE §15.6): `none` on a collection, or source-wide, refuses a VTODO there, read only where stated; the producer's gate and the owner's backstop read it.
- **GUIDE §17**: capture through the queue with `CREATED`, a move as one superseding `add`, the M1 writer and reader rules.
- **vectors/gtd/writers.json** and its fixtures: input VTODO, operation, `now`, expected bytes (or expected lines for a capture), validated for shape by checks/vectors.py.
- **`list_replied`** (STORAGE §14.1, GUIDE §14 and §17): which message ids a live mail replies to, for the review's "reply received" (umbrella M8), asked by unfog's track D.
- **Annex A.4**: the stale "bucket an organising client keeps" wording.

## Out

- An implementation: io-pimdir cairn/changes/gtd-hardening.
- Folding into the log and landing: the user's review comes first.
