---
cairn: change
id: scoped-mail-sync
status: active
created: 2026-10-07
---

# A mail sync shows the newest mail first, within a scope on the `Date` header

## Why

Two clients of one store met the same wall from opposite ends, on 2026-10-07.

- **MOA** (desktop, neverest underneath): a 1 GB Microsoft 365 box showed nothing for about 2 minutes. neverest lists a whole folder before it writes anything, Graph's message delta pages hold 10 mails by default (126 requests in a row for a 1,254-mail Inbox), and only then do the probes get their meta. MOA's own plan: a sync window on the `Date` header, widened step by step (`moa/docs/plan/sync-window.md`).
- **Pimalaya Android** (io-pimdir over JNI, its own connectors): the store holds a window of the newest 50 messages per mailbox, so older mail is unreachable and search only sees one page. Its plan: store every mailbox's meta whole, newest first, in committed chunks, with an optional bound of N months, and a list that loads lazily (`android/cairn/changes/full-mail-index/`).

Both run io-pimdir's sync through the same seam (SYNC.md §4): an enumeration of handles and flags, probes, then a `Meta` upgrade, then for MOA a `Full` one. The seam has no notion of a bounded scope, no way to commit a round before it ends, and no way to name a member at the enumeration it already read the envelope in. Each plan works around it on its side (MOA by a ladder of whole runs, Android by dropping probes in its own engine); this change fixes it once, in the spec, so neverest and the Android bridge implement one behaviour.

## What the two plans agree on, and where they differed

| | MOA (sync-window) | Android (full-mail-index) | This change |
|---|---|---|---|
| Bound | window on the `Date` header, widened by MOA | "all, or last N months", user's choice | one **scope**: a floor on the `Date` header; the received date only narrows the listing, with a two-day margin |
| Outside the bound | out of scope, never deleted | "retire what the bound no longer holds" | never deleted by a sync, as nothing in pimdir is; freeing the space is the owner's manual **collection** |
| Time to first mail | ladder of short runs | newest first, chunks committed | **paged rounds**: a full round committed page by page, newest first, resumable; a ladder becomes optional |
| Probes | unchanged | removed in its own engine | **removed**: every enumerated member arrives named, with its meta |
| What it reports | coverage per collection ("since …"), bytes, throttling | nothing yet | **coverage** stored per collection and source, read by every reader |
| Graph `date` | from `receivedDateTime`, to fix | from `receivedDateTime` too | `sentDateTime` everywhere (Annex A: the `Date` header) |
| Attachment mark | from the body, fetched anyway | from `Content-Type`, without `BODYSTRUCTURE` | the source's own flag, else `multipart/mixed`, corrected by the body |
| Bodies | `Full` while syncing, newest first | on open only | unchanged: the consumer's choice of tier, outside the seam |

## What

### 1. The scope (SYNC.md §5, STORAGE.md)

- A source MAY sync a mail collection under a **scope** `[since, until)`, `until` open in the usual case. A member is in scope when its summary `date` falls in it, or when it has no usable `date` (rare, small, never lost; drafts before sending).
- **The `Date` header decides, always** (Annex A's `date`, the mail `sort_key`): same on every provider and every copy, and what both clients sort their list by. A provider's received-date filter (Graph delta's `receivedDateTime ge`, Gmail's `after:`, JMAP's `after`) only narrows the listing to a superset, taken with a **margin of two days** (skew, zones, `SENTSINCE`'s whole days, Gmail's PST midnight); IMAP narrows with `SENTSINCE`/`SENTBEFORE`, with a day's margin. The connector drops what its local check on the `Date` puts out of scope. Received dates are never stored.
- **Absence means deleted only in scope.** A complete round reconciles the in-scope placements and leaves the others alone: no drop, no push, no pull. An explicit removal (IMAP `VANISHED`, Graph `@removed`, Gmail deletion history, JMAP `destroyed`) applies whatever the date.
- **A sync never deletes on the server.** A `Remove` is derived from a tombstone a consumer staged and from nothing else: not from a scope, a narrowing, a widening, an interrupted round, a restarted round or a collection. Vectors pin it: no run of §11's scoped cases pushes a `Remove` the consumer did not stage.
- **Local changes push whatever the scope**: tombstones, moves, flags, creates and intents are never held back by it.
- **A checkpoint belongs to its scope.** The store records the scope a checkpoint was made under. A changed scope starts a round over the new one; a connector whose cursor is not bound to a scope (IMAP `CHANGEDSINCE`, Gmail history, JMAP state, all filtered locally) MAY list only the band it lacks and keep its cursor. A Graph delta link made under a `$filter` is bound to it.
- Mail only. A scope on a DAV, Google Agenda or People collection is refused by name.

### 2. Paged rounds (SYNC.md §4, §5)

- A full round MAY be answered in **pages**, newest first in the source's own recency order (UID descending; Graph message delta, which already answers by `receivedDateTime` descending; Gmail's list order; JMAP `receivedAt` descending). The engine merges each page as a delta without removals, commits it in one write, and stamps every binding it saw with the round's id.
- The round's **resume cursor** (opaque, the connector's) lands with each page. An interrupted round resumes from it; a cursor the source rejects (an expired Graph skip token, a Gmail page token) restarts the round, which costs a relisting and no refetch, the members already named being matched by handle.
- **Deletes are inferred once, when the last page lands**: in-scope bindings of this source not stamped by the round are dropped `Deleted`. The delta checkpoint is the one taken when the round began where the source gives one up front (IMAP `HIGHESTMODSEQ` at the select, Gmail's `historyId`, JMAP's state), so what moved during the round is caught by the next delta. Graph gives its delta link only on the last page of the round, and that link covers the round itself.
- A round of one page is today's complete enumeration: nothing changes for a connector that does not page.
- **Default page sizes**, safe on a slow network and under every provider's limits; each page is one request (or one batch of requests) and one write:

