# pimdir test vectors

Normative test data for the pimdir format (SPEC.md §16), part of it alongside migrations/ and queries/. They exist because the values a store fixes are the ones nothing checks: a schema mismatch fails a query, while two writers naming the same body differently produce no error at all, silently never deduplicating and silently never finding the blob the other wrote.

## Files

- **objects.json**: bodies to object names under both `hash_algo` values, with the shard path §5 derives from each. An implementation **MUST** pass this: object naming is where a disagreement costs data rather than presentation.
- **meta.json** and **fixtures/**: bodies to the `link_id`, `meta` and `sort_key` Annex A's conventions produce, including every case that annex has to hedge. An implementation **SHOULD** pass the cases for each `kind` it writes; Annex A is informative, so these bind an implementation to the conventions it claims to implement.

Three of meta.json's cases pin the **minted** `link_id` (SPEC.md §9): a hint the collection already holds under another handle is filed under `dup:`, the hint, `#` and the handle, concatenated verbatim in that order. Each reuses the fixture of the case above it, since minting depends on the hint and the handle and never on the body, and each carries the `hint` and `handle` its key was built from, so a consumer rebuilds the key rather than pattern-matching the string. The kind fallbacks (`alt:` for a message with no usable `Message-ID`, `hash:` for a DAV resource stating no `UID`) are untouched by them, `event-no-uid.ics` still pinning that an id was derived rather than what it equals: minting is a third trigger, not a replacement for either.

## How the expected values were derived

From the algorithm and prose specifications, never by running an implementation. That is the whole point: values taken out of one implementation would record what it does rather than what the format says, and nothing could then meaningfully disagree with it.

- The base32 encoder was written from RFC 4648 §6 rather than taken from a library, and checked against the RFC's own §10 vectors, which appear under `base32.cases` so a consumer can check its encoder before trusting anything below.
- The digests are anchored on published values: SHA-256 of the empty string and of `abc` are NIST's, and BLAKE3's empty digest is the one its specification publishes. The long bodies reuse the BLAKE3 project's test-vector input convention (byte `i` is `i mod 251`), so the 0, 1023, 1024 and 1025 byte cases can be checked against that project's own `test_vectors.json`.
- Every value was then reproduced through a second, independent path, which is what checks/vectors.py re-runs on every push: `hashlib`, `blake3` and `base64`, never a pimdir implementation. Every UTC normalisation in meta.json was reproduced against the tzdb with coreutils `date`, both daylight-saving transitions included.

## Rules for a consumer

- **Compare parsed structures, never JSON text.** Key order is not fixed here, and pinning one would pin an accident of whichever serialiser wrote the file.
- **Read the fixtures as bytes.** They are CRLF throughout, as RFC 5322 and RFC 5545 require, so a harness that opens them in text mode changes the body and therefore the object name. This repository pins them with a `-text` gitattribute, and a consumer that vendors them owes itself the same. Each case carries its fixture's `blake3` and `sha256-128` name for exactly this reason: check them first, and a mangled read fails there rather than somewhere confusing later.
- **Vendoring is allowed, unchecked vendoring is not** (§16). An implementation that cannot read this directory from its own build may copy it, provided it records the digests and re-checks them against this repository in CI. A frozen copy that keeps passing while the format moves is worse than no copy.

## What is deliberately not pinned

- **The `link_id` of content with no usable `UID`.** `event-no-uid.ics` carries `"link_id": null`: the format requires a writer to derive an id rather than refuse the item, and says nothing about what that id is. Check that one was derived, never that it equals a value.
- **Non-ASCII case folding.** `card-casefold.vcf` is ASCII on purpose. Annex A names the mapping (Unicode simple lowercase, locale-independent), but a non-ASCII vector would pin behaviour the two runtimes have not been checked against each other on, and a vector nobody has agreed to is a failing test rather than a specification.
