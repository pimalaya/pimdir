---
cairn: log
change: two-sync-vectors-follow-the-prose
date: 2026-10-30
---

# Two sync vectors follow the prose

io-pimdir's engine, made to reproduce every vector of sync-draft-05, found two that contradicted SYNC.md. No rule moved; the vectors now state what the prose already required. Lands in sync-draft-05.

- vectors/sync/76-a-propagated-absence-is-pushed.json: jmap holds no coverage, so its run opens its first round (SYNC §5, step 2) and stamps the bindings it lists with the round's id (§5, Rounds). The vector left jmap's `Ma` binding at `round: null`; it now expects `1`, as vector 75 stamps imap's `12`.
- vectors/sync/93-a-second-source-message-under-a-held-id-mints.json: source b lacks basic-1@example.org and the store holds its body, so the projection offers it to b as a `Created` placement (§3) and the round's last page pushes its `Add` (§5, creates wait for the page that lands them). The vector expected no push; it now expects that `Add`, left pending since the remote reports no outcome.

Guarded by the vectors themselves: io-pimdir's tests/vectors_sync.rs had corrected both in an erratum that asserted the old values, and now reads them as they are.
