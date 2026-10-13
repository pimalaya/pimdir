---
cairn: change
id: round-head
status: active
created: 2026-10-13
---

# A round shows what arrives while it fills: the head

## Why

A first round over a large mailbox can stay open for many runs. Gmail is paced below its quota, so a 20,000-message Inbox takes about a quarter of an hour; IMAP and Graph take minutes on large folders. Paged rounds (scoped-mail-sync) show the newest mail within seconds, but only the mail that was there when the round began. While the round is open, every run resumes it, its remaining pages list older mail, and no delta runs before it closes. A message arriving meanwhile is invisible until the round ends.

The case MOA met:

- 10:00: a Gmail Inbox of 20k opens its round. neverest reads the history id H = 1000 before page 1; page 1 lands the 100 newest mails.
- 10:03: "Facture" arrives (history id 1001). carillon signals it; MOA runs a targeted Inbox sync, which resumes the round from its page token. The next page holds older mail, and Facture is in none of the remaining pages.
- 10:03 to 10:18: every run resumes the round the same way.
- 10:18: the last page lands. The round closes on checkpoint H, and the members it did not list are found absent.
- Next run: the delta from H lists Facture, 15 minutes late. MOA's triage, notifications and "À traiter" saw nothing during that time.

The store held the right answer the whole time: the round's checkpoint H, taken before page 1, is a position the source can list changes from. The engine never asked.

## What

### 1. The head (SYNC §2, §4, §5)

While a round is open, a run resuming it lists the **head** before the round's next page. The head is one page of what changed in the collection since the round began. It is checked against the run's scope, as a delta is. It never moves the round's cursor.

There are two kinds, chosen by what the source can list from:

| | Delta head | Band head |
|---|---|---|
| Lists from | the round's checkpoint (`round_checkpoint`), or, for a band round, which carries none, the source's checkpoint | the instant the round opened (`round_started_at`), less two days |
| Lists | what changed since that position: arrivals, flag changes, removals | every member the source dates at or after that instant, by an instant that never moves back (last modified where the source states it, else received) |
| Removals | stated (vanished handles), applied at once | none stated, none inferred |
| Stamps its members | yes, with the round's id | no |
| Checkpoint | carried, MUST; becomes the round's | none |
| IMAP | QRESYNC `SELECT … CHANGEDSINCE` | `UID SEARCH SINCE` on `INTERNALDATE` (server without QRESYNC) |
| Gmail | `history.list` since the history id | (not needed) |
| JMAP | `Email/changes` since the state | (not needed) |
| DAV | `sync-collection` since the token | (not needed) |
| Graph | only once a checkpoint exists (a band round's delta link) | `/messages` filtered and ordered on `lastModifiedDateTime` (else `receivedDateTime`), summary `$select` |
| Google Agenda | only once a sync token exists | `events.list` with `updatedMin` |

A connector states which kinds it lists, as it states `scope_bound`. The engine asks for a delta head when it holds a position and the connector lists delta heads, else for a band head when the connector lists band heads, else for none.

### 2. With the open round (SYNC §5)

- **Merged as a page before the last.** The candidates are the head's members and vanished handles only. Every member is named on §6's identity rules, a pending create's arrival is landed rather than minted, and a vanished handle is dropped `Deleted` at once.
- **A delta head stamps its members** with the round's id, so the round's last page never finds them absent. Facture survives the close. A member it named and the source removes later is reported by the next head, or by the first delta after the round closes on the head's checkpoint.
- **A band head stamps nothing.** It has no position, so if a member it named were stamped and the source removed it before the round's checkpoint was taken, no later listing would state the removal, and the member would stay for ever. Instead, the connector MUST list again, in every round's last page, read no earlier than that page's checkpoint, every member a band head would list then. What is gone is then found absent by the close, which already handles this.
- **A head never moves the round's cursor, scope or coverage**, and infers nothing from an absence.
- **One member, one handle.** A member a head named and a later page lists again is refreshed, never doubled. For a later page to list a member a delta head stated removed, the member must really be back: a connector listing delta heads MUST read each page's members no earlier than the head before it, as IMAP `UID FETCH` and Gmail's metadata reads already do, and leave out what the source no longer holds.
- **A rejected head position restarts the round** over the run's scope, never a band. The checkpoint the round would close with is void. Restarting costs a relisting, no fetch, and the new first page carries a fresh checkpoint.

### 3. The checkpoint at the close (SYNC §5, STORAGE §10)

The round closes on its last page's checkpoint when that page carries one (Graph's delta link, read after every head). Otherwise it closes on the latest a head or a page landed in `round_checkpoint`. Otherwise it keeps the source's old checkpoint. That is exactly what `close_round`'s `coalesce(:checkpoint, round_checkpoint, checkpoint)` already does. A delta head records its checkpoint through `set_round_cursor` with a `NULL` cursor, which now keeps the cursor a page landed (`coalesce(:cursor, round_cursor)`).

A band head records nothing, so a Graph round closes on its delta link as today.

A band round's pages hand no checkpoint, but its heads do. A widening band round on IMAP therefore closes on the latest head's checkpoint rather than the old one. That is sound because the head was checked against the run's whole scope, not the band.

### 4. Creates stay held (SYNC §5)

A head derives no `Add`. Until the round's last page lands, its unlisted pages may still carry a pending create's own arrival, relocated by a move's other half or added by an add whose record was lost. A head lands the arrivals it does list (vector 67). Other pushes follow the page-before-the-last rule: a `SetFlags` or `Remove` derives only for a placement the head lists.

