---
cairn: log
change: a-provider-filing-sent-files-only-sent
landed: 2026-11-24
---

# A provider filing Sent files only Sent

Found by the live test night of 2026-11-23 (.lanes/live/report.md of the workspace, neverest N1), ruled by the owner on 2026-11-24 (neverest R1: Gmail adds the label, Graph declares `mail.submit.copy` partial). Annex B.2 let a performer whose provider files the sent message itself (Graph's `sendMail`, Gmail) support `mail.submit.copy` as that filing, enqueuing nothing, whatever collection `copy` named: a send asking its copy in another folder had it filed in Sent alone, the folder it asked for left without it.

## STORAGE.md Annex B.2, a `submit` naming `copy`

- The provider's own filing stands for the copy only when `copy` is the collection whose role is `sent` (§14). A copy elsewhere is filed as the provider allows: another label on the sent message where labels are collections (Gmail), else an `add` of the message into `copy` replacing the intent, as a performer whose provider files nothing files every copy.
- A performer that can file a copy nowhere but in Sent declares `mail.submit.copy` `partial`, and `none` on its other collections, so the gate refuses such a copy at enqueue, a `submit` being anchored on the collection its copy belongs to.

No vector: the runners express no performer and no capability declaration (sync/ runs an engine against a remote, payloads.json a payload's schema), so the rule binds the connectors, neverest's from its commit for N1. storage-draft-17 keeps its number (not tagged). Nothing io-pimdir vendors moves.
