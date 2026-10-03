# End-to-end run, 2026-10-03

Before the draft-03 bump: the capabilities change exercised through the four tools on fresh local stores, uncommitted builds of io-pimdir, neverest, himalaya, cardamum and calendula (`[patch.crates-io]` on the local io-pimdir), plus the released neverest 0.3.0 and himalaya 2.2.1 for the upgrade path.

Servers: Stalwart `neverest-relay-a` (IMAP :143, SMTP :2525) and Radicale `neverest-dav-tests` (:5232, a fresh `e2e-book` and `e2e-cal`). Accounts: `main` (IMAP with SMTP, CardDAV, CalDAV in one store), `ro` (IMAP and CardDAV with `item.delete = false`, no SMTP), `legacy` (IMAP with SMTP, store created by neverest 0.3.0). Both servers restored afterwards.

## Scenarios

| # | Scenario | Result |
| --- | --- | --- |
| D1 | Declaration at sync, every source of three kinds | pass: `imap` 11 rows, `cards` 5, `cal` 10, `none` and `partial` with their detail |
| D2 | Rights withheld (`ro`) | pass: `mail.message.move`, `.remove`, `contacts.card.remove`, `.move` `none`; no SMTP makes `mail.submit` and `.copy` `none` |
| R1 | `himalaya message move` on `ro` | pass: refused in text and `--json`, nothing queued |
| R2 | `himalaya message delete` on `ro` | pass: refused as the move to trash it is |
| R3 | `himalaya message send` on `ro` | pass: "No source of this account supports mail.submit" |
| R4 | flag change on `ro` | pass: queued and pushed |
| R5 | `cardamum card delete` on `ro` | pass: refused in text and `--json`; `card update` queued and pushed |
| B1 | a `move` written into `ro`'s queue by hand, as a producer predating capabilities | pass: parked by the drain with the capability and the detail |
| P1 | two sending sources (one declared by hand) | pass: refused with both candidates and the command |
| P2 | `himalaya pimdir performer mail.submit imap`, then a send before any sync | pass: the queued choice holds, the send names `imap`; the next sync applies the choice |
| S1 | send with `save-copy` | pass: one `submit` carrying `copy`, no `add`; sent, one copy in Sent Items, filed in the same run |
| S2 | send with `--no-save` | pass: sent, no copy |
| S3 | send to an unknown local recipient (550) | pass: parked as permanent, no copy filed |
| U1 | new himalaya on a store created by neverest 0.3.0 | **fail, fixed**: `copy` went into the `submit`, the old owner ignored it, no copy filed. Fixed in himalaya: `copy` only for a declared performer, else the `add` beside the `submit` as before (STORAGE Annex B.2, himalaya tests). Rerun: pass, the old owner sends and files the copy |
| U2 | the new neverest opens the 0.3.0 store | pass: tables created, 11 rows declared; the next send carries `copy`, one copy filed |
| K1 | `calendula event create` with `X-PIMDIR-ONLINE-MEETING:TRUE` on CalDAV | pass: refused |
| K2 | scheduled event on CalDAV (`partial`) | pass, but the detail is not shown (finding 2) |
| K3 | an update changing an occurrence, `calendar.occurrence.update` forced `none` then `full` | pass: refused, then queued |
| K4 | delete of a scheduled event, scheduling forced `none` | pass: refused with the `SCHEDULE-AGENT=NONE` hint |
| K5 | an update bumping `DTSTAMP` and the master's summary only, occurrence forced `none` | pass: not taken for an occurrence change |

## Findings

1. **An old owner ignores `copy`** (U1): fixed before landing, the rule in Annex B.2.
2. **No CLI shows a `partial` detail.** `enqueue` returns the row id alone; the partials come from `PimdirProducer::check`. §15.6 says the detail SHOULD be shown, and Google's scheduling is the case that matters. Left to himalaya, cardamum, calendula.
3. **neverest ignores a misplaced right.** `sources.imap.item.delete = false` (outside the backend table) is accepted silently, the backend being flattened into the source, so the right never applies. Not a capability matter; filed in neverest.
4. Pre-existing, unrelated: himalaya's confirmations end with no newline, and `flag add` with no id reports success (2.2.1 does both).
