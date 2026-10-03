# Desk check, 2026-10-03

Three checks of the vocabulary before any code: every MOA tool expressed with it, every neverest backend declared with it, and a second owner. Read against MOA's catalogue (crates/moa-core/src/servers/catalog/{mail,pim}.json) and neverest 0.3.0.

## 1. MOA's tools onto the vocabulary

Reads are answered by the store and need no capability; they are listed for completeness.

| Tool | Needs |
| --- | --- |
| `mail_accounts`, `mail_mailboxes` | read; the roles (inbox, sent, drafts, trash, junk, archive) are data, `collection-role` |
| `mail_search`, `mail_read`, `mail_thread`, `mail_followups`, `mail_replied`, `mail_html`, `mail_attachment`, `mail_compose_start`, `mail_compose_load`, `mail_outbox_build`, the four `*_preview` | read (a full sync holds every body) |
| `mail_draft` | `mail.message.add` into the drafts role, with `\Draft`; `replaces` also `mail.message.move` of the old version to the trash role |
| `mail_compose_save` | same as `mail_draft` with `replaces` |
| `mail_organize` | `mail.flags.seen` (read, unread), `mail.flags.flagged` (follow), `mail.message.move` (archive, move) |
| `mail_trash` | `mail.message.move` to the trash role |
| `mail_send`, `mail_outbox_send` | `mail.submit`, plus filing the sent copy (finding 1), plus `mail.message.move` of the draft to the trash role |
| `calendar_accounts`, `calendar_events`, `calendar_free_slots` | read |
| `calendar_create` | `calendar.item.add` |
| `calendar_invite` | `calendar.item.add`, `calendar.scheduling`; `calendar.online-meeting` when `online` |
| `calendar_respond` | `calendar.reply` |
| `calendar_update` (edit) | `calendar.item.update`, `calendar.scheduling` when it has attendees; `calendar.occurrence.update` on an occurrence |
| `calendar_update` (cancel) | `calendar.cancel` |
| `contacts_search` | read |
| `contacts_upsert` | `contacts.card.add` or `contacts.card.update` |

Every tool is expressible. The gaps are in the details: findings 1, 2 and 3.

## 2. neverest 0.3.0 declared

From the code, before any configured right. A right set to false (`item.create`, `item.delete`, `flag.update`, `item.update`) turns its capabilities `none`, which is what the configuration means.

**Mail.**

| Capability | IMAP + SMTP | Gmail | Graph |
| --- | --- | --- | --- |
| `mail.message.add` | full (client.rs `add_message_stream`) | full (`messages.insert`) | none, "pull-only (append)" (msgraph/client.rs:240) |
| `mail.message.copy` | full (an add by origin, SYNC §4) | full | none |
| `mail.message.move` | full (`move_messages`, COPY + expunge without MOVE) | full (label swap, gmail/client.rs:624) | none (client.rs:477) |
| `mail.message.remove` | full | partial: removes the label, permanent from `TRASH` only | partial: soft delete, out of sight, not into Deleted Items |
| `mail.flags.seen` | full | full (`UNREAD`) | full (`isRead`) |
| `mail.flags.flagged` | full | full (`STARRED`) | full (`flag`) |
| `mail.flags.answered` | full | none (label_of, gmail/client.rs:813) | none (flags_patch, msgraph/client.rs:618) |
| `mail.flags.draft` | full | none | none |
| `mail.flags.keywords` | partial: as the server's PERMANENTFLAGS allow | partial: `$Important` alone | none |
| `mail.submit` | full, SMTP (submit.rs) | none without an `smtp` block, then the SMTP one | full, `sendMail` |

**Calendar and contacts.**

