---
cairn: log
change: collection-create-occurrences-receipts
date: 2026-10-04
---

# Collection creation, occurrence intents and queue receipts

Three gaps a client of the queue met (MOA, through himalaya and neverest): it could not ask for a folder on the server, could not answer or cancel one occurrence of a series, and could not learn the item its `add` created once the owner applied it, so it matched the body against the store by Message-ID.

- **Annex B.2 `collection.create`.** Kind `collection-create`, payload `{ "v": 1, "source": id, "name": text, "parent": collection? }`: the performer creates the collection on its server and it arrives with the next sync, labelled `name`. Anchored on `parent`, else on a collection of the account and the kind the new one takes, so a collection row `none` refuses children there alone. At least once: a collection of that name already under that parent is a success. Annex B's naming rule gains its one domainless capability, declared for every kind. The SQL reads no payload, so io-pimdir's gate and payload tests guard it.
- **Annex B.2 `recurrence_id`.** Optional in `calendar-reply` and `calendar-cancel`: the occurrence's `RECURRENCE-ID` value as the item spells it, parameters aside; absent is the whole series, as before. Read beside the intent as `copy` is beside `submit`, through `calendar.reply.occurrence` and `calendar.cancel.occurrence` from the same performer, so a producer never sends it to an owner that would ignore the field and answer or cancel the whole series. io-pimdir gate tests.
- **§4.3, §13, §14.1, §15.1, §15.2, §15.4, migration 0001: receipts.** Table `receipts` (`id`, `applied_at`, `collection`, `seq`), written by `record_receipt` in the transaction applying a row, `seq` the item an `add` created; read with `load_action` (a pending or parked row) and `load_receipt`; kept at least seven days, then `prune_receipts`. A cancelled row leaves none. Guarded by checks/invariants.sh ("receipt:") and checks/names.sh; io-pimdir drain tests.

Decided: a receipt table over a producer-supplied `link_id` and `seq_by_link`, because the key alone cannot tell an applied row from a cancelled one and a later move retires the key's item there; occurrence capabilities over a version bump of the two payloads, because `v: 1` stays readable by every owner and the gate is what keeps an older one from widening the action. A store from an earlier draft lacks the table; §6 lets an implementation reconcile it on open, as io-pimdir does for `capabilities`.

Normative edits after the `draft-03` tag, so the three Status lines, the README and AGENTS §2 move to `draft-04`; the `draft-04` tag is the user's to make.
