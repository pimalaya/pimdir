---
cairn: change
id: embedding-index
status: draft
created: 2026-10-27
---

# An embedding index beside the search index

## Why

SEARCH.md gives the store a relational, notmuch-shaped index: exact terms, fields, tags, dates, threads. An agent also asks questions no term matches ("the mail where the landlord talked about the boiler"). Semantic search answers those, and the two are complementary: hybrid search ranks better than either alone.

The need is already written down outside this repository: moa docs/plan/server.md §5.2 (2026-10-16) plans bodies extracted to text, chunks, a full-text index, vector storage and hybrid search over REST and MCP, embeddings from a configured OpenAI-compatible `/v1/embeddings` endpoint, and states that the 2027 NLnet search work "should end up being this same index". If every consumer builds its own vector store, two clients reading the same store answer the same question differently, the divergence SEARCH.md was written to prevent, one level up.

Deferred: this comes after the search index (search-milestones M1), which it builds on. Nothing here blocks the 2027 NLnet plan, Task 2 "pimdir Notmuch".

## What

A normative part (EMBEDDINGS.md, or a section of SEARCH.md), with the same discipline as the search index: derived, rebuildable, never migrated.

- **The file**: embeddings.db beside index.db, its own `user_version`. It is large (1M chunks at 768 dimensions in float32 is about 3 GB) and rebuilt on its own schedule, so it never weighs on index.db.
- **Chunks**: shared with the search index. Extraction (SEARCH §6) records chunk boundaries per object hash; the embedding index embeds those chunks and keys them on `(hash, chunk)`, so a body filed in three collections is embedded once. Bodiless placements have no chunk today (see open questions).
- **The model is part of the index**: model id, dimension, normalisation and chunking parameters recorded in the index's meta. Any mismatch is a rebuild, as a tokenizer mismatch is for index.db. Without this, two clients with different models corrupt each other's index silently.
- **Storage**: vectors as plain BLOBs in a table any SQLite reads. Approximate nearest neighbours and quantisation (int8, binary) are an implementation's choice, not the format. sqlite-vec is pre-1.0 and a loadable extension, which collides with bundled SQLite on Android and mingw.
- **The refresh**: from the change feed, as the search index; deletions and purges remove vectors. Chunks not yet embedded are counted in coverage.
- **The query**: nearest chunks to a query vector, folded to hits as `(account, seq)` with placements, so a hit is addressable exactly as a search hit is. Hybrid search fuses the full-text and vector rankings by reciprocal rank fusion with a `k` the spec fixes. Coverage gains a semantic axis: whether the vector leg ran, and how much of the scope is embedded.
- **No network in the library**: io-pimdir hands out the chunks to embed and accepts vectors; the CLI or the host (MOA) calls the endpoint. The library holds no credentials, as it holds none for servers.
- **Privacy**: opt-in, off by default, a local endpoint as the advice. Encrypted items are never embedded. Sending bodies to a remote endpoint is the deployer's choice and the spec says so.
- **Conformance**: semantic ranking cannot be tested across models, so its cases under vectors/embeddings/ are deterministic instead: a fixture store with precomputed chunk embeddings, a fixed query vector, an expected order for the vector leg and for the fused ranking. What is tested is storage, chunking, distance, fusion and coverage, not the model.
- **MCP**: one search tool with `mode: text | semantic | hybrid`, hybrid by default when embeddings exist, coverage saying whether the semantic leg ran. Two overlapping tools make agents choose badly.

## Not in scope

- Attachment text (PDF, office files): parsing hostile files belongs to a sandboxed extractor outside the library (MOA's moa-files). The spec may define a slot that such an extractor fills.
- Shipping or choosing an embedding model.
- Re-ranking by a model.

## Open questions

- Its own part (EMBEDDINGS.md) or a section of SEARCH.md.
- The distance: cosine on normalised vectors (then dot product), or left to the model's meta.
- Whether the spec fixes chunk size and overlap, or records them as model parameters.
- Its funding: its own task in a later NLnet plan, or a milestone after M1 of Task 2.
- Chunk offsets assume identical extraction: they are UTF-8 bytes into the extracted text, and SEARCH §6 does not pin extraction byte for byte (how text parts are joined, how HTML is reduced). An embedding index shared by clients needs the extractor identified in the index meta, or extraction pinned, or chunk text stored.
- Bodiless placements: `chunk` is keyed on `object`, so a summary has no chunk (SEARCH §6, 2026-10-27). Embedding summaries needs a chunk shape keyed on the placement, or summaries left out of the vector leg.
