-- The placements whose indexed card states a category (§6): category: on a
-- card, :value folded as the values are (§8). A task answers on the store's
-- task_summary instead.
SELECT p.collection, p.seq FROM object_category c
JOIN object o ON o.id = c.object JOIN placement p ON p.hash = o.hash
WHERE c.value = :value;
