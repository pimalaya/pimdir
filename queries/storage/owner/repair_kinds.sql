-- Reconciliation's repair (§6): a collection an earlier draft declared with a
-- media type outside the closed set (§13) is recorded kindless, before the
-- rebuild that would refuse it.
UPDATE collections SET kind = ''
WHERE kind NOT IN ('', 'message/rfc822', 'text/vcard', 'text/calendar', 'application/octet-stream');
