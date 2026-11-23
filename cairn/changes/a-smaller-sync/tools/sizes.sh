#!/usr/bin/env bash
# Prints, for io-pimdir's engine files, the lines of code and of inline
# tests (split at the first #[cfg(test)]), the count of public items under
# src/, and SYNC.md's words per section.
# Usage: sizes.sh [IO_PIMDIR] [SYNC_MD]
set -euo pipefail
I=${1:-/home/soywod/code/pimalaya/io-pimdir}
S=${2:-/home/soywod/code/pimalaya/pimdir/SYNC.md}
total=0
printf 'file\tcode\ttests\n'
for f in sync.rs client/write.rs hub.rs mutate.rs upgrade.rs rekey.rs remote.rs \
  change.rs placement.rs collection.rs coroutine.rs load.rs sync/join.rs \
  client/run.rs open.rs; do
  p=$I/src/$f
  [ -f "$p" ] || continue
  all=$(wc -l < "$p")
  cut=$(grep -n '^#\[cfg(test)\]' "$p" | head -1 | cut -d: -f1 || true)
  code=${cut:-$((all + 1))}; code=$((code - 1))
  printf '%s\t%d\t%d\n' "$f" "$code" "$((all - code))"
  total=$((total + code))
done
printf 'engine code\t%d\n' "$total"
printf 'public items\t%d\n' "$(grep -rhE '^\s*pub (fn|struct|enum|trait|type|const|static|mod) ' "$I/src" | wc -l)"
awk '/^## /{if(s!="")printf "%s\t%d\n",s,w; s=$0; w=0; next} {w+=NF} END{printf "%s\t%d\n",s,w}' "$S"
printf 'SYNC.md words\t%d\n' "$(wc -w < "$S")"
