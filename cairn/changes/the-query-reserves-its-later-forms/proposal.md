---
cairn: change
id: the-query-reserves-its-later-forms
status: landed
created: 2026-11-21
---

# The query reserves its later forms

## Why

compared-with-notmuch and the owner's decisions of 2026-11-21 plan query forms pimdir will take after v1: stemmed words, regular expressions, subqueries (`thread:{…}`, `from:{…}`, a-query-reads-across-domains), and decrypted bodies. Each must arrive as a minor version, adding answers and changing none. Today's grammar would not allow that: it reads each of those spellings already, as something else (verified on search-draft-15 through `pimdir count`):

- `~meeting` and `meeting~` answer as `meeting`, the `~` a separator (§8.5);
- `/meeting/` and `subject:/notes/` answer as the word between the slashes;
- `thread:{from:carol}` and `from:{kind:contact}` read the braces as part of a value and answer nothing.

Giving them a meaning later would change what a query a client stored or a user typed answers. Refusing them now keeps every later form additive.

## What

- **Plain words stay exact** (owner decision, 2026-11-21): a text term matches the folded token, never a stem, in this version and every later one. Stemming comes, if it does, as its own operator. §5 and §8.5 say so in one sentence each.
- **Three forms refused**, with a new §8.4 code, `reserved-form`, its span the form, whole and before anything else is read of the term, so no later meaning can collide with an answer today:
  - a term or a value beginning with `~` (the stem operator: `~meeting`, `subject:~meeting`);
  - a value or a text both beginning and ending with `/`, two characters or more (a regular expression on a field's raw value, notmuch's syntax: `subject:/^\[PATCH/`); a `/` elsewhere stays a character as today (`a/b`);
  - a field value beginning with `{` (a subquery: `thread:{from:jane}`, `from:{category:family}`).
  A phrase is never a reserved form: `"~meeting"`, `"/a/"` and `"{x}"` stay text, the way to search those characters.
- **The extraction status is an open vocabulary.** `object.status` (`ok`, `unparseable`, `encrypted`) is declared open (STORAGE §13's rule for open vocabularies): an index MAY hold a status a query client does not know, which it counts as `unparseable` in coverage. This keeps a later `decrypted`, and its own coverage count, a minor version (owner: decryption is not planned now but will come, without a breaking change). SEARCH §6 keeps "decrypted content is indexed only when the user asks", and an index that holds plaintext will say so in `index_meta`, a column a later version adds.
- **Vectors**: a refusal case per form and position, a phrase case per form answering as text, and the `/` and `~` cases inside a word (`a/b`, `x~y`) answering as today.

## Later, not here

What each form will mean: `~word` (language, stemmer), `/re/` (the dialect, ERE as notmuch's `regcomp(REG_EXTENDED)`, on which fields, matched as notmuch matches it: a filter over the other terms' candidates, a scan of the field when alone, an expansion over the distinct values of a closed field), `field:{query}` (a-query-reads-across-domains).
