---
cairn: tasks
change: capabilities
---

# Tasks

## Landed in this repository, awaiting review

- [x] migrations/storage/0001_init.sql: `capabilities` and `performers` tables; `set-performer` in the queue's action comment.
- [x] queries/storage/owner/: `delete_capabilities`, `set_capability`, `set_performer`, `delete_performer`.
- [x] queries/storage/read/: `load_capabilities`, `load_item_capabilities`, `list_capability_sources`, `load_performer`.
- [x] STORAGE.md: terminology, §4.3 tables, §8 roles, §13 encodings, §14 and §14.1 statements, §15.2 park and skip, §15.3 `set-performer`, new §15.6, Annex B registry; a source id is store-wide.
- [x] GUIDE.md §1 checklist, §13 queue, §14 reader; OVERVIEW.md §8.
- [x] checks/invariants.sh: undeclared versus declared, the producer's reads, the candidates of an intent, the performer upsert per account.

## From the desk check (desk-check.md)

- [x] Finding 2: the flags of an `add` or `copy` are gated like a `set-flags` (Annex B.1, GUIDE §13).
- [x] Finding 4: an optional collection on a row, overriding the source's row there (schema, `set_capability`, `load_capabilities`, `load_item_capabilities`, §15.6, invariants).
- [x] Finding 5: a declaration writes every capability of its kinds, `none` included (§15.6, GUIDE §13).
- Findings 1 and 3 withdrawn on review.

## From the prototype (prototype.md)

- [x] Finding 1: `capabilities` rows carry the source's account, and `list_capability_sources` reads it rather than the synced collections, so a declared source is a candidate before its first sync (schema, `set_capability`, `list_capability_sources`, §4.3, §13, §14, §15.6, GUIDE §13, invariants; io-pimdir declares under the handle's account; checked end to end with a never-synced Graph source).

## From the iTIP/iMIP review (2026-10-03)

- [x] An intent's candidates are read at its anchor collection, the collection row winning over the source-wide one (`list_capability_sources(account, collection, capability)`, invariants "implementations:").
- [x] `calendar.online-meeting` is a state capability read from the resource (`X-PIMDIR-ONLINE-MEETING:TRUE`), not an intent: a meeting is created with its event in one push, so attendees get one invitation (Annex B.1).
- [x] A scheduled resource is defined by `SCHEDULE-AGENT`; the user's acceptance that nobody is notified is `NONE` in the resource, readable by the backstop (Annex B.1).
- [x] No fallback in producers: iMIP is an implementation a source declares, one per source and capability, several sources being the user's choice (§15.6 Implementations; B.3 withdrawn the same day).
- The rules reading the resource (scheduled, occurrence, online meeting) are checked by io-pimdir's tests of the gate, the SQL does not read bodies; the candidates rule by checks/invariants.sh.

## From the sent-copy review (2026-10-03)

- [x] A `submit` asks for its copy (`copy`), and its performer files it once sent: natively where the provider files sent mail itself, otherwise by replacing the intent with an `add` into `copy` in one transaction (§15.5, Annex B.2, `mail.submit.copy`; GUIDE §13; invariant "replace:"). Supersedes the client adding to Sent beside the send, which could file a copy of a message never sent.
- [x] An intent is checked whenever its account has declared anything, not only when its anchor collection is synced by a declared source (io-pimdir).

## From the end-to-end run (e2e.md)

- [x] An owner predating §15.6 ignores `copy`: a producer asks for it only of a declared performer, else files the copy itself (Annex B.2; himalaya tests "a_send_asking_for_a_copy_*").

## On landing

- [x] Review the three open questions of the proposal: decided (proposal.md, Decisions); a pending `set-performer` read over the recorded one (§15.6, GUIDE §13, io-pimdir test "an_intent_needs_the_user_to_choose_among_several_performers").
- [x] Bump `draft-02` to `draft-03` in the three Status lines, the README and AGENTS.md §2; the tag is the user's.
- [x] Log entry cairn/log/2026-10-03-capabilities.md naming the rules and their checks; status `landed`. It records the one-way target edge of decision 1.

## Left to io-pimdir

Tracked in io-pimdir cairn/changes/capabilities.

- [x] Re-vendor migrations/ and queries/ so tests/spec_drift.rs stays green; reconcile `capabilities` and `performers` on open (§6).
- [x] A typed registry (`PimdirCapability`), the declaration on the owner handle, the producer gate returning a refusal naming capability, source and detail.
- [x] `set-performer` applied by the drain; the park for an undeclared capability or performer.

## Left to neverest

Tracked in neverest cairn/changes/sources-declare-their-capabilities: every mail, contacts and calendar source declared, Google Calendar honouring `SCHEDULE-AGENT`; collection rows, intents and online meetings open there.

- [ ] Declare each source from its backend and its configured rights, at every run before the drain; collection rows from the remote's access rights (Google `accessRole`, Graph `canEdit`, DAV `current-user-privilege-set`, IMAP `MYRIGHTS`).
- [ ] Gmail: expose All Mail as the archive collection, so archiving a message with no other label does not retain it (desk check, finding 3).
- [ ] Google Calendar: pass `sendUpdates` on insert, update and delete (desk check, §6).
- [ ] Carry the performer in `submit`; perform `calendar.reply`, `calendar.cancel` where the backend can; honour `SCHEDULE-AGENT` and `X-PIMDIR-ONLINE-MEETING` on push.

## Left to himalaya, cardamum, calendula

- [x] Gate every pimdir write on the declaration, with a stable error naming capability, source and detail: io-pimdir's `enqueue`, so himalaya, cardamum and calendula all refuse; calendula names the `SCHEDULE-AGENT=NONE` remedy.
- [ ] calendula: `event reply` and `event cancel` as plain intents, the performer resolved at the event's calendar.
- [ ] Resolve the performer of `submit` (himalaya) and the calendar intents (calendula); report ambiguity with the candidates; a command recording the choice.
- [ ] MOA: show the `detail` of a `partial` support before the write (Google scheduling first), and mark the attendees `SCHEDULE-AGENT=NONE` when the user accepts that nobody is notified.
- [x] himalaya, cardamum, calendula: show the `detail` of a `partial` support when a write passes with one (`PimdirProducer::check`), e2e.md finding 2.
