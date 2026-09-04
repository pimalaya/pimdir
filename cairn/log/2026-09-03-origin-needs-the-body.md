---
cairn: log
change: origin-needs-the-body
date: 2026-09-03
---

# An origin is a binding holding the body the copy intends

SYNC §3 gave a `Created` placement an origin wherever the same source bound the identity in another collection, and only for an item the source lacked. A staged copy of a locally edited item would then have pushed as a server-side copy of the unedited body, and a copy staged through the store, which binds the placeholder, carried no origin at all.

The origin now needs a binding with a base present and, when the placement has a body, that body as its `base_object`; any `Created` placement carries it, bound or not. Found by the engine's property tests running over a real store.
