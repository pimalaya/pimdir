---
cairn: log
change: mail-in-reply-to
landed: 2026-08-16
---

# Carry In-Reply-To in the mail summary

[himalaya issue 734](https://github.com/pimalaya/himalaya/issues/734) asks for `In-Reply-To` on the shared envelope: it is the 9th element of the IMAP `ENVELOPE` (RFC 3501 §7.4.2), so a connector already has it, and without it the only way to pair a reply with its parent is to fetch and parse the body.

The same argument binds harder here than on any server-backed listing. A pimdir store is where a body read is most expensive: an item at `level < 2` has no local body at all, so a reader would answer "unknown" rather than pay a fetch. If the shared envelope carries the field and the summary does not, the offline backend becomes the one that cannot answer.

## What landed

`in_reply_to` in the `message/rfc822` convention (Annex A.1), optional, an **array** of bare msg-ids.

An array rather than a string because RFC 5322 §3.6.4 gives the field as `1*msg-id`: one id is the common case, a reply to a merged thread is not, and JMAP already models it as a list (`Email/inReplyTo`), so a scalar would force the one backend that hands the data over correctly to truncate it. Ids are stripped of their angle brackets exactly as `message_id` is, which is what lets a reader match the two byte-for-byte across backends that spell the header differently.

The change is additive at `v: 1`, so it needs no version bump: Annex A already reads an absent optional field as unknown, older rows read as absent, and older readers ignore the key. That is the only safe shape here, unlike the calendar convention renamed the same day: the mail summary is already written by himalaya, neverest, pimalaya-linux and pimalaya/android.

## What was left out

`References:`. It is the field a real threading algorithm walks, and `in_reply_to` alone gives a parent pointer that breaks wherever a client omitted the header. But it is *not* in the IMAP `ENVELOPE`, so it costs an extra `BODY.PEEK[HEADER.FIELDS (REFERENCES)]` item, and a full chain is a few hundred bytes on every row of the store rather than the forty of one id. It belongs to whichever change actually builds threads, and it lands here at that point, additively, the same way.
