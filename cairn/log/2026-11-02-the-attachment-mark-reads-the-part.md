---
cairn: log
change: the-attachment-mark-reads-the-part
date: 2026-11-02
---

# The attachment mark reads the part

The mark counted only a part carrying `Content-Disposition: attachment`, so a shop's order sent as one bare `application/pdf` part, or a `message/rfc822` forwarded without a disposition, read as a message with no attachment and stood for no file (pimalaya/himalaya#802, where IMAP, Maildir and `attachment list` each answered differently). The user decided on 2026-11-01 the rule below and to fold it into storage-draft-08 without a number bump, as the two folds before it: the part is untagged, no schema moves, and checks/tags.sh reads it as "no tag yet". A store of storage-draft-08 written before keeps the marks and stand-ins it recorded, a stand-in being recorded once and never recomputed (§14.3).

Rules, and the check guarding each:

- **The attachment mark** (STORAGE Annex A.1, normative). A part the walk reads makes it when it is disposed as an attachment, its `Content-Disposition` type any but `inline` (an unknown type read as `attachment`, RFC 2183 §2.8), or when it states no disposition and is sent bare as a file: neither `multipart/*` nor `text/*`, and named by no `Content-ID`, which marks a resource a body shows (RFC 2392). The message's own entity when it is a multipart, every child of a `multipart/encrypted` and every child but the first of a `multipart/signed` never make it: the last two are RFC 1847's control data and signature. The media type defaults to `text/plain` when absent, under a `multipart/digest` too, so a digest's messages make no mark. The rule the issue first proposed, any bare part neither text nor multipart, was refused: it marks every PGP/MIME message (vectors/fixtures/mail-encrypted.eml's control part) and every HTML newsletter whose images sit in `multipart/related`. Guarded by three vectors/summaries.json cases: "mail, parts sent bare" (vectors/fixtures/mail-bare-parts.eml: a bare PDF, a bare `message/rfc822` of 45 octets and an `X-Unknown` disposition stood for; a `Content-ID` image, a bare `text/csv` and a disposed `multipart/signed` signature not), "mail, a message that is a file" (vectors/fixtures/mail-bare-file.eml, section 1) and "mail, an encrypted message". checks/vectors.py's walk reads the rule; HEAD's walk fails the first two, and the walk without the RFC 1847 exclusion fails the first and the third.
- **The stand-ins follow the mark** (STORAGE §14.3, normative): a part is stood for exactly when it makes it, so the three cases' `attachments` pin which parts a file stands for, and SEARCH's `attachment` field, the stand-ins' names and media types (SEARCH §6), follows without an edit.
- **A message/rfc822 stand-in's size** is its body's octets as written, such a body taking no transfer encoding (RFC 2046 §5.2.1). checks/vectors.py sizes it by serializing the stdlib's parsed message unfolded with CRLF, which gives back the fixture's octets, the stdlib keeping none.
- **GUIDE §14** (informative) states the mark where it walks the parts for stand-ins. checks/names.sh lists `inline` among the protocol words. vectors/manifest.json restated: 59 summaries over 56 fixtures.

`nix flake check path:$PWD` passes (floor, invariants, schema, names, vectors, references) and checks/tags.sh passes, every part's version untagged.
