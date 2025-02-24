#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
enpdev='enp0s8'
leaderip=`echo $@ | awk '{print $1}'`
pool=`echo $@ | awk '{print $2}'`
vol=`echo $@ | awk '{print $3}'`
volip=`echo $@ | awk '{print $4}'`
vtype=`echo $@ | awk '{print $5}'`
echo $@ > /root/`basename "$0"`

docker exec etcdclient /TopStor/logqueue.py `basename "$0"` running $userreq
/TopStor/etcddel.py $leaderip vol $vol
/TopStor/etcddel.py $leaderip replivol $vol
/TopStor/etcddel.py $leaderip size $vol 
#/TopStor/deltolocal.py size $vol 
#/TopStor/deltolocal.py vol $vol 
/TopStor/crondelete $vol
rm -rf /TopStordata/exports.${volip}.new
rm -rf /TopStor/exports.${vol}
echo vol = $vol
resname=$vtype'-'$volip
docker  rm -f $resname 
rm -rf /$pool/user_$vol
rm -rf /$pool/group_$vol
/TopStor/etcddel.py $leaderip vol $vol 
/TopStor/etcddel.py $leaderip replivol $vol
nmcli conn mod cmynode -ipv4.addresses $volip 
nmcli conn up cmynode
/pace/VolumeCheck.py $leaderip `hostname`
docker exec etcdclient /TopStor/logqueue.py `basename "$0"` finish $userreq
