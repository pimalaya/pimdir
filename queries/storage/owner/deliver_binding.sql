-- Records a create delivered (SYNC.md §2, §4): the binding this source holds
-- under the provisional :handle, whose add was accepted with no handle or into
-- which a relocation was accepted, gains a base naming nothing, no flag set,
-- revision nor body, so it derives no add while no page has landed it
-- (SYNC.md §5, §6). A binding holding a base, or none under that handle, is
-- left as it is: the create was landed, withdrawn or delivered since. Seeks
-- bindings_by_handle.
UPDATE bindings SET base_present = 1
WHERE collection = :collection AND source = :source AND handle = :handle
  AND substr(handle, 1, 1) = char(1)
  AND base_present = 0;
