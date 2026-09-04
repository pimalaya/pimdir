# pimdir test vectors

Test data for the pimdir standard (STORAGE.md §16, SYNC.md §11, SEARCH.md §11), part of it alongside migrations/ and queries/. objects.json binds every writer, summaries.json every owner, sync/ every engine, search/ every index and query client. They exist because the values a store fixes are the ones nothing checks: a schema mismatch fails a query, while two writers naming the same body differently produce no error at all, silently never deduplicating and silently never finding the blob the other wrote.

## Files

- **objects.json**: bodies to object names under both `hash_algo` values, with the shard path §5 derives from each. An implementation **MUST** pass this: object naming is where a disagreement costs data rather than presentation.
- **summaries.json** and **fixtures/**: bodies to the `link_id`, the summary row, the address rows and the `sort_key` Annex A produces, every case that annex has to hedge included, and the encodings that split earlier writers (an RFC 2047 header, an escaped vCard value, a quoted parameter). An implementation **MUST** pass the cases for each `kind` it writes.
- **sync/**: one case per file, a store, a run, a remote and what is expected after (SYNC.md §11). Bodies are named by label and resolved to fixtures, so a case reads, and every expected push carries the idempotency key SYNC.md §4 derives, which checks/vectors.py re-derives. An engine conforms by reproducing them.
- **search/**: the fixture store and the queries every conforming index answers alike (SEARCH.md §11), hits keyed `(account, seq)`.

One case, event-no-uid.ics, pins the **`hash:`** key Annex A.2 derives for content with no usable `UID`, the FNV-1a 64 digest of the bytes, and checks/vectors.py re-derives it. Three of summaries.json's cases pin the **minted** `link_id` (STORAGE.md §9): a hint the collection already holds under another handle is filed under `dup:`, the hint, `#` and the handle, concatenated verbatim in that order. Each reuses the fixture of the case above it, since minting depends on the hint and the handle and never on the body, and each carries the `hint` and `handle` its key was built from, so a consumer rebuilds the key rather than pattern-matching the string.

## How the expected values were derived

From the algorithm and prose specifications, never by running an implementation. Values taken out of one implementation would record what it does rather than what the format says, and nothing could then meaningfully disagree with it.

- The base32 encoder was written from RFC 4648 §6 rather than taken from a library, and checked against the RFC's own §10 vectors, which appear under `base32.cases` so a consumer can check its encoder before trusting anything below.
- The digests are anchored on published values: SHA-256 of the empty string and of `abc` are NIST's, and BLAKE3's empty digest is the one its specification publishes. The long bodies reuse the BLAKE3 project's test-vector input convention (byte `i` is `i mod 251`), so the 0, 1023, 1024 and 1025 byte cases can be checked against that project's own `test_vectors.json`.
- Every value was then reproduced through a second, independent path, which is what checks/vectors.py re-runs on every push: `hashlib`, `blake3` and `base64`, never a pimdir implementation. Every UTC normalisation in summaries.json was reproduced against the tzdb with coreutils `date`, both daylight-saving transitions included.
- The sync and search cases were written from SYNC.md and SEARCH.md by hand. checks/vectors.py checks their shape and that every fixture, object label and placement they name resolves; running one takes an implementation, and the reference implementation's suite is where they run.

## Rules for a consumer

- **Compare parsed structures, never JSON text.** Key order is not fixed here, and pinning one would pin an accident of whichever serialiser wrote the file.
- **Read the fixtures as bytes.** They are CRLF throughout, as RFC 5322, RFC 6350 and RFC 5545 require, so a harness that opens them in text mode changes the body and therefore the object name. This repository pins them with a `-text` gitattribute, and a consumer that vendors them owes itself the same. Each case carries its fixture's `blake3` and `sha256-128` name for exactly this reason: check them first, and a mangled read fails there rather than somewhere confusing later.
- **Vendoring is allowed, unchecked vendoring is not** (§16). An implementation that cannot read this directory from its own build may copy it, provided it records the digests and re-checks them against this repository in CI. A frozen copy that keeps passing while the format moves is worse than no copy.

## What is deliberately not pinned

- **Non-ASCII case folding of a sort key.** card-casefold.vcf is ASCII on purpose. Annex A names the mapping (Unicode simple lowercase, locale-independent), but a non-ASCII vector would pin behaviour the two runtimes have not been checked against each other on. The decoded values of mail-encoded.eml and card-escaped.vcf are pinned, being what split the writers; only the folding of a key is not.
- **`attachment` at the `Meta` tier.** The mail cases pin the `Full` derivation, where the parts were walked; a summary written from an `ENVELOPE` writes `NULL` there and agrees on every other column.
