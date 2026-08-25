---
cairn: log
change: spec-completeness
date: 2026-08-25
---

# The format says the things its implementations were already relying on

A review of the four repositories together (pimdir, io-replica, io-pimdir, neverest) found the format itself sound and incomplete in one direction: several rules its implementations depend on were carried in code and in nobody's prose, and thirteen of its own canonical statements were named nowhere in SPEC.md.

## What landed

- **A rebuild is licensed to rebind, and nothing else is** (§12). §10 forbids repointing a binding's `handle` and calls the legitimate case "the rebuild that drops the old spine and inserts the new one", which reads as delete-and-insert. An implementation persisting the batch as a diff sees neither: a rebuilt spine and a source holding one identity twice produce the same before and after, and only the drop's reason separates them. §12 now states that, and states that the licence is per handle, so a rebuild batch carrying a genuine duplicate still freezes that one. This was a live defect: a `UIDVALIDITY` bump froze every item of its collection in the reference implementation, under handles the server had just voided.

- **The owner lock excludes other processes and nothing inside its own** (§8). §8 makes the lock the process's and shares it across handles, which is right, and §5 then rests the collector's whole safety argument on "no writer is in flight". Between processes that holds; within one it does not, and an owner running the collector beside its own writer must serialise them itself. The acquisition and release are one operation for the same reason: an implementation that lets a handle read as released while its file description is still open refuses itself the store, reporting a conflict with no other process in it. Both were reproduced.

- **The collector names its statements, and the owner is told to run it** (§5). It walks the blob directory and asks `object_exists` about the file in front of it, on the primary key, rather than reading `list_object_hashes` whole to answer a question about one file: a store of the size §1 promises holds hundreds of thousands of them. `list_object_hashes` stays for the §7 diagnosis that visits every row anyway. And since no write reclaims, a store whose owner never collects keeps every dereferenced body for ever, so the format says whose job it is; an owner that purges is releasing bodies by definition and is the natural place.

- **A purge returns what it was pinning** (§11.2). `purge_item` and `purge_retained_before` are `DELETE ... RETURNING object_hash, conflict_object`, so the caller settles the pins with `release_pins` in the same transaction. The pins must be released by whoever deletes the rows, and asking beforehand visits every swept row twice for an answer the delete already has.

- **Thirteen canonical statements were named nowhere in SPEC.md** and now are: `park_action`, `load_parked_actions`, `list_queued_collections`, `release_pins`, `list_garbage_objects`, `delete_garbage_objects`, `list_object_hashes`, `object_exists`, `seq_for_link_any`, `bump_next_seq`, `bump_generation`, `load_generation`, `load_account`, `update_binding`. §4.4 says the statements service the operations of §14; the collector and the parked-action surface were described in prose with no statement named, which is the half of a specification an implementer cannot follow.

- **Two locks, named once** (§2). §3 called them "the owner's exclusive advisory lock" and "the producers' shared advisory lock", §5 called the second one the staging lock, §8 called them by their file names, and §2 defined neither. Both are defined in §2 now and named the same way everywhere.

- **A purge reports the rows it removed** (§11.1, §14), not "the rows it retired". Retiring is what `retain_item` does; a purge is what takes a retired row away, and the two reading alike in the one paragraph that distinguishes them was the wrong word in the wrong place.

## Verification

The reference implementation's fidelity suite gained the check that would have caught the hand edits above: every canonical statement now **prepares** against the canonical schema, not merely exists by name. This repository holds no toolchain, so io-pimdir is the only place the format's own SQL is ever loaded, and without it a spec edit naming a column the migration does not have is found by whichever consumer runs it first. Verified by injecting a typo into `queries/objects.sql` and watching it fail.

Both repositories also gained CI, having had none: io-pimdir's checks out this repository so its three spec suites run rather than skip, and this repository's runs io-pimdir's suites against the pull request. Each asserts the suites ran, since they skip silently when the sibling checkout is absent and a green run would otherwise prove nothing.

Still open, unchanged: §5 and §14's agreement about an object indexed with no referrer is settled (no write collects), and `distinct_sources` scanning `bindings` is the implementation's, not the format's.
