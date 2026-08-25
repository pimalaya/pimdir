---
cairn: log
change: cross-implementation-vectors
date: 2026-08-25
---

# The format's values are checkable, and authoring them found the gaps that made them uncheckable

vectors/ exists, SPEC.md §16 makes it part of the format, and §5 now says what an object name actually is. The second half of that sentence is the real content of this change: the vectors could not be authored from the spec, because the spec did not fix enough to author them from.

## What was missing before a single value could be written

The change was proposed because io-pimdir and the Android app named the same body two different ways. Reading §5 to author the expected names, the reason is plain: **§5 did not say what an object name is**. It said "lowercase base32 (RFC 4648, no padding)" over a hash under `store_meta.hash_algo`, and no more. It did not say

- how wide `blake3` is (BLAKE3 has a variable output length, and only its *default* is 32 bytes),
- what the `128` in `sha256-128` truncates, or from which end,
- which RFC 4648 alphabet, though the RFC defines two and §7's base32hex produces a string of the same length from the same bytes with none of the same characters,
- whether the shard prefix comes off the encoded name or off the digest's hex.

Four independent ways for two correct readers to disagree, in one sentence. §5 now states all four, and states why they are normative rather than incidental: a store whose writers name bodies differently reports nothing at all, it just stops deduplicating and stops finding the other's blobs.

## Annex A had the same problem, four more times

Writing meta.json turned up the same shape in the per-kind conventions. Each of these was a place where two people implementing the annex faithfully would produce different stores, and each is now pinned:

- **"the earlier offset"** for an ambiguous zoned time (§A.3) does not say earlier *what*. The intended reading is the offset in effect before the transition, which for `America/New_York` is EDT at `-04:00`: the earlier *instant*, and the numerically *greater* offset. Read as "the smaller number" it gives EST and an answer an hour late. The annex now says which, and the vector carries both candidates so the wrong one fails loudly.
- **`meta.date`** was "RFC 3339", which permits any offset. Two writers either side of a sender would record the same message differently. It is UTC now, like the `sort_key` and for the same reason.
- **`from` and `to`** were "first sender address" and "first recipient address", which does not say whether the display name comes too. Bare `addr-spec` now.
- **"casefolded"** for a card's `sort_key` named no mapping. It is the Unicode simple lowercase mapping, locale-independent, and the annex now says so explicitly enough to exclude the Turkish dotless-i tailoring that a default locale applies.
- **`recurring`** was optional, and "absent means unknown" made `false` look redundant. A reader planning an expansion needs to tell "no rule" from "not examined", so a writer that parsed the body writes the boolean either way.

## The proposal's own reasoning, corrected

The proposal asked for "the RFC 4648 boundary lengths (1 to 5 bytes, so the leftover-bit padding is exercised)" on the *bodies*. Body length does not exercise base32 padding at all: base32 is applied to the digest, which is a fixed 32 or 16 bytes whatever the body was. Those widths happen to leave 4 and 2 leftover bits respectively, so every vector exercises partial-group encoding whether or not the bodies are short.

The right layer got the treatment instead. objects.json carries RFC 4648 §10's own seven vectors as `base32.cases`, which is what actually pins the alphabet and the leftover-bit handling, and a consumer checks its encoder against those before trusting a single name. The short bodies stayed, for the reason they are genuinely worth having: they catch a hasher mishandling a partial block, which is a different bug.

## What is in the files

**objects.json**: 13 bodies, each with its `blake3` and `sha256-128` name and shard path, plus the seven RFC encoding vectors. The bodies cover the empty body, one byte and that byte a NUL, lengths 2 to 5, bytes above `0x7f` that a writer treating a body as UTF-8 would mangle, the SHA-256 block boundary at 64, and 1023/1024/1025 around the BLAKE3 chunk boundary where a streaming hasher most often breaks.

**meta.json** and **fixtures/**: 17 cases over the three kinds. Every case Annex A hedges is there, including both daylight-saving transitions with the offsets verified against the tzdb, a `VTODO` carrying both `DUE` and `DTSTART` to pin which one decides the key, a card whose `FN` needs case and space normalisation to pin that `meta.fn` stays verbatim while only the key is normalised, and a message whose `Date` is unparseable.

The fixtures are CRLF throughout, as their RFCs require, and each case carries its fixture's object name. A harness reading them in text mode changes the body and fails on the name, which is where that mistake should surface rather than three assertions later.

## How the values were authored

From the algorithms and the prose, never from an implementation, which is what lets an implementation genuinely disagree with the file rather than agree with itself. The base32 encoder was written from RFC 4648 §6 rather than taken from a library and checked against the RFC's §10 vectors. The digests are anchored on published values, and the long bodies reuse the BLAKE3 project's own test-vector input convention (byte `i` is `i mod 251`) so the 0, 1023, 1024 and 1025 byte rows can be checked straight against its published vectors. Everything was then reproduced through coreutils `sha256sum` and `base32`, and every UTC normalisation through coreutils `date`, before being written down.

## Deliberately not pinned

Two things, both recorded in vectors/README.md so they are decisions rather than omissions. The `link_id` of content carrying no usable `UID` is writer-derived and the format says nothing about it, so that case carries `null` and a consumer checks only that an id was derived. And non-ASCII case folding: the annex now names the mapping, but the vector stays ASCII, because a vector neither runtime has been checked against is a failing test rather than a specification.

## Not landed here

io-pimdir's `tests/vectors.rs`, and the Android app's vendored copy with its digest re-check in CI. Both are their own repositories' entries to write.
