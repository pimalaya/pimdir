---
cairn: log
change: zulu-designator
date: 2026-09-03
---

# Every instant the format fixes ends in `Z`

§13 forbade a local offset in a sort key and showed `Z`, but `+00:00` is also RFC 3339 UTC and sorts apart from it, and neverest hit exactly that between its two mail derivations: `chrono` wrote `+00:00` where `mail_parser` wrote `Z`, the `alt:` key embedded the date, and a message with no `Message-ID` linked one way at `Meta` and another at `Full`.

§13 now makes the designator normative for every instant the store fixes: `created_at`, `retained_at`, a sort key, a summary's `date`. Annex A.0 restates it for the derivations.
