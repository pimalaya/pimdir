# Pimdir sync specification

Status: draft

The sync part of the pimdir standard: how one or more sources reconcile through a store ([STORAGE.md](./STORAGE.md)) so that the store is an offline replica of each and every source sees every other's changes. It fixes what an engine derives from the store's rows and a source's answers, and what it writes back.

An engine conforms by reproducing §11's vectors. What every writer owes the store, whichever engine reconciles it, is STORAGE §10 to §12. This is the part where implementing the document costs the most: the reference engine, io-pimdir, is meant to be used rather than rewritten, and its I/O-free core runs over any store and any transport.

It fixes no protocol: what a connector hands the engine is §4, how it gets it over IMAP, JMAP or DAV is the connector's.

[OVERVIEW.md](./OVERVIEW.md) §5 and §6 explain the model; [GUIDE.md](./GUIDE.md) §9 to §12 run the verbs as procedures. Both are informative and this part wins on any disagreement.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as in RFC 2119. §n of STORAGE.md is written STORAGE §n. A sentence carrying none of them describes; one carrying one binds.

## Contents

1. [Scope](#1-scope)
2. [Terminology](#2-terminology)
3. [The projection](#3-the-projection)
4. [The remote seam](#4-the-remote-seam)
5. [Sync](#5-sync)
6. [Upgrade](#6-upgrade)
7. [Mutate](#7-mutate)
8. [Rekey](#8-rekey)
9. [Several sources](#9-several-sources)
10. [The load and the write](#10-the-load-and-the-write)
11. [Test vectors](#11-test-vectors)

## 1. Scope

An engine reads a store as one source, derives what that source and the store owe each other, and writes the result. Five verbs: **open** (read the projection, no network), **sync** (reconcile against an enumeration), **upgrade** (raise items up the detail ladder), **mutate** (stage a local edit offline), **rekey** (rebuild a collection onto a new handle space).

Every verb MUST be a pure function of the rows it loads and the answers it is given; its only effects are a write batch (§10) and requests to the remote (§4). The store is the base of every merge: the bindings hold what each source last agreed to (STORAGE §4.3), and this part defines no reconciliation of two sources against each other.

Nothing here requires a language or a coroutine shape. A conforming engine is one whose runs reproduce §11's vectors.

## 2. Terminology

- **Source**: one remote a collection syncs with, named in `bindings.source` and `sources.source`.
- **Placement**: one source's view of one item in one collection: handle, flags, object, level, summary, sort key, status, base and conflict columns. Derived by the projection (§3), written back by the write (§10).
- **Status**: what a placement owes: `Clean`, `Dirty` (a flag or content push), `Tombstone` (a delete), `Conflict` (a decision), `Created` (an append).
- **Base**: what the source last agreed with its remote: flags, object, revision, and `base_present` (STORAGE §13).
- **Pending create**: a `Created` placement the source binds under a provisional handle, a binding with no base, waiting for its add to be accepted.
- **Provisional handle**: `U+0001` followed by the link id, a name no protocol hands out, so it never collides with a member the next enumeration lists and two engines derive one create's key alike (§4).
- **Origin**: where the same source already holds a `Created` placement's identity and body, so its add is a server-side copy (§3).
- **Destination**: where the same source holds a pending create of a `Tombstone` placement's identity, so its remove is a relocation (§3).
- **Tier**: what a fetch returns: `Meta`, identity and summary; `Full`, the body too.
- **Snapshot**: what an enumeration returned: members with handle, flags and revision, vanished handles, whether it is complete, and the checkpoint.
- **Change**: what the engine asks a source to do: `Add`, `Remove`, `SetFlags`, `Update`, each with an idempotency key (§4).
- **Outcome**: `Accepted`, with the handle assigned to an `Add` and the revision a mutable kind reports, or `Rejected`.

## 3. The projection

Placements are read from the store, never stored. For a collection and a source, the projection MUST yield one placement per item the source binds, one `Created` placement per item the source lacks and the store holds a body for, and one `Probed` placement per `probes` row of the source. A retained item (STORAGE §11) MUST be projected for nobody.

**Status**, the first that applies:

1. `Conflict` when `bindings.conflicted` is 1, carrying `conflict_revision` and `conflict_object`, or when `items.conflicted` is 1, two sources disagreeing on the body (§9), which every binding of the item projects until an `Edit` settles it (§7); neither is downgraded.
2. `Tombstone` when `items.deleted` is 1 and the source binds the item; the content is kept so an edit still beats the delete (§5). A tombstone whose binding has no base is a create the consumer withdrew: it derives no `Remove`, the write drops the binding and the item is retained (STORAGE §11).
3. `Created` when the binding has no base (`base_present` 0, every base column `NULL`), or the source does not bind the item, `items.deleted` is 0 and `object_hash` is present.
4. `Dirty` when the flags differ from `base_flags`, both known, or, for a mutable kind, `object_hash` is present and differs from `base_object`. A placement holding no body owes no body, whatever its base names.
5. `Clean` otherwise.

An unknown flag set (`NULL`) holds no opinion: neither an addition nor a removal, and an unknown base is no base on the flag axis. An immutable kind never owes a body: one identity is one message, and the write adopts the shared body as its base (§9).

**Level** MUST be `Full` only when `object_hash` is present, whatever `items.level` claims, so an item whose body a remote change dropped projects at most `Meta` and an upgrade refetches it.

**Origin.** A `Created` placement carries an origin when the same source binds the same `link_id` in another collection, with a base present and, when the placement has a body, that body as `base_object` (`origin_for_link`): a server-side copy from that handle rather than an upload. A binding whose base holds another body would copy what the server has, not what the placement intends.

**Destination.** A `Tombstone` placement carries a destination when the same source holds a pending create of the same `link_id` in another collection (`destination_for_link`): the relocation its remove offers (§5). Origins and destinations are derived from bindings, never stored, so both read the same after a crash and after a hub folded the item.

**Probes.** A `probes` row projects as a placement with a handle, the reported flags, no link id, level `Probed` and no base. A `Meta` fetch names it; until then it is a member the engine MUST NOT lose (STORAGE §4.3).

## 4. The remote seam

A connector answers three requests.

**Enumerate** returns a snapshot: `items` (handle, known flags, optional revision), `vanished`, `complete` (every member listed, or only the changed since the checkpoint), and the new `checkpoint`. `items` SHALL be sorted by handle in byte order, the one order two engines over one store agree on, and list each once; an engine MUST sort an unsorted list and keep a duplicate's first entry. A connector whose checkpoint the source rejects because the handle space changed (an IMAP `UIDVALIDITY` bump) MUST fail the enumeration and name a rekey (§8) rather than answer a complete snapshot of new handles, which a sync would read as every member gone and every new one arrived.

**Fetch** takes a tier and a batch of handles and returns per handle the identity hint and summary inputs of Annex A, at `Full` a body (inline or already streamed to its blob path, STORAGE §14), and the body's revision. A batch has no order: a connector MAY fetch concurrently and MUST key results by handle; the engine matches by handle.

**Push** takes a batch of changes and returns an outcome each:

- `Add { handle, link_id, flags, origin, object }`: create by server-side copy from `origin` when present, else by uploading `object`; accepted with the assigned handle. A connector to a mutable kind MUST report the revision the member holds once accepted, else the next enumeration reads its own push as a remote edit and refetches it.
- `Remove { handle, to, link_id, if_match }`: delete when `to` is absent or already holds `link_id` (§5); relocate into `to` otherwise. A connector that cannot relocate MUST reject the change rather than delete: the destination has not received the member, and a delete would take the only copy.
- `SetFlags { handle, flags }`: replace the flag set.
- `Update { handle, object, if_match }`: replace a mutable body, gated on `if_match` where supported; accepted with the revision the member holds, on `Add`'s terms.

**The idempotency key.** Every change carries a key naming it, so a connector logging keys recognises the replay of a push whose record was lost, and a chunk replayed after a crash (§5) applies once. The key MUST be derived as follows, so two engines over one store key one change alike:

- FNV-1a, 64 bits (offset basis `cbf29ce484222325`, prime `100000001b3`), over a sequence of fields, each field's bytes followed by one `0x00` byte, rendered as sixteen lowercase hexadecimal digits.
- The fields, in order: the collection id, the handle, the kind as `add`, `remove`, `set-flags` or `update`, then the kind's own. An optional value is the field `1` followed by the value's field, or the field `0` alone. A flag set is the field `unknown` when unknown, else the field `known`, the count in decimal ASCII, then each flag in code point order.
- `add`: the link id (optional), the flags, the origin as `1`, its collection and its handle, or `0` alone, then the object hash (optional). `remove`: `to` (optional). `set-flags`: the flags. `update`: the object hash.

A precondition (`if_match`) is not part of the key: a retry of one operation is one operation. The key names a push within one run, not for ever: a flag set restored, or a body pushed again against a newer revision, is a new change under an old key. A connector logging keys MUST forget them once the checkpoint after their chunk has landed, and MUST NOT answer a key it remembers from an earlier checkpoint as a replay. §11's vectors carry the key of every push.

## 5. Sync

A sync reconciles one collection against one enumeration. The **candidates** of a full snapshot are the projected placements and the listed members; of a delta, the changed and vanished handles plus every projected placement that is not `Clean`, whose pending push the delta would never revisit. A `Created` placement is a candidate with no remote side. The engine MUST walk both sides in handle order.

**Creates wait for the probes.** An `Add` MUST NOT be derived while the collection holds a probe of this source: a probe may be that create's own arrival, relocated or added by another client, and pushing before the fetch names it makes a second copy. The upgrade naming the probes lands or frees the create (§6) and the next run pushes what is left.

**The flag axis** merges element-wise over `(local, base, remote)` and never conflicts: a flag is in the result when both sides carry it, or when one side carries it and the base does not, an addition; it is out when the base carries it and either side does not, a removal. With no base, the result is the union of the two known sets, no side being known to have removed anything. It MUST run for every placement present on both sides, one whose content axis derived a push included; one handle yields at most one change, so the flag axis then withholds its push and still merges and writes.

A content push accepted in the same run MUST rebase the placement the flag merge wrote, never the one read before it, or the pulled flag is lost until an enumeration happens to relist the item.

It leaves the status alone while the content axis still owes a push, and leaves an unresolved conflict alone.

**The content axis** applies to a mutable kind, which reports a revision. A local body the base does not hold is an `Update` gated on the base revision. A remote revision the base does not hold is a pull, which drops the local body, lowers the level to `Probed` and keeps the summary as that of the body it dropped. A placement holding no body, a pull having emptied it, owes nothing until the upgrade refetches it.

Both is a conflict, resolved by the source's policy. Mail reports no revision and never reaches this axis.

A `Conflict` placement meeting a revision newer than its `conflict_revision` records the new one and drops its `conflict_object`, which described the old revision; the upgrade fetches it anew (§6). A conflict whose fetched body equals the placement's own is no divergence, the push whose record was lost having landed: the binding adopts the revision and body as its base and the conflict clears.

**Conflict policy**, the source's, settling it against its own remote: `Manual` (default) marks the binding conflicted with the observed revision and asks for the diverging body (§6). `PreferRemote` drops the local edit and pulls. `PreferLocal` pushes the local body gated on the observed revision, falling back to `Manual` when content pushes are forbidden.

The collection's `conflict` (STORAGE §4.3) is the other axis, settling the shared item between sources (§9), and the two are named apart on purpose.

**Deletes.** A `Tombstone` derives a `Remove`, carrying its destination when it has one (§3). A member absent from a complete enumeration, or listed vanished by a delta, is dropped with reason `Deleted` (§10), unless its placement holds a body its base does not, a local edit the remote never saw: new content beats a delete on both sides, so that placement is re-staged instead as a pending create under a provisional handle, its binding kept without a base, and the next run adds it. A remote edit over a local tombstone MUST revive it and pull; a tombstone also holding a local edit is the both-changed case and follows the policy.

A revision the tombstone's base does not name is a remote edit, an enumeration carrying no body to say otherwise. A move whose staged edit was pushed ahead of its remove and whose push record was lost is therefore abandoned rather than half-applied: the member stays in the source, live and clean at the pushed revision, and the consumer restages the move.

**Push direction and rights.** A source has a master `push` switch and four rights: `flags`, `content`, `add`, `remove`. With `push` false nothing is pushed and remote changes are still pulled; a forbidden kind keeps its change pending while other kinds propagate. A rejected push is pending like any other and follows no policy.

**A refused delete**, one the source's rights forbid, is decided per item from the bindings the run loaded. When the item has another binding the tombstone is held, since a revert would read as a resurrection there and the other source pushes the delete; the row stays in the trash view until that source has dropped it (STORAGE §11). When this binding is the item's last, the delete is reverted and the placement lands on what it still owes, since a held tombstone would hide a member an incremental source never lists again.

**A move** is a `Created` placement in the target plus a `Tombstone` in the source, each derived by its own collection's sync in either order and each able to deliver alone. Neither half MUST be dropped for the other.

The create delivers by copy from its origin, or by upload when the store holds the body. The remove delivers by relocating into its destination, which the connector MUST reject when it cannot relocate (§4), and is a plain delete once the destination holds the identity.

A relocated member is listed by the target's next enumeration under a new handle, and the fetch naming it lands the create (§6); until then the create waits, as every create does behind a probe. A mutation of a `Probed` placement is refused (§7), so every tombstone with a destination carries a link id.

**Push discipline.** A push MUST be confirmed before local state moves: `Accepted` rebases the placement, and for an add supersedes the provisional handle in the same batch; `Rejected` or unreported leaves it pending, and an engine SHOULD report a create rejected on consecutive runs rather than push it for ever. Pushes go in bounded chunks, each followed by the write recording its outcomes, and the owner MUST NOT collect between two chunks (STORAGE §5). The checkpoint MUST land in the write after the last chunk and in no earlier one.

**Events.** A sync reports per item, in order, what the remote changed locally and what the run settled: `Added`, `FlagsChanged`, `ContentChanged` and `Vanished` on a pull, `Conflicted` on a divergence, `Created` on an accepted add under its assigned handle. A pushed flag, body or delete reports nothing: the consumer made it.

## 6. Upgrade

An upgrade raises placements up the ladder `Probed`, `Meta`, `Full` at the tier asked for. Enumeration stops at the first rung; hydration is what a consumer runs for the members it wants.

**Identity is resolved once**, at the first fetch carrying a hint; a later fetch MUST NOT re-identify a linked placement of an immutable kind. A mutable resource whose later fetch states another hint under the same handle is a new identity there, on the terms STORAGE §9 sets for a changed `hash:` key: the old binding is retired and the resource keyed afresh. A `Meta` fetch of a probe names it: item and binding inserted, probe dropped, one transaction. The key follows STORAGE §9: the hint when free, a minted `dup:<hint>#<handle>` when this source already binds the hint under another handle, minted again over a held key.

Minting MUST be decided against the whole collection and from the handles in byte order, not reply order, so a rebuild mints the same key; an upgrade therefore loads the fetched hints by key (§10) before it assigns any.

**A pending create is landed by its arrival.** A fetched hint the collection holds as a pending create of this source (§2) is that create delivered: by a relocation (§5), by an accepted add whose record was lost, or by another client. The engine MUST land it rather than mint; only a hint held by a based binding is minted.

Landing is a `Superseded` drop of the provisional handle in the same batch, the binding moved to the fetched one, and the base set to the flags the fetch reported and, for an immutable kind, the staged body, one identity being one message. For a mutable kind the base takes the fetched revision and the fetched body when the fetch carried one; a fetched body differing from the staged one is the content axis's both-changed case (§5). The flags and body staged on the create stay, so an edit made on it still pushes.

**A fetch moves the base.** A fetch carrying a body over a placement holding no local edit sets `base_object` to that body and `base_revision` to its revision, whatever the placement's level was, so the next sync reads the fetched body as agreed and not as an edit to push. Over a placement holding a local edit, a body its base does not hold, the fetched body lands as the base and the local body stays when the revision is the base's, and the both-changed case applies when it is not.

**Linking instead of fetching.** A `Full` upgrade of an immutable kind asks `lookup_objects` for the placement's key and adopts a body the store holds, recording it as the base too, when the summary the source served agrees with the held body on `size`, else fetching: two messages under one `Message-ID` with different bytes are the wrong merge §9 avoids. A mutable placement, a conflicted one, and one under a writer-derived key MUST be fetched, never linked.

**Claims are revisited.** A level claiming a tier the row does not hold (`Full` with no object, `Meta` with no summary) is fetched again. A fetch carrying no body writes the level the payload supports, never lower than the row holds. The sort key is adopted from every fetch; the link id is not.

**A conflict's body.** A conflicted placement holding no `conflict_object` is revisited, and the body fetched MUST land in `conflict_object`, never in its own object.

**Rows.** Every fetch writes the summary row and address rows Annex A derives, in the batch recording the fetch.

## 7. Mutate

A mutation stages a local edit to one collection with no network, through the same write as a sync (§10), never by direct row edits. The queue's actions map onto them: `set-flags` to `SetFlags`, `remove` to `Remove`, `move` and `copy` to `Move` and `Copy`, `update` to `Edit`, `add` to `Add`. A mutation naming a `Probed` placement MUST be refused: nothing keys it until a `Meta` fetch names it.

- `SetFlags` replaces the flags and marks the placement `Dirty`; a `Created`, `Conflict` or `Tombstone` placement keeps its status.
- `Remove` tombstones the placement, binding and base kept so the remove is pushed against the right handle. On a conflicted binding it is the decision: the base adopts `conflict_revision`, the conflict clears and its `conflict_object` is released, so the remove pushes gated on what the remote holds; on a conflicted item (§9) it clears the item's conflict the same way. On a pending create it withdraws the create: the binding goes and the item is retained (STORAGE §11).
- `Edit` stores a new body and repoints the placement, keeping the base. An edit whose object the base holds stages nothing. On a conflicted placement it resolves, the base adopting `conflict_revision` and `conflict_object` together; on a conflicted item it resolves too, `items.conflicted` cleared and its `conflict_object` released; on a tombstone it revives, `Dirty`, and the destination its tombstone offered no longer derives. It MAY restate the sort key.
- `Copy` stages a `Created` placement in a target under a provisional handle with the source's origin; `Move` also tombstones the source, whose destination the target's pending create then derives (§3). Both read the target and mint the key when a live placement there already holds the identity; a tombstoned holder blocks nothing. Both MUST be refused for a placement holding neither a body nor a based binding, since nothing could deliver the create.
- `Add` stages a new item under a provisional handle at `Full`, no base, no origin. It MUST fail when a live placement holds the `link_id`; a retained one revives (STORAGE §11); a tombstone still propagating is revived the same way, the row adopting the new body and its delete withdrawn on every source.

## 8. Rekey

A source may renumber every member (an IMAP `UIDVALIDITY` bump, a restore). A rekey re-enumerates the spine, which MUST be a complete snapshot, and carries each placement's body, summary, level, flags, base and pending state onto its new handle **by link id**, the one identifier that survived. A resync would instead delete the collection and lose every staged edit.

The batch drops each old handle it re-writes with reason `Rekeyed`, which licenses the binding to move (STORAGE §10, §12), per handle: a genuine duplicate in the same batch is still refused. It is one batch, every `Rekeyed` drop preceding every upsert, since a new handle may be an old one another member held. A handle the new space lacks is dropped `Deleted`. A binding with no base is outside the rekey: no space ever held its provisional handle, and it is carried as it is.

A member resolving to an identity already handed out takes the minted key an old copy carried, else a mint over its own handle; pending creates' keys count as taken. Where one hint had several old copies, a member is matched to the old copy holding its body first, and in handle order only among what the bodies cannot tell apart, so a renumbering that swapped two resources under one `UID` carries each one's flags and pending edit onto itself. The sort key is carried, preferring the fetch's.

A mutable member whose fetched revision differs from the one its old base held changed on the remote while the handles did. The engine MUST carry it as a pull (§5), or as a `Conflict` at the fetched revision when it also holds a local edit.

A base claiming a revision it never reconciled is the one thing a rekey MUST NOT write: the next sync would read the stale body as current, or push the local edit last-writer-wins.

The batch and the epoch bump commit together, and the batch carries no op for the bump: a batch holding a `Rekeyed` drop is a rebuild, and the storage bumps the collection's generation in the transaction that applies it (STORAGE §12).

## 9. Several sources

N sources hold one item per identity and one binding each. A change one source folded into the item reads as `Dirty` against every other source's base, and each source's next sync pushes it. There is no cross-merge.

**Absorbing a write** folds a source's batch into the shared item: flags adopted, a body adopted or refused by the rule below, the level merged as a maximum under §3's body rule, a pull writing `Probed` since it took the body away. A known flag set, sort key or summary replaces a known one; an unknown one leaves the shared value alone. A tombstone adopts no content and its flags ride along.

**Two bases.** `base_object` is what the source last agreed with its remote and only a sync moves it. `shared_object` is what it last agreed with the shared item and every live upsert moves it. The cross-source comparison MUST be made from `shared_object`, falling back to the sync base until the source has folded once.

**Cross-source content**, mutable kinds only. Three facts are read before the upsert is applied: the source changed when the incoming body differs from the base its binding held before this upsert, not the base the upsert carries; the item changed when the shared body differs from `shared_object`; the two disagree when the incoming body differs from the shared one. All three is a divergence, resolved by the collection's `conflict` policy: `manual` keeps the shared body, flags the item and records the incoming body in `items.conflict_object`, every binding then projecting `Conflict` (§3) until an `Edit` or a `Remove` settles it (§7); `prefer-incoming` adopts; `prefer-existing` keeps. Only the source having changed is a fast-forward; only the item having changed leaves the incoming body behind and the binding `Dirty`, which is propagation.

An immutable kind never diverges: one identity is one message, so a body differing from the shared one is the same message served differently, the shared body stands and the binding's base adopts it. An upsert leaving a conflicted binding counts as the source having changed its body. Flags never conflict.

**Deletes propagate.** A `Deleted` drop or a `Tombstone` upsert marks the item deleted; the dropping source loses its binding, a tombstoning one keeps it. Every other source projects a `Tombstone`; a source lacking the item projects nothing. A live upsert clears `deleted`. With no binding left the item is retained (STORAGE §11). A `Superseded` or `Rekeyed` drop marks nothing.

**Propagation is hydration-safe.** A source lacking an item MUST be offered it only when the store holds the body, and a projection never raises a level. Mirroring is a sync plus an upgrade.

**A per-source conflict is its own fact.** `bindings.conflicted` and `items.conflicted` never set each other. An upsert carrying no divergence clears the binding's and becomes the shared body, so resolving is an ordinary edit. A tombstone projected for a conflicted binding still carries the divergence.

A binding with no base is a pending create, and a minted key is an ordinary key: it reconciles, propagates and conflicts like any other, a target's refusal reported as a rejected push. A `hash:` key is not offered to another source: it asserts no identity, and a server re-serialising the body hands it back under another key, one new item per run on each side.

## 10. The load and the write

Every verb begins with a load naming a collection and a **scope**: `All`, `Handles` or `Links`. A mutation asks for the one placement it edits, or for every holder of the link id an `Add` must not collide with; an upgrade asks for the handles it raises; a sync and a rekey ask for the whole collection, being the only verbs that reason about what is missing from it. A `Copy` or a `Move` also loads its target for the identity it carries into it. The scope is a floor: a storage SHALL return at least the placements it names and MAY return more (STORAGE §14). A `Links` load answers who holds the key: it SHALL NOT return the `Created` placement the projection offers for an item the source lacks, else an upgrade settling a fetched identity reads another source's copy as this source's holding and mints a key over it (§6).

Every verb ends in a batch applied in order and atomically (STORAGE §14): `UpsertPlacement`, `DropPlacement { handle, reason }`, `StoreObject { hash, size, bytes? }`, `SetCheckpoint`. A drop's reason says why the row goes: `Deleted`, the member is gone from the source; `Superseded`, a provisional handle an accepted add or a landed arrival replaced (§6); `Rekeyed`, a handle a rebuild renumbered (§8). Order carries meaning (a batch names one handle twice to supersede a provisional one, a rebuild drops every old handle before it upserts any new one) and a storage MUST NOT reorder. A batch is cut between candidates, never inside one, and a rekey is never cut.

An unlinked upsert for a handle a binding holds folds into that binding's item; only a handle nothing holds is a probe. An upsert resolving a binding to a different handle is refused, except through a `Superseded` or `Rekeyed` drop of the bound handle in the same batch. An upsert resolving a bound handle to a different link id retires the old binding first (STORAGE §10). A `Deleted` drop of a source's last binding retains the item.

A `StoreObject` carries bytes or references a body already streamed to its blob path; a `Full` fetch MAY stream it there itself. The checkpoint is per source and lands last (§5). Summary and address rows are written with the placement they describe; stamps follow from the rows (STORAGE §4.5).

## 11. Test vectors

vectors/sync/ holds cases every conforming engine MUST reproduce, one JSON file each. `store` is the rows before the run, bodies named by label; `run` the verb, collection, source and options (`push`, `rights`, `conflict`), a `mutate` run carrying its `mutation`; `remote` the snapshot and the fetch answers by handle and tier; `expect` the pushes in order, the outcomes fed back, the events, and the rows after. A provisional handle is written with its leading `U+0001`.

A push is compared on its kind, handle and `key` (§4) and on what the kind carries: `flags`, `to` and `link_id`, `if_match`, `origin` as collection and handle, and `object` by label. An outcome names its handle, `Accepted` or `Rejected`, and for an add the `assigned` handle and the `revision` reported.

Rows are compared as parsed structures, `changed` stamps and `retained_at` instants excluded. Chunked pushes or writes are compared concatenated. checks/vectors.py validates shape, references and every push's key; only an implementation runs one.
