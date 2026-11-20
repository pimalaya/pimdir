---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator's engine, fourth part: refusals, handle-less adds, hash keys

The fourth part of plan 2's "The scripted remote states", of cairn/changes/the-freeze-plan. No part of the standard moves.

- **Outcomes** (generator/src/engine.rs, generator/src/remote.rs, SYNC §4, §5): a remote answers each change by its key `Accepted`, `Rejected` (left pending, pushed again) or `Refused` with a reason, recorded on the binding pushed for with the change's key and reported; a change carrying the key a refusal standing on its binding names is held, not pushed, and reported every run; an accepted push clears the refusal, and a create landed under its new key takes none along.
- **An add accepted with no handle** (SYNC §4): an IMAP-like remote without UIDPLUS answers an append with no UID; the create is recorded delivered, no `Created` reported and nothing pushed again, and the listing naming its member lands it.
- **A stated `hash:` key** (SYNC §7, sync format 10): the model's drain parks an `add` stating a `hash:` key its body's bytes do not give, and stages one stating its own.
- **Landing a pushed body**: a body the model hands its remote declares the hint its summary reads (a message's `Message-ID`, a resource's `UID`), and a landing keys a member as STORAGE §9 does (`model::key`), escape and fallbacks included.
- **The shared body of a pending create** (G6 of io-pimdir's tests/generated/drain.rs): a create the drain stages, by `add`, `move` or `copy`, holds as its binding's `shared_object` the body the write carries, as an edit's does (SYNC §9).
- **`load_pending_arrivals`**, the read the spec lane added for an overlay's arrivals, is answered by the oracle, which answers every read statement.
- **Histories**: one address book whose remote refuses a create and rejects an edit once, the create edited and pushed under its new key, an add stating another body's `hash:` key beside one stating its own; one mailbox on a server without UIDPLUS.
- **Checks**: tests state each run from SYNC; a test states the shared body of a drained write, failing before the G6 alignment; each step's store is written and self-checked. Broken by hand to see each fail: a refusal not held, a refusal not cleared, a `hash:` key unchecked. `PIMDIR_GENERATOR_TREE` points the crate's tests at a snapshot of the tree while another lane's change is half written.
