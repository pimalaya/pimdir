---
cairn: log
change: the-schema-text-stays-the-tags
date: 2026-10-31
---

# The schema text stays the tags'

Corrects 2026-10-31-the-documents-follow-draft-07: migrations/storage/0001_init.sql's leading comment is back to storage-draft-07's bytes, `DROP COLUMN` mention included. An implementation vendors the canonical text byte for byte and checks it out at the tag it claims (io-pimdir's CI at storage-draft-07), so an edit to it after the tag, a comment included, fails that check until the next draft. STORAGE §4.1's prose keeps the correction; the comment follows at the next storage draft.

Guarded by io-pimdir's tests/spec_drift.rs against the tag; `nix flake check` green.
