---
cairn: delta
change: conventions-leave-the-core
---

## REMOVED Requirements

### Requirement: SYNC §4 Provider page sizes
The per-provider page sizes and vendor notes leave SYNC for GUIDE §10's connector notes; SYNC keeps that a connector chooses its page size within what the source accepts and SHOULD lower it after a timeout or a `413`, and states its other rules in protocol-neutral terms, IMAP, JMAP and DAV as examples.

## MODIFIED Requirements

### Requirement: STORAGE §14.3 A local calendar collection
A calendar collection no source syncs MAY hold what a person keeps on the device; its id and name are a convention's, GTD.md naming the one Pimalaya's task consumers share. The task conventions (GUIDE §17 and §18 before, vectors/gtd) live in GTD.md, informative and versioned apart (`gtd-draft-01`).
