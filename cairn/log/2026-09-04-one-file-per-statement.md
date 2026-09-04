---
cairn: log
change: one-file-per-statement
date: 2026-09-04
---

# One file per statement

The reference statements sat in one file per concern, each statement introduced by a `-- name:` marker, so every consumer carried a parser for the marker and a list of the concern files. They now sit one per file, named after the statement: queries/storage/ holds the store's 99, queries/search/ the index's 31, and an implementation reads them by listing the directory. A statement keeps the comment it had; the concern headers went, STORAGE §4.4, §14 and SEARCH §3 saying what they said. checks/schema.sh prepares each file as it is.
