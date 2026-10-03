---
cairn: log
change: capabilities
date: 2026-10-03
---

# Capabilities

Sources do not push the same things, and a producer learned it from a rejected push. The owner now declares what each source can do, a producer refuses before it enqueues, and the owner parks what slipped past. Reviewed in cairn/changes/capabilities (proposal, desk check, prototype, end-to-end run).

- **STORAGE §4.3, §13, §14, migration 0001.** Tables `capabilities` (account, source, optional collection, capability, support, detail) and `performers` (account, capability, source); statements `delete_capabilities`, `set_capability`, `set_performer`, `delete_performer`, `load_capabilities`, `load_item_capabilities`, `list_capability_sources(account, collection, capability)`, `load_performer`. Guarded by checks/invariants.sh ("capability:", "override:", "performer:", "implementations:") and checks/names.sh.
- **§15.6 Declaring.** The owner declares every source it runs, under its account, every Annex B capability of its kinds, `none` included; a collection row overrides the source-wide one there; a source with no row is undeclared and gates nothing. Invariants "capability:", "override:".
- **§15.6 Implementations.** One implementation per source and capability; several for an account are several sources, the user choosing for an intent; an implementation reaching only what its source holds is declared on those collections. Invariants "implementations:".
- **§15.6 The producer's gate and the owner's backstop.** An action needs its capabilities from every source concerned (Annex B.1, flags carried by an `add` or `copy` included); a `partial` passes, its detail shown; the drain parks what a declared source does not support. io-pimdir tests/capabilities.rs; end-to-end B1.
- **§15.6 Intents.** Candidates read at the anchor collection; one is the performer, several are the user's, the latest queued `set-performer` read over the recorded one. Invariants "implementations:", "performer:"; io-pimdir test of the queued choice; end-to-end P1, P2.
- **§15.5 Replacing an intent.** A performed intent leaving a store change behind is replaced by it in one transaction, the body pinned throughout. Invariant "replace:".
- **Annex B.1 calendar rules read from the resource.** A resource is scheduled by its `SCHEDULE-AGENT`s, the user's acceptance being `NONE`; an occurrence change ignores `DTSTAMP` and `LAST-MODIFIED`; `calendar.online-meeting` asked by `X-PIMDIR-ONLINE-MEETING:TRUE`. The SQL reads no body, so io-pimdir's gate tests guard these; end-to-end K1 to K5.
- **Annex B.2 `submit` copy.** `copy` asks the performer to file the sent message once sent (`mail.submit.copy`), natively or by replacing the intent; asked only of a declared performer, an older owner ignoring the field. io-pimdir and himalaya tests; end-to-end S1 to S3, U1, U2.

Decided on review: strict gating over several sources, scheduling refused rather than noted, performers in the store because a client knows nothing of its owner. Known edge left to a later change: a source receiving one-way copies would veto every action on what it binds, should a store ever mix one with a two-way source. iMIP fits as an implementation a sending source declares, deferred to the NLnet 2027 plan.

Normative edits after the `draft-02` tag, so the three Status lines, the README and AGENTS §2 move to `draft-03`; the `draft-03` tag is the user's to make.
