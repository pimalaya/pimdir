# Pimdir sync specification

Status: sync-draft-08, requiring storage-draft-09

The sync part of the pimdir standard: how one or more sources reconcile through a store ([STORAGE.md](./STORAGE.md)), so the store is an offline replica of each source and every source sees every other's changes. It fixes what an engine derives from the store's rows and a source's answers, and what it writes back.

§12 states what an engine and a connector owe. What every writer owes the store, whichever engine reconciles it, is STORAGE §10 to §12 and §14, the write's interface among them.

*Note:* This part is the costliest to implement: the reference engine, io-pimdir, is meant to be used rather than rewritten, and its I/O-free core runs over any store and any transport.

It fixes no protocol: what a connector hands the engine is §4; how it gets it over IMAP, JMAP or DAV is the connector's.

[OVERVIEW.md](./OVERVIEW.md) §5 and §6 explain the model; [GUIDE.md](./GUIDE.md) §9 to §12 run the verbs as procedures. Both are informative and this part wins on any disagreement.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals, as shown here. Every statement of behaviour in this part is normative: a key word marks its requirement level, and a statement carrying none binds as one carrying MUST. Notes, examples and rationale are informative and marked as such: a paragraph opening with *Note:*, an instance of what a sentence states given in parentheses or after "for example", and a reason given with "so", "since" or "because", none of which adds a requirement. §n of STORAGE.md is written STORAGE §n.

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
12. [Conformance](#12-conformance)

## 1. Scope

An engine reads a store as one source, derives what that source and the store owe each other, and writes the result. Five verbs:

- **open**: read the projection, no network;
- **sync**: reconcile against a listing, a delta or a round of pages;
- **upgrade**: raise items to their body, or revisit a claim;
- **mutate**: stage a local edit offline;
- **rekey**: rebuild a collection onto a new handle space.

Every verb MUST be a pure function of the rows it loads and the answers it is given; its only effects are a write batch (§10) and requests to the remote (§4).

The store is the base of every merge: the bindings hold what each source last agreed to (STORAGE §4.3). This part defines no reconciliation of two sources against each other.

Nothing here requires a language or a coroutine form. A collection of a media type outside STORAGE §13's kinds is recorded with no kind and never synced (STORAGE §14): an engine names none of its members.

## 2. Terminology

- **Source**: one remote a collection syncs with, named in `bindings.source` and `sources.source`.
- **Engine**: the program that runs this part's verbs over a store as its owner (STORAGE §8, §17).
- **Connector**: what answers an engine's requests for one source over one protocol (§4).
- **Run**: one verb executed for one collection and one source: its load, the requests it makes, its batches (STORAGE §2) and the events it reports.
- **Projected placement**: one source's view of one placement (STORAGE §2): the placement's flags, object, level, summary and sort key, the source's binding of it (handle, base and conflict columns) and the status the projection derives. Derived by the projection (§3), never stored, written back by the write (§10). This part writes it *placement* where no other is meant.
- **Status**: what a placement owes: `Clean`, `Dirty` (a flag or content push), `Tombstone` (a delete), `Conflict` (a decision), `Created` (an append).
- **Base**: what the source last agreed with its remote: flags, object, revision, and `base_present` (STORAGE §13).
- **Pending create**: a `Created` placement the source binds under a provisional handle, a binding with no base, waiting for its add to be accepted.
- **Provisional handle**: `U+0001` followed by the link id. No protocol hands out such a name, so it never collides with a member the next enumeration lists, and two engines derive one create's key alike (§4).
- **Origin**: where the same source already holds a `Created` placement's identity and body, so its add is a server-side copy (§3).
- **Destination**: where the same source holds a pending create of a `Tombstone` placement's identity, so its remove is a relocation (§3).
- **Tier**: what a fetch returns, `Meta`, identity and summary, or `Full`, the body too (STORAGE §2).
- **Meta**: what names a member without its body: the identity hint, the summary and address rows, and the `sort_key` STORAGE Annex A derives. Every member a listing carries carries its meta (§4).
- **Page**: what one enumeration request returned: members (handle, flags, revision, meta), vanished handles, whether it belongs to a round, a head or a delta, whether it is the last of its listing, its resume cursor, and the checkpoint when it carries one.
- **Round**: one complete listing of a scope, in one page or several, under an id drawn when it opens. It stamps the bindings it lists and closes when its last page lands (§5).
- **Delta**: a listing of what changed since the checkpoint, one page, always the last.
- **Head**: one page listed while a round is open, of what changed in the collection since the round began, so what arrives during a long round shows before it closes. A **delta head** lists from the round's checkpoint; a **band head** lists the members the source dates from the instant the round opened (§4, §5).
- **Scope**: `[since, until)` on a message's summary `date`, either bound open: what a round lists, and the only place its absence means anything (§5). Mail only.
- **Coverage**: the scope of the last round that closed, and when it closed: the scope the checkpoint serves (STORAGE §4.3).
- **Resume cursor**: the connector's opaque position in an open round, landed with each page.
- **Change**: what the engine asks a source to do, one of `Add`, `Remove`, `SetFlags` and `Update`, each with an idempotency key (§4). A **push** is a change sent, in a batch of them.
- **Outcome**: `Accepted`, with the handle assigned to an `Add` and the revision a mutable kind reports, or `Rejected`.

## 3. The projection

Placements are read from the store, never stored. For a collection and a source, the projection MUST yield one placement per item the source binds, and one `Created` placement per item the source lacks and the store holds a body for. A retained item (STORAGE §11) MUST be projected for nobody.

**Status**, the first that applies:

1. `Conflict` when `bindings.conflicted` is 1, carrying `conflict_revision` and `conflict_object`; or when `items.conflicted` is 1, two sources disagreeing on the body (§9), which every binding of the item projects until an `Edit` or a `Remove` settles it (§7). Neither is downgraded.
2. `Tombstone` when `items.deleted` is 1 and the source binds the item; the content is kept so an edit still beats the delete (§5). A tombstone whose binding has no base is a create the consumer withdrew: it derives no `Remove`, the write drops the binding and the item is retained (STORAGE §11).
3. `Created` when the binding has no base (STORAGE §13: `base_present` and `base_flags_known` 0, every other base column `NULL`), or when the source does not bind the item, `items.deleted` is 0 and `object_hash` is present.
4. `Dirty` when the flags differ from the base flags as sets, both known (STORAGE §13); or, for a mutable kind, when `object_hash` is present and differs from `base_object` (a base naming no body differs from every body). A placement holding no body owes no body, whatever its base names.
5. `Clean` otherwise.

An unknown flag set (`flags_known` or `base_flags_known` 0) holds no opinion: neither an addition nor a removal. An unknown base is no base on the flag axis.

An immutable kind never owes a body: one identity is one message, and the write adopts the shared body as its base (§9).

**Level** MUST be `Full` only when `object_hash` is present, whatever `items.level` claims: an item whose body a remote change dropped projects at most `Meta`, and an upgrade refetches it.

**Origin.** A `Created` placement carries an origin when the same source binds the same identity in another collection with a base present and, when the placement has a body, with that body as `base_object` (`origin_for_link`). Its add is then a server-side copy from that handle rather than an upload.

**Superseded.** A `Created` placement whose item superseded an item of its own identity in another collection (STORAGE §15.3) names the binding it may be moved from (`list_superseded_bindings`), when the same source binds that item with a base: its collection, its handle and its base revision. Unlike an origin it holds whatever body: the connector moves the member, then writes the placement's body over it.

**Destination.** A `Tombstone` placement carries a destination when the same source holds a pending create of the same identity in another collection (`destination_for_link`), named by that create's handle: the relocation its remove offers (§5).

**The same identity**, for both, is the same `link_id`, or the one minted over the provisional handle the other derives (`dup:`, the key, `#`, `U+0001` and the key again): the key a `Copy` or a `Move` gives its create beside a live holder (§7). The bare key MUST be preferred.

Origins and destinations are derived from bindings, never stored, so both read the same after a crash and after another source's write folded the item.

## 4. The remote seam

A connector answers three requests: enumerate, fetch and push.

**Enumerate** takes the checkpoint, the scope (§5) and, resuming a round, its resume cursor, or, for a head, the checkpoint or the instant it lists from (below). It returns a page:

- `items`: every member with its handle, its known flags, an optional revision and its meta;
- `vanished`: the handles the source states removed;
- `complete`: whether the page belongs to a round (every member of the scope listed across its pages, save what a narrowing filter cannot list and what a cap leaves out, §5) rather than to a delta;
- `last`: whether it closes its listing, which a delta's one page always does;
- `cursor`: an opaque resume cursor, on every page of a round but the last;
- `checkpoint`: on the page where the source gives one;
- `narrowed`: on every page of a round, whether a date filter narrowed its listing (§5);
- `enumerated`: on the last page of a narrowed round, optionally, every handle the collection holds on the source, read by an enumeration no date filter narrowed (§5).
- `capped`: on every page of a round, whether the source caps what it lists of the collection (§5).

A connector MUST set `complete` only on a page of a round. It MUST mark a page `last` only once its listing is exhausted, every member of the scope listed across the round's pages, and MUST hand a `cursor` with every other page of a round.

An engine MUST refuse a page that is neither `last` nor carrying a cursor: the run fails before that page's write, and the round stays open as the pages before it left it.

Within a page, `items` SHALL be sorted by handle in byte order and list each member once. An engine MUST sort an unsorted page and keep a duplicate's first entry.

A connector whose checkpoint the source rejects because the handle space changed (an IMAP `UIDVALIDITY` bump) MUST fail the enumeration and name a rekey (§8), rather than answer a round of new handles.

**Members arrive named.** A member's meta MUST come with it, as a `Meta` fetch would return it: the identity hint, the summary inputs and the `sort_key` of STORAGE Annex A. Nothing reaches the store unnamed.

- Mail reads it in the listing itself, from the summary the source serves: an IMAP `FETCH` of `UID FLAGS INTERNALDATE ENVELOPE` and the header fields Annex A needs, `Content-Type` among them; a JMAP `Email/get` with summary properties.
- A kind whose meta is the body (DAV) fetches each page's bodies (`multiget`) before handing the page over, and its members MAY carry the body, as a `Full` fetch does.

GUIDE §10 lists what each provider's connector reads.

**Files.** A source syncing a folder (STORAGE §14.3) MUST state, for every member, an id its server keeps across a rename and a move, unique across the servers the source reaches (GUIDE §10 names the providers' ids). That id is the member's handle and its hint, so its link id.

The remote path is the folder and the member's name, which the connector derives. A rename on the server is the same handle listed under a new name: a summary write on the same placement. A move between two folders the source syncs is the member leaving one and joining the other under the same key, as a move of a message is.

A server stating no such id (a plain WebDAV collection keyed by href alone) is not a file source in this draft.

A file's meta is what its listing states, never its bytes (STORAGE Annex A.7): its decoded name, its media type and its length; the listing carries no body. A file stays at `Meta` until a `Full` upgrade fetches its bytes, which then fix its size. Its revision is its ETag (`getetag`), and a source stating none for a file MUST NOT push its content.

A file is a mutable kind. An edit is a new body under the same key, pushed as an `Update` gated on the base ETag; a server edit is a pull; both is a conflict under the source's policy. Under `Manual` a person keeps both (the local body saved as a new file with an `Add`, before an `Edit` adopts the server's) or picks one with an `Edit`. A local rename or move pushes nothing in this draft: no change names a file's name.

**Pages.** A round MAY be answered in pages, newest first in the source's own recency order (IMAP by UID descending, JMAP by `receivedAt` descending). Each page is one request (or one batch of requests) and one write (§5). A connector that does not page answers a round of one page.

A connector chooses its page size within what the source accepts, small enough to resume cheaply on a slow network, and SHOULD lower it after a timeout or a `413`. GUIDE §10 gives the sizes measured per provider.

**The resume cursor** is the connector's and opaque to the engine. A connector whose cursor the source rejects (an expired skip or page token) MUST fail the enumeration and name a restart (§5), rather than answer from the beginning as if it resumed.

**The checkpoint** a round carries is the one taken when it began, where the source gives one up front (IMAP `HIGHESTMODSEQ` at the select, JMAP's state), handed with the first page. What moves during the round is caught by the round's next head (below) or, once it closes, by the next delta. A source giving its checkpoint only on the round's last page hands it there, and that checkpoint covers the round itself.

A connector states whether its checkpoint is **bound to the scope** it was made under: one the source made under a filter is; IMAP `CHANGEDSINCE` and JMAP's state, filtered locally, are not.

**Heads.** A connector states which heads it lists: delta heads, band heads, both or none. A head is one page, checked against the scope as a delta is, whose members carry their meta as every page's do. It carries no resume cursor and never moves the round's.

- A **delta head** takes a checkpoint and answers what changed since it, as a delta does: the members added or changed (each with its flags and meta), the handles the source states removed, and the checkpoint the source holds now, which it MUST carry. IMAP lists it from a QRESYNC `SELECT` with `CHANGEDSINCE`, JMAP from `Email/changes` since the state, DAV from `sync-collection` since its token. A source whose checkpoint arrives only with a round's last page has none to list from before that round closes.
- A **band head** takes an instant and lists every member the source dates at or after it, less a margin of two days (the margin a received-date narrowing takes, §5). The date is an instant the source keeps for each member and never moves back: the member's last change where the source states it and can filter on it, else its arrival (IMAP's `INTERNALDATE` through `SEARCH SINCE`).
- A band head carries no checkpoint and no vanished handle: a listing by date states no removal and proves none by an absence.

*Note:* A band head by arrival misses a move into the collection and a flag change on older mail until the round's last page lists them.

A connector whose head position the source rejects (an expired history id, a JMAP state the server can no longer calculate changes from, a DAV sync token refused as invalid) MUST fail the head and name a restart, as for a rejected cursor, rather than answer a round. One meeting a moved handle space fails it and names a rekey, as a delta does (§8). One that cannot list the head it is asked for at all (a server without QRESYNC) answers none.

A connector listing band heads MUST list again, in the last page of every round, every member a band head of that round would list then, read no earlier than the checkpoint that page carries: a band head stamps nothing (§5), and that last page is what keeps its members.

A connector listing delta heads MUST read every page's members no earlier than the head before it. One reading a page's handles from an earlier listing (an IMAP `UID SEARCH` cached since the round began, an id list) reads their flags and meta anew, as every page does, and leaves out a member the source no longer holds in the collection. A page thus never lists a member as it stood before a removal a head stated.

**Fetch** takes a tier and a batch of handles and returns, per handle, the identity hint and summary inputs of Annex A, at `Full` a body (inline or already streamed to its blob path, STORAGE §14), and the body's revision. A batch has no order: a connector MAY fetch concurrently and MUST key results by handle; the engine matches by handle.

**Push** takes a batch of changes and returns an outcome each:

- `Add { handle, link_id, flags, origin, supersedes, object }`: create by server-side copy from `origin` when present, else by uploading `object`; accepted with the assigned handle. A connector to a mutable kind MUST report the revision the member holds once accepted, else the next enumeration reads its own push as a remote edit and refetches it.
  - With `supersedes` (§3), a connector whose source moves a member between collections (WebDAV `MOVE`, RFC 4918 §9.9) MAY deliver it by moving that member into the collection, gated on its revision, then writing `object` over it; accepted with the moved member's handle and the revision the write left.
  - A source answering the move as one it cannot do (`405`, `501`, or a `404` for the member it binds, which some providers answer) SHALL have the change delivered by an upload instead, as without `supersedes`. One refusing it for the member's identity rejects the change, as a refused upload would.
- `Remove { handle, to, link_id, if_match }`: delete when `to` is absent or already holds `link_id` (§5); relocate into `to` otherwise.
  - `link_id` is the tombstone's key, and MUST be absent when its destination is a create under a minted key (§3): `to` held the identity before the move, so holding it proves no delivery.
  - A connector that cannot relocate MUST reject the change rather than delete.
  - A delete of a member already gone is accepted: pushes are at least once (below), and a create delivered by a move (`Add`) takes the member it supersedes along.
- `SetFlags { handle, add, remove }`: add the flags of `add` and remove those of `remove`, leaving every other flag the member holds, so a flag the server changed after the listing survives the push.
  - The engine derives both from the placement's flags after the flag merge (§5), against the set the source holds (the one the run listed, else the base): `add` what the placement carries and that set lacks, `remove` what that set carries and the placement lacks.
  - A placement whose flags are unknown pushes none, and one deriving two empty sets pushes nothing.
- `Update { handle, object, if_match }`: replace a mutable body, gated on `if_match` where supported; accepted with the revision the member holds, on `Add`'s terms.

**An add accepted without a handle.** A source that creates a member without saying which (an IMAP `APPEND` on a server without UIDPLUS, RFC 4315) is answered `Accepted` with no assigned handle. The engine then MUST leave the create pending (its provisional binding, staged body and flags kept, no `Superseded` drop written, no `Created` reported) and MUST NOT push it again in that run.

The next listing names the member, and the page naming it lands the create (§6), as for an add whose record was lost.

*Note:* **The unguarded window.** A precondition guards a push only where the source enforces it. An `Update` or a `Remove` sent with `If-Match` (RFC 9110 §13.1.1), or a flag `STORE` with `UNCHANGEDSINCE` (RFC 7162 §3.1.3), fails rather than overwrite a member changed since the revision it names.

*Note:* A source enforcing none (a server ignoring `If-Match`, an IMAP server without CONDSTORE, an API with no precondition) leaves a window between the listing a push was derived from and the push. A change made on the server in that window is lost: a body under an `Update`, the member under a `Remove`, the flags a `SetFlags` names. Every other change the server made survives, and the next listing reports it.

*Note:* In this draft no row of the store says which sources leave the window open, so a producer cannot tell an unguarded write from a guarded one.

**The idempotency key.** Every change carries a key naming it, so a connector logging keys recognises the replay of a push whose record was lost, and a chunk replayed after a crash (§5) applies once. The key MUST be derived as follows, so two engines over one store key one change alike:

- FNV-1a, 64 bits (offset basis `cbf29ce484222325`, prime `100000001b3`), over a sequence of fields, each field's bytes followed by one `0x00` byte, rendered as sixteen lowercase hexadecimal digits.
- The fields, in order: the collection id, the handle, the change as `add`, `remove`, `set-flags` or `update`, then the change's own. An optional value is the field `1` followed by the value's field, or the field `0` alone. A flag set is the field `unknown` when unknown, else the field `known`, the count in decimal ASCII, then each flag in code point order.
- `add`: the link id (optional), the flags, the origin as `1`, its collection and its handle, or `0` alone, then the object hash (optional). `supersedes` is not part of it: a create delivered by a move or by an upload is one change. `remove`: `to` (optional). `set-flags`: `add`, then `remove`, each a flag set. `update`: the object hash.

A precondition (`if_match`) is not part of the key: a retry of one operation is one operation. The key names a push within one run, not for ever: a flag set restored, or a body pushed again against a newer revision, is a new change under an old key.

A connector logging keys MUST forget them once the checkpoint after their chunk has landed, and MUST NOT answer a key it remembers from an earlier checkpoint as a replay. §11's vectors carry the key of every push.

## 5. Sync

A sync reconciles one collection against one listing: a delta from the checkpoint, or a round of one page or several. Its **candidates** are:

- for a round's last page: every projected placement and the page's members;
- for a delta: the changed and vanished handles, plus every projected placement that is not `Clean`, whose pending push the delta would never revisit;
- for a page before the last and for a head: its members and vanished handles alone.

A `Created` placement is a candidate with no remote side. The engine MUST walk both sides in handle order. Every member a page carries is named in the page's write on §6's identity rules: minting decided against the whole collection, and a pending create landed rather than minted.

**The scope.** A source MAY sync a mail collection under a scope `[since, until)`, `until` open in the usual case. A member is in scope when its summary `date` (STORAGE Annex A.1) falls in it, or when it has no usable `date` (rare, small and never lost: a draft before sending, a server's own notice).

The `Date` header always decides. A received date is never stored and never decides.

A connector MAY narrow its listing by the provider's received-date filter (JMAP's `after`, and those GUIDE §10 lists) to a superset of the scope, and MUST then take it with a margin of two days below `since`. IMAP narrows with `SENTSINCE` and `SENTBEFORE` with a margin of one day, their whole days being the server's.

**A narrowed listing says so.** A filter lists a member only when it matches: a received-date filter misses an undated member received before its window and one whose `Date` runs ahead of its arrival, and a server reading the `Date` itself may skip an undated one. A connector narrowing a round's listing by any date filter MUST set `narrowed` on every page of that round, and MUST NOT set it otherwise. On the last page of a narrowed round it MAY hand `enumerated`: every handle the collection holds on the source, read by an enumeration no date filter narrowed (IMAP's `UID SEARCH ALL`, JMAP's `Email/query` filtered by the mailbox alone, Graph's message ids). A connector offering such an enumeration SHOULD hand it.

