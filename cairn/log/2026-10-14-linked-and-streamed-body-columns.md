---
cairn: log
change: linked-and-streamed-body-columns
date: 2026-10-14
---

# A linked or streamed body states what only the body gives

A placement linked to a body the account already held (an upgrade linking from the store, an IMAP COPY or MOVE, a Gmail second label) kept the summary its listing read without the body: the attachment mark guessed from the top-level `Content-Type`, no invitation, the server's size. Since the row then held a body, the rule that a listing never writes those columns over a held body kept the guess for good. And a writer streaming a body to its blob, never holding it whole, left the invitation `NULL`.

- **Annex A.1**: a placement gaining a body the account holds, linked rather than read, holds it as read: its `size` the body's octets, its mark and invitation those a row holding the body states (`held_mail_summary`), never the listing's, a mark no such row states leaving the listing's. A writer reading a body as it streams derives the mark and the invitation as the whole body gives them, in one pass; one recording attachments states them from the walk finding its stand-ins (§14.3).
- **§14**: `held_mail_summary(link_id, object)`, queries/storage/owner/held_mail_summary.sql: the mark and invitation of a row of the account holding that body under that key, one stating its mark first, then one stating an invitation; a writer-derived key never matches.
- **SYNC §6** ("Linking instead of fetching") and GUIDE's upgrade step 2 say the same of a link.

No schema change, no vector change: the vectors pin what a body derives, which did not move. Implemented in io-pimdir (`client::attachments::gaining` in the write path, the streamed walk's `finish_parts`), tested against `derive` there. checks/names.sh, schema.sh, invariants.sh and vectors.py pass. draft-04 is not tagged yet, so the number stays.
