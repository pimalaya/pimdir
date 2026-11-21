#!/bin/sh
# usage: incr.sh RUN_NAME MAIL_ROOT CPU -> appends to runs/NAME/incr.log
B=/home/soywod/code/pimalaya/.bench-notmuch
R=$B/runs/$1 ROOT=$2 CPU=$3
export NOTMUCH_CONFIG=$R/nm.conf HOME=$R TZ=UTC
T="$B/tools-1/bin/time -f wall=%e,user=%U,sys=%S,rss_kib=%M"
NM="taskset -c $CPU $B/tools/bin/notmuch" PB="taskset -c $CPU $B/target/release/pimbench"
PD="taskset -c $CPU $B/target-cli/release/pimdir -s $R/pd/store"
L=$R/incr.log
both() { # label
  sync; echo "== $1 notmuch new" >> $L; $T $NM new --quiet >> $L 2>&1
  sync; echo "== $1 pimdir sync" >> $L; $T $PB sync $R/pd/store $ROOT $R/pd/state >> $L 2>&1
  echo "== $1 pimdir index" >> $L; $T $PB index $R/pd/store >> $L 2>&1
}
both noop
# 1000 new messages in a new folder, distinct Message-IDs (copy 2 of Enron)
mkdir -p $ROOT/zz-new/inbox/cur $ROOT/zz-new/inbox/new $ROOT/zz-new/inbox/tmp
find $B/corpus/c2/dasovich-j~2/all_documents/cur -type f | head -1000 | while read f; do ln "$f" $ROOT/zz-new/inbox/cur/; done
both add1000
# 1000 flag changes: add F to 1000 files of one big folder
D=$ROOT/dasovich-j/all_documents/cur
ls $D | grep -v F | head -1000 | while read f; do mv "$D/$f" "$D/${f%%:2,*}:2,F${f##*:2,}"; done
both flag1000
echo "== tag notmuch +bench from:jeff.dasovich" >> $L
$T $NM tag +bench -- from:jeff.dasovich@enron.com >> $L 2>&1
echo "== tag pimdir --add bench from:jeff.dasovich" >> $L
$T $PD tag --refresh-timeout 0s --add bench from:jeff.dasovich@enron.com > /dev/null 2>> $L
echo "pd tagged: $($PD count --refresh-timeout 5m tag:bench | head -1)" >> $L
echo "nm tagged: $($NM count tag:bench)" >> $L
echo done >> $L
