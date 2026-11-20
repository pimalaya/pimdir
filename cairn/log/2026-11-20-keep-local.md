---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# Keep local

The owner's D2 (agreed 2026-11-20, cairn/changes/the-freeze-plan): a change made on a source's remote alone was adopted whatever the source's policy, SYNC §5 asking `PreferLocal` only when both sides changed, so a source the store is authoritative over (neverest's one-way targets, a copy written from its sources) pulled an edit made on its server into the store, and from there toward every other source. sync-draft-15 adds a policy value for it, additive to the three.

## What moved

- **SYNC §5** (normative): `KeepLocal`, `PreferLocal` for a source the store is authoritative over. A remote revision the base does not hold is a divergence whether or not a local body is staged, never a pull; it is settled as `PreferLocal` settles a both-changed case, the store's body (the staged edit or the base's) pushed over the member's, which is kept as a retained item and reported `Overruled`. A placement holding no body has nothing to keep and pulls as any. It falls back to `Manual` without content pushes, the divergence recorded rather than pulled, and a remote-only change whose member carries no body is recorded as `Manual` records it (no policy pushes over a body nobody has read). The content axis names the exception; §6's settle of a fetched body and §9's kept bodies name `KeepLocal` beside `PreferLocal`.
- **Vectors**: the sync format moves to 9 for the run policy `keep-local` (a value added to a closed set, vectors/schema/sync.schema.json), every case restated at 9. Vector 174: a change the source alone made, its body carried, is kept and the store's body pushed over it, gated on the observed revision. Vector 175: the same change carrying no body is recorded, nothing pulled or pushed.
- **Vector 173**, the two-source case of SYNC §5's base read (io-pimdir cairn/log/2026-11-20-a-base-read-keeps-the-item-conflict.md): an upgrade reading the body a base named at its revision, while the item's conflict holds its diverging body, fills the base and settles nothing, the item keeping its body and its conflict. No rule moves: §5 and §6 said so; an engine that read the body as a fast-forward lost both edits.
- checks/vectors.py counts keep-local with prefer-local among the policies that settle a divergence once its body is read. GUIDE §10, OVERVIEW and vectors/README.md follow.

## Guards

- vectors/sync/174 and 175 fail on io-pimdir with the content axis pulling a remote-only change, as before; 173 fails with io-pimdir's base-read fix disabled. All three pass on io-pimdir following this draft.
- checks/vectors.py re-derives 174's push key; `nix flake check path:$PWD` passes.

## Left

- neverest maps its store authority (`Authority::Store`, src/sync/driver.rs) to `KeepLocal`, after the Y2 lane leaves neverest (the freeze plan, section 5).
- For the owner: `KeepLocal` covers content, as D2 states it. A flag change and a delete made on such a source's remote alone still merge and propagate as today (flags never conflict, SYNC §9; an absence deletes, §5); whether a store-authoritative source pushes its flags back and re-creates a member its server deleted is not decided.