### 5. Moves, global handles, flags, coverage

- **Moves between collections**: each collection keeps its own listing. A message moved from Archive into INBOX on the server is a removal in Archive (stated by Archive's delta or head) and an arrival in INBOX (landed by INBOX's head while INBOX's round is open). On IMAP and Graph it gets a new handle there; on Gmail it keeps its id under the INBOX label. A local move into a collection whose round is open keeps its create held, as before. That collection's head may land its arrival early, which delivers the create without a push (vector 67).
- **Global handles (Gmail labels)**: a head is per collection, as every listing is: Gmail's history projected on the collection's label. One message under two labels is one binding in each collection, each landed by its own head or page.
- **Flags**: a head lists the member with its current flags. They are merged three-way like any listing's (vector 63). A band head filtered on last-modified also sees flag changes on old mail; one filtered on received time does not, and those wait for the close.
- **Coverage**: unchanged by a head. The coverage moves only when a round closes, and `until` stays as the round has it. A head's members lie in the run's scope, and a reader of `list_coverage` keeps seeing "never complete" until the round closes.

### 6. Storage

There is no schema change. `round_checkpoint` already holds the checkpoint the round will land, which is the head's position, and `round_started_at` already holds the band head's instant. The statement text of `set_round_cursor` changes (the cursor is coalesced), and statement text plays no part in the reconciliation on open, so no table is rebuilt and nothing migrates. Alternatives rejected:

- **A new `sources.round_head` column** for the head's position: the close would then have to choose between two checkpoints, and the `sources` table would be rebuilt on every store's next open.
- **A `bindings.head` stamp** separating head-landed bindings: a column on the largest table, rebuilt on open. It is only needed if band heads infer absence by themselves, which the last page's relisting makes unnecessary.

No audit or report field is normative. neverest may report heads per collection.

### 7. Vectors (vectors/sync/62 to 69)

| # | Case |
|---|---|
| 62 | the example above: a delta head from `h1000` lands the arrival, stamped; the last page finds an unstamped binding absent and keeps the arrival; the round closes on the head's `h1001` |
| 63 | a delta head's vanished handle drops at once, a bound flag change is pulled, an unbound vanished handle is nothing; cut after the head, the cursor stays and the round's checkpoint moves |
| 64 | a member the head named and the last page lists again is one item, one binding, one `Added` |
| 65 | Graph-like band head from `round_started_at`: the arrival is named unstamped, a flag change pulled, no checkpoint recorded |
| 66 | Graph-like close: a band head infers no delete; the last page relists the band and carries the delta link; the relisted head member is kept, the one the source removed is found absent; closes on the link |
| 67 | a head lands a pending create's arrival (`Created`), holds the other create, and pushes no flag for a dirty placement it did not list |
| 68 | a rejected head position restarts the round under a new id |
| 69 | a band round's head lists from the source's checkpoint over the run's scope, names an arrival outside the band, and the band round closes on the head's checkpoint |

Each case also pins that no `Remove` is pushed without a staged tombstone (checks/vectors.py). checks/vectors.py checks that a head resumes an open round, of a kind the connector lists, from the right position or instant. checks/invariants.sh checks that `set_round_cursor` with a `NULL` cursor keeps the cursor.

## What each client then does

- **io-pimdir**: a head listing in the coroutine (`PimdirListing::Head`, a delta or a band head, and an answer that a head was refused, or that none can be listed), `PimdirRemote::heads()`, the head merged as a page before the last, stamps and `SetRoundCursor { cursor: None, checkpoint }` for a delta head, nothing for a band head, a rejected head restarting the round over the run's scope.
- **neverest**: IMAP delta head through the QRESYNC delta it already lists (`delta_page`), band head by `UID SEARCH SINCE` without QRESYNC; Gmail delta head through the history it reads once a run; Graph band head on `/messages` by `lastModifiedDateTime`, and its whole-folder round's last page relisting the head band after the delta link (the band-mode pass already lists every held member); pages read fresh after a delta head (Gmail: drop a member whose labels no longer hold the collection's).
- **MOA**: nothing to change. The targeted Inbox sync that an arrival triggers already resumes the round, and the head makes the arrival show in that run. "Première synchronisation" keeps showing until the round closes.
- **Android**: the same connectors, through the same seam.

## Open questions

- **Graph's band head instant**: is `$filter`/`$orderby` on `lastModifiedDateTime` honoured on `/messages` with the summary `$select`? Measure on the test tenant. Without it, `receivedDateTime` misses moves into the folder and flag changes until the close.
- **Does Graph's whole-folder delta round list arrivals made during it?** The relisting rule holds either way, but it decides whether band heads only shorten the wait or also fill a gap.
- **The two-day margin** makes a band head relist two days of mail every run, one Graph request of 512 summaries for most boxes. A narrower margin would need a server instant stated by the first page instead of the store's clock.
- **Pushing during a head**: the placements a delta head does not list but the round has already stamped could safely push their flags and tombstones too. Their base is reconciled up to the head's position: every change after it is reported by a later head. A mark-as-read during a first sync would then not wait for the close. Left out, so that a head adds no new push semantics. A follow-up if MOA needs it.
- **Cadence between pages**: the text allows a head between two pages of one long run. Whether the engine lists one on a timer, or only when the consumer asks, is left to io-pimdir.
