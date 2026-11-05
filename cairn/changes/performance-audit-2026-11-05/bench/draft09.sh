#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Runs bench/draft09.c over every candidate schema, on both SQLite builds of
# draft09.nix: N writes in batches of 500 (three runs each), then the mail
# list's reads over a store of READS messages. Measure on an idle core.
#
# Usage: bench/draft09.sh DIR [N] [READS]   (from the repository root)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
dir=${1:?usage: draft09.sh DIR [N] [READS]}
n=${2:-20000}
reads=${3:-100000}
mkdir -p "$dir"

perl "$here/variants.pl" migrations/storage/0001_init.sql "$here/draft09-id.sql" "$dir"
bin=$(nix-build --no-out-link "$here/draft09.nix")/bin

for exe in "$bin"/draft09-*; do
    for variant in rows:0 rows:1 cols:0 cols:1 id:0 id:1; do
        family=${variant%:*}
        pending=${variant#*:}
        schema="$dir/$family.sql"
        [ "$pending" = 1 ] && schema="$dir/$family-pending.sql"
        for run in 1 2 3; do
            "$exe" "$schema" "$family" "$pending" "$dir/write.db" "$n" write
        done
    done
    for family in rows cols id; do
        "$exe" "$dir/$family.sql" "$family" 0 "$dir/read.db" "$reads" read
    done
done
