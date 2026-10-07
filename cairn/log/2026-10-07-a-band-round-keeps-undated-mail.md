---
cairn: log
change: a-band-round-keeps-undated-mail
date: 2026-10-07
---

# A band round infers no delete of an undated member

A mail with no usable `date` is in every scope (SYNC §5), and a round's last page dropped every based binding it did not stamp whose `date` is in its scope or unknown. A band round, the widening a connector bound to no scope may list instead of the whole scope, lists by a date filter (`SENTSINCE`, Gmail's `after:`, JMAP's `after`), which never returns undated mail: every bound undated mail was found absent and dropped from the store, nothing pushed, until a later round over a whole scope relisted it. The neverest implementer found it (neverest 3938d10) and worked around it by relisting undated mail on a band round's last page; the Android bridge had no such workaround. The text had asked the band's listing to carry its undated members, which no date filter does.

- **Deletes on a band round** (SYNC §5, STORAGE §10). Inferred only for bindings whose `date` lies inside the band; an undated member is reconciled by rounds over a whole scope and by deltas, and a removal the source states still applies whatever its date. The band's listing need carry no undated member. Guarded by invariants.sh "band: the last page infers deletes inside the band only, never of an undated member" and "a round over the whole scope still finds the undated member absent", and by sync vectors 41 (one page), 46 (two pages, the stamps read from the store) and 47 (the counterpart: a whole-scope round over the same widening drops it).
- **`sources.round_band`**, recorded by `open_round` (`:band`), cleared by `close_round`, returned last by `load_round`, read by `list_unstamped_bindings`. Its `CHECK` holds no band without an open round. Guarded by "band: the round records that it lists the band alone", "closing clears the band with the round" and "round: no round, no band, by the schema".
- **Resuming** (SYNC §5 step 1). An open round resumes only when it lists a band exactly when the run would, so a store reconciled from an earlier build, reading its open round as no band round, restarts a band listing rather than resuming it as a whole-scope one; the same-run path and the resumed one infer the same deletes. Left to io-pimdir's tests, the SQL holding no engine.

Folded into 0001 beside the round columns of scoped-mail-sync; draft-04 is not tagged yet, so the number stays.
