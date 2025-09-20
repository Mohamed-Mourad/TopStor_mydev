#!/bin/bash
# synclogs.sh
# Usage: ./synclogs.sh <leaderip> <etcdip> <logid> <stamp>

leaderip="$1"
etcdip="$2"
logid="$3"
stamp="$4"

logdata=$(ETCDCTL_API=3 /TopStor/etcdget.py "$leaderip" "log/$logid")

if [ -z "$logdata" ]; then
    echo "[$(date)] No log data found for log/$logid on leader $leaderip"
    exit 1
fi

if [ "$etcdip" != "$leaderip" ]; then
    ETCDCTL_API=3 /pace/etcdput.py "$etcdip" "log/$logid" "$logdata" >/dev/null 2>&1
fi

ETCDCTL_API=3 /pace/etcddel.py "$etcdip" "sync/log/$logid/request/$HOSTNAME" >/dev/null 2>&1

echo "[$(date)] Synced log/$logid from $leaderip to $etcdip"
exit 0

