-- A placement whose body is now indexed, or that holds none any more (§4).
DELETE FROM missing WHERE collection = :collection AND seq = :seq;
