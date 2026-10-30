---
cairn: change
id: a-rekey-parks-a-mass-absence
status: landed
created: 2026-10-30
---

# A rekey missing most members parks

## Why

A follow-up to absence-deletes-only-from-a-complete-round, decided by the orchestrator of the pimdir stable-release effort (2026-10-30). The mass-absence guard of SYNC §5 parks a round that would drop more than half of at least 20 based bindings, but a rekey (SYNC §8) is the other listing whose absences delete: every old handle the new space lacks is dropped `Deleted`, and every other source then pushes the remove (§9). A connector answering a truncated listing of a renumbered collection, the neverest UIDVALIDITY and DAV truncation findings among them, would cost every member it missed.

## What

- SYNC §8: a rekey whose listing leaves more than half of the source's based bindings in the collection, at least 20, resolving to no member is not written unless the run carries `accept_absences`: no drop, no upsert, the checkpoint and the generation unmoved, the counts reported. The old checkpoint makes the connector name the rekey again.
- SYNC §5 and §11: the run reports a parked rekey as a parked round, `parked` in a vector.
- GUIDE §11: the step.
- checks/vectors.py: a rekey's absent bindings are the based ones no listed member resolves to by link id; a mass absence parks and a parked rekey writes nothing.
- vectors/sync/89.

## Lands in

sync-draft-05.
