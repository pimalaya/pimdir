# Pimdir sync specification

Status: draft

The sync part of the pimdir standard: how one or more sources reconcile through a store ([STORAGE.md](./STORAGE.md)) so that the store is an offline replica of each and every source sees every other's changes. It fixes what an engine derives from the store's rows and a source's answers, and what it writes back.

An engine conforms by reproducing §11's vectors. What every writer owes the store, whichever engine reconciles it, is STORAGE §10 to §12. This is the part where implementing the document costs the most: the reference engine, io-pimdir, is meant to be used rather than rewritten, and its I/O-free core runs over any store and any transport.

It fixes no protocol: what a connector hands the engine is §4, how it gets it over IMAP, JMAP or DAV is the connector's.

[OVERVIEW.md](./OVERVIEW.md) §5 and §6 explain the model; [GUIDE.md](./GUIDE.md) §9 to §12 run the verbs as procedures. Both are informative and this part wins on any disagreement.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as in RFC 2119. §n of STORAGE.md is written STORAGE §n.

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

Every verb is a pure function of the rows it loads and the answers it is given; its only effects are a write batch (§10) and requests to the remote (§4). The store is the base of every merge: the bindings hold what each source last agreed to (STORAGE §4.3), and this part defines no reconciliation of two sources against each other.

Nothing here requires a language or a coroutine shape. A conforming engine is one whose runs reproduce §11's vectors.

## 2. Terminology

- **Source**: one remote a collection syncs with, named in `bindings.source` and `sources.source`.
- **Placement**: one source's view of one item in one collection: handle, flags, object, level, summary, sort key, status, base and conflict columns. Derived by the projection (§3), written back by the write (§10).
- **Status**: what a placement owes: `Clean`, `Dirty` (a flag or content push), `Tombstone` (a delete), `Conflict` (a decision), `Created` (an append).
- **Base**: what the source last agreed with its remote: flags, object, revision, and `base_present` (STORAGE §13).
- **Tier**: what a fetch returns: `Meta`, identity and summary; `Full`, the body too.
- **Snapshot**: what an enumeration returned: members with handle, flags and revision, vanished handles, whether it is complete, and the checkpoint.
- **Change**: what the engine asks a source to do: `Add`, `Remove`, `SetFlags`, `Update`, each with an idempotency key (§4).
- **Outcome**: `Accepted`, with the handle assigned to an `Add`, or `Rejected`.

## 3. The projection

Placements are read from the store, never stored. For a collection and a source, the projection yields one placement per item the source binds, one `Created` placement per item the source lacks and the store holds a body for, and one `Probed` placement per `probes` row of the source. A retained item (STORAGE §11) is projected for nobody.

**Status**, the first that applies:

1. `Conflict` when `bindings.conflicted` is 1, carrying `conflict_revision` and `conflict_object`; it is never downgraded.
2. `Tombstone` when `items.deleted` is 1 and the source binds the item; the content is kept so an edit still beats the delete (§5).
3. `Created` when the binding has no base (`base_present` 0, every base column `NULL`), or the source does not bind the item and `object_hash` is present.
4. `Dirty` when the flags differ from `base_flags`, both known, or `object_hash` differs from `base_object`.
5. `Clean` otherwise.

An unknown flag set (`NULL`) holds no opinion: neither an addition nor a removal, and an unknown base is no base on the flag axis.

**Level** is `Full` only when `object_hash` is present, whatever `items.level` claims, so an item whose body a remote change dropped projects at most `Meta` and an upgrade refetches it.

**Origin.** A `Created` placement carries an origin when the same source binds the same `link_id` in another collection, with a base present and, when the placement has a body, that body as `base_object`: a server-side copy from that handle rather than an upload. A binding whose base holds another body would copy what the server has, not what the placement intends. Origins are derived from bindings, never stored.

**Probes.** A `probes` row projects as a placement with a handle, the reported flags, no link id, level `Probed` and no base. A `Meta` fetch names it; until then it is a member the engine must not lose (STORAGE §4.3).

## 4. The remote seam

A connector answers three requests.

