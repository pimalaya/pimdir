---
cairn: log
change: three-standards-one-guidance
date: 2026-09-04
---

# Three normative parts, and one place saying how to use them

The previous entry demoted SYNC and the index half of SEARCH to a reference status, binding for io-pimdir and descriptive for everyone else. That overshot: an engine written from the document and the vectors is doable and conforms, and a part that binds nobody is not a standard. All three parts are normative again, by profile for the store and in full for a layer offered.

The guidance moved into README's Using the standard: implement the documents, use io-pimdir's I/O-free core over your own store and transport, or use its std client; readers, producers and query clients are expected to implement, owners, engines and indexes to use the reference, SYNC being where writing from scratch costs the most. The profiles, the checklist and the statement layout stay.
