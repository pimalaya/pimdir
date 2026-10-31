-- A thread row no message points to any more, once its members are
-- repointed or pruned (§9). A row a member still names is kept.
DELETE FROM thread WHERE id = :id AND NOT EXISTS (SELECT 1 FROM message WHERE thread = :id);
