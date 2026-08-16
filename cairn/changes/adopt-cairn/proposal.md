---
cairn: change
id: adopt-cairn
status: landed
created: 2026-08-16
---

# Adopt Cairn, in its draft-format form

## Why

Every other repository in the organisation that this format binds already follows Cairn (io-pimdir, calendula, cardamum, himalaya), so a change to the format is recorded everywhere except in the format's own repository. The immediate case is [pimdir issue 1](https://github.com/pimalaya/pimdir/issues/1): SPEC.md §13 and §11 moved, two products moved with them, and nothing here says when or why.

## What

The structure, an activation file, and one deliberate deviation.

### `cairn/spec/` stays empty

This repository *is* a specification. SPEC.md is the current truth already, in one normative document other repositories cite by section (io-pimdir's spec-fidelity capability, calendula's backends capability). Restating those sections as capability files would create a second place where the same rule is written, and the two would drift the first time one is edited alone.

So SPEC.md plays the part `cairn/spec/` plays elsewhere: a change is folded into the section that states the rule, and the log is what records that it moved. The directory exists because conformance asks for it (CAIRN.md §8, C2), and it stays empty until the freeze makes the question worth reopening.

### While the format is `draft`, a log entry is the whole obligation

The schema is still edited in place (SPEC.md §6), nothing depends on a frozen version, and the cost of a proposal plus a task list per change is not repaid at this stage. A change folder is optional and reserved for intent that wants review before the edit. The forcing rule is unchanged: SPEC.md reflects the new truth and the log says it moved.

This relaxation is scoped to the draft, and ends with it.
