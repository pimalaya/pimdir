-- `IS` so binding NULL selects the collections of a single-account store.
SELECT id, account, kind, name, parent, color, description, sort_order, generation
FROM collections WHERE account IS :account
ORDER BY sort_order IS NULL, sort_order, id;
