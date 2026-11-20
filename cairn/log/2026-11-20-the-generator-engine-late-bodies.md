---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine, eleventh part: fills, revivals and overrules

The eleventh part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan, closing the four items the engine model left open. No part of the standard moves.

- **An upgrade reading a change over an emptied item** (generator/src/engine.rs, SYNC §6, §9, vector 112): an upgrade fetching, for a binding whose base holds a body, a revision its base does not name folds it as a pull would; over an item holding no body the divergence is recorded as `manual` records one whatever the policy, the body read the item's `conflict_object` and the binding's base, nothing kept.
- **The fill** (SYNC §9, vectors 30, 82, 114, 115): an upgrade reading a body for a binding whose base names none fills the item, adopted without a divergence measured. An item conflict waiting on the item's own body is then settled by the policy: `manual` keeps it, the filling binding's shared body pinned; `prefer-incoming` adopts the diverging body and `prefer-existing` the one filled, the body not adopted kept over the filling binding's handle, reported `Overruled`. The rows of a diverging body are kept (`Model::rows`) so an item adopting it later shows them.
- **A revival** (SYNC §6, STORAGE §11.1, vectors 108, 110): a member naming a key a retained row of the collection holds, its summary agreeing, a message's size too where both state one, revives the row under its key and `seq`, reported `Added`. A message keeps its body as the member's own; a mutable kind takes the body the member carries, none at `Meta` when it carries none, the body the row held kept as a retained item over the member's handle, reported `Overruled`. A message at another size is minted apart.
- **The overruling `Edit`** (SYNC §7, vectors 100, 101): `Model::overrule` settles a conflict by an engine's rule through a source's binding. It is refused, staging nothing, while a conflict it settles holds a body nobody read; else the binding's conflict is adopted as its base, the item takes the edit's body, and each diverging body it does not adopt is kept over the binding's handle, the binding's then the item's, reported `Overruled`.
- **A history** of three address books where `a`'s pull empties the item, `b`'s upgrade records its server's edit and `a`'s upgrade fills it under each policy; a card restored unread after its server deleted it; two messages deleted, one restored as it was and one resent at another size; and a conflict an engine overrules with the item's body, carried or unread.
- **Checks**: tests state each rule above from SYNC and STORAGE; every step's store is written and self-checked. Broken by hand to see each fail: a moved base filled, the fill ignoring `prefer-incoming` or the conflict waiting, no revival, a revived body lost, a revival at any size, an overrule over an unread body, an overrule keeping nothing.
