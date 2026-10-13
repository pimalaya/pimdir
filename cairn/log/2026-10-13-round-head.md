---
cairn: log
change: round-head
date: 2026-10-13
---

# A round shows what arrives while it fills: the head

While a collection's round is open, a run resuming it lists the round's head first (SYNC §4, §5 "Heads"; vectors 62 to 69), so a message arriving during a long first round shows at the next run instead of when the round closes.

- **Two kinds, stated by the connector.** A delta head lists from a checkpoint and carries the new one (IMAP QRESYNC, Gmail history); a band head lists from the round's start instant less two days, by an instant the source keeps per member (Graph `receivedDateTime`, IMAP `SEARCH SINCE` without QRESYNC), carrying no checkpoint and stating no removal.
- **A delta head stamps its members with the round** and moves `round_checkpoint`, so the close keeps them and lands on the head's checkpoint. Not stamping would have lost an arrival: the close finds it absent and the next delta, past its arrival, never lists it again.
- **A band head stamps nothing**; the connector lists again, in the round's last page, every member a band head would list then, so the close finds absent only what really went.
- **No schema change**: `round_checkpoint` already is "the checkpoint the round will land", `round_started_at` the band head's instant; `set_round_cursor` coalesces its cursor so a head moves the checkpoint alone.
- Implemented in io-pimdir `07bd316`; neverest connectors: Gmail delta head (`d485913`), Graph mail band head with last-page relisting (`986a306`), IMAP delta head with QRESYNC, band head otherwise, the round cursor carrying the round's top UID (`e081198`). A moved IMAP `UIDVALIDITY` refuses the head, restarting the round.

Left: live checks on Gmail and Microsoft 365 test boxes, MOA on a large Gmail box, heads in the Android connectors.
