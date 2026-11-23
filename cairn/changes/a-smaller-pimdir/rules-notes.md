**Points to settle in the morning**
1. **Unwritten rules are outside this ledger.** The preamble makes a sentence without a key word bind as MUST, and most sentences naming the dropped structures have none: the §4.3 entries for the flag, summary and list tables, §4.4 "A flag set is written in two parts" and "Lists as rows", and the §13 `flag` and `item_address.role` entries. One of them must survive: §4.4 "A statement names its columns" (no `*` read, no positional insert). §4.2 and §6 rely on it, and checks/schema.sh already enforces it. If "no requirement leaves without a line" covers these too, a second pass is still owed.
2. **Five SEARCH §2–§3 sentences are kept although design §6 removes those sections.** They are what two implementations need to share one store directory:
   - index.db is a SQLite file at the path STORAGE §3 reserves;
   - `index_meta` names its format, version and shape;
   - an indexer leaves an index that is not its own untouched;
   - a query client refuses an index it does not implement;
   - the index.lock rule.

   I propose a short paragraph on the index file in SEARCH §1. The hit-set guarantee and its HTML/charset exceptions are kept too, moving to §12 and §6.
3. **One rule has two levels.** §9.2 says, with no key word (so MUST), that an owner records a collection's bare name; §14 says SHOULD. The rewrite should state it once, at one level.
4. **The reader overlay is stated twice:** §14.1 "MAY overlay pending actions" and §15.4 "A reader MAY overlay …". I kept both and flagged it.
5. **Your counts are off.**
   - STORAGE.md has 219 key-word uses in 181 sentences, against design §6's 212. The 219 are 114 MUST, 41 MUST NOT, 28 MAY, 26 SHOULD, 1 SHOULD NOT, 5 RECOMMENDED, plus REQUIRED, OPTIONAL, SHALL and SHALL NOT in the boilerplate.
   - SEARCH.md has 59 uses in 44 sentences, against tasks.md's 50.
6. **Borderline calls for you to judge:**
   - **Line 83, moved:** the purge cutoff's text shape, which I read as a parameter detail.
   - **Line 72, moved:** "A substituted statement SHOULD keep both plans".
   - **Lines 211, 213 and 214, kept:** re-expansion and tz/zone changes in §7. They are restated without index_meta or statement names because they decide what answers and coverage state.
   - **Line 186, kept:** its PRAGMA clauses move to io-pimdir.

