---
cairn: log
change: a-delivered-create-waits-for-its-arrival
date: 2026-11-11
---

# A delivered create waits for its arrival

A create its source took before any listing named it, an add accepted with no handle or a relocation into it accepted, was left a pending create, so a `Remove` or a `Move` staged on it withdrew it and nothing reached the server (android cairn/log/2026-11-11-gmail-trash-stays.md: a Gmail message deleted into the trash, then deleted for good or restored before the trash was listed, came back). It is now a **delivered create**: its binding keeps the provisional handle and holds a base naming nothing. The sync part moves to **sync-draft-09** (the owner, 2026-11-12), so an engine of sync-draft-08, which would push against a delivered create's provisional handle and drop it as absent, refuses a store this draft's engine wrote, and the reverse; storage-draft-09 stays in place, no migration moving. Proposal: cairn/changes/a-delivered-create-waits-for-its-arrival.

## Rules and their checks

- **Delivery** (SYNC §2, §4, §10; STORAGE §14): an add accepted with no handle, and an accepted relocation into the destination's create, write `DeliverPlacement { collection, handle }`, which `deliver_binding` (new) applies only while the binding holds no base. Only a create a listing can land is delivered: one keyed by a key minted over a member's handle stays pending (SYNC §6). Vectors 20, 48 and 92 now expect the create delivered; checks/invariants.sh "A delivered create is no member a listing names" runs `deliver_binding` on a pending create, a member's handle, an unbound handle, twice and for another source.
- **It waits** (SYNC §5, §7): no `Add`, `SetFlags`, `Update` nor `Remove`; never absent nor counted (`list_unstamped_bindings` leaves out provisional handles); a `Remove` or `Move` of it tombstones it, held. Vector 136 (a delta), invariants (the absence, failing on the old statement).
- **It waits whatever a round lists** (SYNC §5), reported while it waits: vector 139 (a round landing neither a live nor a tombstoned delivered create drops nothing). **It stays a destination** (SYNC §3, `destination_for_link`), so an owner may record the delivery before the relocation leaves (SYNC §4): invariants, failing on the old statement. **A delete leaves one collection** (SYNC §4): on a source naming one message by one id in several collections, a connector deletes it for good only where it is held nowhere else.
- **The outcome states the relocation** (SYNC §2, §4, §11): a connector states whether an accepted `Remove` carrying `to` relocated or deleted the member, and only a relocation delivers; a delete, the target already holding the identity, leaves the create pending, so its body is pushed again rather than kept on the device alone. Vector 140; vectors 20, 48 and 137 state it; sync vectors move to format 4; checks/vectors.py requires the field.
- **It lands** (SYNC §6, §8, STORAGE §9's table): as a pending create, a tombstone keeping its status, the run pushing against the listed handle and relocating into the destination derived then; a rekey carries it onto its member or leaves it; no upgrade fetches a provisional handle. Vectors 137 (a restore staged on it, relocated against 7, the INBOX create delivered in turn) and 138 (its staged `\Seen` pushed against 7).
- **No origin** (SYNC §3, STORAGE §14): `origin_for_link` leaves out a provisional handle. Invariants, failing on the old statement.
- checks/vectors.py: a binding with no base is provisional, and a provisional one holding a base names nothing; a delivered create is never absent nor counted; a `Remove` may be pushed against the handle a page lands a delivered tombstone on. GUIDE §9 to §12, OVERVIEW §5 and vectors/README.md follow; vectors/manifest.json restated.
- Checked on the working tree (2026-11-11): `nix flake check path:$PWD`, its seven checks (names, vectors with 140 sync cases, invariants with 258 of 258 statements, schema, references, floor). checks/tags.sh is left for the commit.

## Consumers

io-pimdir follows on its branch delivered-create (its cairn/log/2026-11-11-a-delivered-create-waits-for-its-arrival.md), passing vectors 20, 92 and 136 to 139, which failed before it; checks/io-pimdir.rev moves once both are committed. The Android app pins that branch to close its two `@Ignore`d Gmail tests.
