---
cairn: log
change: a-rekey-parks-a-mass-absence
date: 2026-10-30
---

# A rekey missing most members parks

A follow-up to absence-deletes-only-from-a-complete-round, decided by the orchestrator. A rekey drops `Deleted` every old handle its listing lacks, and each other source pushes the remove, so a truncated listing of a renumbered collection cost every member it missed, the guard of SYNC §5 covering rounds alone.

- **SYNC §8** (normative): a rekey whose listing leaves more than half of the source's based bindings in the collection, at least 20, resolving to no member by link id is not written unless the run carries `accept_absences`: no drop, no upsert, the checkpoint and the generation unmoved, the absent and bound counts reported. The old checkpoint still names the old handle space, so the connector names the rekey again on the next run. Guarded by vector 89 and checks/vectors.py.
- **SYNC §5, §11** (normative): the report of a parked rekey; `parked` covers a rekey; a based binding leaves only for a rekey not parked.
- **GUIDE §11** (informative): the step, and the rekey's match order now names SYNC §8's first criterion, the base naming the fetched revision (a contradiction should-fix-before-the-freeze listed).

checks/vectors.py now resolves a rekey's listed members to link ids through summaries.json and fails a rekey dropping more than half of at least 20 bound members without `parked` ("a mass absence parks") and a parked rekey writing anything. A copy of 89 without `parked` passes the check of the morning and fails this one; the check of the morning refuses 89 itself ("only a mass absence parks", "a parked round stays open"). `nix flake check path:$PWD` passes. io-pimdir and neverest follow in their cairns.
