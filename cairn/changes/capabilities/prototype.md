# Prototype, 2026-10-03

`move` and `submit` end to end, uncommitted, over the spec as amended by the desk check: io-pimdir (tables, statements, the gate inside `enqueue`, `declare`, `set-performer`, the drain's backstop, the tables created on open in a 0.5 store), neverest (a declaration per mail source from its backend and rights, before any credential is read; a `submit` sent only by the source it names), himalaya (the performer written into `submit`, `himalaya pimdir performer`). neverest and himalaya build against the local io-pimdir through `[patch.crates-io]`.

Run against the local Stalwart test containers (`neverest-relay-a`, IMAP :143, SMTP :2525; `neverest-relay-b`, IMAP :144), restored afterwards.

## Scenarios

| # | Scenario | Result |
| --- | --- | --- |
| 1 | `message move` on an IMAP source | passes the gate, queued, pushed by the next sync (but see finding 2) |
| 2 | `message move` on a source that cannot move (`item.delete = false`), and a Graph source declared with no network | refused at once, nothing queued: `Source imap does not support mail.message.move: item.create or item.delete is disabled`, the same in `--json`; the Graph source's ten rows written from its configuration alone, its token command failing afterwards |
| 3 | `message send` with two sending sources | refused with both candidates and the command to choose; `himalaya pimdir performer mail.submit imap` queued the choice, the next sync applied it, the next send named `imap` without asking, neverest sent it over SMTP and acknowledged the row, the message came back through IMAP |
| 4 | a `move` written straight into the queue, as a producer predating capabilities would | parked by the drain, reported by the sync: `parked queue action #1 (move in imap/INBOX from old-himalaya): Source imap does not support mail.message.move: …` |

io-pimdir: the five scenarios as tests (tests/capabilities.rs) and five unit tests of the gate; the existing suites (269 unit, every integration test), neverest's 170 and its build pass unchanged.

## Findings

1. **A declared source that has not synced yet is no candidate.** `list_capability_sources` finds an account's sources through the collections they sync, so a Graph source configured beside an IMAP one, declared but not synced yet, cannot send: the first sends go through the IMAP source with no ambiguity reported, and the choice only appears once Graph has synced a collection. A declaration should place its source in an account by itself. **Amend**: `capabilities` rows carry the source's `account`, which the owner knows when it declares, and the candidates read it rather than the collections.

2. **A move over IMAP is delivered twice, before any of this.** Reproduced with the released neverest 0.3.0 and himalaya 2.2.1 on a fresh store: one `message move` and one sync leave the message twice in the target. The remove relocates it with IMAP MOVE and the create uploads it too, the target having been enumerated before the relocation, so no probe holds the create back (SYNC §5, "Creates wait for the probes"). Not a capability matter, but MOA archives by moving, so every archived message would be duplicated. Filed in neverest as `a-move-is-delivered-once`.

3. **Sending and saving stayed apart, as reviewed.** The sends were delivered and nothing was filed in Sent, `message.send.save-copy` being unset.
