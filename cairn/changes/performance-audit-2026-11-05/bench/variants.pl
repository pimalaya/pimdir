#!/usr/bin/env perl
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Writes the store schemas bench/draft09.c compares into DIR:
#   rows.sql   storage-draft-08 as it stands (migrations/storage/0001_init.sql)
#   cols.sql   the same with the system flags as columns, items.marks and
#              bindings.base_marks, every other flag a row
#   id.sql     cols plus the integer placement id (bench/draft09-id.sql)
# and each again with the pending stamp of io-pimdir's
# a-page-lands-in-few-statements, *-pending.sql.
#
# Usage: perl variants.pl CANONICAL_SQL ID_SQL DIR

use strict;
use warnings;

my ($canonical, $id, $dir) = @ARGV;
die "usage: variants.pl CANONICAL_SQL ID_SQL DIR\n" unless $dir;

sub slurp { local $/; open my $f, '<', $_[0] or die "$_[0]: $!"; <$f> }
sub spit { open my $f, '>', $_[0] or die "$_[0]: $!"; print $f $_[1] }

sub edit {
    my ($text, $from, $to, $what) = @_;
    my $count = ($text =~ s/\Q$from\E/$to/);
    die "variants.pl: $what not found\n" unless $count;
    $text;
}

sub cols {
    my $t = shift;
    $t = edit($t, "    changed         INTEGER NOT NULL DEFAULT 0 CHECK (typeof(changed) = 'integer'),  -- the change stamp (§4.5), trigger-maintained\n",
        "    changed         INTEGER NOT NULL DEFAULT 0 CHECK (typeof(changed) = 'integer'),  -- the change stamp (§4.5), trigger-maintained\n"
        . "    marks           INTEGER NOT NULL DEFAULT 0 CHECK (typeof(marks) = 'integer'),\n"
        . "    CHECK (flags_known = 1 OR marks = 0),\n", 'items.changed');
    $t = edit($t, "    flags_known, object_hash, sort_key, level, deleted, retained_at, conflicted, conflict_object\nON items\nWHEN OLD.flags_known IS NOT NEW.flags_known\n",
        "    flags_known, marks, object_hash, sort_key, level, deleted, retained_at, conflicted, conflict_object\nON items\nWHEN OLD.flags_known IS NOT NEW.flags_known\n  OR OLD.marks IS NOT NEW.marks\n",
        'items_stamp_update');
    $t = edit($t, "CREATE INDEX items_by_sort ON items(collection, sort_key, seq) WHERE deleted = 0;\n",
        "CREATE INDEX items_by_sort ON items(collection, sort_key, seq, marks) WHERE deleted = 0;\n"
        . "CREATE INDEX items_unread ON items(collection, sort_key, seq) WHERE deleted = 0 AND marks & 1 = 0;\n",
        'items_by_sort');
    $t = edit($t, "    base_present      INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_present) = 'integer') CHECK (base_present IN (0, 1)),\n",
        "    base_present      INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_present) = 'integer') CHECK (base_present IN (0, 1)),\n"
        . "    base_marks        INTEGER NOT NULL DEFAULT 0 CHECK (typeof(base_marks) = 'integer'),\n",
        'bindings.base_present');
    $t = edit($t, "    PRIMARY KEY (collection, link_id, source),\n",
        "    PRIMARY KEY (collection, link_id, source),\n    CHECK (base_flags_known = 1 OR base_marks = 0),\n",
        'bindings key');
    $t;
}

sub pending {
    my $t = shift;
    my $n = 0;
    $n += ($t =~ s/(CREATE TRIGGER items_stamp_insert AFTER INSERT ON items)\nBEGIN/$1\nWHEN NEW.changed <> -2\nBEGIN/);
    $n += ($t =~ s/(CREATE TRIGGER items_stamp_update .*?\nWHEN )(.*?)(\nBEGIN)/$1NEW.changed <> -2 AND ($2)$3/s);
    $n += ($t =~ s/(CREATE TRIGGER placement_flag_stamp_insert AFTER INSERT ON placement_flag\nBEGIN\n\s*UPDATE items SET changed = -1 WHERE [^;]*?);/$1 AND changed <> -2;/s);
    die "variants.pl: pending rewrote $n triggers, not 3\n" unless $n == 3;
    $t;
}

my $rows = slurp($canonical);
my $cols = cols($rows);
my $ids = slurp($id);
for ([rows => $rows], [cols => $cols], [id => $ids]) {
    my ($name, $text) = @$_;
    spit("$dir/$name.sql", $text);
    spit("$dir/$name-pending.sql", pending($text));
}
