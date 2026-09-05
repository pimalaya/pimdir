---
cairn: log
change: algorithm-audit-2026-09-04
date: 2026-09-05
---

# What porting the reference engine sent back

io-pimdir was brought onto the audited text the same night, and the port sent six corrections back into the documents, none a new rule. `lookup_objects` now joins `objects` and answers the size beside the hash, since SYNC §6's size witness cannot be applied to a hash alone. Vector 28 is a `mutate` case: an upgrade never fetches a placement whose item already holds a body, so the divergence it pins is reached by the edit settling b's binding conflict while the shared body moved through a. SYNC §5's refused delete is decided per collection from the other sources syncing it, a binding or a checkpoint (`collection_sources`), since a source whose remote dropped its last member holds no binding and still syncs; the sentence deciding it from "the bindings the run loaded" failed exactly there. STORAGE §15.2 says which source a store-wide drain applies an action as, one binding the item or syncing the collection rather than the handle draining, since neverest drains the queue with one side's handle and the other side's adds must not bind to it. SYNC §8 pairs the copies of one hint by base revision first, then body, then handle order, and says that a `Conflict` is carried as it is and that an item-level conflict gains no revision unless the remote moved: carried at the fetched revision it pinned one source on a conflict with a server that never moved, and held its pushes for ever while the other sources settled the item. SYNC §5 says only a sync reports events.

The engine reproduces the thirty-two vectors and its property suites converge; the open items of the ledger stand.
