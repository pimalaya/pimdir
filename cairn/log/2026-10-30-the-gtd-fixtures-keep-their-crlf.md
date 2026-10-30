---
cairn: log
change: the-gtd-fixtures-keep-their-crlf
date: 2026-10-30
---

# The GTD fixtures keep their CRLF

A correction to gtd-leaves-the-standard: .gitattributes still exempted vectors/gtd/fixtures/ from end-of-line normalisation, so 45b084d recorded the moved conventions/gtd/fixtures/ with LF and a clone no longer held the bytes the writer cases name. The exemption now names conventions/gtd/fixtures/, and the 24 fixtures are recorded again byte for byte as 79cb5c7 held them.

queries/storage/read/list_replied.sql no longer cites GTD.md in its comment; the statement is unchanged.

Guarded by checks/vectors.py ("a fixture is CRLF throughout"), which fails on the CI checkout without the exemption.
