-- A store knows an account only through its collections, account configuration
-- living outside the store (§9.2), so an account with no collection yet is
-- invisible here and that is deliberate.
SELECT DISTINCT account FROM collections WHERE account IS NOT NULL ORDER BY account;