**Enumerate** returns a snapshot: `items` (handle, known flags, optional revision), `vanished`, `complete` (every member listed, or only the changed since the checkpoint), and the new `checkpoint`. `items` SHALL be sorted by handle and list each once; an engine sorts an unsorted list and keeps a duplicate's first entry.

**Fetch** takes a tier and a batch of handles and returns per handle the identity hint and summary inputs of Annex A, at `Full` a body (inline or already streamed to its blob path, STORAGE §14), and the body's revision. A batch has no order: a connector MAY fetch concurrently and MUST key results by handle; the engine matches by handle.

**Push** takes a batch of changes and returns an outcome each:

- `Add { handle, link_id, flags, origin, object }`: create by server-side copy from `origin` when present, else by uploading `object`; accepted with the assigned handle.
- `Remove { handle, to, link_id, if_match }`: delete, or relocate into `to` when it does not already hold `link_id` (§5).
- `SetFlags { handle, flags }`: replace the flag set.
- `Update { handle, object, if_match }`: replace a mutable body, gated on `if_match` where supported.

Every change carries an **idempotency key** derived from the collection, the handle, the kind and the state the change makes true. The same derived change keys the same on every run, so a connector logging keys recognises the replay of a push whose record was lost.

## 5. Sync

A sync reconciles one collection against one enumeration. The **candidates** of a full snapshot are the projected placements and the listed members; of a delta, the changed and vanished handles plus every projected placement that is not `Clean`, whose pending push the delta would never revisit. A `Created` placement is a candidate with no remote side. The engine walks both sides in handle order.

**The flag axis** merges element-wise over `(local, base, remote)` and never conflicts. It runs for every placement present on both sides, one whose content axis derived a push included; one handle yields at most one change, so the flag axis then withholds its push and still merges and writes.

It leaves the status alone while the content axis still owes a push, and leaves an unresolved conflict alone.

**The content axis** applies to a mutable kind, which reports a revision. A local body the base does not hold is an `Update` gated on the base revision; a remote revision the base does not hold is a pull, which drops the local body and lowers the level; both is a conflict, resolved by the source's policy. Mail reports no revision and never reaches this axis.

A `Conflict` placement meeting a revision newer than its `conflict_revision` records the new one and drops its `conflict_object`, which described the old revision; the upgrade fetches it anew (§6).

**Conflict policy**: `Manual` (default) marks the binding conflicted with the observed revision and asks for the diverging body (§6). `PreferRemote` drops the local edit. `PreferLocal` pushes the local body gated on the observed revision, falling back to `Manual` when content pushes are forbidden.

`KeepBoth` pulls the remote and stages the local body as a new `Created` item under a provisional handle made of the placement's handle, the body's hash and the revision it forked against, joined by `U+0001`, and under the minted key `dup:<hint>#<that handle>` (STORAGE §9): a second copy of one identity, kept beside the first. A replay stages the same row. A create colliding with a remote member on the same identity is always kept as a conflict.

**Deletes.** A `Tombstone` derives a `Remove`. A member absent from a complete enumeration, or listed vanished by a delta, is dropped with reason `Deleted` (§10). A remote edit over a local tombstone revives it and pulls: new content beats a delete on both sides.

A revision the tombstone's base does not name is a remote edit, an enumeration carrying no body to say otherwise. A move whose staged edit was pushed ahead of its remove and whose push record was lost is therefore abandoned rather than half-applied: the member stays in the source, live and clean at the pushed revision, and the consumer restages the move.

**Push direction and rights.** A source has a master `push` switch and four rights: `flags`, `content`, `add`, `remove`. With `push` false nothing is pushed and remote changes are still pulled; a forbidden kind keeps its change pending while other kinds propagate. A refused delete follows the **delete policy**:

`Revert` (default) undoes the delete alone and lands the placement on what it still owes, since a held tombstone hides a member an incremental source never lists again; `Keep` holds it. A source bound beside other sources (§9) SHALL be given `Keep`, a revert reading as a resurrection there.

**A move** is a `Created` placement in the target plus a `Tombstone` in the source, each derived by its own collection's sync in either order and each able to deliver alone: the create by copy from its origin, the remove by relocating into the destination when it does not already hold the identity, by a plain delete when it does. Neither half may be dropped for the other.

An unresolved identity stages the source half alone.

