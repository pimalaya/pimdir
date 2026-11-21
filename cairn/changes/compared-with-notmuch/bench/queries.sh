#!/bin/sh
# usage: queries.sh RUN_NAME CPU -> runs/NAME/queries.txt (hyperfine medians, ms)
B=/home/soywod/code/pimalaya/.bench-notmuch
R=$B/runs/$1 CPU=$2
export NOTMUCH_CONFIG=$R/nm.conf HOME=$R TZ=UTC
NM=$B/tools/bin/notmuch PD="$B/target-cli/release/pimdir -s $R/pd/store"
H=$B/tools-2/bin/hyperfine
OUT=$R/queries.txt; : > $OUT
med() { # cmd -> median ms
  $H -N --warmup 2 --runs ${RUNS:-10} --export-json $R/h.json "taskset -c $CPU $1" >/dev/null 2>&1
  nix-shell -p jq --run "jq -r '.results[0].median*1000|.*10|round/10' $R/h.json" 2>/dev/null
}
printf 'label\tnm_count\tnm_count_ms\tnm_page_ms\tnm_threads_ms\tpd_count\tpd_count_ms\tpd_page_ms\tpd_threads_ms\n' >> $OUT
while IFS='	' read -r label nq pq; do
  nc=$($NM count "$nq")
  pc=$($PD count --refresh-timeout 0s --json "$pq" | nix-shell -p jq --run "jq -r '.count'" 2>/dev/null)
  a=$(med "$NM count '$nq'")
  b=$(med "$NM search --output=messages --sort=newest-first --limit=50 '$nq'")
  c=$(med "$NM search --sort=newest-first --limit=50 '$nq'")
  d=$(med "$PD count --refresh-timeout 0s '$pq'")
  e=$(med "$PD search --refresh-timeout 0s -n 50 '$pq'")
  f=$(med "$PD search --refresh-timeout 0s --threads -n 50 '$pq'")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$nc" "$a" "$b" "$c" "$pc" "$d" "$e" "$f" >> $OUT
done < $B/scripts/queries.tsv
