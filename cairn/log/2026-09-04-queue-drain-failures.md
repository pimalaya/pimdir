---
cairn: log
change: queue-drain-failures
date: 2026-09-04
---

# A drain parks a store failure and skips a foreign remove

§15.2 named retry and park and left the boundary to the owner, and the reference owner retried a refused rebind forever, stopping every row behind it. A failure of the store is now permanent and parks; a failure of the environment retries; neither stops later rows. §15.3's `remove` of an item the draining source does not bind is skipped for the source that binds it, where "already absent is success" had been read as swallowing it. The claim-first sentence no longer invokes a second owner §8 forbids.
