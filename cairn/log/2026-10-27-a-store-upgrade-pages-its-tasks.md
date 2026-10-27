---
cairn: log
change: a-store-upgrade-pages-its-tasks
date: 2026-10-27
---

# A store upgrade pages its tasks

tasks-carry-their-organisation (2026-10-27) added four `task_summary` columns and asked an upgraded store to re-derive them from the held task bodies, but named no statement to page those bodies: only `list_held_mail` existed, so an owner (io-pimdir, the first to follow) would have written its own SQL.

- **STORAGE §6**: the backfill of a rebuild now names the task columns: `priority`, `categories`, `parent` and `mid` re-derived from every held task body (Annex A.4), then the four task rules over every item of their end (§14.2). New statement `list_held_tasks`, the task rows holding a body, live or not, keyset-paged on (collection, link_id) as `list_held_mail` is. Guarded by a scenario in checks/invariants.sh: a task with a body listed, a task without one and an event holding one left out, the page after it empty.
- **GUIDE.md** §3 of the store procedure and §14 name `list_held_tasks`.

Draft number unchanged (draft-04, untagged). checks/invariants.sh and names.sh pass.