| Capability | CalDAV / CardDAV | Google (gcal, gpeople) | Graph (calendar, contacts) |
| --- | --- | --- | --- |
| `*.add`, `*.update`, `*.remove` | full | full | full |
| `*.move`, `*.copy` | full (dav move_items) | none (client.rs:481-484) | none |
| `calendar.occurrence.update` | full (a body edit) | none ("modified instance does not push yet") | none ("exception edited locally does not push") |
| `calendar.scheduling` | partial: the server's (RFC 6638) if it schedules, unknown to neverest | none: insert and delete pass no `sendUpdates` (gcal/client.rs:353, 407), so Google notifies nobody | full on add, update and delete; the cancellation carries no message |
| `calendar.reply`, `calendar.cancel`, `calendar.online-meeting` | none | none | none |

Every behaviour found in the code has a name. Nothing neverest does needed a word the registry lacks, except findings 1 and 4.

## 3. A second owner

Two candidates, on paper:

- **A phone owner** syncing the store with Android's ContactsProvider and CalendarProvider. Cards: add, update, remove full; move none (a raw contact belongs to its account). Calendar: add, update, remove full; `calendar.reply` full (the provider's attendee status, sent by the account's sync adapter). Everything fits the table as it is.
- **A read-only source**: a holiday calendar, a subscribed calendar, or MOA's former one-way mirror (every right false). It supports nothing, and that is where the shape breaks (finding 5).

## Findings

1. ~~**Nobody files the sent copy over SMTP.**~~ Withdrawn on review: sending and saving are two capabilities, `mail.submit` and `mail.message.add` into the sent role, and saving a copy is the client's configuration (himalaya's `message.send.save-copy`), not a side effect of the send. A user asking for a copy with SMTP alone has no source adding to Sent, and the gate says so. That Graph and Gmail file a copy themselves, so a client also saving one duplicates it, is the configuration's to avoid, as himalaya documents.

2. **Flags carried by an `add` are not gated.** `mail_draft` adds with `\Draft`; Gmail drops it silently (the drafts are the `DRAFT` collection, not a flag). **Amend**: B.1 gates the flags of an `add` or `copy` like those of a `set-flags`.

3. ~~**"Archive" and "remove" mean other things on a label model.**~~ Withdrawn on review: pimdir already holds one message in several collections as placements sharing a link id (`list_link_placements`), so a label model needs no capability and `remove` leaves a collection on every source alike. What remains is neverest's: Gmail exposes no collection for the archive role, so archiving a message with no other label retains it as if deleted; neverest should expose All Mail, as IMAP does. Original finding: On Gmail a message is in several collections at once; removing it from one removes a label, and archiving is removing it from `INBOX`, there being no archive collection. A producer reading `mail.message.remove` cannot tell "deletes" from "unlabels". **Amend**: a capability `mail.labels`, "a message may sit in several collections and leaving one does not delete it", declared by Gmail; a producer archives by removing from the inbox when it is declared and no collection carries the archive role.

4. **Some limits are per collection after all.** Google's holiday and subscribed calendars, and a calendar shared read-only, sit in the same `gcal` source as the user's own; Gmail's system labels cannot be removed. A per-source declaration says the source can add events, and the holiday calendar refuses. **Amend**: rows MAY name a collection, overriding the source's row for that collection alone (`load_capabilities` prefers it). Without it the refusal comes back from the push, which is the late failure this change exists to avoid.

5. **A source supporting nothing reads as undeclared.** Every capability `none`, omitted since §15.6 lets `none` rows be omitted, leaves no row, which is the undeclared state, gated by nothing. The read-only source of §3 and any account with every right false hit it. **Amend**: a declaration writes every Annex B capability of the kinds the source syncs, `none` included, so a declared source always has rows and the undeclared state stays the pre-capability store. No new table.

6. **Two facts to carry into neverest, not the spec.** Google calendar notifies nobody today (`sendUpdates` unset): passing `all` makes `calendar.scheduling` full, a one-line fix. And CalDAV scheduling is the server's: neverest can read the `schedule-outbox-URL` (RFC 6638) to declare full or none instead of partial.

## Verdict

The approach holds: every MOA tool and every neverest behaviour found a name, and the phone owner fits unchanged. Findings 2, 4 and 5 were folded into §15.6 and Annex B on review (1 and 3 withdrawn); 4 is the only change of shape, an optional collection on a row.
