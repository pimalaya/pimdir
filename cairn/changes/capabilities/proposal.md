---
cairn: change
id: capabilities
status: landed
created: 2026-10-02
---

# Sources declare what they can do

> Cross-repo change, same id, in this order: **pimdir** (here: the vocabulary, the tables, the rules) → **io-pimdir** (statements, typed registry, the producer gate and the owner park) → **neverest** (declares per backend, performs the intents) → **himalaya**, **cardamum**, **calendula** (refuse before enqueueing, name the performer). MOA consumes the result through the three CLIs.

## Why

A store is fed by sources that do not push the same things. Today the gap is only discovered after the fact: a producer enqueues an action, the owner pushes it, the source refuses, and the refusal lands in a sync report the user never reads. Measured on neverest 0.3.0 (src/client.rs):

- a Graph mailbox takes flags and deletes but refuses `move` and `add` ("Graph messages are pull-only"), so `message delete` (a move to the trash) and a saved draft never reach Microsoft 365;
- Graph flags carry `\Seen` and `\Flagged` only, Gmail the same two through labels, IMAP every flag and keyword;
- Google Calendar and Graph calendars do not push an edited occurrence of a series, CalDAV does;
- an invitation reply exists on Google (an attendee's own `responseStatus`) and not on Graph (`/accept`, `/decline` are endpoints, not state);
- sending is a `submit` intent neverest performs through SMTP or Graph `sendMail`, and nothing says which source sends when an account has two.

A frontend that wants one behaviour across providers has two bad options: the least common denominator (what himalaya's shared API does across protocols), or a table of per-provider exceptions copied in every consumer, which drifts the day the owner improves. The alternative is the LSP one: a vocabulary fixed by the standard, values declared by whoever implements them, consulted before acting.

The owner is the only process that knows what its sources push: it holds the configuration (rights, `item.create = false`) and the backend code. Producers never talk to the owner, and a consumer that had to know which owner runs a store would not survive a second owner. The store is the one channel both already share, so the declaration lives there.

## What

**Vocabulary (Annex B, normative).** Capability names `<domain>.<object>.<verb>`, the domain fixing the kind: `mail` (`message/rfc822`), `contacts` (`text/vcard`), `calendar` (`text/calendar`). Two families:

- **State** capabilities gate the six queue actions per kind: `mail.message.add`, `.copy`, `.move`, `.remove`, `mail.flags.seen`, `.flagged`, `.answered`, `.draft`, `.keywords`; `contacts.card.add`, `.update`, `.remove`, `.move`, `.copy`; `calendar.item.add`, `.update`, `.remove`, `.move`, `.copy`, plus three read from the resource itself: `calendar.occurrence.update` (an update changing a `RECURRENCE-ID` component), `calendar.scheduling` (the source notifies the attendees of a resource the producer has not marked `SCHEDULE-AGENT=CLIENT` or `NONE`) and `calendar.online-meeting` (a resource carrying `X-PIMDIR-ONLINE-MEETING:TRUE`, created with a meeting of the provider in one push).
- **Intent** capabilities gate an application kind performed outside the store by exactly one source: `mail.submit` (kind `submit`, the shape neverest and himalaya already exchange), `calendar.reply`, `calendar.cancel`. Annex B fixes each payload at `v: 1`. A capability is implemented by a source, one implementation per source: a provider's own verb declared on the collections it holds, an iMIP one declared source-wide by a source that sends. Several implementations for an account are several candidates, and the user chooses; a producer never implements a capability itself.

A name outside the registry starts with `x-`.

**Declaration (§15.6).** A new `capabilities` table, one row per `(source, collection, capability)`, carrying `support` (`full`, `partial`, `none`) and a human `detail`; `collection` is `NULL` for the source-wide row and names a collection where the source does otherwise there (a calendar shared read-only). The owner declares a source's whole set in one transaction (`delete_capabilities`, then `set_capability` per row), every capability of its kinds, `none` included, before draining actions for it and whenever its configuration changes. A source with at least one row is **declared**, and a capability it lacks is unsupported; a source with none is **undeclared**, the state of every store written before this change, and is gated by nothing. A source id names one remote store-wide, which this change states.

**The producer gate.** Before enqueueing, a producer reads the sources concerned (`load_capabilities` for a collection, `load_item_capabilities` for an item) and MUST refuse an action a declared source does not support, naming the capability, the source and its detail. A `partial` support passes, its detail shown. An action on an item needs every source binding it; an `add` every source syncing the collection.

**Intents and performers.** An intent names its performer in its payload (`"source"`). The producer resolves it from `list_capability_sources(account, capability)`: none is a refusal, one is the performer, two or more need the user. The user's choice is recorded once with a new core action, `set-performer`, which the owner applies into a new `performers` table (`load_performer`), or given for one action only. A producer MUST NOT pick among several candidates by itself.

**The owner's backstop.** An action that reaches the drain against a declared source lacking its capability, or an intent naming a source that does not declare it, is parked with the capability named: the producer gate is the user-facing check, the park makes a bypass visible instead of a silent rejected push.

## Scope / non-goals

- **Live queries** (another person's free/busy, a server-side search of what was never synced, mail filters, out-of-office, calendar sharing) are not store traffic and are not in the registry. A CLI exposing them may reuse the naming scheme for its own surface.
- **Collections**: creating, renaming or deleting a collection on the remote is not a queue action today, so it has no capability here.
- **Folder roles** (`inbox`, `sent`, `archive`…) are data the owner records about a collection, not a capability. A separate change, `collection-role`.
- **Per-collection limits** (a Gmail system label cannot be removed) stay rejections in the owner's report: the declaration is per source.
- **A stale declaration** is accepted: the owner declares when it runs, so between a configuration change and its next run a source may read as supporting what it no longer does (the owner parks the action, nothing is lost) or as lacking what it now does (the user is refused until the next run). Misinformation for as long as the delay, never data loss. An owner keeps the delay short by declaring at every open of the store.
- **Outcome of an intent**: unchanged. A performed intent is acknowledged by `cancel_action` (§15.5), a failed one parked; a richer outcome record can follow if consumers need more than pending, parked or gone.

## Decisions (reviewed 2026-10-03)

1. **State actions over several sources are strict**: an action on an item needs every source binding it. Accepting a partial delivery would leave two sources disagreeing behind the user's back. Known edge, for the log entry rather than the rule: a source that only receives one-way copies would veto every action on what it binds; only the sources a push reaches should be gated if a store ever mixes such a target with a two-way source. A narrow case: nothing gains from syncing one mailbox through both IMAP and Graph.
2. **`calendar.scheduling` refuses** a scheduled resource on a source that does not notify; the acceptance lives in the resource (`SCHEDULE-AGENT=NONE`), so it is asked once per event and the owner's backstop reads the same answer. A `partial` support passes, so a client SHOULD show its detail: Google's (a new event is imported, notifying nobody) is the case that matters today.
3. **Performers live in the store.** The foundation: a client knows nothing of the owner, and a himalaya user need not run neverest, so a client's configuration cannot name the owner's sources. A choice holds from the moment it is queued: a producer reads a pending `set-performer` over the recorded one (§15.6, §15.4).
