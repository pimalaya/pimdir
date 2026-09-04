-- Run once after stamp_item, which consumed the stamp it read.
UPDATE store_meta SET next_change = next_change + 1 WHERE id = 1;