| Source | Page | Why |
|---|---|---|
| IMAP | 500 UIDs per `UID FETCH` | `ENVELOPE`, flags, `INTERNALDATE` and a few header fields are under 1 KB a mail: half a megabyte a response, short enough to resume cheaply |
| Graph message delta | 1,000 (`Prefer: odata.maxpagesize=1000`) | honoured with the summary `$select`, first page in under 3 s (measured below) |
| Gmail | 100 ids per `messages.list`, their metadata read in batches of 50 | Google advises batches of 50 at most; 100 reads paced near 40 a second commit every 2.5 s |
| JMAP | 500, capped by the server's `maxObjectsInGet` | the server states its own ceiling |
| DAV, Google Agenda, People | 64 bodies per `multiget` or batch | neverest's body batch today (`BATCH_SIZE`) |

A connector MAY lower a page after a timeout or a `413`, and MUST NOT raise one past these without a measurement.

### 3. Members arrive named; probes go (SYNC.md §3 to §6, §12; STORAGE.md)

- **Every enumerated member carries its meta**: the identity hint, the summary and address rows and the `sort_key` of Annex A, as a `Meta` fetch does today. The engine names it in the page's write, on §6's identity rules (minting decided against the whole collection, a pending create landed rather than minted).
- Mail reads it in the listing itself: IMAP from the same `FETCH` (`UID FLAGS INTERNALDATE ENVELOPE` and the header fields Annex A needs, `Content-Type` among them, no `BODYSTRUCTURE`), Graph from `$select`, Gmail from the metadata read it already makes (`Content-Type` among `metadataHeaders`), JMAP from `Email/get` with summary properties.
- DAV, whose meta is the body, fetches each page's bodies (`multiget`) before the page is handed over: nothing reaches the store unnamed.
- **The `probes` table and the `Probed` level go**, with `upsert_probe`, `delete_probe`, `delete_probes`, `load_probes`, `count_probes`. "Creates wait for the probes" becomes "creates wait for the page": a pending create is landed by the page carrying its arrival, as an upgrade lands it today. The `Meta` upgrade remains only to revisit a claim the row does not hold (§6).

### 4. The attachment mark (Annex A)

