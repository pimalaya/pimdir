-- adjust_refcount at -1, set-based, for a caller settling many at once (the
-- `hashes` slot). A hash listed twice releases twice, which is what makes it
-- the same operation as the loop it replaces: that loop costs a hundred
-- thousand statements in one transaction on a fifty-thousand-item purge.
UPDATE objects SET refcount = refcount -
  (SELECT count(*) FROM temp.param WHERE slot = 'hashes' AND value = objects.hash)
WHERE hash IN (SELECT value FROM temp.param WHERE slot = 'hashes');
