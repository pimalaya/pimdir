---
cairn: log
change: a-binding-conflict-persists-its-body
date: 2026-08-28
---

# A binding's unresolved conflict carries the body it diverged from

§13 recorded a binding's unresolved conflict as `conflicted` plus `conflict_revision`, the remote revision observed when the two sides parted. That is enough for the sync layer, which can fetch what the revision names. It is not enough for anything else: resolution is a person's decision, taken in an editor days later, and the format's own promise is that a store answers offline. Naming a body a resolver must go to the server for puts credentials in a tool that has no business holding them.

## What changed

`bindings.conflict_object` (TEXT, nullable, `REFERENCES objects(hash)`) holds the diverging remote body at `conflict_revision`. Its lifetime is the revision's: a binding that is not conflicted MUST NOT carry one, because a body outliving its revision describes a version the remote no longer holds. With it, base, local and remote all read off one row, which is what makes resolution a pure function over bytes the store already has.

It is a reference like any other, so it is counted. §5's refcount invariant now spans five pointer columns rather than four, `recompute_refcounts` gathers the fifth into its `UNION ALL`, and two indexes join the schema: `bindings_by_conflict_object`, so the recomputation reaches the new pointer by index rather than by scanning bindings once per object, and `bindings_conflicted`, partial on the flag.

That counting is the load-bearing half. An object no column names is at refcount zero from the moment it lands, so an uncounted conflict body is taken by the first collection after the run that recorded it, which is exactly the interval the column exists to span. The loss would be silent: a revision naming bytes nobody holds, and a resolver with nowhere to go but the server.

## The listing

`list_conflicted_bindings(account)` is new in §14.1. The flag was in the schema and in no read: it came back with its row and nothing ever filtered on it, so "what is waiting for a decision" cost a pass over every collection. A sync reports that number at the end of every run, so the format now requires a store to answer it without paging, and states what the answer carries: each binding by its collection, link id, source and handle, and the three body hashes the divergence is between.

## Not changed

The cross-source axis, `items.conflicted` / `items.conflict_object`, is untouched and still independent. One says a source and its own server disagree, the other that two sources do.

Version 1 is still a draft, so the column is folded into `migrations/0001_init.sql` rather than numbered as version 2, on the §6 allowance. An implementation reconciles an earlier-draft store on open, as it already does for the columns folded in before this one. Note for anyone doing so by `ALTER TABLE`: SQLite refuses to drop a column a partial index names, so the two indexes above have to be created after the column and dropped before it.
