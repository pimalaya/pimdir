-- Withdraws a recorded choice, a `set-performer` naming no source (§15.6).
DELETE FROM performers WHERE account IS :account AND capability = :capability;
