# Pimdir sync specification

Status: draft-04

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

An engine reads a store as one source, derives what that source and the store owe each other, and writes the result. Five verbs: **open** (read the projection, no network), **sync** (reconcile against a listing, a delta or a round of pages), **upgrade** (raise items to their body, or revisit a claim), **mutate** (stage a local edit offline), **rekey** (rebuild a collection onto a new handle space).

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
- **Meta**: what names a member without its body: the identity hint, the summary and address rows and the `sort_key` STORAGE Annex A derives. Every member a listing carries carries its meta (§4).
- **Page**: what one enumeration request returned: members with handle, flags, revision and meta, vanished handles, whether it belongs to a round or a delta, whether it is the last of its listing, its resume cursor and the checkpoint when it carries one.
- **Round**: one complete listing of a scope, in one page or several, under an id drawn when it opens; it stamps the bindings it lists and closes when its last page lands (§5).
- **Delta**: a listing of what changed since the checkpoint, one page, always the last.
- **Scope**: `[since, until)` on a message's summary `date`, either bound open: what a round lists and the only place its absence means anything (§5). Mail only.
- **Coverage**: the scope of the last round that closed and when it closed, which is the scope the checkpoint serves (STORAGE §4.3).
- **Resume cursor**: the connector's opaque position in an open round, landed with each page.
- **Change**: what the engine asks a source to do: `Add`, `Remove`, `SetFlags`, `Update`, each with an idempotency key (§4).
- **Outcome**: `Accepted`, with the handle assigned to an `Add` and the revision a mutable kind reports, or `Rejected`.

## 3. The projection

Placements are read from the store, never stored. For a collection and a source, the projection MUST yield one placement per item the source binds and one `Created` placement per item the source lacks and the store holds a body for. A retained item (STORAGE §11) MUST be projected for nobody.

**Status**, the first that applies:

1. `Conflict` when `bindings.conflicted` is 1, carrying `conflict_revision` and `conflict_object`, or when `items.conflicted` is 1, two sources disagreeing on the body (§9), which every binding of the item projects until an `Edit` settles it (§7); neither is downgraded.
2. `Tombstone` when `items.deleted` is 1 and the source binds the item; the content is kept so an edit still beats the delete (§5). A tombstone whose binding has no base is a create the consumer withdrew: it derives no `Remove`, the write drops the binding and the item is retained (STORAGE §11).
3. `Created` when the binding has no base (`base_present` 0, every base column `NULL`), or the source does not bind the item, `items.deleted` is 0 and `object_hash` is present.
4. `Dirty` when the flags differ from `base_flags`, both known, or, for a mutable kind, `object_hash` is present and differs from `base_object`, a base naming no body differing from every body. A placement holding no body owes no body, whatever its base names.
5. `Clean` otherwise.

An unknown flag set (`NULL`) holds no opinion: neither an addition nor a removal, and an unknown base is no base on the flag axis. An immutable kind never owes a body: one identity is one message, and the write adopts the shared body as its base (§9).

**Level** MUST be `Full` only when `object_hash` is present, whatever `items.level` claims, so an item whose body a remote change dropped projects at most `Meta` and an upgrade refetches it. A level of `0`, which an earlier draft wrote for a probed or pulled row, MUST be read as `Meta`, a claim the row may not hold (§6), and is never written.

**Origin.** A `Created` placement carries an origin when the same source binds the same identity in another collection, with a base present and, when the placement has a body, that body as `base_object` (`origin_for_link`): a server-side copy from that handle rather than an upload. A binding whose base holds another body would copy what the server has, not what the placement intends.

**Destination.** A `Tombstone` placement carries a destination when the same source holds a pending create of the same identity in another collection (`destination_for_link`), named by that create's handle: the relocation its remove offers (§5).

**The same identity**, for both, is the same `link_id`, or the one minted over the provisional handle the other derives (`dup:`, the key, `#`, `U+0001` and the key again): the key a `Copy` or a `Move` gives its create beside a live holder (§7). The bare key MUST be preferred. Origins and destinations are derived from bindings, never stored, so both read the same after a crash and after a hub folded the item.

## 4. The remote seam

A connector answers three requests.