**Push discipline.** A push is confirmed before local state moves: `Accepted` rebases the placement, and for an add supersedes the provisional handle in the same batch; `Rejected` or unreported leaves it pending. Pushes go in bounded chunks, each followed by the write recording its outcomes. The checkpoint lands in the write after the last chunk and in no earlier one.

**Events.** A sync reports per item, in order, what the remote changed locally and what the run settled: `Added`, `FlagsChanged`, `ContentChanged` and `Vanished` on a pull, `Conflicted` on a divergence, `Created` on an accepted add under its assigned handle. A pushed flag, body or delete reports nothing: the consumer made it.

## 6. Upgrade

An upgrade raises placements up the ladder `Probed`, `Meta`, `Full` at the tier asked for. Enumeration stops at the first rung; hydration is what a consumer runs for the members it wants.

**Identity is resolved once**, at the first fetch carrying a hint; a later fetch never re-identifies a linked placement. A `Meta` fetch of a probe names it: item and binding inserted, probe dropped, one transaction. The key follows STORAGE §9: the hint when free, a minted `dup:<hint>#<handle>` when this source already binds the hint under another handle, minted again over a held key.

Minting is decided against the whole collection and from the handles, not reply order, so a rebuild mints the same key.

**Linking instead of fetching.** A `Full` upgrade of an immutable kind asks `lookup_objects` for the placement's key and adopts a body the store holds, recording it as the base too. A mutable placement, a conflicted one, and one under a writer-derived key are fetched, never linked.

**Claims are revisited.** A level claiming a tier the row does not hold (`Full` with no object, `Meta` with no summary) is fetched again. A fetch carrying no body writes the level the payload supports, never lower than the row holds. The sort key is adopted from every fetch; the link id is not.

**A conflict's body.** A conflicted placement holding no `conflict_object` is revisited, and the body fetched lands in `conflict_object`, never in its own object.

**Rows.** Every fetch writes the summary row and address rows Annex A derives, in the batch recording the fetch.

## 7. Mutate

A mutation stages a local edit to one collection with no network, through the same write as a sync (§10), never by direct row edits. The queue's actions map onto them: `set-flags` to `SetFlags`, `remove` to `Remove`, `move` and `copy` to `Move` and `Copy`, `update` to `Edit`, `add` to `Add`.

- `SetFlags` replaces the flags and marks the placement `Dirty`; a `Created`, `Conflict` or `Tombstone` placement keeps its status.
- `Remove` tombstones the placement, binding and base kept so the remove is pushed against the right handle.
- `Edit` stores a new body and repoints the placement, keeping the base. An edit whose object the base holds stages nothing. On a conflicted placement it resolves, the base adopting `conflict_revision` and `conflict_object` together; on a tombstone it revives, `Dirty`, dropping any move destination. It MAY restate the sort key.
- `Copy` stages a `Created` placement in a target under a provisional handle with the source's origin; `Move` also tombstones the source. Both read the target and mint the key when a live placement there already holds the identity; a tombstoned holder blocks nothing.
- `Add` stages a new item under a provisional handle at `Full`, no base, no origin. It SHALL fail when a live placement holds the `link_id`; a retained one revives (STORAGE §11); a tombstone does not block.

## 8. Rekey

A source may renumber every member (an IMAP `UIDVALIDITY` bump, a restore). A rekey re-enumerates the spine and carries each placement's body, summary, level, flags, base and pending state onto its new handle **by link id**, the one identifier that survived. A resync would instead delete the collection and lose every staged edit.

The batch drops each old handle it re-writes with reason `Rekeyed`, which licenses the binding to move (STORAGE §10, §12), per handle: a genuine duplicate in the same batch is still refused. A handle the new space lacks is dropped `Deleted`.

A member resolving to an identity already handed out takes the minted key an old copy carried, else a mint over its own handle; pending creates' keys count as taken. The sort key is carried, preferring the fetch's.

The batch and the epoch bump commit together, and the batch carries no op for the bump: a batch holding a `Rekeyed` drop is a rebuild, and the storage bumps the collection's generation in the transaction that applies it (STORAGE §12).

## 9. Several sources

N sources hold one item per identity and one binding each. A change one source folded into the item reads as `Dirty` against every other source's base, and each source's next sync pushes it. There is no cross-merge.

