---
cairn: log
change: a-binding-persists-its-agreement-point
date: 2026-08-28
---

# A binding records two agreement points, one per axis

§10 had a binding record one base, "the last state agreed with that source", and the sync model asked two questions of it. What did this source last agree with its own **remote**, which is what makes a pending push derivable, and what did it last agree with the **shared item**, which is what a cross-source divergence is measured from. Only a sync moves the first, so a body a source folded in and has not pushed yet leaves it behind the shared body: the same gap another source folding in leaves, and the format gave an implementation no way to tell the two apart.

The consequence was a lost edit, not a mis-report. A second offline edit reads as two sources disagreeing in a store that has one, and so does the edit resolving a conflict, whose merged body then never becomes the item's and is pushed over by the body it replaced on the next run.

## What changed

`bindings.shared_object` (TEXT, nullable) holds the shared body this source last reconciled against. §10 now states both bases and why neither can serve for the other, §4.3 carries it in the table's prose, and §13 gives its encoding.

It is **not** gated on `conflicted`, unlike the two conflict columns: it describes the ordinary state of an ordinary binding, and a binding cleared of its conflict is exactly the one whose agreement point the resolving edit is measured against.

It names an object and MUST NOT be counted, which §5 now says in as many words, because the rule beside it is that every pointer at a hash is counted and an implementer following that rule here would be wrong rather than merely wasteful. The value is only ever compared for equality, never read as bytes, and a content hash compares the same after the body it named has been swept. Counting it would pin every body a source ever agreed with for the life of the binding.

## The backfill, which §6 now requires generally

Version 1 is still a draft, so the column is folded into migrations/0001_init.sql rather than numbered as version 2, and an implementation reconciles an earlier-draft store on open as it already does for the columns folded in before this one. That is not enough here, and the gap generalises: an added column is a statement about rows written before it, and one whose empty value contradicts them is worse than a missing column, which at least fails visibly.

A binding left empty reads as never having folded, the sync base stands in for it, and a store carrying an unpushed edit has that base behind the shared body by construction. The first absorb after the upgrade would file the source's own next edit as a divergence: one silent lost edit per pending push, on the run that upgrades. So §6 now requires a reconciled column to be backfilled wherever `NULL` is not the value the existing rows already imply, in the same transaction as the `ALTER TABLE`, and queries/bindings.sql carries `backfill_shared_object`, which sets each binding from its item's own `object_hash`.

## Not changed

`list_conflicted_bindings` (§14.1) is untouched. It names the three bodies a resolver merges; the agreement point is which of them a source last saw, which is the engine's bookkeeping and not a fourth side of the divergence.