**A capped listing says so.** A source may list at most a number of members of a collection, whatever it holds (an IMAP server under a folder size limit listing the newest 1,000 of 1,900 messages), so a member past the cap is missing from every round, not once. A connector knowing that the source caps a collection's listing, by the source stating it or by its configuration, MUST set `capped` on every page of that collection's rounds, and MUST NOT set it otherwise.

The connector drops what its own check on the `Date` puts out of scope; the engine filters no page by date and names every member a page carries. A scope on a collection of another kind MUST be refused, naming the kind.

**Absence means deleted only in scope.** A round MUST reconcile the placements in its scope alone: a placement out of scope that no page listed MUST NOT be dropped, pulled or pushed on the evidence of its absence. A removal the source states, a vanished handle (IMAP `VANISHED`, JMAP's `destroyed`), applies whatever the date.

**Local changes push whatever the scope.** Tombstones, moves, flag changes, creates and intents are the consumer's, owed to no listing: no scope holds them back, save the one create below.

**Which absences delete.** An absence is a delete only when a closed, complete round of the source did not list a member in its scope (below). That member is dropped `Deleted`, which marks the shared item deleted; every other source binding it then projects a `Tombstone` and pushes its `Remove` (§9), as for a removal a source stated.

Nothing else is an absence: not a page before the last, an interrupted round, a restarted one, a head, a delta, a member out of the round's scope, an undated member of a band round, a member a narrowed listing's filter could not list (below), a member of a capped round (below), nor a round the guards below park.

**A sync never deletes on the server on its own account.** A `Remove` MUST be derived from a tombstone and from nothing else: one the consumer staged (§7), or one a delete another source inferred or stated left on the shared item (§9).

A scope, a narrowing, a widening, a collection (STORAGE §11.3) and whatever the paragraph above says is no absence derive none. What a sync infers from its own remote it applies to the store, never back to that remote.

**A collection is deleted on a server only when enabled.** An engine mirroring collections between sources MUST NOT delete a collection on one source's server because another source no longer lists it, unless its configuration enables it, and then only when that collection is empty or every member of it was reconciled in the same run.

**Choosing the listing.** The checkpoint serves the scope it was made under, which is the coverage (STORAGE §4.3), and any scope inside it. A run under a scope:

1. resumes the open round when the round's scope is the one asked for and the round lists a band exactly when the run would: from its cursor, or from its first page when it holds none (a parked round, below), listing the round's head first (below);
2. else opens a round over the scope asked for when no round has closed (no coverage, a checkpoint held without one included), when a round is open over another scope or listing a band where the run would not (or the reverse), or when the scope reaches outside the coverage;
3. else runs a delta from the checkpoint, its listing checked against the scope asked for, and records that scope as the coverage when it is narrower (`set_coverage`).

In case 2, a connector whose checkpoint is bound to no scope MAY instead list only the band the coverage lacks, when that band adjoins the coverage. The round's scope is then the band, recorded as a band round when it opens (`open_round`). Its listing need carry no undated member, and the connector keeps its checkpoint and hands none with its pages, a head alone moving it (below).

**Rounds.** A round MUST open in the write of its first page (`open_round`), which draws its id. Each page MUST be merged as a delta whose only removals are the vanished handles it carries, and MUST land in one write: its members named, its bindings stamped with the round's id after its upserts (`stamp_bindings`) whether a member moved or not, its cursor and the checkpoint it carries recorded (`set_round_cursor`).

A round interrupted between pages keeps what landed and resumes from its cursor. A round whose cursor the source rejects MUST restart: a round over the same scope opens under a new id, so the abandoned listing's stamps protect nothing, and the members it named are matched again by handle (a relisting, no fetch).

A round belongs to its source: it stamps that source's bindings alone, and another source's stamps, round and coverage are its own.

**Deletes are inferred once**, when the last page lands, and in scope only. A member the round found absent is every based binding of this source the round did not stamp whose item's `date` falls in the round's scope, or is unknown and the round is no band round, its last page narrowing it as below (`list_unstamped_bindings`). It is handled as the deletes below say.

A band round MUST NOT infer the delete of an undated member. Undated members are reconciled by rounds over a whole scope and by deltas, and a removal the source states applies to them whatever the round.

**A narrowed listing proves only what its filter could list.** A round whose last page is `narrowed` (§4) MUST find absent only a member whose `date` is known and earlier than the instant the round opened (`round_started_at`), which its filter, taken with its margin, could list. An undated member, and one dated at or after that instant, is found absent there only when the last page hands `enumerated` and that enumeration lacks its handle; otherwise it is left as it stands, neither dropped nor pushed, for a removal the source states, an unnarrowed round or a later enumeration to decide.

**A capped listing proves no absence.** A round whose last page is `capped` (§4) MUST find no member absent: a removal is applied there only when the source states it, a vanished handle. It closes as any round does, and an engine SHOULD report the based bindings it left unlisted, counted as the deletes above count them.

A round resumed from the store and one the run opened MUST infer the same deletes. A pending create is no member of the remote and is never absent.

The round closes in the write after its last chunk (`close_round`):

- the checkpoint it carries becomes the source's: the last page's when that page carries one, else the latest a head or an earlier page landed, the old one kept when it carries none;
- the coverage becomes the round's scope, or for a band round the span of the band and the coverage it adjoins, stamped with the instant.

**A mass absence parks.** A round whose last page finds absent more than half of the based bindings of this source in the round's scope, counted as above, MUST NOT close when those bindings number at least 20, unless the run carries the `accept_absences` option.

**An empty listing parks.** A round that named no member, none of its pages nor heads listing one so that no binding carries its id once its last page lands, MUST NOT close while it finds absent any based binding of this source, whatever their number, unless the run carries `accept_absences`: a listing naming nothing is a mailbox emptied or a connector failing alike, and only the caller can tell them apart.

A parked round drops nothing and writes no `CloseRound`. Its last page lands as a page before the last does (members named and stamped, the checkpoint it carries recorded with no cursor, `set_round_cursor`), and the run reports the round parked with the absent and the bound counts.

Nothing records the park but the open round. A later run resumes it from its first page, the round holding no cursor, and decides again; a run carrying `accept_absences` (the caller having confirmed the absences) closes it as above.

**Heads.** A run resuming an open round SHOULD list the round's head before the round's next page when the connector lists heads (§4), and MAY list one between two pages; never between a round's last page and its close, and never before a round's first page has landed. The head is:

- a delta head from the round's checkpoint, or, for a band round, which carries none of its own, from the source's checkpoint, when there is one and the connector lists delta heads;
- else a band head from the instant the round opened (`round_started_at`), when the connector lists band heads;
- else none, and the round resumes as it would without.

A head is checked against the scope the run asks for, not the band a band round lists: what it names outside the band lies in the coverage the band adjoins, which the checkpoint it moves serves too.

A head is merged as a page before the last: its candidates are its members and vanished handles alone, every member named on §6's identity rules (a pending create landed rather than minted), and a vanished handle dropped at once, whatever its date, as the deletes below say. It lands in the write after the chunks of its pushes:

- **A delta head** stamps the bindings of the members it listed with the round's id after its upserts (`stamp_bindings`), so the round's last page never finds them absent. It records the checkpoint it carries as the round's (`set_round_cursor` with no cursor, the page's staying). A member it named whose removal it has not seen yet is the next head's, or the next delta's once the round closes on that checkpoint.
- **A band head** stamps nothing and records no checkpoint. A member it named is decided by the last page, which lists again what the band holds (§4), the rest being found absent.

