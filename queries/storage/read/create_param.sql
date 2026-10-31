-- The list parameters of the canonical statements (§4.4), one table per
-- connection: a caller fills a statement's slots with bind_param inside the
-- statement's transaction, after clear_param, and the statement joins them.
-- `position` keeps a value bound twice twice, which release_pins counts.
CREATE TEMP TABLE IF NOT EXISTS param (
    slot     TEXT    NOT NULL,
    position INTEGER NOT NULL,
    value    ANY,
    PRIMARY KEY (slot, position)
) STRICT;
