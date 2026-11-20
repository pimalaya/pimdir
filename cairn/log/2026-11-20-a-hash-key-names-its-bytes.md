---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# A hash key names its bytes

A finding of the freeze plan's lead, from reading cardamum and calendula: each derives an `add`'s link id from the body it hands to io-pimdir's `enqueue_with_body`, which then removes the `X-PIMDIR-` properties (STORAGE §18) and stores what remains. A UID-less card or event was so queued under a `hash:` key naming bytes the store never held, and the first read of its member, deriving the key from the bytes it holds, retires the binding (§9, §10): a delete and an add for every other source. STORAGE said an `add` may state its `link_id` and said nothing of what it must be.

## What moved

- **STORAGE §15.3** (normative): a stated `link_id` is a key §9 assigns. One beginning with `hash:` names bytes and MUST be the one the object's own bytes give (Annex A.2, A.3): a producer refuses an `add` stating one another body gives, read from the body it stores before anything is appended, and an owner parks one. A producer stating no key checks the duplicate under the one the owner derives, which it may answer the caller.
- **SYNC §7** (normative): an `Add`'s key is the one STORAGE §9 assigns; one stating a `hash:` key its body's bytes do not give is refused, staging nothing. A queued `add` maps onto it, so the vectors bind the owner's drain too.
- **Vectors**: a mutate run's `Add` states the `link_id` it states where it states one, which moves the sync format to 10, every case restated. Vector 176: an add stating another body's `hash:` key is refused, staging nothing. Vector 177: one stating its own is staged under it.
- checks/vectors.py: an `Add` stating a `hash:` key is expected refused exactly when the key is not the FNV-1a 64 of its body's bytes; with 176's `failed` taken out it fails ("an Add stating hash:0b546173f363e9ee is refused: False is not True"). SYNC §11 and vectors/README.md describe the field.

## Guards

- vectors/sync/176 fails on io-pimdir with its engine check disabled ("an add stating a hash: key another body gives is refused"), 177 passes either way; checks/vectors.py as above.
- io-pimdir tests/capabilities.rs pins the producer's refusal of the consumers' pattern and the owner's park (io-pimdir cairn/log/2026-11-20-a-hash-key-names-its-bytes.md).

## Left

- An `alt:` key (a message stating no `Message-ID`) is a writer-derived key too, read from the decoded subject, date and sender; the rule names `hash:` alone, the case the consumers met. Whether a stated `alt:` key the body does not derive is refused the same way is the owner's to decide.
- cardamum and calendula pass no key and report the one io-pimdir answers.