A head never moves the round's cursor, scope or coverage, derives no `Add` (creates wait for the round's last page, below) and infers no delete from an absence. A member a head named and a later page lists is one member under one handle, refreshed as any listed member is. A page listing a member a delta head stated removed lists it present again (no page lists a member as it stood before a head, §4), and names it as any page does.

A head whose position the source rejects restarts the round over the scope the run asks for, never a band: the checkpoint the round would close with is void, and the round, under a new id, takes a fresh one from its first page.

**Creates wait for the page that lands them.** An `Add` MUST NOT be derived before the last page of an open round has landed, a head's write included, nor in a delta before its members are named, since a member a page carries may be that create's own arrival (relocated by a move's other half, added by another client or by an add whose record was lost), and pushing before it lands would make a second copy. The page naming it lands the create (§6), and the run pushes what is left.

A pending create carrying no origin whose `date` the run's scope excludes may be an arrival no page of that scope lists (a relocated message keeps its `Date`). Its `Add` MUST NOT be derived by a run whose scope excludes its date. It waits for a round over a scope holding it, and an engine SHOULD report it while it waits.

**The flag axis** merges element-wise over `(local, base, remote)` and never conflicts. A flag is in the result when both sides carry it, or when one side carries it and the base does not (an addition); it is out when the base carries it and either side does not (a removal). With no base, the result is the union of the two known sets, no side being known to have removed anything.

It MUST run for every placement present on both sides, one whose content axis derived a push included. One handle yields at most one change, so the flag axis then withholds its push and still merges and writes. A content push accepted in the same run MUST rebase the placement the flag merge wrote, never the one read before it.

The flag axis leaves the status alone while the content axis still owes a push, and leaves an unresolved conflict alone.

**The content axis** applies to a mutable kind, which reports a revision. A local body the base does not hold is an `Update` gated on the base revision. A remote revision the base does not hold is a pull: the member's meta becomes the summary, address rows and sort key, and the member's body, when it carries one, becomes the body and the base at its revision, as a fetch's does (§6). A member carrying none drops the local body and lowers the level to `Meta`.

A placement holding no body (a pull having emptied it) owes nothing until the upgrade refetches it. One holding a local body over a base that names a revision and no body (an edit staged after such a pull) MUST derive no `Update`, nor the `Remove` a move's staged edit rides ahead of (below): the body the server holds at that revision is one nobody has read, and pushing over it would lose it unkept. It waits for the upgrade, which fetches that body into the base (§6), after which the local body is an edit over a body read. A placement whose local body the run keeps, pushed or conflicted, keeps that body's summary.

Both is a conflict, resolved by the source's policy. Mail reports no revision and never reaches this axis. A file (STORAGE §14.3) is mutable: a connector to a folder MUST report a revision, an edit being a new body under the same key.

A `Conflict` placement meeting a revision newer than its `conflict_revision` records the new one and drops its `conflict_object`, which described the old revision; the upgrade fetches it anew (§6).

One carrying no `conflict_revision` (the item's conflict, §9) and meeting a revision its base does not hold MUST mark the binding conflicted with that revision and ask for the diverging body, whatever the source's policy, reported as `Conflicted`.

A conflict whose fetched body equals the placement's own is no divergence (the push whose record was lost had landed): the binding adopts the revision and body as its base and the conflict clears.

**Conflict policy** is the source's, settling it against its own remote:

- `Manual` (default) marks the binding conflicted with the observed revision, and records the diverging body in `conflict_object` when the member carries it, else asks the upgrade for it (§6).
- `PreferRemote` pulls, the local edit it drops kept as a retained item and reported (§9). A member carrying no body is pulled as any pull is, the item emptied for the upgrade to fetch: nothing is written to the remote, and the local edit is kept.
- `PreferLocal` keeps the member's body and pushes the local one over it. In a write that commits before the push, the binding's base adopts the observed revision and the member's body, as a person's `Edit` adopts a conflict (§7), and that body is kept as a retained item, reported `Overruled` (§9); the local body, an edit over that base, is then pushed gated on the observed revision. A push rejected, interrupted or replayed finds the body kept and the base moved, so nothing is kept twice, and one that landed unrecorded is read back as the push whose record was lost (above). It falls back to `Manual` when content pushes are forbidden.

No policy pushes over a body nobody has read. A both-changed case whose member carries no body MUST be recorded as `Manual` records it under `PreferLocal`, conflicted at the observed revision with no `conflict_object`, and the upgrade fetching that body settles it by the policy then (§6).

The collection's `conflict` (STORAGE §4.3) is the other axis, settling the shared item between sources (§9); the two are named apart on purpose.

**Deletes.** A `Tombstone` derives a `Remove`, carrying its destination when it has one (§3).

A tombstone an add superseded, whose created item is still a pending create (STORAGE §15.3, `list_superseded_pending`), is **held**: it derives no `Remove`, nor the `Update` a move's staged edit rides ahead on, and is not dropped for it. A remote edit over it still revives it.

Once that create is accepted, withdrawn or gone, the hold lifts and the `Remove` is a plain delete, no pending create of its identity being left to relocate into. A create delivered by a move took the member along, so that delete finds it gone and is accepted (§4).

A member a round found absent, or a vanished handle, is dropped with reason `Deleted` (§10), unless its placement holds a body its base does not: a local edit the remote never saw. That placement is re-staged instead as a pending create under a provisional handle, its binding kept without a base, and the next run adds it.

A remote edit over a local tombstone MUST revive it and pull; a tombstone also holding a local edit is the both-changed case and follows the policy.

A revision the tombstone's base does not name is a remote edit, an enumeration carrying no body to say otherwise. A move whose staged edit was pushed ahead of its remove, and whose push record was lost, is therefore abandoned rather than half-applied: the member stays in the source, live and clean at the pushed revision, and the consumer restages the move.

**Push direction and rights.** A source has a master `push` switch and four rights: `flags`, `content`, `add`, `remove`. With `push` false nothing is pushed and remote changes are still pulled. A change a right forbids stays pending while the others propagate. A rejected push is pending like any other and follows no policy.

**A refused delete**, one the source's rights forbid, is decided per collection from the other sources syncing it, any holding a binding or a checkpoint there (`collection_sources`):

- Beside another source the tombstone is held, and the other source pushes the delete. The row stays in the trash view until that source has dropped it (STORAGE §11).
- A source alone in the collection reverts the delete, and the placement lands on what it still owes.

**A move** is a `Created` placement in the target plus a `Tombstone` in the source, each derived by its own collection's sync in either order and each able to deliver alone. An engine MUST NOT drop either half for the other.

The create delivers by copy from its origin, or by upload when the store holds the body. The remove delivers by relocating into its destination, which the connector MUST reject when it cannot relocate (§4). It is a plain delete once the destination holds the identity the move delivered, a copy the target held before the move not being that delivery (§4). A create landed first, by its copy from the origin, leaves no destination, and the remove is then a plain delete.

A relocated member is listed by the target's next listing under a new handle, and the page naming it lands the create (§6); until then the create waits, as every create waits for the page that lands it.

**Push discipline.** A push MUST be confirmed before local state moves. `Accepted` rebases the placement and, for an add assigned a handle, supersedes the provisional handle in the same batch (one assigned none stays pending, §4). `Rejected` or unreported leaves it pending, and an engine SHOULD report a create rejected on consecutive runs rather than push it for ever.

Pushes go in bounded chunks, each followed by the write recording its outcomes, and the owner MUST NOT collect between two chunks (STORAGE §5). The checkpoint, a delta's or the one a round closes with, MUST land in the write after the last chunk and in no earlier one. A page's cursor and the checkpoint an open round carries are not the source's checkpoint, and land with the page or the head carrying them.

**Events.** An event MUST be reported only once the write recording it has committed, and every event a committed write records MUST be reported: a run failing between two writes reports what the writes before it committed and nothing of the one that failed.

A sync reports per item, in order, what the remote changed locally and what the run settled:

- `Added` for a member named;
- `FlagsChanged`, `ContentChanged` and `Vanished` on a pull;
- `Conflicted` on a divergence, the source's own or one its write records on the item (§9);
- `Overruled` on a body a policy did not adopt (§9), or a revive set aside (§6), naming the retained item that keeps it;
- `Created` on an accepted add under its assigned handle, and on a create a listing landed under the handle it lists.

A run also reports a round it parked (above), as a rekey reports itself parked (§8). A pushed flag, body or delete reports nothing: the consumer made it.

Only a sync reports events: an upgrade, a mutation and a rekey report none, save `Overruled`, which any verb whose write kept a body no one asked to lose reports.

## 6. Upgrade

An upgrade raises placements to `Full`, or revisits at `Meta` a claim the row does not hold. A listing names every member at `Meta` (§4); hydration is what a consumer runs for the members it wants. The identity rules below are those a page names its members by.

**Identity is resolved once**, at the first meta carrying a hint, a listing's or a fetch's; a later one MUST NOT re-identify a linked placement of an immutable kind. A mutable resource whose later meta states another hint under the same handle is a new identity there, on the terms STORAGE §9 sets for a changed `hash:` key: the old binding is retired and the resource keyed afresh.

Naming a member inserts its item and binding in the write of the page that lists it. Its key is the one STORAGE §9's table gives for what holds its hint in the collection: the hint when free, a pending create of this source landed (below), an item other sources or none bind joined, a tombstone or a retained row revived, and a key minted over the member's handle, `dup:<hint>#<handle>`, when this source already binds the hint under another handle or the row holding it is another message (below), minted again over a held key.

A member of a mutable kind reviving a retained row without carrying a body revives it holding none, at `Meta` (STORAGE §11.1): the body the row held, which its server may since have replaced, is kept as a retained item keyed over the member's handle and reported `Overruled`, never left as the item's body, where it would read as a local edit and be pushed over the member's revision.

For mail, a hint the collection holds names the row holding it, whatever that row is (a pending create of this source, a live item other sources or none bind, a tombstone, a retained row), only when the member's summary agrees with the row's as STORAGE §9 says: on `subject`, `date` and `sender` (STORAGE Annex A.1), which no server rewrites, compared byte for byte, `NULL` matching `NULL`, and with a retained row on `size` too where both state one, its body becoming the member's unread as a link's does (below). A member disagreeing is another message reusing the `Message-ID` and MUST be minted the same way, never joined, landed nor revived, the held row's body otherwise standing for both. A step whose load cannot see that row leaves it to the write, which enforces it (STORAGE §14).

Minting MUST be decided against the whole collection and from the handles in byte order, not reply order, so a rebuild mints the same key; a page or an upgrade therefore loads the hints it carries by key (§10) before it assigns any.

**A pending create is landed by its arrival.** A hint a page or a fetch carries that the collection holds as a pending create of this source (§2), keyed by the hint or by the hint minted over the provisional handle it derives (§7), the bare key first, is that create delivered: by a relocation (§5), by an accepted add whose record was lost, or by another client. The engine MUST land it rather than mint; only a hint held by a based binding of this source, or by an item whose summary names another message (above), is minted.

Landing is a `Superseded` drop of the provisional handle in the same batch, the binding moved to the listed one, and the base set to the flags the listing or the fetch reported and, for an immutable kind, to the staged body, one identity being one message.

For a mutable kind the base takes the listed revision, and the body when the listing or the fetch carried one. A carried body equal to the staged one settles the create; one differing is the content axis's both-changed case (§5).

An arrival carrying no body is that case as well, its incoming body unknown, and the engine MUST NOT push the staged body over it.

Whatever the source's policy, the binding is then recorded as `Manual` records a divergence: conflicted at the listed revision with no `conflict_object`, the base at that revision naming no body, and reported `Conflicted` beside the `Created` of the landing.

The upgrade then fetches the body (below). It clears the conflict when it equals the staged one (the add whose record was lost), and is otherwise settled by the source's policy as a carried body would have been (§5), `PreferRemote`'s dropped body and the server body `PreferLocal` pushes over kept and reported (§9). No policy chooses between a body and one nobody has read (§9). The flags and body staged on the create stay, so an edit made on it still pushes.

**A fetch moves the base.** A fetch carrying a body over a placement holding no local edit sets `base_object` to that body and `base_revision` to its revision, whatever the placement's level was, so the next sync reads the fetched body as agreed and not as an edit to push.

Over a placement holding a local edit (a body its base does not hold), the fetched body lands as the base and the local body stays when the revision is the base's; the both-changed case applies when it is not.

**Linking instead of fetching.** A `Full` upgrade of an immutable kind asks `lookup_objects` for the placement's key. It adopts a body the store holds, recording it as the base too, when the summary the source served agrees with the held body on `size`; else it fetches.

A source stating a size that is not the octets (Annex A.1) links only where the two happen to agree.

A mutable placement, a conflicted one, and one under a writer-derived key MUST be fetched, never linked. A linked placement holds the body as read: its summary takes the body's size, attachment mark and invitation (STORAGE.md Annex A.1), not its listing's.

**Claims are revisited.** A level claiming a tier the row does not hold is fetched again, which is what the `Meta` tier remains for: `Full` with no object, or with an object whose blob is missing or fails its name (STORAGE §7); `Full` holding a local body over a base naming a revision and no body, whose push waits for that base (§5); `Meta` with no summary.

A `Meta` row holding its summary claims nothing, whether its body was never fetched or was released (STORAGE §11.4): a listing names it as it names any member, fetching nothing, pushing nothing and inferring no delete.

A fetch carrying no body writes the level the payload supports, never lower than the row holds. The sort key is adopted from every fetch and every listing; the link id is not. A summary column the body was read for (the attachment mark and the size) is never replaced by one read without it while the row holds the body (STORAGE Annex A.1).

**A conflict's body.** A conflicted placement holding no `conflict_object` is revisited. The body fetched MUST land in `conflict_object`, never in its own object, unless it equals the placement's own body: that is no divergence, and the binding adopts the revision and the body as its base and the conflict clears (§5).

Otherwise the source's policy then settles it as a carried body (§5): under `Manual` it stays recorded; under `PreferLocal`, content pushes allowed, the fetched body is kept as a retained item, reported `Overruled`, and the base adopts it with its revision, the conflict cleared, so the next sync pushes the local body gated on that revision; under `PreferRemote` the item adopts it as its body and the base, the local edit kept as §9 keeps it.

An item conflict holding no `conflict_object`, recorded before its incoming body was read (§9), is revisited by the upgrade of every binding of the item whose base names a revision and no body. The body fetched is then settled by the collection's `conflict` policy as a carried one would have been:

- under `manual` it MUST land in `items.conflict_object`, never in the item's own object;
- under `prefer-incoming` the item adopts it, and under `prefer-existing` keeps its own, the conflict cleared either way and the body not adopted kept and reported (§9), when the item holds a body; one holding none waits, recorded as `manual` records it, for the fill that reads its own (§9).

**Rows.** Every fetch and every page writes the summary row, its list rows and the address rows Annex A derives, in the batch recording it.

## 7. Mutate

A mutation stages a local edit to one collection with no network, through the same write as a sync (§10), never by direct row edits. The queue's actions map onto them: `set-flags` to `SetFlags`, `remove` to `Remove`, `move` and `copy` to `Move` and `Copy`, `update` to `Edit` (its `if_match` and `resolves` carried), `add` to `Add`.

- `SetFlags` replaces the flags and marks the placement `Dirty`; a `Created`, `Conflict` or `Tombstone` placement keeps its status.
- `Remove` tombstones the placement, binding and base kept so the remove is pushed against the right handle.
  - On a conflicted binding it is the decision: the base adopts `conflict_revision` and `conflict_object` together, as an `Edit` does, and the conflict clears, so the remove pushes gated on what the remote holds.
  - A diverging body not fetched yet leaves `base_object` unknown, never the old body, so an item another source's edit revives reads `Dirty` (§3) rather than in sync.
  - On a conflicted item (§9) it clears the item's conflict the same way.
  - On a pending create it withdraws the create: the binding goes and the item is retained (STORAGE §11).
- `Edit` stores a new body and repoints the placement, keeping the base. An edit whose object the base holds stages nothing for its source, though on a conflicted item it still settles the item's conflict (below). It MAY restate the sort key.
  - An edit carrying `if_match` (a queued `update` stating the body it replaced, STORAGE §15.3) MUST be refused, staging nothing, when the item holds another body.
  - An `Edit` without `overrule` settles a conflict only as a person's resolution, stating `resolves`: the diverging bodies it was decided over (a queued `update`'s `resolves`, STORAGE §15.3). It meets the item's conflict when `items.conflicted` is 1 and its binding's when `bindings.conflicted` is 1. Meeting either, it MUST be refused, staging nothing, unless `resolves` names the `conflict_object` of each conflict it meets; stating `resolves` and meeting none, it MUST be refused the same way, the conflict it was decided over being settled already. A conflict whose diverging body nobody has read (`conflict_object` `NULL`) is named by no resolution. An ordinary edit, made before the conflict arose or without it in view, so never discards a diverging body.
  - On a conflicted placement it resolves, the base adopting `conflict_revision` and `conflict_object` together.
  - On a conflicted item it resolves too: `items.conflicted` cleared and its `conflict_object` released.
  - On a tombstone it revives, `Dirty`, and the destination its tombstone offered no longer derives.
  - An `Edit` settling a conflict by a rule of the engine's or a connector's (a one-way mode restating the body its authority holds) MUST state `overrule`; a person's resolution, which states `resolves`, does not.
  - An overruling `Edit` keeps each diverging body it does not adopt, the binding's `conflict_object` then the item's, as a policy's loser is kept (§9): a retained item keyed over the edited placement's handle, reported `Overruled`, before any body the collection's policy keeps in the same write.
  - An overruling `Edit` MUST be refused, staging nothing, when the conflict it settles holds no diverging body, one nobody has read (§9): the upgrade fetches it first (§6). On a placement and an item in no conflict it keeps nothing.
  - With `resolves` the settle is a person's choice, and what it discards it loses. On a conflicted item, through any binding of it (the source agreeing with the item or one the item moved away from), the item takes the edit's body whatever it is: its own, the diverging one, or another, a merge of the two among them. No divergence is measured (§9) and nothing is retained or reported. The editing binding's `shared_object` moves to that body, every other binding's stays, and each source whose base holds another body owes it. The write tells this settle from a sync's upsert, which leaves an item's conflict standing (§9), by the engine stating it with a `Settle`, as it states an overrule with an `Overrule` (STORAGE §14).
- `Copy` stages a `Created` placement in a target under a provisional handle with the source's origin; `Move` also tombstones the source, whose destination the target's pending create then derives (§3).
  - Both read the target. When a live placement there already holds the identity, they key the create by the identity minted over the provisional handle it derives, minted again over a held key; a tombstoned or retained holder blocks nothing, the create taking the key and reviving it, or, a message that does not agree with it, minted beside it (STORAGE §9's table).
  - Both MUST be refused, staging nothing, for a placement holding no body unless its binding is based and its source syncs the target, holding a binding or a checkpoint there (`collection_sources`): a create carrying no body is delivered only by a server-side copy from its origin, which only that source holds (§3). Another source of the target is offered the create only once the store holds the body (§9), so the upgrade fetches it first.
- `Add` stages a new item under a provisional handle at `Full`, no base, no origin.
  - It MUST fail, staging nothing, when its body cannot be read (STORAGE §15.2).
  - It MUST fail when a live placement holds the `link_id`. A retained one revives (STORAGE §11); a tombstone still propagating is revived the same way, the row adopting the new body and its delete withdrawn on every source; a message agreeing with neither is minted instead (STORAGE §9's table).

A delete meant to land in a trash collection is a relocation: stage it as `Move` into that collection, so the trash shows it at once and the push relocates it (§4). `Remove` fits a delete meant to be final, as from the trash itself.

## 8. Rekey

A source may renumber every member (an IMAP `UIDVALIDITY` bump, a restore). A rekey re-enumerates the spine, which MUST be a round over the whole collection whatever the scope, every page read before its one batch is written.

It carries each placement's body, summary, level, flags, base and pending state onto its new handle **by link id**, the one identifier that survived.

The batch drops each old handle it re-writes with reason `Rekeyed`, which licenses the binding to move (STORAGE §10, §12), per handle: a genuine duplicate in the same batch is still refused. It is one batch, every drop preceding every upsert, since a new handle may be an old one another member held.

An old binding no member resolves to by link id is dropped `Deleted`, whether or not the new space reuses its handle, since a server restarting its numbering at 1 hands a carried member the handle a gone one held, and an upsert under it before that drop would fold the carried member into the gone one's item (§10).

A binding with no base is outside the rekey and is carried as it is.

**A rekey missing most members parks.** A rekey whose listing leaves more than half of the based bindings of this source in the collection resolving to no member, when those bindings number at least 20, MUST NOT be written unless the run carries the `accept_absences` option. They are counted as §5 counts a round's absences, the whole collection being its scope and a binding absent when no member resolves to its link id. A rekey whose listing names no member parks the same way while any based binding of this source is absent, whatever their number (§5, an empty listing).

A parked rekey writes no drop and no upsert, and leaves the checkpoint and the generation unmoved; the run reports the rekey parked with the absent and the bound counts. The checkpoint still names the old handle space, so the next run meets the moved space again and names the rekey again; a run carrying `accept_absences` carries it out.

A member resolving to an identity already handed out takes the minted key an old copy carried, else a mint over its own handle; pending creates' keys count as taken.

Where one hint had several old copies, a member is matched to the old copy whose base names its fetched revision first, then to the one holding its body when the fetch carried one, and in handle order only among what neither can tell apart. A renumbering that swapped two resources under one `UID` thus carries each one's flags and pending edit onto itself. The sort key is carried, preferring the fetch's.

A mutable member whose fetched revision differs from the one its old base held changed on the remote while the handles did. The engine MUST carry it as a pull (§5), or as a `Conflict` at the fetched revision when it also holds a local edit.

A `Conflict` the old handle held is carried as it is, revision and diverging body kept while the fetched revision is the one recorded. One the item's conflict projects (§3) records no revision and gains none unless the remote moved.

A base claiming a revision it never reconciled is the one thing a rekey MUST NOT write.

The batch lands the rekey's checkpoint and leaves the coverage as it was. The batch and the epoch bump commit together, and the batch carries no op for the bump: a batch holding a `Rekeyed` drop is a rebuild, and the storage bumps the collection's generation in the transaction that applies it (STORAGE §12).

## 9. Several sources

N sources hold one item per identity and one binding each. A change one source folded into the item reads as `Dirty` against every other source's base, and each source's next sync pushes it. There is no cross-merge.

**Absorbing a write** folds a source's batch into the shared item: flags adopted, a body adopted or refused by the rule below, the level merged as a maximum under §3's body rule, a pull without a body writing `Meta` since it took the body away. A known flag set, sort key or summary replaces a known one; an unknown one leaves the shared value alone. A tombstone adopts no content and its flags ride along.

**Two bases.** `base_object` is what the source last agreed with its remote, and only a sync moves it. `shared_object` is what it last agreed with the shared item: a live upsert carrying a body moves it to the body the item settles on.

An upsert carrying no body (a pull at `Meta` having agreed to no body), and one leaving the item conflicted, a divergence included (the conflict being settled against it), MUST NOT move it.

The cross-source comparison MUST be made from `shared_object`, falling back to the sync base until the source has folded once. It is the common ancestor an engine reads to merge two bodies, and stays pinned until the binding agrees with another (STORAGE §5).

**Cross-source content**, mutable kinds only. Three facts are read before the upsert is applied:

- the source changed when the incoming body differs from the base its binding held before this upsert, not the base the upsert carries;
- the item changed when the shared body differs from `shared_object`;
- the two disagree when the incoming body differs from the shared one.

All three is a divergence, resolved by the collection's `conflict` policy:

- `manual` keeps the shared body, flags the item and records the incoming body in `items.conflict_object`, every binding then projecting `Conflict` (§3) until an `Edit` or a `Remove` settles it (§7);
- `prefer-incoming` adopts and `prefer-existing` keeps, the body the policy does not adopt kept as below.

Only the source having changed is a fast-forward. Only the item having changed leaves the incoming body behind and the binding `Dirty`, which is propagation.

An immutable kind never diverges: one identity is one message, so a body differing from the shared one is the same message served differently; the shared body stands and the binding's base adopts it. Another message under the same `Message-ID` never reaches this rule: its summary disagrees and §6 mints it an item of its own.

An upsert leaving a conflicted binding counts as the source having changed its body. Flags never conflict.

**A body not held.** An item holding no body (a pull at `Meta` having taken it away) has changed for every binding whose `shared_object`, or the sync base it falls back to, names one: its body is one nobody has read, not the agreed one. An upsert carrying no body over an item holding one disagrees with it. The three facts are read with these, and two rules keep every body:

- An upsert carrying a body over an item holding none, from a binding whose base names no body, **fills** the item: the item adopts the body without measuring a divergence, the pull that emptied it being the one this body was read for. An item conflict standing stays, its `conflict_object` kept, until the policy settles it (below).
- A divergence where either body is unread, the incoming one not carried or the item holding none, MUST be recorded as `manual` records one, whatever the policy: the shared body stays, none when the item holds none, the item is flagged, and its `conflict_object` holds the incoming body when the upsert carries it, else waits for the upgrade to fetch it (§6). No policy chooses between a body and one nobody has read.
- Once the missing body is read, the policy applies: the incoming one when the upgrade fetches it (§6), the item's own when a fill lands it (above). `manual` keeps the conflict, a fetched incoming body landing in `conflict_object`; `prefer-incoming` adopts the incoming body and `prefer-existing` keeps the item's, the conflict cleared and the body not adopted kept as below, keyed over the handle of the binding whose upgrade fetched it or whose upsert filled the item.

**A policy's loser is kept.** A body a policy does not adopt MUST be kept:

- the shared body `prefer-incoming` replaced;
- the incoming body `prefer-existing` refused;
- the local edit a source's `PreferRemote` dropped (§5), which reaches the write as an upsert whose source changed, over an item that had not changed for it, replacing a body the binding's base did not hold.
- the server's body a source's `PreferLocal` pushes over (§5), which reaches the write as an upsert moving the binding's base to it, before the push.

So MUST the diverging body an overruling `Edit` does not adopt (§7): an automatic settle never discards a body silently, and only a person's resolution may.

The write keeps it as a retained item beside the one it lost to (STORAGE §11), keyed by the identity minted over the handle of the binding whose upsert, upgrade (§6) or overruling `Edit` (§7) settled it (`dup:`, the link id, `#`, that handle), minted again over a held key: a key any row of the collection has, the retained body a policy kept before included (STORAGE §9). A second body one binding loses is so kept beside the first, and an overruling `Edit` keeping two bodies keys the item's over the binding's. The run reports each `Overruled` (§5), in the order kept.

**Deletes propagate.** A `Deleted` drop or a `Tombstone` upsert marks the item deleted; the dropping source loses its binding, a tombstoning one keeps it. Every other source projects a `Tombstone`; a source lacking the item projects nothing.

This is how an absence a closed round found (§5) reaches every other source, and the only way. A live upsert clears `deleted`. With no binding left the item is retained (STORAGE §11). A `Superseded` or `Rekeyed` drop marks nothing.

**Propagation is hydration-safe.** A source lacking an item MUST be offered it only when the store holds the body, and a projection never raises a level. Mirroring is a sync plus an upgrade.

**A per-source conflict is its own fact.** `bindings.conflicted` and `items.conflicted` never set each other. An upsert carrying no divergence clears the binding's and becomes the shared body, so resolving is an ordinary edit. A tombstone projected for a conflicted binding still carries the divergence.

A binding with no base is a pending create, and a minted key is an ordinary key: it reconciles, propagates and conflicts like any other, a target's refusal reported as a rejected push. A `hash:` key is not offered to another source: it asserts no identity.

## 10. The load and the write

An engine reads and writes the store through STORAGE §14's interface: `load` of a selection, and `write` of a batch of operations the store applies in order and atomically, whose drop reasons, refusals and chunks STORAGE §14 states. This section says which an engine asks for, and when.

Every verb begins with a load naming a collection and a selection, `All`, `Handles` or `Links` (STORAGE §14):

- A mutation asks for the one placement it edits, or for every holder of the link id an `Add` must not collide with. A `Copy` or a `Move` also loads its target for the identity it carries into it, and the sources syncing the target (`collection_sources`) for a placement holding no body (§7).
- An upgrade asks for the handles it raises.
- A delta, reasoning about what it does not list only through what owes a push, asks for `Handles` of the members it lists or drops and of those `list_owing_bindings` names, and for `Links` of the hints it carries and of those `list_lacking_items` names: every placement a push or a propagation can concern, so its load grows with what moved, not with the collection.
- The last page of a round and a rekey ask for the whole collection: what each finds absent, and whether a mass absence parks it (§5, §8), is counted over every based binding of the source in its scope.
- A page before the last and a head ask for `Handles` of their members and `Links` of the hints they carry, which naming them needs (§6).

Every verb ends in a batch. A sync's carries the round's own operations: `OpenRound` first in its first page's batch, `Stamp` after the page's upserts, `SetRoundCursor` with every page and head (a head's carrying no cursor, so the one a page landed stays), `CloseRound` last in the write after the last chunk, and `SetCoverage` beside a delta's checkpoint. Its drops are `Deleted` for a member gone from the source, `Superseded` for a provisional handle an accepted add or a landed arrival replaced (§4, §6), and `Rekeyed` for a handle a rekey renumbered (§8). A mutation's `Edit` states `Overrule` before its upsert when it carries `overrule`, and `Settle` when its `resolves` names the item's conflict (§7); an upgrade settling a conflict under `PreferLocal` states `Overrule` before the upsert adopting the fetched body (§6).

A batch is cut between candidates, never inside one, and a rekey is never cut. The checkpoint is per source and lands last (§5). A `Full` fetch MAY stream its body to its blob path itself and hand a `StoreObject` naming it.

**The write keys another message apart.** A `Links` load answers this source's holders alone, so a page before the last, a head and an upgrade name a member without seeing an item another source binds under the same hint, and cannot apply §6's rule for another message reusing a `Message-ID`. The write applies it whichever step named the member (STORAGE §14), and an engine whose load showed the row mints the member the same way first, so both name it alike.

**The version of the sync state.** An engine records its version, this part's (`sync-draft-08` now), in `store_meta.sync_version` with `set_sync_version` (STORAGE §14), in the transaction of its first write to a store naming none. A store naming none holds no sync state yet.

While this part is a draft, an engine MUST refuse a store whose `sync_version` names another version than its own draft's, naming both, and run no verb on it: a draft's sync state is read under that draft alone, as a draft's store is (STORAGE §4.2). Once this part is released, an engine MUST refuse sync state a draft wrote, or a major above its own; sync state of a major below its own it reads as that major defines it, and records its own version only in the write converting what the majors between them changed.

## 11. Test vectors

vectors/sync/ holds cases every conforming engine MUST reproduce, one JSON file each, stating `v` 3 (the version of the format this section describes) and conforming to vectors/schema/sync.schema.json. A case states:

- `store`: the rows before the run, bodies named by label, summaries by their row. An object stated with `blob` false has its row and no blob file: a body that cannot be read. One stated `corrupt` has its row and a blob file whose bytes do not hash to its name (any other bytes, the fixture's altered): a body that fails verification (STORAGE §7).
- `run`: the verb, collection, source and options (`push`, `rights`, `conflict`, `scope` as `since` and `until`, and `accept_absences`); an `upgrade` run its `tier` and the `handles` it upgrades; a `mutate` run carries its `mutation` (§7) by `kind`: an `Add` its `object` and `flags`, an `Edit` its `seq` and `object` with its `if_match`, `overrule` and `resolves` (a list of object labels) where it states them, a `Remove` its `seq`, a `SetFlags` its `seq` and `flags`, a `Copy` or a `Move` its `seq` and the collection it goes `to`, objects named by label.
- `remote`: what the connector answers:
  - one page as `snapshot` or a round's pages as `pages`, each member with its `meta` read from a fixture (and the source's own `attachment` flag and `size` where it states them) or, for a file, the `link_id` and `summary` it states, and `carries` where the member carries its body, the meta's fixture, as a DAV listing may (§4); a member stating none carries no body;
  - `narrowed` on every page of a round a date filter narrowed, and `enumerated` on its last page, the handles an unfiltered enumeration lists (§4, §5); `capped` on every page of a round the source caps (§4, §5);
  - `cursor_rejected` when it refuses the stored cursor, `interrupted_after` when it fails after that many pages (a head not counted), `scope_bound` false for a checkpoint bound to no scope;
  - `heads`, the heads it lists (`delta`, `band`), and `head`, its answer to the run's head: its `kind`, the `from` checkpoint or the `since` instant the engine MUST ask it from, then `rejected` when it refuses that position, or the page's `items`, `vanished` and `checkpoint`;
  - the fetch answers by handle and tier, a file's carrying its stated `meta`.
- `expect`: the pushes in order, the outcomes fed back, the events (an `Overruled` one naming the retained item's `link_id`), `parked` with the `absent` and `bound` counts of a round or a rekey the run parked, `failed` when the run MUST fail, and the rows after, which a failed run leaves as its last write did. An object it states after the run is the row and the file the run leaves under its name, `blob` and `corrupt` read as in `store`: one stating neither holds bytes hashing to its name.

A provisional handle is written with its leading `U+0001`. A source row states its round as `round`, `round_open` and the round's columns (`round_band` among them and, where a band head reads it, `round_started_at`), and its coverage as `covered` and the coverage's bounds; a binding states its `round`.

A `store` may state `supersessions`, rows of the table (STORAGE §4.3), for a held tombstone. `expect` may state the `collections` a run declares, with their `name` and `role`, and the `references` it records. Vector 70 binds an engine whose owner records attachments (STORAGE §14.3); every other case leaves them out of its store.

A push is compared on its change, handle and `key` (§4) and on what the change carries: `flags` for an `Add`, `add` and `remove` for a `SetFlags`, `to` and `link_id`, `if_match`, `origin` as collection and handle, `supersedes` as collection, handle and `if_match` when the add carries it, and `object` by label. An outcome names its handle, `Accepted` or `Rejected`, and for an add the `assigned` handle and the `revision` reported. An add accepted with no handle (§4) states `assigned` as `null`.

Rows are compared as parsed structures on the columns a case names, a flag set and a summary's lists as arrays (STORAGE §16), excluding `changed` stamps and the instants SQLite stamps (`retained_at`, `covered_at`, `round_started_at`), which a case states as present or absent. Chunked pushes or writes are compared concatenated.

Every case pins two rules: no `Remove` is pushed but for a tombstone the store held or the run staged; and no based binding of the run's source is dropped but for a removal its remote stated, an absence from a round the run closed (in that round's scope and not parked), a tombstone, or a rekey not parked. checks/vectors.py validates each case's structure, references, every push's key, every `Overruled` event's key (§9, STORAGE §9), those two rules, the mass-absence and empty-listing guards of §5 and §8, a narrowed round's absences (§5), a held message named apart from a member it does not agree with (§6), and that no body is pushed over, nor left facing, a server edit nobody has read (§5, §6, §9), and that an `Edit` settling a conflict its `resolves` does not name fails with the rows unchanged (§7); only an implementation runs one.

## 12. Conformance

An implementation offering sync conforms by one profile or both, stated as STORAGE §17 says (`sync-draft-08 engine`, `sync-draft-08 connector (IMAP)`), and MUST meet every section its row names and pass the vectors it names.

| Profile | What it does | Owes | Vectors |
| --- | --- | --- | --- |
| engine | runs the verbs over a store as its owner (STORAGE §17) | §1 to §10, and STORAGE §10 to §12 and §14 | every case under vectors/sync/ |
| connector | answers an engine's enumerate, fetch and push for one source over one protocol, which its statement names | §4, and what §5 and §8 ask of a listing | none alone: a case's `remote` is what a connector answers, run by an engine |

Both meet STORAGE §18 where it names them: a connector writes no credential into a checkpoint, a resume cursor or an error, and a name a server hands it is untrusted.
