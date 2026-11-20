---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine, eighth part: rekey

The eighth part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan. No part of the standard moves.

- **The handle-space epoch** (generator/src/model.rs, writer.rs, oracle.rs, STORAGE §12): a collection holds its `generation`, from 1; the writer bumps it with `bump_generation`, and the oracle states it for `load_generation` and the collection listings.
- **A renumbering source** (generator/src/remote.rs): `Remote::renumber` hands every member a new handle in arrival order from a given number, as a `UIDVALIDITY` bump or a restore does, forgetting the removals the old space stated.
- **The rekey** (generator/src/engine.rs, SYNC §8): one round over the whole collection, read before its one write. Each based binding of the source is carried onto the member resolving to its link id, a minted key included (the copy whose base names the listed revision first, then the one whose base holds the carried body, then in old handle order), its flags, base and pending state kept. A member of a mutable kind listed at another revision is pulled to `Meta`, its base at that revision naming no body, or recorded in conflict at it over a local edit, the base untouched. A binding no member resolves to is dropped `Deleted` though the new space reuses its handle. A pending create stays outside the rekey. The generation is bumped and the checkpoint lands; the coverage stays. A rekey missing more than half of at least 20, naming no member while any is missing, or capped while any is, writes nothing and parks with the absent and the bound counts, unless the run accepts absences.
- **An upgrade no item conflict waits on** (SYNC §6, vector 133): the body read only moves the base; the collection's policy is met by an item conflict waiting for that body alone. The model had recorded a conflict there.
- **A history** of a mailbox renumbered from one with its first message gone, then renumbered carrying every message and a copy under a minted key, a delta in the new space, a rekey missing most messages parked then accepted, a capped one parked; and an address book renumbered over a server edit and one made on both sides, then an edit over the card pulled unread, its upgrade reading the base, and its push.
- **Checks**: tests state each rule above from SYNC; every step's store is written and self-checked. Broken by hand to see each fail: no generation bump, an absent binding kept, no park on a mass absence, a capped rekey written, a server edit ignored, two copies matched the wrong way round, an upgrade no conflict waits on recording one.
