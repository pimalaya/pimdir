---
cairn: log
change: the-freeze-plan
landed: 2026-11-20
---

# The generator states every read, capabilities, references and the feed

The fifth code step of the generator of cairn/changes/the-freeze-plan (section 2). No part of the standard moves.

- **Capabilities and performers** (generator/src/capability.rs): four sources declare the base set of their kinds, `none` gaps with their detail and collection overrides among them, through `delete_capabilities` and `set_capability`, a performer through `set_performer`. The model's drain runs the owner's backstop (STORAGE §15.6, Annex B): the capabilities an action needs from the sources it concerns, a pending create left out for a `remove`, `move` or `copy`, the target's sources asked what an `add` needs, flags by their capability without regard to ASCII case, a scheduled resource, a VTODO landing where a row states `calendar.component.vtodo`, a capability added after the base set read only where a row states it; an intent whose source declares none of its capability, and a `set-performer` naming such a source, parked.
- **References and stand-ins**: references by a person and by a rule, one to a retained item, written through `add_reference`, which must answer each; the fixtures' parts stood for in the lab account's attachments collection (STORAGE §14.3), one saved with its body in a folder.
- **The change feed**: every item and collection listed once with a stamp, the cursor's purges, id and incarnation, and a check that the stamps order the rows totally and stand at most at the cursor (STORAGE §4.5).
- **The oracle** now answers every statement under queries/storage/read/ but the list slots' own three and `load_store_meta`: capabilities and performers, references, attachments, the feed, `count_mail_by_day` under three shifts, `sum_mail` under three windows, the four `search_` statements under seven `LIKE` patterns (an escaped underscore, ASCII folding), the `_by_link` loads. The self-check fails on a statement under read/ it does not answer, so a statement the spec adds there reaches the generator first.
- **Checks**: broken by hand and seen to fail: overrides ignored, `LIKE` case-sensitive, the day shift ignored, sums per row rather than per message, references in another order, a saved copy ignored, `none` read as support, a later capability read as unsupported, scheduling not gating a remove. The last three are drain decisions, which the self-check reads back from the model, so they are held by a test stating each from the spec (queue.rs, `the_backstop_parks_by_what_the_sources_declare`).