**Absorbing a write** folds a source's batch into the shared item: flags adopted, a body adopted or refused by the rule below, the level merged as a maximum under §3's body rule. A known flag set, sort key or summary replaces a known one; an unknown one leaves the shared value alone. A tombstone adopts no content.

**Two bases.** `base_object` is what the source last agreed with its remote and only a sync moves it. `shared_object` is what it last agreed with the shared item and every live upsert moves it. The cross-source comparison is made from `shared_object`, falling back to the sync base until the source has folded once.

**Cross-source content.** An upsert whose body differs from the source's base while the shared body differs from what the source last agreed with is a divergence, resolved by the collection's `conflict` policy: `manual` flags the item and records the diverging body; `prefer-incoming` adopts; `prefer-existing` keeps. Only the source changing is a fast-forward.

An upsert leaving a conflicted binding counts as the source having changed its body. Flags never conflict.

**Deletes propagate.** A `Deleted` drop or a `Tombstone` upsert marks the item deleted; the dropping source loses its binding, a tombstoning one keeps it. Every other source projects a `Tombstone`; a source lacking the item projects nothing. A live upsert clears `deleted`. With no binding left the item is retained (STORAGE §11). A `Superseded` or `Rekeyed` drop marks nothing.

**Propagation is hydration-safe.** A source lacking an item is offered it only when the store holds the body, and a projection never raises a level. Mirroring is a sync plus an upgrade.

**A per-source conflict is its own fact.** `bindings.conflicted` and `items.conflicted` never set each other. An upsert carrying no divergence clears the binding's and becomes the shared body, so resolving is an ordinary edit. A tombstone projected for a conflicted binding still carries the divergence.

A binding with no base is a pending create, and a minted key is an ordinary key: it reconciles, propagates and conflicts like any other, a target's refusal reported as a rejected push.

## 10. The load and the write

Every verb begins with a load naming a collection and a **scope**: `All`, `Handles` or `Links`. A mutation asks for the one placement it edits, or for every holder of the link id an `Add` must not collide with; an upgrade asks for the handles it raises; a sync and a rekey ask for the whole collection, being the only verbs that reason about what is missing from it. A `Copy` or a `Move` also loads its target for the identity it carries into it. The scope is a floor: a storage SHALL return at least the placements it names and MAY return more (STORAGE §14). A `Links` load answers who holds the key: it SHALL NOT return the `Created` placement the projection offers for an item the source lacks, else an upgrade settling a fetched identity reads another source's copy as this source's holding and mints a key over it (§6).

Every verb ends in a batch applied in order and atomically (STORAGE §14): `UpsertPlacement`, `DropPlacement { handle, reason }`, `StoreObject { hash, size, bytes? }`, `SetCheckpoint`. A drop's reason says why the row goes: `Deleted`, the member is gone from the source; `Superseded`, a provisional handle an accepted add replaced; `Rekeyed`, a handle a rebuild renumbered (§8). Order carries meaning (a batch names one handle twice to supersede a provisional one) and a storage MUST NOT reorder. A batch is cut between candidates, never inside one.

An unlinked upsert for a handle a binding holds folds into that binding's item; only a handle nothing holds is a probe. An upsert resolving a binding to a different handle is refused, except through a `Superseded` or `Rekeyed` drop of the bound handle in the same batch. A `Deleted` drop of a source's last binding retains the item.

A `StoreObject` carries bytes or references a body already streamed to its blob path; a `Full` fetch MAY stream it there itself. The checkpoint is per source and lands last (§5). Summary and address rows are written with the placement they describe; stamps follow from the rows (STORAGE §4.5).

## 11. Test vectors

vectors/sync/ holds cases every conforming engine MUST reproduce, one JSON file each: `store`, the rows before the run, bodies named by label; `run`, the verb, collection, source and options; `remote`, the snapshot and the fetch answers by handle and tier; `expect`, the pushes in order, the outcomes fed back, and the rows after.

Rows are compared as parsed structures, `changed` stamps and `retained_at` instants excluded. Chunked pushes or writes are compared concatenated. checks/vectors.py validates shape and references; only an implementation runs one.
