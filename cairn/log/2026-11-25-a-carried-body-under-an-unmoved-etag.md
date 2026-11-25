---
cairn: log
change: the-freeze-plan
landed: 2026-11-25
---

# A carried body under an unmoved ETag

The owner ruled Q1 of cairn/log/2026-11-25-the-quirks-findings-close.md on 2026-11-25, reading B: a DAV server may serve another body under the ETag the base holds, and a member carrying, at the revision its base names, a body differing from the one that base holds is a remote edit. Under reading A, the revision alone deciding, a local edit pending over such a card was pushed gated on the unchanged ETag, which the server accepts, and the server's edit was lost unseen. sync-draft-16 is untagged, so SYNC.md is edited in place and no number moves: storage-draft-19, sync-draft-16 and search-draft-20 stand. Vectors 237 to 242 are new, each failing on io-pimdir b5606f3 and passing on the io-pimdir change of the same name (its cairn/log/2026-11-25-a-carried-body-under-an-unmoved-etag.md).

## Rules

- **SYNC §5, A carried body is a remote edit under an unmoved revision** (new paragraph after the content axis). Such a member is read, in §5, §6 and §8, as meeting a revision its base does not hold: a pull when no local body is staged, the both-changed case when one is, a divergence under `KeepLocal`, and a remote edit over a tombstone. The observed revision is the base's own: a conflict records it, and a push rebased on the member's body is gated on it. A member carrying no body, and a base naming its revision and no body, leave the revision alone deciding. Checks: vector 237 (nothing staged: the item and the base take the carried body at `r1`, its summary and sort key, `ContentChanged`; io-pimdir b5606f3 kept the old body under the carried body's summary, "events differ"), vector 238 (a local edit under `manual`: conflicted at `r1` with the carried body as `conflict_object`, nothing pushed; b5606f3 pushed the `Update` gated on `r1`, "pushes differ"), vector 239 (the same under `prefer-local`: the carried body kept as a retained item, reported `Overruled`, before the push gated on `r1`; b5606f3 pushed it keeping nothing, "events differ"), vector 240 (a tombstone: revived and pulled, no `Remove`; b5606f3 pushed the delete gated on `r1`, "pushes differ"), vector 242 (the same under `prefer-remote`: the item and the base take the carried body, the local edit kept as a retained item and reported `Overruled`; b5606f3 pushed the `Update`, "pushes differ", and a first cut of the io-pimdir change pulled it and dropped the edit unkept, "events differ", its shared-item fold telling a pull by a moved base revision alone).
- **SYNC §6, A fetch moves the base**: over a local edit, the fetched body lands as the base and the local body stays when the revision is the base's and the base holds no body or that one; a fetched body differing from the one the base holds at its own revision is the both-changed case. Check: no vector, the state being out of a vector's reach without an artificial store (an upgrade fetches a placement holding a local edit over a base holding a body only when its level claims `Meta` or its blob is missing); io-pimdir's unit test `upgrade::tests::a_body_fetched_at_the_base_revision_over_an_edit_conflicts`, failing on b5606f3's rule (`Dirty`, not `Conflict`).
- **SYNC §8, a rekey's carried member**: a mutable member carrying, at the revision its old base held, a body differing from the one that base holds changed on the remote while the handles did, carried as a pull or as a `Conflict` over a local edit. Check: vector 241 (vector 23's store, the listing at `r1` carrying another body: conflicted at `r1` holding it; b5606f3 carried the edit unconflicted, "bindings rows differ").
- checks/vectors.py: an `Update` pushed after a member carried, at the revision it is gated on, a body the base does not hold must leave that body kept as a retained item, as one pushed over a moved revision must; a vector 238 expecting the old reading's push fails it ("pushed over a body it read keeps that body").

## Text changed after review

The first sentence of the new §5 paragraph read "a body that base holds and differs from", which parses as a body the base holds; it now reads "a body differing from the one that base holds". No neighbouring rule contradicts the ruling: §4's `Add` and `Update` reporting the revision once accepted, §5's lost push ("the very body the placement holds over that base"), the policies, the tombstone and conflict rules and §6's revisits all read through "a revision its base does not hold", which the paragraph extends; §6's "A fetch moves the base" over no local edit already takes any fetched body.

One consequence is worth naming, though no text moves for it: a server transforming a body it accepts while answering the `Update` with an ETag (RFC 9110 §9.3.4 forbids that validator) now serves, under the revision the push recorded, a body the base does not hold, which the next sync pulls as a remote edit. That costs one pull of the server's own form, never a loss; io-pimdir's fake remote behaved that way for every push and had to serve the bytes it accepted.

## Generator and campaign

io-pimdir's generator follows the rule in its model's `refresh` and `rekey`, and its tests/generated/campaign.rs files no difference under `ETAG_KEPT_OVER_A_SERVER_EDIT` any more: the quirks profile's `revisions` step 2 compares again, and campaign-1's quirks profile over seeds 1201 to 1224 (384 jobs) reports no failure and no difference.

## Versions

None moves. vectors/README.md names 237 to 242; vectors/manifest.json restated (242 sync cases). checks/io-pimdir.rev moves with the io-pimdir commit landing its change.
