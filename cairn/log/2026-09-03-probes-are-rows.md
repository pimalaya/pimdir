---
cairn: log
change: probes-are-rows
date: 2026-09-03
---

# An enumerated handle is a row until a fetch names it

§14 let an implementation hold freshly probed placements "in memory, or a residual table", and the reference implementation held them in memory.

A sync writes the checkpoint that stops an incremental source from ever listing those handles again, and the `Meta` upgrade that would name them runs after it; a crash between the two lost every one of them, with no run that would bring them back short of a full resync.

`probes(collection, source, handle, flags)` is the row. A probe becomes an item and a binding in the transaction of the fetch that names it, and its row goes in the same one; a rebuild voids a source's probes at once. The sixth sync vector pins the shape and the seventh the naming.
