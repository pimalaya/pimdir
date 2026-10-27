---
cairn: log
change: search-field-cases
date: 2026-10-27
---

# Every text field has a case

An end-to-end run of io-pimdir answered `location:ada` with a raw SQLite error while `count` worked: no case used `location:`, `attachment:` or `mimetype:`, so the compiler's column mapping for them was never exercised.

- **vectors/search**: six cases over existing fixtures, each field alone and with another predicate: `location:room` and `location:room date:2026-11-06` (home 6, the series' `LOCATION`), `attachment:invoice` (home 13, its part's file name) and `attachment:invoice is:unread` (none, the message is seen), `mimetype:application/pdf` (home 13) and `mimetype:pdf date:2026-10` (home 13). The stand-in file home 14 has no `attachment` field, its summary holding none (SEARCH §6), so neither field reaches it.
- **Every other field**: thirteen cases more, one per field no answered case used: `summary:moved` (home 15), `title:roadmap` (home 11, 12), `body:report` (home 1, work 1), `to:carol@example.org` (home 1, work 1), `cc:carol@example.org` (home 2), `bcc:grace@example.org` (home 11), `email:jane@example.org` (home 4), `organizer:erin` (home 15), `attendee:frank@example.com` (home 15), `flag:\Flagged` (home 3), `folder:home/Calendar` (home 6, 7, 15), `id:reply-1@example.org` (home 11), `when:2026-09-03` (home 15). Fixtures extended minimally: event-override-only.ics gains an `ORGANIZER` (Erin, erin@example.com) and an `ATTENDEE` (Frank, frank@example.com), mail-reply.eml a `Bcc` (grace@example.org); no earlier case moves.
- **checks/vectors.py** reads the field names from SEARCH.md §8's table, fails when the grammar's fields are not the table's, and fails when a field is used by no hits or threads case, so a field added to the table without a case fails the check; the flake runs it over the documents with the vectors. Removing the `when:` case, or adding a field to the table, fails it.

No rule of the format changed: the cases pin SEARCH §6 and §8 as written. checks/vectors.py parses each query and resolves each hit; an implementation runs them. checks/schema.sh, names.sh, invariants.sh and vectors.py pass.