- Without the body: the source's own flag where it states one (Graph `hasAttachments`, JMAP `hasAttachment`), else `1` when the top-level `Content-Type` is `multipart/mixed` and `0` otherwise.
- With the body: the walk of the parts, as today, which replaces the first.
- Known misses, both corrected when the body is read: a `multipart/mixed` with no attachment (Mailman footers, Apple Mail's inline images) reads as one; an attachment under `multipart/signed` or `multipart/encrypted` reads as none. Saves IMAP the `BODYSTRUCTURE`, by far the heaviest item of a bulk fetch.

### 5. Coverage (STORAGE.md, beside the checkpoint)

- Per `(collection, source)`: the scope of the last complete round and when it landed, and, while a round is open, its scope and resume cursor. `NULL` coverage means never complete.
- Read by `list_collections` and its kin, so a reader says "mail since …", a search knows it is not exhaustive, and nobody opens the sync state to find out.

### 6. Collecting what lies outside the scope (STORAGE.md §11 kin)

- Nothing in pimdir is deleted by inference, and a scope is no exception: mail older than the scope stays stored, and stays readable, until the owner collects it.
- `collect_before(collection, before)`: the owner's manual collection of the placements whose `date` is older than `before`, with their bindings and the objects no longer referenced. No tombstone, no push. A later widening relists and refetches them.
- The answer to Android's narrowed bound; MOA never calls it.

### 7. Readers

- Pages and counts under a filter, so a list can be sized by a count and loaded around the scroll position: `count_mail`, a page by `(sort_key, seq)` keyset (exists: `list_mail_page_desc`), per-day counts, unread counts, each over a set of collections and the read and attachment chips.
- Search over sender and subject by `LIKE` until SEARCH.md's index; full text waits for the 2027 plan.

### 8. Fixes that need no spec, first

- Graph's `date` from `sentDateTime`, in neverest and in the Android bridge: today both store `receivedDateTime` under a column Annex A defines as the `Date` header.
- Larger Graph pages: `Prefer: odata.maxpagesize=1000` on message delta (measured below), `$top=1000` on plain listings. io-msgraph has no way to send the header yet.
- **IMAP delete expunges one message only.** neverest's `delete_message` marks a UID `\Deleted` and sends a plain `EXPUNGE`, which removes every message any client marked `\Deleted` in that mailbox. It SHALL use `UID EXPUNGE` on that UID (RFC 4315, part of IMAP4rev2) and, on a server offering neither, reject the push rather than expunge the mailbox, as Android already refuses.
- Throttling: follow `Retry-After`, back off on 429, 503 and Gmail quota errors, keep what landed, and report `throttled { source, until }`.
- **Gmail paced below its quota, not at it.** 250 units per user per second, `messages.list` and `messages.get` 5 each: about 50 reads a second, batched or not. A connector holds itself near 40 a second rather than waiting for 429s, and Gmail over IMAP stays well under its daily download cap, past which the account is locked out for up to a day. With pages newest first, an unbounded Gmail scope shows its first page at once and fills the rest in the background (100k mails: about 40 minutes of meta); a scope stays the user's choice, not Gmail's.

### Graph, measured on the test tenant (2026-10-07)

On `microsoft@pimalaya.onmicrosoft.com`, Inbox of 1,254 mails:

- **`$deltatoken=latest` is ignored by message delta**: with or without `$select` or `$filter`, either casing, the answer is an ordinary first page (10 mails, a next link), not an empty page with a delta link. There is no shortcut to a delta link; none is needed.
- **Message delta answers newest first** (`receivedDateTime` descending, 2026-10-07 to 2023-10-08), so it is already a paged round in recency order.
- **Full summary `$select`** (`id, subject, from, toRecipients, ccRecipients, sentDateTime, receivedDateTime, isRead, flag, hasAttachments, internetMessageId, conversationId, parentFolderId`): `maxpagesize=1000` is honoured, 3 requests, first page in 2.6 to 2.9 s, the whole Inbox in about 6.5 s; at 200, 7 requests, about 12 s. Ids only at 200: 7 requests, under a second.
- A plain listing by `sentDateTime desc` at `$top=1000`: 2 requests, about 6 s, but no delta link at its end.

So Graph's connector is one filtered message delta with the summary `$select` at 1,000 a page, each page committed as it lands: the Inbox that took two minutes shows its newest thousand mails in about three seconds.

## What each client then does

- **neverest**: pages and named members for `imap`, `msgraph` and `gmail`, bodies fetched per page for DAV; `item.filter.since` in the account (the `ItemSyncConfig` slot reserved for it) and `sync --since` for one run; coverage, bytes and throttling in its report; Gmail paced. Bodies stay its own hydration, newest first.
- **himalaya**: coverage in `pimdir collection list --json`, so MOA never reads the store itself.
- **MOA**: the ladder of `sync-window.md` keeps its order (Inbox and Sent first) but each step shows its first page within seconds, so it can shrink to Inbox and Sent over 30 days, every folder over a year, then no scope. The agent says "dans les mails depuis le …" from coverage. The paperclip and triage read the mark of §4 until the body is in.
- **Android**: its four connectors page and carry meta; `PER_MAILBOX` and the probe-then-upgrade step go; the account's bound is a scope, a narrowed bound a collection; the lazy list reads the counts and pages of §7.

## Open questions

- **Skip token lifetime**: how long Graph keeps a delta round's next link valid, which decides whether an interrupted round resumes or restarts. To measure.
- **An old mail moved into the Inbox** keeps its old `Date` and leaves every scope that does not reach it: acceptable while the widening ends within hours; otherwise a move seen in a delta could be followed whatever the date.

## Out of scope

- Server-side search; full-text search (SEARCH.md, 2027).
- Bodies: when to fetch them stays each client's choice.
- A per-mailbox view ordered by UID.
- Scopes on anything but mail.
