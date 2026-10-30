---
cairn: log
change: gtd-leaves-the-standard
date: 2026-10-30
---

# GTD leaves the standard

The task conventions unfog and the Android app share are a Pimalaya convention built on the parts, not a commitment of pimdir: no part requires them, and a client that never reads them loses nothing. They moved out of the standard's documents into conventions/, still versioned apart as `gtd-draft-01`. No rule moved.

- **GTD.md** is now conventions/gtd.md, its writer vectors vectors/gtd/ are now conventions/gtd/ (writers.json, fixtures/), and their JSON Schema vectors/schema/gtd-writers.schema.json is conventions/gtd/writers.schema.json. Its header says it is no part of the standard.
- **OVERVIEW** no longer describes the GTD views or time entries: a task's organisation is its standard properties, read into summary columns any search view can ask for.
- **STORAGE §14.1, §14.3, §16**, **GUIDE** (contents note, §16), **vectors/README.md** and the search fixture notes (store.json items 17 to 21, the four task view cases of queries.json) no longer name GTD.md; the local calendar collection, the `U+0001` id rule, `list_replied`, the task summary columns and the search cases stay, being generic.
- **README**, **AGENTS.md**, checks/names.sh, checks/vectors.py (the view table read from conventions/gtd.md, the writers and their schema read from conventions/gtd/) and flake.nix follow.

Guarded by checks/vectors.py, which reads the view table and the writer cases from their new place and fails if either is missing. unfog (src/shared/task/vectors.rs) and the Android app (rust/src/calendar/vectors.rs) read the writer vectors from ../pimdir/conventions/gtd by default.