**Enumerate** takes the checkpoint, the scope (§5) and, resuming a round, its resume cursor, and returns a page: `items`, every member with its handle, its known flags, an optional revision and its meta; `vanished`, the handles the source states removed; `complete`, whether the page belongs to a round, every member of the scope listed across its pages, rather than to a delta; `last`, whether it closes its listing, which a delta's one page always does; `cursor`, an opaque resume cursor on every page of a round but the last; and `checkpoint`, on the page where the source gives one. Within a page `items` SHALL be sorted by handle in byte order, the one order two engines over one store agree on, and list each once; an engine MUST sort an unsorted page and keep a duplicate's first entry. A connector whose checkpoint the source rejects because the handle space changed (an IMAP `UIDVALIDITY` bump) MUST fail the enumeration and name a rekey (§8) rather than answer a round of new handles, which a sync would read as every member gone and every new one arrived.

**Members arrive named.** A member's meta MUST come with it, as a `Meta` fetch would return it: the identity hint, and the summary inputs and the `sort_key` of STORAGE Annex A. Mail reads it in the listing itself: IMAP from the same `FETCH` (`UID FLAGS INTERNALDATE ENVELOPE` and the header fields Annex A needs, `Content-Type` among them, no `BODYSTRUCTURE`), Graph from its `$select`, Gmail from the metadata read it already makes (`Content-Type` among its `metadataHeaders`), JMAP from `Email/get` with summary properties. A kind whose meta is the body (DAV, Google Agenda, People) fetches each page's bodies (`multiget`) before it hands the page over, and its members MAY carry the body, as a `Full` fetch does. Nothing reaches the store unnamed.

**Pages.** A round MAY be answered in pages, newest first in the source's own recency order: IMAP by UID descending, Graph's message delta, which already answers by `receivedDateTime` descending, Gmail's list order, JMAP by `receivedAt` descending. Each page is one request, or one batch of requests, and one write (§5); a round of one page is the complete enumeration of a connector that does not page. The default page sizes are safe on a slow network and under every provider's limits:

| Source | Page | Why |
| --- | --- | --- |
| IMAP | 500 UIDs per `UID FETCH` | `ENVELOPE`, flags, `INTERNALDATE` and a few header fields are under 1 KB a message: half a megabyte a response, short enough to resume cheaply |
| Graph message delta | 1,000 (`Prefer: odata.maxpagesize=1000`) | honoured with the summary `$select`, the first page in under 3 s |
| Gmail | 100 ids per `messages.list`, their metadata read in batches of 50 | Google advises batches of 50 at most; 100 reads paced near 40 a second commit every 2.5 s |
| JMAP | 500, capped by the server's `maxObjectsInGet` | the server states its own ceiling |
| DAV, Google Agenda, People | 64 bodies per `multiget` or batch | one body batch |

A connector MAY lower a page after a timeout or a `413`, and MUST NOT raise one past these without a measurement.

**The resume cursor** is the connector's and opaque to the engine. A connector whose cursor the source rejects (an expired Graph skip token, a Gmail page token) MUST fail the enumeration and name a restart (§5) rather than answer from the beginning as if it resumed.

**The checkpoint** a round carries is the one taken when it began, where the source gives one up front (IMAP `HIGHESTMODSEQ` at the select, Gmail's `historyId`, JMAP's state), handed with the first page, so what moves during the round is caught by the next delta. Graph gives its delta link only on the last page of the round, and that link covers the round itself. A connector states whether its checkpoint is **bound to the scope** it was made under: a Graph delta link made under a `$filter` is; IMAP `CHANGEDSINCE`, Gmail's history and JMAP's state, filtered locally, are not.

**Fetch** takes a tier and a batch of handles and returns per handle the identity hint and summary inputs of Annex A, at `Full` a body (inline or already streamed to its blob path, STORAGE §14), and the body's revision. A batch has no order: a connector MAY fetch concurrently and MUST key results by handle; the engine matches by handle.

**Push** takes a batch of changes and returns an outcome each:

- `Add { handle, link_id, flags, origin, object }`: create by server-side copy from `origin` when present, else by uploading `object`; accepted with the assigned handle. A connector to a mutable kind MUST report the revision the member holds once accepted, else the next enumeration reads its own push as a remote edit and refetches it.
- `Remove { handle, to, link_id, if_match }`: delete when `to` is absent or already holds `link_id` (§5); relocate into `to` otherwise. `link_id` is the tombstone's key, and MUST be absent when its destination is a create under a minted key (§3): `to` held the identity before the move, so holding it proves no delivery. A connector that cannot relocate MUST reject the change rather than delete: the destination has not received the member, and a delete would take the only copy.
- `SetFlags { handle, flags }`: replace the flag set.
- `Update { handle, object, if_match }`: replace a mutable body, gated on `if_match` where supported; accepted with the revision the member holds, on `Add`'s terms.

