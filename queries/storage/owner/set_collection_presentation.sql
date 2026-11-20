-- How a collection is shown, as its source states it, each NULL when it
-- states none: a color as written (a DAV calendar-color, a CSS color), a
-- description, and a position among its siblings that list_collections orders
-- by. Presentation alone: nothing keys on them, and a reader takes the color
-- and the description as untrusted text. The collection is declared first.
UPDATE collections SET color = :color, description = :description, sort_order = :sort_order
WHERE id = :collection;
