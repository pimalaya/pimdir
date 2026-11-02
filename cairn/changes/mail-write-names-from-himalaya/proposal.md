---
cairn: change
id: mail-write-names-from-himalaya
status: draft
created: 2026-11-02
---

# Mail write names himalaya declares beyond Annex B

## Why

Himalaya's shared API is now a union of capabilities named in Annex B's grammar without the domain word (himalaya cairn/changes/capability-shared-api, landed 2026-11-02): its `message.move` is `mail.message.move`, its `mailbox.*` is `collection.*`. Every write name its registry declares today is already an Annex B row (`mail.message.add`, `.copy`, `.move`, `.remove`, the four flags, `mail.submit`, `mail.submit.copy`); the rest are reads, which a store answers locally and Annex B does not name, and `message.trash`, a `move` to the collection holding the `trash` role.

Its inventory also lists writes a replica would push that Annex B cannot name yet. Proposing them here, in pimdir's spelling, keeps the two vocabularies one before himalaya grows the shared verbs that need them.

## What

Four rows, each a write a source performs and some sources lack:

| Capability | Kind | Needed by |
| --- | --- | --- |
| `collection.rename` | the collection's | a rename of a collection, its items kept |
| `collection.delete` | the collection's | a delete of a collection and what it holds |
| `mail.flags.important` | `message/rfc822` | a flag change on `$Important` (RFC 8457), beside `mail.flags.keywords` |
| `mail.flags.junk` | `message/rfc822` | a flag change on `$Junk`, beside `mail.flags.keywords` |

- **The two flags leave `mail.flags.keywords`.** Gmail (`IMPORTANT`, `SPAM`) and Graph (`importance`, the junk folder) carry them as fields while taking no arbitrary keyword, Gmail only labels that exist and Graph categories; under `mail.flags.keywords` alone such a source must declare all keywords or neither of these. A source supporting `mail.flags.keywords` keeps reading a flag change on either as supported there, so a store declaring neither new row is read as before.
- **`collection.rename` and `collection.delete` need intents**, as `collection.create` is one (B.2): a payload, a schema under payloads/, and the delete's rule for the items it removes (one `remove` each, or the collection's absence on the next round). The deletion's detail differs per server, Graph deleting the folder with everything in it where an IMAP server may refuse one with children, which a `partial` row's detail says.

Left out, from himalaya's inventory:

- **The draft verbs** (`draft.save`, `draft.send`): a draft is already an `add` with `\Draft` in the `drafts` collection and its sending a `submit`, so a store needs no name of its own; Gmail's and Graph's draft resources are a source's way to perform those.
- **`submit.cancel`**: cancelling a submit the queue still holds is the queue's own (`cancel_action`), and cancelling one a server holds (JMAP `EmailSubmission` with `undoStatus` `pending`) happens outside any replica.
- **Mailbox moves**: a reparent is a rename where the hierarchy is the name (IMAP, Gmail), and a property where it is a parent id (JMAP, Graph); whether it is `collection.rename` or a row of its own waits for the rename intent's payload.
