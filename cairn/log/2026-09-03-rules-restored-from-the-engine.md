---
cairn: log
change: rules-restored-from-the-engine
date: 2026-09-03
---

# Four rules the engine enforces and the sync part had dropped, and one it never stated

Auditing io-replica 0.5.0 against SYNC.md found rules its own cairn specs state and the folding into SYNC.md lost, and one shape the spec was silent on. Each was put to the maintainer and restored as one or two sentences:

- **A lost push record abandons a move** (§5): a revision the tombstone's base does not name is a remote edit, so a move whose edit was pushed ahead of its remove and whose record was lost leaves the member live in the source rather than half-applied.
- **A load states its scope** (§10, STORAGE §14): `All`, `Handles` or `Links`, a floor the storage may exceed and never under-deliver, mapped onto `load_items_by_link`, `load_bindings_by_link` and `link_for_handle`.
- **A conflict's body is dropped when its revision advances** (§5): the stored diverging body described the old revision, and the upgrade fetches the new one.
- **The KeepBoth fork key** (§5, STORAGE §9): the kept local body is minted `dup:<hint>#<provisional handle>`, a second copy of one identity, rather than the engine's unprefixed `keepboth` form, which STORAGE §9's exclusions did not cover and which would have matched `lookup_objects` and shared a `seq`. No new prefix; the engine changes one string.
- **How a batch signals a rebuild** (§8, STORAGE §12): it carries no op; a `Superseded` drop is the signal and the store bumps the generation in the transaction applying the batch.

GUIDE.md §5, §9, §10 and §11 carry the procedures. The engine and the store follow the spec from here: no migration is offered for a store written before today, since nothing outside heavy development depends on one.
