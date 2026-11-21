---
cairn: log
change: the-query-reserves-its-later-forms
landed: 2026-11-21
---

# The query reserves its later forms

search-draft-16, still untagged, edited in place: no number moves. From cairn/changes/the-query-reserves-its-later-forms and the owner's decisions of 2026-11-21 (cairn/changes/compared-with-notmuch, The plan): stemming, regular expressions and subqueries come later as their own operators, so the spellings they will take are refused now and each arrives as a minor version.

- **SEARCH §5, §8.5: a word is exact.** A text term matches its folded tokens, never a stem, in this version and every later one.
- **SEARCH §8.3, §8.4: `reserved-form`.** A text or a value beginning with `~`, a text or a value of two characters or more beginning with `/`, and a value beginning with `{` are refused, the span the text or the value. A term is checked for its count, its field, an empty value, then the form, then the wildcard and the value, so an unknown field stays `unknown-field` once a form has a meaning. A phrase is never a reserved form; a `~`, `/` or `{` elsewhere, a lone `/` and a free text `{x}` stay text. The proposal reserved only a word both beginning and ending with `/`; the owner chose, on 2026-11-21, a word beginning with one, since `subject:/foo bar/` lexes as `subject:/foo` and `bar/` and would otherwise answer as words today, leaving a later regular expression no room for a space unquoted. Loosening a refusal is a minor version, tightening one is not.
- **SEARCH §6, §8.2: the extraction status is open.** `object.status` is an open vocabulary (STORAGE §13); a status the reader does not know is read as `unparseable`, counted so in coverage and matched by no `is:` value, so a later `decrypted` is a minor version. queries/search/coverage.sql counts `status <> 'encrypted'` among the bodies not read whole as unparseable.

Rules and their checks: the reserved forms by 22 new cases of vectors/search/queries.json (refusals per form in text and value, behind a negation, before a wildcard, after an unknown field, one holding a space, a closed and an open field; phrases per form, `stand~up`, `stand/up`, `{reunion}` and a lone `/` answering as text) and checks/vectors.py's re-derivation (`check_reserved`), which fails three of them with the rule removed; `subject:{weekly}`, the FTS5 brace case, became `subject:weekly{sync}`; vectors/schema/search-queries.schema.json lists the code. The open status by a scenario of checks/invariants.sh (a body recorded `decrypted` counted unparseable), which fails on the previous coverage.sql. GUIDE §15 step 2 names the refusal.

io-pimdir follows (parser, `PimdirQueryErrorCode::ReservedForm`, coverage), and checks/io-pimdir.rev moves with its commit.