**The idempotency key.** Every change carries a key naming it, so a connector logging keys recognises the replay of a push whose record was lost, and a chunk replayed after a crash (§5) applies once. The key MUST be derived as follows, so two engines over one store key one change alike:

- FNV-1a, 64 bits (offset basis `cbf29ce484222325`, prime `100000001b3`), over a sequence of fields, each field's bytes followed by one `0x00` byte, rendered as sixteen lowercase hexadecimal digits.
- The fields, in order: the collection id, the handle, the kind as `add`, `remove`, `set-flags` or `update`, then the kind's own. An optional value is the field `1` followed by the value's field, or the field `0` alone. A flag set is the field `unknown` when unknown, else the field `known`, the count in decimal ASCII, then each flag in code point order.
- `add`: the link id (optional), the flags, the origin as `1`, its collection and its handle, or `0` alone, then the object hash (optional). `remove`: `to` (optional). `set-flags`: the flags. `update`: the object hash.

A precondition (`if_match`) is not part of the key: a retry of one operation is one operation. The key names a push within one run, not for ever: a flag set restored, or a body pushed again against a newer revision, is a new change under an old key. A connector logging keys MUST forget them once the checkpoint after their chunk has landed, and MUST NOT answer a key it remembers from an earlier checkpoint as a replay. §11's vectors carry the key of every push.

## 5. Sync

A sync reconciles one collection against one listing: a delta from the checkpoint, or a round of one page or several. The **candidates** of a round's last page are every projected placement and the page's members; of a delta, the changed and vanished handles plus every projected placement that is not `Clean`, whose pending push the delta would never revisit; of a page before the last, its members and vanished handles alone. A `Created` placement is a candidate with no remote side. The engine MUST walk both sides in handle order. Every member a page carries is named in the page's write on §6's identity rules, minting decided against the whole collection and a pending create landed rather than minted.

