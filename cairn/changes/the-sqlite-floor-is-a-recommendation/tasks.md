---
cairn: tasks
change: the-sqlite-floor-is-a-recommendation
---

# Tasks

- [x] Review with the user: the shape rule, `store_meta.shape`, the tables replacing JSON, `temp.param`, the fold before the tokenizer (agreed 2026-10-31; details settled in the log)
- [x] STORAGE §4.1, §6, Annex A: floors RECOMMENDED, the shape rule, `store_meta.shape`, `sqlite_master`; STORAGE.md:479's spelling rule replaced by the flag tables
- [x] migrations/storage: `placement_flag`, `binding_base_flag`, `flags_known`, `base_flags_known`, `mail_in_reply_to`, `task_category` (not `item_category`), `queue.target_collection`, `store_meta.shape`; `temp.param` as `create_param`; the draft-06 move as a §6 step (`backfill_flags_known`, `backfill_base_flags_known`)
- [x] queries/: every `json_each` to its table or to `temp.param`; rename_queue_targets on `target_collection`; `iif` to `CASE`
- [x] SEARCH §2, §5, §8: FTS5 RECOMMENDED, another shape allowed by hit sets, the fold before the tokenizer, relevance the shape's own
- [x] SYNC §4: flag deltas over the tables
- [x] Vectors: model vectors split from the canonical shape's (STORAGE §16, SEARCH §11); the Greek fold case; no fixture needed regenerating
- [x] checks/: schema.sh refuses JSON functions in the canonical text; `nix flake check path:.` green (2026-10-31)
- [x] Status lines: storage-draft-07, search-draft-07, sync-draft-06; log cairn/log/2026-10-31-the-sqlite-floor-is-a-recommendation.md
- [ ] Tags storage-draft-07, search-draft-07, sync-draft-06: the user's
