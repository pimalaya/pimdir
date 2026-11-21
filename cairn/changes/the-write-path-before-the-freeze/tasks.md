---
cairn: tasks
change: the-write-path-before-the-freeze
---

- [ ] Prototype 1 (a page of bodies flushes together) in io-pimdir, measure fsync count, bytes written and wall per tier against today
- [ ] Prototype 2 (objects keyed by an integer) on a scratch schema, measure bytes written per message and the import CPU
- [ ] Prototype 3 (addresses interned), measure; drop it if it does not pay
- [x] Count the transactions a sync page takes today; find what forces more than one (io-pimdir WRITE_CHUNK, raised to 4,096, prototypes-2026-11-21.md)
- [ ] Owner decision per item, with the numbers
- [ ] Fold the kept items: STORAGE §5 and §4, migrations/storage, queries/, GUIDE, vectors, checks/invariants.sh crash and GC scenarios, signatures and manifest restated; log entry
