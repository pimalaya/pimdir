#!/usr/bin/env bash
# Prints the sizes the night is judged by, for a pimdir tree and an io-pimdir
# tree (default: the checkouts beside this repository). Needs sqlite3 on PATH
# or SQLITE3 set.
#
# Usage: sizes.sh [PIMDIR] [IO_PIMDIR]
set -euo pipefail
P=${1:-/home/soywod/code/pimalaya/pimdir}
I=${2:-/home/soywod/code/pimalaya/io-pimdir}
SQLITE3=${SQLITE3:-$(command -v sqlite3 || ls /nix/store/*-sqlite-3.5*-bin/bin/sqlite3 | head -1)}

echo "# documents (words)"
for d in STORAGE.md SYNC.md SEARCH.md OVERVIEW.md GUIDE.md; do
  [ -f "$P/$d" ] && printf '%s\t%s\n' "$d" "$(wc -w < "$P/$d")" || printf '%s\tgone\n' "$d"
done

echo "# store schema (a fresh store)"
db=$(mktemp -d)/s.db
"$SQLITE3" "$db" < "$P/migrations/storage/0001_init.sql" >/dev/null
for t in table index trigger view; do
  n=$("$SQLITE3" "$db" "SELECT count(*) FROM sqlite_master WHERE type='$t' AND name NOT LIKE 'sqlite_%';")
  printf '%s\t%s\n' "$t" "$n"
done
printf 'columns\t%s\n' "$("$SQLITE3" "$db" "SELECT count(*) FROM sqlite_master m, pragma_table_info(m.name) WHERE m.type='table' AND m.name NOT LIKE 'sqlite_%';")"

echo "# index schema (io-pimdir)"
idx=$(mktemp -d)/i.db
if [ -d "$I/spec/migrations/search" ]; then
  cat "$I"/spec/migrations/search/*.sql | "$SQLITE3" "$idx" >/dev/null
  printf 'tables\t%s\n' "$("$SQLITE3" "$idx" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE TABLE ''%';")"
fi

echo "# statements"
printf 'pimdir queries/\t%s\n' "$( [ -d "$P/queries" ] && find "$P/queries" -name '*.sql' | wc -l || echo 0)"
printf 'io-pimdir storage\t%s\n' "$(find "$I/spec/queries/storage" -name '*.sql' | wc -l)"
printf 'io-pimdir search\t%s\n' "$(find "$I/spec/queries/search" -name '*.sql' | wc -l)"

echo "# io-pimdir lines"
printf 'src\t%s\n' "$(find "$I/src" -name '*.rs' -print0 | xargs -0 cat | wc -l)"
printf 'src/client store layer\t%s\n' "$(cat "$I/src/client.rs" "$I"/src/client/*.rs | wc -l)"
printf 'tests\t%s\n' "$(find "$I/tests" -name '*.rs' -print0 | xargs -0 cat | wc -l)"
printf 'pub items\t%s\n' "$(grep -rhoE '^\s*pub (struct|enum|fn|trait|const|type) ' "$I/src" | wc -l)"
printf 'test fns\t%s\n' "$(grep -rh '#\[test\]' "$I/src" "$I/tests" | wc -l)"
