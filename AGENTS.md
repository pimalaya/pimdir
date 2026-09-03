# AGENTS.md

## Cairn

This repository follows **Cairn**, a language- and tool-agnostic convention for keeping a living spec, reviewable change proposals, and an honest history next to the code. The full format and by-hand guide live at <https://github.com/pimalaya/cairn> (`CAIRN.md` and `GUIDE.md`). No tooling is required: you create and check the structure by reading and following the rules.

If you are an agent working in this repository, do the following **by default, without being asked**.

### 1. The spec is STORAGE.md, SYNC.md and SEARCH.md, not `cairn/spec/`

This repository is a specification, so its current truth is already normative documents. [STORAGE.md](./STORAGE.md) is the store, [SYNC.md](./SYNC.md) the sync part and [SEARCH.md](./SEARCH.md) the search part, each with a status of its own, and they are where a requirement is written, edited and read.

`cairn/spec/` stays empty while the format is `draft`: a capability file restating a section would be a second source of truth for the same rule, and the two would drift.

Fold a change into the document it belongs to exactly as you would fold a delta into a capability file: the section that states the rule now states the new one, and nothing records the old one but the log.

[OVERVIEW.md](./OVERVIEW.md) and [GUIDE.md](./GUIDE.md) are informative and stay so: no RFC 2119 word, no rule the parts do not state, and the parts win on any disagreement. The overview names no table, column or statement; the guide names them at every step. Rationale, history and measurements belong to the log, not to any of the five documents.

### 2. While the format is `draft`, the log is the tracker

The format is not frozen (STORAGE.md §6), the schema is still edited in place, and no store depends on it, so a proposal and a task list per change would cost more than they buy. Until version 1 is frozen:

- **Every landed change gets a log entry**, `cairn/log/YYYY-MM-DD-<change-id>.md`, kebab-case id, frontmatter `cairn: log`. That is the whole obligation.
- A change folder under `cairn/changes/` is **optional**, and worth writing only when the intent needs review before the edit (a shape that is hard to reverse, or one another repository must follow).

When a part leaves `draft`, this relaxation ends for it: a change then carries `proposal.md` and `tasks.md`, and `cairn/spec/` is reconsidered along with everything else the freeze settles.

### 3. The forcing rule still binds

> A change that affects behaviour is not *done* until the spec is updated and the log entry is written.

Here that reads: the document that owns the rule (and the canonical SQL under migrations/ and queries/, and the data under vectors/, when the change touches them) reflects the new truth, and `cairn/log/` records that it moved. A change that moves a procedure, a statement name or a concept the overview explains updates GUIDE.md or OVERVIEW.md in the same change, so the informative layer never lags the parts. Log entries are immutable; a correction is a new entry, never an edit.

### 4. Stay conformant

Check the structure yourself against the strict rules (CAIRN.md §8): a discoverable root, `spec/ changes/ log/` present, every Cairn file carrying a valid `cairn:` type, each change folder (when one exists) having `proposal.md` and `tasks.md`, kebab-case ids, literal delta headings, and a log entry for every landed change. Everything else (prose, naming, ordering, extra files) is free.

## Everything else

The repository holds no implementation. What binds an implementation is the three documents, the canonical schema under migrations/, the reference statements under queries/ and the data under vectors/; the Pimalaya standards it follows are in the [organisation guidelines](https://github.com/pimalaya/.github/blob/master/GUIDELINES.md).
