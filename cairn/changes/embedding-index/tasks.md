---
cairn: tasks
change: embedding-index
---

# Tasks

Deferred until search-milestones M1 has landed. Recorded from the discussion of 2026-10-27.

## pimdir (this repository)

- [ ] Decide the open questions (part or section, distance, chunk parameters, funding)
- [ ] SEARCH §6: chunk boundaries per object hash, shared with this index (can land with M1)
- [ ] The part: embeddings.db, its schema, the model meta and the rebuild rule
- [ ] Refresh from the change feed; deletions and purges; coverage's semantic axis
- [ ] Hybrid fusion: reciprocal rank fusion and its `k`
- [ ] vectors/embeddings: fixture store with precomputed vectors, query vector, expected orders
- [ ] GUIDE and OVERVIEW follow

## Elsewhere

- [ ] io-pimdir: an `embeddings` feature (chunks out, vectors in, no network)
- [ ] CLI: embedding through a configured OpenAI-compatible endpoint, opt-in
- [ ] MCP: the search tool's `mode`
- [ ] MOA: server.md §5.2 points here