**The scope.** A source MAY sync a mail collection under a scope `[since, until)`, `until` open in the usual case. A member is in scope when its summary `date` (STORAGE Annex A.1) falls in it, or when it has no usable `date`, which is rare, small and never lost: a draft before sending, a server's own notice. The `Date` header decides, always: it is the same on every provider and every copy, and it is what a list sorts by. A received date is never stored and never decides. A connector MAY narrow its listing by the provider's received-date filter (Graph delta's `receivedDateTime ge`, Gmail's `after:`, JMAP's `after`) to a superset of the scope, and MUST then take it with a margin of two days below `since`, for clock skew, time zones and Gmail's midnight in Pacific time; IMAP narrows with `SENTSINCE` and `SENTBEFORE` with a margin of one day, their whole days being the server's. The connector drops what its own check on the `Date` puts out of scope; the engine filters no page by date and names every member a page carries. A scope on a collection of another kind MUST be refused, naming the kind.

**Absence means deleted only in scope.** A round reconciles the placements in its scope and leaves the others alone: a placement out of scope that no page listed is neither dropped, nor pulled, nor pushed on the evidence of its absence. A removal the source states, a vanished handle (IMAP `VANISHED`, Graph's `@removed`, Gmail's deletion history, JMAP's `destroyed`), applies whatever the date.

**Local changes push whatever the scope.** Tombstones, moves, flag changes, creates and intents are the consumer's, owed to no listing, and no scope holds them back, save the one create below.

**A sync never deletes on the server on its own account.** A `Remove` MUST be derived from a tombstone the consumer staged (§7) and from nothing else: not from a scope, a narrowing, a widening, an interrupted round, a restarted round, a collection (STORAGE §11.3) or any absence. What a sync infers from the remote it applies to the store alone.

**Choosing the listing.** The checkpoint serves the scope it was made under, which is the coverage (STORAGE §4.3), and any scope inside it. A run under a scope:

1. resumes the open round from its cursor when the round's scope is the one asked for, and the round lists a band exactly when the run would;
2. else opens a round over the scope asked for when no round has closed (no coverage, a checkpoint from an earlier draft included, whose store held probes this draft no longer keeps), when a round is open over another scope or listing a band where the run would not (or the reverse), or when the scope reaches outside the coverage. A connector whose checkpoint is bound to no scope MAY instead list only the band the coverage lacks, when that band adjoins the coverage: the round's scope is the band, recorded as a band round when it opens (`open_round`), its listing need carry no undated member, and the connector keeps its checkpoint and hands none;
3. else runs a delta from the checkpoint, its listing checked against the scope asked for, and records that scope as the coverage when it is narrower (`set_coverage`): a checkpoint made under a scope serves any scope inside it.

**Rounds.** A round opens in the write of its first page (`open_round`), which draws its id. Each page is merged as a delta whose only removals are the vanished handles it carries, and lands in one write: its members named, its bindings stamped with the round's id after its upserts (`stamp_bindings`), whether a member moved or not, its cursor and the checkpoint it carries recorded (`set_round_cursor`). A round interrupted between pages keeps what landed and resumes from its cursor. A round whose cursor the source rejects restarts: a round over the same scope opens under a new id, so the stamps of the abandoned listing protect nothing, and the members it named are matched again by handle, which costs a relisting and no fetch. A round belongs to its source: it stamps that source's bindings alone, and another source's stamps, round and coverage are its own.

**Deletes are inferred once,** when the last page lands, and in scope only: every based binding of this source the round did not stamp, whose item's `date` falls in the round's scope, or is unknown and the round is no band round (`list_unstamped_bindings`), is a member the round found absent, and is handled as the deletes below say. A band round MUST NOT infer the delete of an undated member: a band is listed by a date filter, which returns no undated mail, so absence from it proves nothing. Undated members are reconciled by rounds over a whole scope and by deltas, and a removal the source states applies to them whatever the round. A round resumed from the store and one the run opened MUST infer the same deletes. A pending create is no member of the remote and is never absent. The round closes in the write after its last chunk (`close_round`): the checkpoint it carries becomes the source's, the old one kept when it carries none, and the coverage becomes the round's scope, or for a band round the span of the band and the coverage it adjoins, stamped with the instant.

**Creates wait for the page that lands them.** An `Add` MUST NOT be derived before the last page of an open round has landed, nor in a delta before its members are named: a member a page carries may be that create's own arrival, relocated by a move's other half, added by another client or by an add whose record was lost, and pushing before it lands makes a second copy. The page naming it lands the create (§6), and the run pushes what is left. A pending create carrying no origin whose `date` the run's scope excludes may be an arrival no page of that scope lists, a relocated message keeping its `Date`: its `Add` MUST NOT be derived by a run whose scope excludes its date. It waits for a round over a scope holding it, and an engine SHOULD report it while it waits.

**The flag axis** merges element-wise over `(local, base, remote)` and never conflicts: a flag is in the result when both sides carry it, or when one side carries it and the base does not, an addition; it is out when the base carries it and either side does not, a removal. With no base, the result is the union of the two known sets, no side being known to have removed anything. It MUST run for every placement present on both sides, one whose content axis derived a push included; one handle yields at most one change, so the flag axis then withholds its push and still merges and writes.

A content push accepted in the same run MUST rebase the placement the flag merge wrote, never the one read before it, or the pulled flag is lost until an enumeration happens to relist the item.

It leaves the status alone while the content axis still owes a push, and leaves an unresolved conflict alone.

**The content axis** applies to a mutable kind, which reports a revision. A local body the base does not hold is an `Update` gated on the base revision. A remote revision the base does not hold is a pull: the member's meta becomes the summary, address rows and sort key, and the member's body, when it carries one, becomes the body and the base at its revision, as a fetch's does (§6); a member carrying none drops the local body and lowers the level to `Meta`. A placement holding no body, a pull having emptied it, owes nothing until the upgrade refetches it. A placement whose local body the run keeps, pushed or conflicted, keeps that body's summary.

Both is a conflict, resolved by the source's policy. Mail reports no revision and never reaches this axis.

A `Conflict` placement meeting a revision newer than its `conflict_revision` records the new one and drops its `conflict_object`, which described the old revision; the upgrade fetches it anew (§6). One carrying no `conflict_revision`, the item's conflict (§9), and meeting a revision its base does not hold MUST mark the binding conflicted with that revision and ask for the diverging body, whatever the source's policy, reported as `Conflicted`: the item's conflict is still open, so the source's own divergence is recorded beside it rather than pulled or pushed into it, and an incremental enumeration never lists the member again. A conflict whose fetched body equals the placement's own is no divergence, the push whose record was lost having landed: the binding adopts the revision and body as its base and the conflict clears.

**Conflict policy**, the source's, settling it against its own remote: `Manual` (default) marks the binding conflicted with the observed revision and records the diverging body in `conflict_object` when the member carries it, else asks the upgrade for it (§6). `PreferRemote` drops the local edit and pulls. `PreferLocal` pushes the local body gated on the observed revision, falling back to `Manual` when content pushes are forbidden.

The collection's `conflict` (STORAGE §4.3) is the other axis, settling the shared item between sources (§9), and the two are named apart on purpose.

**Deletes.** A `Tombstone` derives a `Remove`, carrying its destination when it has one (§3). A member a round found absent, or a vanished handle, is dropped with reason `Deleted` (§10), unless its placement holds a body its base does not, a local edit the remote never saw: new content beats a delete on both sides, so that placement is re-staged instead as a pending create under a provisional handle, its binding kept without a base, and the next run adds it. A remote edit over a local tombstone MUST revive it and pull; a tombstone also holding a local edit is the both-changed case and follows the policy.

A revision the tombstone's base does not name is a remote edit, an enumeration carrying no body to say otherwise. A move whose staged edit was pushed ahead of its remove and whose push record was lost is therefore abandoned rather than half-applied: the member stays in the source, live and clean at the pushed revision, and the consumer restages the move.

**Push direction and rights.** A source has a master `push` switch and four rights: `flags`, `content`, `add`, `remove`. With `push` false nothing is pushed and remote changes are still pulled; a forbidden kind keeps its change pending while other kinds propagate. A rejected push is pending like any other and follows no policy.

**A refused delete**, one the source's rights forbid, is decided per collection from the other sources syncing it, any holding a binding or a checkpoint there (`collection_sources`). Beside another source the tombstone is held, since a revert would read as a resurrection there and the other source pushes the delete; the row stays in the trash view until that source has dropped it (STORAGE §11). A source alone in the collection reverts the delete and the placement lands on what it still owes, since a held tombstone would hide a member an incremental source never lists again.

**A move** is a `Created` placement in the target plus a `Tombstone` in the source, each derived by its own collection's sync in either order and each able to deliver alone. Neither half MUST be dropped for the other.

The create delivers by copy from its origin, or by upload when the store holds the body. The remove delivers by relocating into its destination, which the connector MUST reject when it cannot relocate (§4), and is a plain delete once the destination holds the identity the move delivered, a copy the target held before the move not being that delivery (§4). A create landed first, by its copy from the origin, leaves no destination, and the remove is then a plain delete.

A relocated member is listed by the target's next listing under a new handle, and the page naming it lands the create (§6); until then the create waits, as every create waits for the page that lands it.

**Push discipline.** A push MUST be confirmed before local state moves: `Accepted` rebases the placement, and for an add supersedes the provisional handle in the same batch; `Rejected` or unreported leaves it pending, and an engine SHOULD report a create rejected on consecutive runs rather than push it for ever. Pushes go in bounded chunks, each followed by the write recording its outcomes, and the owner MUST NOT collect between two chunks (STORAGE §5). The checkpoint, a delta's or the one a round closes with, MUST land in the write after the last chunk and in no earlier one; a page's cursor and the checkpoint an open round carries are not the source's checkpoint, and land with their page.

**Events.** A sync reports per item, in order, what the remote changed locally and what the run settled: `Added` for a member named, `FlagsChanged`, `ContentChanged` and `Vanished` on a pull, `Conflicted` on a divergence, `Created` on an accepted add under its assigned handle and on a create a listing landed under the handle it lists. A pushed flag, body or delete reports nothing: the consumer made it. Only a sync reports events: an upgrade, a mutation and a rekey deliver what the consumer asked for and report none.

## 6. Upgrade

An upgrade raises placements to `Full`, or revisits at `Meta` a claim the row does not hold. A listing names every member at `Meta` (§4); hydration is what a consumer runs for the members it wants. The identity rules below are those a page names its members by.

**Identity is resolved once**, at the first meta carrying a hint, a listing's or a fetch's; a later one MUST NOT re-identify a linked placement of an immutable kind. A mutable resource whose later meta states another hint under the same handle is a new identity there, on the terms STORAGE §9 sets for a changed `hash:` key: the old binding is retired and the resource keyed afresh. Naming a member inserts its item and binding in the write of the page that lists it. The key follows STORAGE §9: the hint when free, a minted `dup:<hint>#<handle>` when this source already binds the hint under another handle, minted again over a held key.

Minting MUST be decided against the whole collection and from the handles in byte order, not reply order, so a rebuild mints the same key; a page or an upgrade therefore loads the hints it carries by key (§10) before it assigns any.

**A pending create is landed by its arrival.** A hint a page or a fetch carries that the collection holds as a pending create of this source (§2), keyed by the hint or by the hint minted over the provisional handle it derives (§7), the bare key first, is that create delivered: by a relocation (§5), by an accepted add whose record was lost, or by another client. The engine MUST land it rather than mint; only a hint held by a based binding is minted.

Landing is a `Superseded` drop of the provisional handle in the same batch, the binding moved to the listed one, and the base set to the flags the listing or the fetch reported and, for an immutable kind, the staged body, one identity being one message. For a mutable kind the base takes the listed revision and the body when the listing or the fetch carried one; a fetched body differing from the staged one is the content axis's both-changed case (§5). The flags and body staged on the create stay, so an edit made on it still pushes.

**A fetch moves the base.** A fetch carrying a body over a placement holding no local edit sets `base_object` to that body and `base_revision` to its revision, whatever the placement's level was, so the next sync reads the fetched body as agreed and not as an edit to push. Over a placement holding a local edit, a body its base does not hold, the fetched body lands as the base and the local body stays when the revision is the base's, and the both-changed case applies when it is not.

**Linking instead of fetching.** A `Full` upgrade of an immutable kind asks `lookup_objects` for the placement's key and adopts a body the store holds, recording it as the base too, when the summary the source served agrees with the held body on `size`, else fetching: two messages under one `Message-ID` with different bytes are the wrong merge §9 avoids. A source stating a size that is not the octets (Annex A.1) links only where the two happen to agree, a missed link costing a fetch and never a merge. A mutable placement, a conflicted one, and one under a writer-derived key MUST be fetched, never linked.

**Claims are revisited.** A level claiming a tier the row does not hold (`Full` with no object, `Meta` with no summary, `0` from an earlier draft) is fetched again, which is what the `Meta` tier remains for. A `Meta` row holding its summary claims nothing, whether its body was never fetched or released (STORAGE §11.4): a listing names it as it names any member, fetching nothing, pushing nothing and inferring no delete. A fetch carrying no body writes the level the payload supports, never lower than the row holds, and never `0`. The sort key is adopted from every fetch and every listing; the link id is not. A summary column the body was read for, the attachment mark and the size, is never replaced by one read without it while the row holds the body (STORAGE Annex A.1).

**A conflict's body.** A conflicted placement holding no `conflict_object` is revisited, and the body fetched MUST land in `conflict_object`, never in its own object.

**Rows.** Every fetch and every page writes the summary row and address rows Annex A derives, in the batch recording it.

## 7. Mutate

A mutation stages a local edit to one collection with no network, through the same write as a sync (§10), never by direct row edits. The queue's actions map onto them: `set-flags` to `SetFlags`, `remove` to `Remove`, `move` and `copy` to `Move` and `Copy`, `update` to `Edit`, `add` to `Add`.

- `SetFlags` replaces the flags and marks the placement `Dirty`; a `Created`, `Conflict` or `Tombstone` placement keeps its status.
- `Remove` tombstones the placement, binding and base kept so the remove is pushed against the right handle. On a conflicted binding it is the decision: the base adopts `conflict_revision` and `conflict_object` together, as an `Edit` does, and the conflict clears, so the remove pushes gated on what the remote holds; a diverging body not fetched yet leaves `base_object` unknown, never the old body, so an item another source's edit revives reads `Dirty` (§3) rather than in sync; on a conflicted item (§9) it clears the item's conflict the same way. On a pending create it withdraws the create: the binding goes and the item is retained (STORAGE §11).
- `Edit` stores a new body and repoints the placement, keeping the base. An edit whose object the base holds stages nothing. On a conflicted placement it resolves, the base adopting `conflict_revision` and `conflict_object` together; on a conflicted item it resolves too, `items.conflicted` cleared and its `conflict_object` released; on a tombstone it revives, `Dirty`, and the destination its tombstone offered no longer derives. It MAY restate the sort key.
- `Copy` stages a `Created` placement in a target under a provisional handle with the source's origin; `Move` also tombstones the source, whose destination the target's pending create then derives (§3). Both read the target and, when a live placement there already holds the identity, key the create by the identity minted over the provisional handle it derives, minted again over a held key (STORAGE §9); a tombstoned holder blocks nothing. Both MUST be refused for a placement holding neither a body nor a based binding, since nothing could deliver the create.
- `Add` stages a new item under a provisional handle at `Full`, no base, no origin. It MUST fail when a live placement holds the `link_id`; a retained one revives (STORAGE §11); a tombstone still propagating is revived the same way, the row adopting the new body and its delete withdrawn on every source.

A delete meant to land in a trash collection is a relocation: stage it as `Move` into that collection, so the trash shows it at once and the push relocates it (§4). `Remove` fits a delete meant to be final, as from the trash itself.

## 8. Rekey

A source may renumber every member (an IMAP `UIDVALIDITY` bump, a restore). A rekey re-enumerates the spine, which MUST be a round over the whole collection whatever the scope, every page read before its one batch is written: the old handles being void, it is the one listing whose absence covers every member. It carries each placement's body, summary, level, flags, base and pending state onto its new handle **by link id**, the one identifier that survived. A resync would instead delete the collection and lose every staged edit.

The batch drops each old handle it re-writes with reason `Rekeyed`, which licenses the binding to move (STORAGE §10, §12), per handle: a genuine duplicate in the same batch is still refused. It is one batch, every `Rekeyed` drop preceding every upsert, since a new handle may be an old one another member held. A handle the new space lacks is dropped `Deleted`. A binding with no base is outside the rekey: no space ever held its provisional handle, and it is carried as it is.

A member resolving to an identity already handed out takes the minted key an old copy carried, else a mint over its own handle; pending creates' keys count as taken. Where one hint had several old copies, a member is matched to the old copy whose base names its fetched revision first, then to the one holding its body when the fetch carried one, and in handle order only among what neither can tell apart, so a renumbering that swapped two resources under one `UID` carries each one's flags and pending edit onto itself. The sort key is carried, preferring the fetch's.

A mutable member whose fetched revision differs from the one its old base held changed on the remote while the handles did. The engine MUST carry it as a pull (§5), or as a `Conflict` at the fetched revision when it also holds a local edit. A `Conflict` the old handle held is carried as it is, revision and diverging body kept while the fetched revision is the one recorded; one the item's conflict projects (§3) records no revision and gains none unless the remote moved.

A base claiming a revision it never reconciled is the one thing a rekey MUST NOT write: the next sync would read the stale body as current, or push the local edit last-writer-wins.

The batch lands the rekey's checkpoint and leaves the coverage as it was. The batch and the epoch bump commit together, and the batch carries no op for the bump: a batch holding a `Rekeyed` drop is a rebuild, and the storage bumps the collection's generation in the transaction that applies it (STORAGE §12).

## 9. Several sources

N sources hold one item per identity and one binding each. A change one source folded into the item reads as `Dirty` against every other source's base, and each source's next sync pushes it. There is no cross-merge.

**Absorbing a write** folds a source's batch into the shared item: flags adopted, a body adopted or refused by the rule below, the level merged as a maximum under §3's body rule, a pull without a body writing `Meta` since it took the body away. A known flag set, sort key or summary replaces a known one; an unknown one leaves the shared value alone. A tombstone adopts no content and its flags ride along.

**Two bases.** `base_object` is what the source last agreed with its remote and only a sync moves it. `shared_object` is what it last agreed with the shared item and every live upsert moves it. The cross-source comparison MUST be made from `shared_object`, falling back to the sync base until the source has folded once.

**Cross-source content**, mutable kinds only. Three facts are read before the upsert is applied: the source changed when the incoming body differs from the base its binding held before this upsert, not the base the upsert carries; the item changed when the shared body differs from `shared_object`; the two disagree when the incoming body differs from the shared one. All three is a divergence, resolved by the collection's `conflict` policy: `manual` keeps the shared body, flags the item and records the incoming body in `items.conflict_object`, every binding then projecting `Conflict` (§3) until an `Edit` or a `Remove` settles it (§7); `prefer-incoming` adopts; `prefer-existing` keeps. Only the source having changed is a fast-forward; only the item having changed leaves the incoming body behind and the binding `Dirty`, which is propagation.

An immutable kind never diverges: one identity is one message, so a body differing from the shared one is the same message served differently, the shared body stands and the binding's base adopts it. An upsert leaving a conflicted binding counts as the source having changed its body. Flags never conflict.

**Deletes propagate.** A `Deleted` drop or a `Tombstone` upsert marks the item deleted; the dropping source loses its binding, a tombstoning one keeps it. Every other source projects a `Tombstone`; a source lacking the item projects nothing. A live upsert clears `deleted`. With no binding left the item is retained (STORAGE §11). A `Superseded` or `Rekeyed` drop marks nothing.

**Propagation is hydration-safe.** A source lacking an item MUST be offered it only when the store holds the body, and a projection never raises a level. Mirroring is a sync plus an upgrade.

**A per-source conflict is its own fact.** `bindings.conflicted` and `items.conflicted` never set each other. An upsert carrying no divergence clears the binding's and becomes the shared body, so resolving is an ordinary edit. A tombstone projected for a conflicted binding still carries the divergence.

A binding with no base is a pending create, and a minted key is an ordinary key: it reconciles, propagates and conflicts like any other, a target's refusal reported as a rejected push. A `hash:` key is not offered to another source: it asserts no identity, and a server re-serialising the body hands it back under another key, one new item per run on each side.

## 10. The load and the write

Every verb begins with a load naming a collection and a **scope**: `All`, `Handles` or `Links`. A mutation asks for the one placement it edits, or for every holder of the link id an `Add` must not collide with; an upgrade asks for the handles it raises; a delta, the last page of a round and a rekey ask for the whole collection, being the only steps that reason about what is missing from it, and a page before the last asks for `Handles` of its members and `Links` of the hints they carry, which naming them needs (§6). A `Copy` or a `Move` also loads its target for the identity it carries into it. The scope is a floor: a storage SHALL return at least the placements it names and MAY return more (STORAGE §14). A `Links` load answers who holds the key: it SHALL NOT return the `Created` placement the projection offers for an item the source lacks, else an upgrade settling a fetched identity reads another source's copy as this source's holding and mints a key over it (§6).

Every verb ends in a batch applied in order and atomically (STORAGE §14): `UpsertPlacement`, `DropPlacement { handle, reason }`, `StoreObject { hash, size, bytes? }`, `SetCheckpoint`, and for a sync the round's own: `OpenRound { since, until }`, first in its first page's batch; `Stamp { handles }`, after the page's upserts; `SetRoundCursor { cursor, checkpoint }`; `CloseRound { since, until, checkpoint }`, last in the write after the last chunk; `SetCoverage { since, until }`, beside a delta's checkpoint. A drop's reason says why the row goes: `Deleted`, the member is gone from the source; `Superseded`, a provisional handle an accepted add or a landed arrival replaced (§6); `Rekeyed`, a handle a rebuild renumbered (§8). Order carries meaning (a batch names one handle twice to supersede a provisional one, a rebuild drops every old handle before it upserts any new one) and a storage MUST NOT reorder. A batch is cut between candidates, never inside one, and a rekey is never cut.

An unlinked upsert for a handle a binding holds folds into that binding's item; one for a handle nothing holds MUST be refused, nothing reaching the store unnamed. An upsert resolving a binding to a different handle is refused, except through a `Superseded` or `Rekeyed` drop of the bound handle in the same batch. An upsert resolving a bound handle to a different link id retires the old binding first (STORAGE §10). A `Deleted` drop of a source's last binding retains the item.

A `StoreObject` carries bytes or references a body already streamed to its blob path; a `Full` fetch MAY stream it there itself. The checkpoint is per source and lands last (§5). Summary and address rows are written with the placement they describe; stamps follow from the rows (STORAGE §4.5).

## 11. Test vectors

vectors/sync/ holds cases every conforming engine MUST reproduce, one JSON file each. `store` is the rows before the run, bodies named by label, summaries by their row; `run` the verb, collection, source and options (`push`, `rights`, `conflict`, and `scope` as `since` and `until`), a `mutate` run carrying its `mutation`; `remote` what the connector answers: one page as `snapshot` or a round's pages as `pages`, each member with its `meta` read from a fixture (and the source's own `attachment` flag and `size` where it states them), `cursor_rejected` when it refuses the stored cursor, `interrupted_after` when it fails after that many pages, `scope_bound` false for a checkpoint bound to no scope, and the fetch answers by handle and tier; `expect` the pushes in order, the outcomes fed back, the events, and the rows after. A provisional handle is written with its leading `U+0001`. A source row states its round as `round`, `round_open` and the round's columns, `round_band` among them, and its coverage as `covered` and the coverage's bounds; a binding states its `round`.

A push is compared on its kind, handle and `key` (§4) and on what the kind carries: `flags`, `to` and `link_id`, `if_match`, `origin` as collection and handle, and `object` by label. An outcome names its handle, `Accepted` or `Rejected`, and for an add the `assigned` handle and the `revision` reported.

Rows are compared as parsed structures on the columns a case names, `changed` stamps and the instants SQLite stamps (`retained_at`, `covered_at`, `round_started_at`) excluded, which a case states as present or absent. Chunked pushes or writes are compared concatenated. Every case pins that no `Remove` is pushed but for a tombstone the consumer staged. checks/vectors.py validates shape, references, every push's key and that last rule; only an implementation runs one.
