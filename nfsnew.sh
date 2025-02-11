#!/bin/sh
cd /TopStor
export ETCDCTL_API=3
echo $@ > /root/nfshtmp
echo I am here
echo param= $@
resname=`echo $@ | awk '{print $1}'`
mounts=`echo $@ | awk '{print $2}' | sed 's/\-v/ \-v /g'`
ipaddr=`echo $@ | awk '{print $3}'`
ipsubnet=`echo $@ | awk '{print $4}'`
vtype=`echo $@ | awk '{print $5}'`
share=`echo $@ | awk '{print $6}'`
echo params $@ > /root/nfstmp
echo name $resname >> /root/nfstmp
echo mounts $mounts >> /root/nfstmp
echo ip and subnet $ipaddr $ipsubnet >> /root/cifstmp
docker rm -f $resname
nmcli conn mod cmynode -ipv4.addresses ${ipaddr}/$ipsubnet
echo nmcli conn mod cmynode -ipv4.addresses ${ipaddr}/$ipsubnet
nmcli conn up cmynode
nmcli conn mod cmynode +ipv4.addresses ${ipaddr}/$ipsubnet
nmcli conn up cmynode

docker run -d $mounts --rm --privileged \
  		-e "HOSTIP=$ipaddr"  \
		-e SHARED_DIRECTORY=$share \
  		-p $ipaddr:2049:2049/tcp \
  		-p $ipaddr:11111:111 \
  		-v /TopStor/:/TopStor \
  		--name $resname itsthenetwork/nfs-server-alpine
