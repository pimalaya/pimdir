---
cairn: log
change: an-automatic-settle-keeps-what-it-discards
date: 2026-10-30
---

# An automatic settle keeps what it discards

neverest's one-way mode (its change a-one-way-overwrite-keeps-what-it-discards, test `a_one_way_overwrite_keeps_the_target_body_as_a_retained_item` in src/offline/driver.rs) overwrites a target's own edit by settling the target's conflict with an `Edit` restating the store's body (`keep_store_bodies`). §7 made the diverging body the base and kept nothing, so the push collected it: the silent loss a-merge-keeps-every-body exists to prevent, and the plan's "prefer-* kept with the losing body pinned and reported" did not hold for that path. Lending the collection a `prefer-*` policy for the write cannot settle it: the target's divergence is a binding conflict, which no collection policy meets, and the body the `Edit` restates is the shared one, so no cross-source divergence is measured either. Lands in sync-draft-05 and storage-draft-05, no number bump.

- **SYNC §7, §9, STORAGE §11** (normative): an `Edit` settling a conflict by a rule of the engine's or a connector's MUST state `overrule`; a person's resolution and a queued `update` do not. An overruling `Edit` keeps each diverging body it does not adopt, the binding's `conflict_object` then the item's, as a retained item keyed over the edited handle, reported `Overruled`, before any body the collection's policy keeps in the same write. It MUST be refused, staging nothing, when the conflict holds no diverging body, one nobody has read; the upgrade fetches it first. Without `overrule` the settle is a person's choice and keeps nothing. Guarded by vectors 100 (binding conflict, the neverest case), 101 (refused over an unread body), 102 (item conflict); 103 pins that a resolution without `overrule` keeps nothing.
- **SYNC §11** (normative, vector format): a `mutate` run's `Edit` carries `overrule` where it states it. Additive: the schema leaves `mutation` open, so the format stays at `v` 1.
- **GUIDE §11, §12** (informative) follow.

**Why a flag, not a policy on the mutation.** A mutation stating its policy would restate what its body already decides (the `Edit` names the body adopted), admit contradictory pairs (a body and a policy choosing the other), and need a vocabulary spanning the source's and the collection's policies, which §5 names apart on purpose. `overrule` carries the one bit the body does not: whether a person chose the loss. Its consequence is §9's existing keep, key and event, so a one-way overwrite reads exactly as a `prefer-*` settle in a sync.

**Not covered, open.** A sync's `PreferLocal` (§5) pushes the local body over the diverging one and keeps nothing: vector 15 pushes c2 over a carried c3 that no row then holds, and a member carrying no body is pushed over unread. It is the same class of loss on a pushing pass; keeping it needs the keep to land once across a rejected or interrupted push, and the unread case a fetch before the push, so it is left for its own change.

io-pimdir's tests/vectors_sync.rs (2026-10-30) fails 100 and 102 ("events differ": no `Overruled`) and 101 ("the run failing differs": applied), and passes 103. neverest's `keep_store_bodies` follows once io-pimdir does: it states `overrule` and fetches a placement's diverging body before settling it, as `resolve_conflicts` already does for a merge. `nix flake check path:$PWD` passes.
