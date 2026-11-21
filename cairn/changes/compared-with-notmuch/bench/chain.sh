#!/bin/sh
B=/home/soywod/code/pimalaya/.bench-notmuch
T="$B/tools-1/bin/time -f wall=%e,user=%U,sys=%S,rss_kib=%M"; EAT=$B/tools-eat/bin/eatmydata
R=$B/runs/x1-eat; rm -rf $R; mkdir -p $R/pd; chmod 700 $R/pd; L=$R/log; : > $L
echo "== eat pimdir sync" >> $L; $T taskset -c 12 $EAT $B/target/release/pimbench sync $R/pd/store $B/corpus/x1eat $R/pd/state >> $L 2>&1
echo "== eat pimdir index" >> $L; $T taskset -c 12 $EAT $B/target/release/pimbench index $R/pd/store >> $L 2>&1
echo done >> $L; rm -rf $R/pd
$B/scripts/tier.sh x2 $B/corpus/x2 12
RUNS=5 $B/scripts/queries.sh x2 12
