-- The inverse of get_item, for a consumer that just staged an add.
SELECT seq FROM items WHERE collection = :collection AND link_id = :link_id;
