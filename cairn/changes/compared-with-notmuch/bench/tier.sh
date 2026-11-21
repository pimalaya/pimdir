#!/bin/sh
# usage: tier.sh NAME MAIL_ROOT CPU  -> runs/NAME/{nm,pd}, log in runs/NAME/log
set -e
B=/home/soywod/code/pimalaya/.bench-notmuch
NAME=$1 ROOT=$2 CPU=$3
R=$B/runs/$NAME; rm -rf $R; mkdir -p $R/nm $R/pd; chmod 700 $R/pd
T="$B/tools-1/bin/time -f wall=%e,user=%U,sys=%S,rss_kib=%M"
$B/scripts/nmconf.sh $ROOT $R/nm $R/nm.conf
export NOTMUCH_CONFIG=$R/nm.conf HOME=$R
L=$R/log; : > $L
echo "files $(find $ROOT -type f | wc -l)" >> $L
sync; echo "== notmuch new" >> $L
$T taskset -c $CPU $B/tools/bin/notmuch new --quiet >> $L 2>&1
echo "nm_db $(du -sb $R/nm | cut -f1)" >> $L
sync; echo "== pimdir sync" >> $L
$T taskset -c $CPU $B/target/release/pimbench sync $R/pd/store $ROOT $R/pd/state >> $L 2>&1
sync; echo "== pimdir index" >> $L
$T taskset -c $CPU $B/target/release/pimbench index $R/pd/store >> $L 2>&1
for f in pimdir.db index.db objects; do echo "pd_$f $(du -sb $R/pd/store/$f | cut -f1)" >> $L; done
ls -la $R/pd/store >> $L
echo done >> $L
