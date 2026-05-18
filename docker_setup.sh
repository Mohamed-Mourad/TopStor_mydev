#!/usr/bin/sh

# =============================================================================
# docker_setup.sh — QuickStor Node Bootstrap
#
# Runs on every node start. Handles in order:
#   1. Pre-flight cleanup (reset guard, bond reconciliation)
#   2. System hardening (firewall, SELinux, SSH)
#   3. First-boot / second-boot hostname provisioning
#   4. Cmdline-driven lifecycle (stop / reboot / reset / restart)
#   5. Network config: node IP, cluster IP, primary election
#   6. Logical bond creation (single-NIC vs dual-NIC)
#   7. Core Docker containers (all nodes)
#   8. Cluster join / etcd initialization loop
#   9. Primary-only containers (httpd, flask, React UI, Prometheus)
#  10. Per-node monitoring exporters
# =============================================================================


# -----------------------------------------------------------------------------
# PRE-FLIGHT: RESET GUARD
# If "reset" appears in any argument, wipe all non-system nmcli connections
# before doing anything else (gives a clean slate for re-initialization).
# -----------------------------------------------------------------------------
echo "$@" | grep -q "reset"
if [ $? -eq 0 ]; then
    nmcli -t -f NAME conn show | grep -Ev '^(docker0|lo|br-)' | while read -r conn; do
        nmcli conn delete "$conn"
    done
fi

# Disabled: more targeted cleanup of node/cluster logical connections.
# Left here in case selective cleanup is needed in future.
#nmcli -t -f NAME conn show | grep -E '(node|cluster)' | while read -r conn; do
#    echo "[*] Deleting old logical connection: $conn"
#    nmcli conn delete "$conn"
#done


# -----------------------------------------------------------------------------
# BOND RECONCILIATION
# Detect physical NIC bonds via reconcile_bonds.sh.
# Returns 4 values: <node-bond> <cluster-bond> <data1-bond> <data2-bond>
# (data1 and data2 currently use the same bond device)
# -----------------------------------------------------------------------------
bonds=$(/TopStor/reconcile_bonds.sh | tr -d '\r')
read -r nmbond cmbond dbond dbond <<< $bonds
echo "After bonds reconcilation:"
echo "    bonds: $bonds"
echo "    Node Device: $nmbond"
echo "    Cluster Device: $cmbond"
echo "    Data1 Device: $dbond"
echo "    Data2 Device: $dbond"


# -----------------------------------------------------------------------------
# DRIVERS, NETWORK MANAGER, IDENTITY
# -----------------------------------------------------------------------------
modprobe bnx2                      # Broadcom NIC driver
modprobe hpsa                      # HP Smart Array driver
systemctl restart NetworkManager

# Paths to cluster/node identity files (read by other scripts)
myclusterf='/topstorwebetc/mycluster'
mynodef='/topstorwebetc/mynode'
myhost=`hostname`


# -----------------------------------------------------------------------------
# FIREWALL: OPEN REQUIRED SERVICE PORTS
# -----------------------------------------------------------------------------
firewall-cmd --permanent --add-service={nfs,rpc-bind,mountd}
firewall-cmd --permanent --add-port=5672/tcp   # RabbitMQ AMQP
firewall-cmd --permanent --add-port=5672/udp
firewall-cmd --permanent --add-port=137/tcp    # NetBIOS name service
firewall-cmd --permanent --add-port=137/udp
firewall-cmd --permanent --add-port=138/tcp    # NetBIOS datagram
firewall-cmd --permanent --add-port=138/udp
firewall-cmd --permanent --add-port=139/tcp    # NetBIOS session (SMB)
firewall-cmd --permanent --add-port=139/udp
firewall-cmd --permanent --add-port=445/tcp    # SMB over TCP
firewall-cmd --permanent --add-port=445/udp
firewall-cmd --permanent --add-port=389/tcp    # LDAP
firewall-cmd --permanent --add-port=389/udp
firewall-cmd --permanent --add-port=88/tcp     # Kerberos
firewall-cmd --permanent --add-port=88/udp
firewall-cmd  --permanent --add-port=2381-2481/tcp   # QuickStor internal range
firewall-cmd  --permanent --add-port=2381-2481/udp
firewall-cmd --reload

# QuickStor manages NFS via containers — disable host NFS server
systemctl stop nfs-server
systemctl  disable nfs-server

# Ensure SSH allows reverse tunneling (required for node-to-node comms)
cat /etc/ssh/sshd_config | grep Gateway | grep yes
if [ $? -ne 0 ];
then
    echo GatewayPorts yes >> /etc/ssh/sshd_config
fi


# -----------------------------------------------------------------------------
# HANDLE RESET FLAG WRITTEN TO /root/nodeconfigured
# If a previous run wrote "reset" into nodeconfigured, treat this boot as a
# reset: restore persistent data from TopStordata backup, then clear the flag.
# The 'l' prefix in "echo l$order" prevents a false match on empty string.
# -----------------------------------------------------------------------------
cmdline=$@
order=`cat /root/nodeconfigured`
echo l$order | grep  reset
if [ $? -eq 0 ];
then
    cmdline='reset'
    cp /TopStordata/ports /root/
    cp /TopStordata/bootdiskf /root/
    rm -rf /TopStordata/*
    cp /root/ports /TopStordata/
    rm -rf /root/ports
    cp /root/bootdiskf /TopStordata/
    rm -rf /root/bootdiskf
    echo no > /root/nodeconfigured
fi


# -----------------------------------------------------------------------------
# SYSTEM STATE INIT
# -----------------------------------------------------------------------------
mypid='/TopStordata/diskchange'
echo stop stop stop stop > $mypid      # Signal any running disk-change watcher to stop

cp /TopStor/101-qstor.rules /usr/lib/udev/rules.d/   # Install QuickStor udev disk rules
udevadm control -R                                     # Reload udev rules immediately

sed -i 's/\=enforcing/\=disabled/g' /etc/selinux/config   # Disable SELinux persistently

echo '# init' > /etc/exports          # Reset NFS exports to empty
rm -rf /TopStordata/exportip.*         # Clear any stale exported-IP state

# On a reboot path, zpool export would block — skip it.
# On all other paths, bring up the node interface and cleanly export pools.
echo ${myhost}$cmdline | grep reboot
if [ $? -ne 0 ];
then
    nmcli conn up mynode
    zpool export -a
fi

/usr/bin/targetcli clearconfig confirm=True
targetcli saveconfig


# -----------------------------------------------------------------------------
# FIRST-BOOT PROVISIONING (init / local mode)
# Triggered when "init" or "local" appears in cmdline.
# Assigns a random DHCP-style hostname, writes it, sets iSCSI IQN,
# then reboots (first of a two-reboot provisioning cycle).
# -----------------------------------------------------------------------------
echo ${myhost}$cmdline | egrep 'init|local'
if [ $? -eq 0 ];
then
    myhost='dhcp'`echo $RANDOM$RANDOM | cut -c -6`
    hostname $myhost
    echo $myhost > /etc/hostname
    echo frstreboot > /root/hostname
    echo InitiatorName=iqn.1994-05.com.redhat:$myhost > /etc/iscsi/initiatorname.iscsi
    reboot
fi

# Second-boot: /root/hostname still says "frstreboot" from the previous boot.
# Finalize the hostname file and reboot once more to fully apply it.
cat /root/hostname | grep frstreboot
if [ $? -eq 0 ];
then
    echo $myhost > /root/hostname
    reboot
fi


# -----------------------------------------------------------------------------
# RESTART: RESET DOCKER CONTAINERS ONLY (no reboot, no data wipe)
# 'l' prefix prevents false match on empty cmdline.
# -----------------------------------------------------------------------------
echo l$cmdline | grep restart
if [ $? -eq 0 ];
then
    /TopStor/resetdocker.sh
fi


# -----------------------------------------------------------------------------
# CMDLINE LIFECYCLE HANDLING: stop / reboot / reset
# Only entered when at least one argument was passed.
# -----------------------------------------------------------------------------
lencmdline=`echo $cmdline | wc -w`
if [ $lencmdline -ge 1 ];
then
    echo $cmdline | egrep 'stop|reboot|reset'
    if [ $? -eq 0 ];
    then
        /TopStor/resetdocker.sh

        # Full factory reset: wipe all node state and etcd data, restore defaults
        echo $cmdline | grep reset
        if [ $? -eq 0 ];
        then
            rm -rf /root/node*
            rm  -rf /root/etcddata/*
            echo yes | cp /TopStor/passwd /etc/
            echo yes | cp /TopStor/group /etc/
            echo reset > /root/nodestatus
            echo no_fromreset > /root/nodeconfigured
            systemctl start target
            targetcli clearconfig confirm=True
            targetcli saveconfig
            /TopStor/resetdocker.sh
            nmcli conn up clusterstub
            nmcli conn delete mynode
            nmcli conn delete mycluster
            hostname localhost
            echo localhost > /etc/hostname
        fi

        # Reboot after a reset or explicit reboot command
        echo $cmdline | egrep 'reboot|reset'
        if [ $? -eq 0 ];
        then
            reboot
        fi

        # Stop: tear down containers and exit without rebooting
        echo $cmdline | grep 'stop'
        if [ $? -eq 0 ];
        then
            echo hihihihihi
            exit
        fi
    fi

    # Not a restart invocation: treat $1 as the node Ethernet device override
    echo $cmdline | grep restart
    if [ $? -ne 0 ];
    then
        eth1=$1
    fi
fi

# Optional second Ethernet device argument
if [ $# -ge 2 ];
then
    eth2=$1
fi


# -----------------------------------------------------------------------------
# ASSIGN BOND DEVICES TO LOGICAL ROLES
# -----------------------------------------------------------------------------
mynodedev=$nmbond
myclusterdev=$cmbond
data1dev=$dbond
data2dev=$dbond

setenforce 0        # Disable SELinux enforcement at runtime
aliast='alias'      # etcd key namespace for node alias entries

targetcli clearconfig confirm=true

# Bring up node connection and clean up any leftover logical bond definitions
# (disabled: more aggressive cleanup that deletes clusterstub/mynode/mycluster)
#nmcli conn delete clusterstub
#nmcli conn delete mynode
#nmcli conn delete mycluster
nmcli conn up mynode
nmcli conn delete cmynode
nmcli conn delete cmycluster


# =============================================================================
# NETWORK CONFIGURATION BRANCH
#
# PATH A (nodeconfigured != "yes"): Node has never been configured.
#   - Assigns a fresh node IP (from /root/newipaddr or random).
#   - Pings 10.11.11.250 to determine primary election.
#
# PATH B (nodeconfigured == "yes"): Node was previously configured.
#   - Reuses existing connections; optionally updates IPs from staged files.
#   - Pings cluster IP with retries to determine primary election.
#
# The 'S' prefix trick: prepending 'S' to the file contents lets us check
# for "Syes" without a false match when the file is empty.
# =============================================================================
isinitn='S'`cat /root/nodeconfigured`
echo $isinitn | grep 'Syes'
if [ $? -ne 0 ];
then
    # --- PATH A: FIRST-TIME NODE CONFIGURATION ---
    isconf='no'
    ipaddr=`cat /root/newipaddr`
    ipaddrn=`echo 'S'$ipaddr | wc -c`
    if [ $ipaddrn -ge 5 ];
    then
        mynode=$ipaddr                               # Use pre-staged IP if present
    else
        x=$(( ( RANDOM % 40 )  + 3 ))
        mynode='10.11.11.'$x'/24'                   # Otherwise assign a random node IP
    fi

    nmcli conn delete mynode
    nmcli conn add con-name mynode type bond ifname $mynodedev ip4 $mynode
    nmcli conn mynode up
    nmcli conn delete clusterstub
    nmcli conn add con-name clusterstub type bond ifname $myclusterdev ip4 169.168.12.12
    #nmcli conn up clusterstub

    # Primary election: ping the well-known initial cluster IP (10.11.11.250).
    # No response → this node is the first up → it becomes primary.
    ping -w 3 10.11.11.250
    if [ $? -ne 0 ];
    then
        mycluster='10.11.11.250/24'
        isconf_prim='noyes'
        isprimary=1
        echo the ping didn\'t find the initial cluster 250 so I am primary
    else
        mycluster=$mynode
        isconf_prim='nono'
        isprimary=0
        echo the ping found the initial cluster so I will not be primary
    fi

    nmcli conn delete mycluster
    nmcli conn add con-name mycluster type bond ifname $myclusterdev ip4 $mycluster

else
    # --- PATH B: RE-CONFIGURATION OF EXISTING NODE ---
    isconf='yes'

    # Update node IP if a new one was staged in /root/newipaddr
    ipaddr=`cat /root/newipaddr`
    ipaddrn=`echo 'S'$ipaddr | wc -c`
    if [ $ipaddrn -ge 5 ];
    then
        mynode=$ipaddr
        nmcli conn mod mynode connection.interface-name $mynodedev
        nmcli conn mod mynode ipv4.addresses $ipaddr
        nmcli conn up mynode

    else
        mynode=`nmcli conn show mynode | grep ipv4.addresses | awk '{print $2}'`
        if [ "$mynodedev" != "bond0" ]; then
            nmcli conn mod mynode connection.interface-name $mynodedev
            nmcli conn up mynode
        fi
    fi

    # Update cluster IP if a new one was staged in /root/newcaddr
    caddr=`cat /root/newcaddr`
    caddrn=`echo 'S'$caddr | wc -c`
    if [ $caddrn -ge 5 ];
    then
        mycluster=$caddr
        nmcli conn mod mycluster connection.interface-name $myclusterdev
        nmcli conn mod mycluster ipv4.addresses $caddr
    else
        mycluster=`nmcli conn show mycluster | grep ipv4.addresses | awk '{print $2}'`
        if [ "$myclusterdev" != "bond0" ]; then
            nmcli conn mod mycluster connection.interface-name $myclusterdev
        fi
    fi

    myclusterip=`echo $mycluster | awk -F'/' '{print $1}'`
    mynodeip=`echo $mynode | awk -F'/' '{print $1}'`

    # Wait until the node interface is reachable before proceeding
    # (alternative: comment this block and use the sleep below instead)
    ping -w 3 $mynodeip
    while [ $? -ne 0 ];
    do
        sleep 1
        ping -w 3 $mynodeip
    done
    #sleep 20

    # Primary election for already-configured node:
    # Ping cluster IP with a random retry count (5–14 attempts).
    # If ALL retries fail → cluster IP is unreachable → this node becomes primary.
    isconf_prim='yesno'
    isprimary=0
    ping -w 3 $myclusterip
    counter=`echo $RANDOM | cut -c -1`
    counter=$((counter+5))
    while [ $counter -ne 0 ];
    do
        echo counter=$counter
        ping -w 1 $myclusterip
        if [ $? -eq 0 ];
        then
            counter=0       # Cluster responded — stay as non-primary
        else
            counter=$((counter-1))
            if [ $counter -eq 0 ];
            then
                isconf_prim='yesyes'
                isprimary=1   # All retries exhausted — become primary
            fi
        fi
    done
fi

# Extract plain IP from CIDR notation (e.g. 10.11.11.5/24 → 10.11.11.5)
myclusterip=`echo $mycluster | awk -F'/' '{print $1}'`
mynodeip=`echo $mynode | awk -F'/' '{print $1}'`
myip=$mynodeip
myhostip=$mynodeip


# =============================================================================
# LOGICAL BOND CREATION
#
# Two topologies:
#   SINGLE-NIC: mynodedev == myclusterdev → one bond carries both IPs
#   DUAL-NIC:   separate bonds for node (cmynode) and cluster (cmycluster)
#
# isconf_prim values:
#   noyes  = first-boot, primary
#   nono   = first-boot, secondary (joins via clusterstub → exits early)
#   yesno  = re-boot, secondary
#   yesyes = re-boot, primary
# The case blocks below are stubs reserved for future per-topology logic.
# =============================================================================
echo $mynodedev | grep $myclusterdev
if [ $? -eq 0 ];
then
    # SINGLE-NIC TOPOLOGY
    case $isconf_prim in
    nono)
    ;;
    noyes)
    ;;
    yesno)
    ;;
    yesyes)
    ;;
    esac

    if [ $isprimary -ne 0 ];
    then
        # Primary: cmynode carries both node IP and cluster IP
        echo I am prmary
        nmcli conn delete cmynode
        echo nmcli conn add con-name cmynode type bond ifname $mynodedev ip4 $mynode ip4 $mycluster
        nmcli conn add con-name cmynode type bond ifname $mynodedev ip4 $mynode ip4 $mycluster
    else
        # Secondary: cmynode carries only the node IP
        echo I am a cluster node
        nmcli conn delete cmynode
        nmcli conn add con-name cmynode type bond ifname $mynodedev ip4 $mynode
    fi

else
    # DUAL-NIC TOPOLOGY
    case $isconf_prim in
    nono)
    ;;
    noyes)
    ;;
    yesno)
    ;;
    yesyes)
    ;;
    esac

    # Separate bonds: cmynode = node IP, cmycluster = cluster IP
    nmcli conn add con-name cmynode type bond ifname $mynodedev ip4 $mynode
    nmcli conn add con-name cmycluster type bond ifname $myclusterdev ip4 $mycluster
    if [ $isprimary -ne 0 ];
    then
        nmcli conn up cmycluster
    fi
fi

echo adding cmynode
nmcli conn up cmynode

# iSCSI target and initiator only needed on already-configured nodes
if [[ $isconf == 'yes' ]];
then
    echo strting target
    systemctl start target
    echo starting iscsid
    systemctl start iscsid
fi


# -----------------------------------------------------------------------------
# START DOCKER ENGINE
# -----------------------------------------------------------------------------
echo starting docker
systemctl start docker

# Consume staged IP override files (one-shot — deleted after use)
rm -rf /root/newipaddr
rm -rf /root/newcaddr


# =============================================================================
# CORE CONTAINERS — ALL NODES (primary and non-primary)
# =============================================================================

# Legacy web UI on node IP port 80 (serves git-based admin pages via /root/gitrepo)
docker run --rm --name software --hostname software \
    -v /etc/localtime:/etc/localtime:ro \
    -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
    -p $myhostip:80:80 \
    -v /root/gitrepo/httpd.conf:/usr/local/apache2/conf/httpd.conf \
    -v /root/gitrepo:/usr/local/apache2/htdocs/ \
    -itd moataznegm/quickstor:git

# Internal DNS server on bridge0 at fixed IP 10.11.12.7
echo starting intdns
docker run --rm --name intdns --hostname intdns \
    --net bridge0 --ip 10.11.12.7 \
    -e DNS_DOMAIN=qs.dom \
    -e DNS_IP=10.11.12.7 \
    -e LOG_QUERIES=true \
    -v /etc/localtime:/etc/localtime:ro \
    -v /root/gitrepo/dnshosts:/etc/hosts \
    -itd moataznegm/quickstor:dns

# Web terminal (Wetty) on node IP port 3000 — SSH proxy into this node
docker run -d --name wetty --rm \
    -p $mynodeip:3000:3000 \
    wettyoss/wetty --ssh-host=$mynodeip --ssh-user=root --base=/


# -----------------------------------------------------------------------------
# ETCD ROLE ASSIGNMENT
# Primary owns the cluster IP → etcd binds to it and acts as leader.
# Secondary uses its own node IP and fetches the current leader from etcd.
# -----------------------------------------------------------------------------
leaderip=$myclusterip
if [ $isprimary -eq 1 ];
then
    etcd=$myclusterip
    leader=$myhost
else
    etcd=$mynodeip
    leader=`/pace/etcdget.py $myclusterip leader`
fi

# Point resolv.conf at internal DNS before starting containers that need it
echo nameserver 10.11.12.7 >  /root/gitrepo/resolv.conf

# etcd key-value store (cluster-wide state: pools, volumes, nodes, leader)
echo starting etcd
docker run -itd --rm --name etcd --hostname etcd \
    --net bridge0 \
    -v /etc/localtime:/etc/localtime:ro \
    -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
    -p $etcd:2379:2379 \
    -v /TopStor/:/TopStor \
    -v /root/etcddata:/default.etcd \
    moataznegm/quickstor:etcd

# etcd client helper — used by /pace scripts for local etcd read/write ops
echo starting etcdclient
docker run -itd --rm --name etcdclient --hostname etcdclient \
    --net bridge0 \
    -v /etc/localtime:/etc/localtime:ro \
    -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
    -v /TopStor/:/TopStor \
    -v /pace/:/pace \
    moataznegm/quickstor:etcdclient

# EXIT POINT: fresh secondary that joined via clusterstub (isconf_prim=nono).
# It has no cluster IP yet — the primary will configure it via etcd sync.
if [[ $isconf_prim == 'nono' ]];
then
    exit
fi


# -----------------------------------------------------------------------------
# CLUSTER TOPOLOGY REGISTRATION
# Register this node's IP/port assignments into the cluster
# -----------------------------------------------------------------------------
echo /TopStor/setipports.sh $myclusterip $leader $myhost sync
/TopStor/setipports.sh $myclusterip $leader $myhost sync


# =============================================================================
# CONTAINERS FOR ALL NON-nono NODES (primary + joining secondaries)
# =============================================================================

# Samba (internal SMB — bridge0, privileged for kernel-level mount support)
echo starting intstub
docker run -itd --rm --privileged \
    --net bridge0 \
    --name intsmb --hostname intsmb \
    -v /TopStor/smb.conf:/etc/samba/smb.conf:rw \
    -v /etc/:/hostetc/ \
    -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
    -v /var/lib/samba/private:/var/lib/samba/private:rw \
    -v /TopStor/smbuser.sh:/root/smbuser.sh \
    moataznegm/quickstor:smb
docker exec intsmb sh /hostetc/VolumeCIFSupdate.sh

# RabbitMQ runs on the host via systemctl (not containerized).
# Disabled containerized RabbitMQ kept below for reference:
#docker run -d --rm --name rmq --hostname rmq \
#    -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
#    --net bridge0 -p $etcd:5672:5672 \
#    -v /TopStor/:/TopStor -v /pace/:/pace moataznegm/quickstor:rabbitmq
echo starting rabbitmq
systemctl start rabbitmq-server &
systemctl is-active rabbitmq-server
while [ $? -ne 0 ];
do
    sleep 1
    echo checking rabbitmq again
    systemctl is-active rabbitmq-server
done
rabbitmqctl add_user rabb_Mezo YousefNadody 2>/dev/null
rabbitmqctl set_permissions -p / rabb_Mezo ".*" ".*" ".*" 2>/dev/null


# =============================================================================
# CLUSTER INITIALIZATION LOOP
#
# Phase 1: Wait for etcd to signal readiness.
# Phase 2: Register this node and sync pool/volume state with the cluster.
#          Loop exits when local etcdclient confirms leaderip == myclusterip.
#
# The "echo hihi$checkcluster | grep $myclusterip" pattern:
#   - Prepending "hihi" prevents matching when checkcluster is '0' (initial value)
#   - When checkcluster becomes the actual cluster IP, the grep matches → exit loop
# =============================================================================

# Phase 1: Wait for etcd to be ready
started=0
while [ $started -eq 0 ];
do
    echo waiting etcd to settle
    docker logs etcd | grep 'successfully notified init daemon'
    if [ $? -eq 0 ];
    then
        started=1
    else
        sleep 1
    fi
done

# Phase 2: Node registration and sync loop
echo starting > /root/dockerlogs.txt
checkcluster='0'
echo hihi$checkcluster | grep $myclusterip
while [ $? -ne 0 ];
do
    sleep 1
    docker exec etcdclient /pace/etcdputlocal.py clusternodeip $mynodeip
    docker exec etcdclient /pace/etcdputlocal.py clusternode $myhost

    if [ $isprimary -eq 1 ];
    then
        # PRIMARY: seed the cluster-wide etcd keys for the first time
        echo initializing etcd params
        echo docker exec etcdclient /pace/etcdput.py $myclusterip clusternode $myhost
        echo isprimary $isprimary >> /root/dockerlogs.txt
        /TopStor/etcdput.py $myclusterip ActivePartners/$myhost $mynodeip
        /TopStor/etcdput.py $myclusterip leaderip $myclusterip
        echo docker exec  etcdclient /TopStor/etcdput.py $myclusterip leaderip $myclusterip >> /root/dockerlogs.txt
        /TopStor/etcdput.py $myclusterip leader $myhost
        /TopStor/etcdput.py $myclusterip nextlead/er 'None'
        etcdip=$myculsterip   # Note: intentional typo preserved — variable unused downstream

    else
        # SECONDARY: register as "possible" member and wait for leader to promote us
        echo waiting for me to join the cluster
        echo isprimaryin0 $isprimary >> /root/dockerlogs.txt
        /pace/etcdget.py $myclusterip Active --prefix | grep $myhost
        if [ $? -ne 0 ];
        then
            /TopStor/etcdput.py $myclusterip possible/$myhost $mynodeip
            echo I joined the cluster
        fi

        # Spin until the leader removes us from "possible" (promotes to Active)
        stillpossible=1
        while [ $stillpossible -eq 1 ];
        do
            /TopStor/etcdget.py possible --prefix | grep $myhost
            if [ $? -ne 0 ];
            then
                stillpossible=0
            else
                sleep 2
                echo waiting for me to join the cluster
            fi
        done
        etcdip=$mynodeip
        stamp=`date +%s%N`
    fi

    # Sync local etcd shadow with cluster-wide state
    echo initializaing volume pool leader clsuternode data
    myalias=`docker exec etcdclient /pace/etcdgetlocal.py $aliast/$myhost`
    leader=`/pace/etcdget.py $myclusterip leader`
    docker exec etcdclient /pace/etcdputlocal.py leader $leader
    docker exec etcdclient /pace/etcdputlocal.py leaderip $myclusterip
    docker exec etcdclient /pace/etcdputlocal.py clusternode $myhost
    docker exec etcdclient /pace/etcddellocal.py sync/Snapperiod/initial $myhost request/$myhost 2>/dev/null
    docker exec etcdclient /pace/etcddellocal.py pool --prefix 2>/dev/null
    docker exec etcdclient /pace/etcddellocal.py volume --prefix 2>/dev/null
    docker exec etcdclient /pace/etcddellocal.py sync/pool Add_ 2>/dev/null
    docker exec etcdclient /pace/etcddellocal.py sync/pool Del_ 2>/dev/null
    docker exec etcdclient /pace/etcddellocal.py sync/volume Add_ 2>/dev/null
    docker exec etcdclient /pace/etcddellocal.py sync/volume Del_ 2>/dev/null
    /pace/etcdput.py $myclusterip $aliast/$myhost $myalias

    #/TopStor/syncq.py $myclusterip $myhost 2>/root/syncqerror
    stamp=`date +%s%N`
    myalias=`echo $myalias | sed 's/\_/\:\:\:/g'`
    /pace/etcddel.py $myclusterip sync/$aliast/Add_${myhost} --prefix

    if [ $isprimary -ne 0 ];
    then
        /pace/etcddel.py $myclusterip ready --prefix
        /pace/etcddel.py $myclusterip sync/ready/Add --prefix
    else
        /pace/etcddel.py $mynodeip ready --prefix
        /TopStor/activepoolsync.py
    fi

    # Publish alias sync request to the cluster
    /pace/etcdput.py $myclusterip sync/$aliast/Add_${myhost}_$myalias/request ${aliast}_$stamp.
    /pace/etcdput.py $myclusterip sync/$aliast/Add_${myhost}_$myalias/request/$myhost ${aliast}_$stamp.
    /pace/etcdput.py $myclusterip sync/$aliast/Add_${myhost}_$myalias/request/$leader ${aliast}_$stamp.

    # Decide between full sync (syncall) and incremental (syncrequest)
    issync=`/pace/etcdget.py $myclusterip sync initial`initial
    /pace/checksyncs.py restetcd $myclusterip $myhost >/dev/null
    echo $issync | grep $myhost
    if [ $? -eq 0 ];
    then
        echo syncrequests only
        echo row 262 checksync init >> /root/checksync
        /pace/checksyncs.py syncrequest $myclusterip $myhost $myip >/dev/null & disown
    else
        echo have to syncall
        echo row 266 checksync init >> /root/checksync
        /pace/checksyncs.py syncall $myclusterip $myhost $myip >/dev/null & disown
    fi

    checkcluster=`docker exec etcdclient /TopStor/etcdgetlocal.py leaderip`
    echo $checkcluster >> /root/dockerlogs.txt
    echo hihi$checkcluster | grep $myclusterip
done


# =============================================================================
# POST-SYNC: NODE REGISTRATION AND STATE CLEANUP
# Runs after the cluster init loop confirms this node is synced.
# =============================================================================

# Clear stale cluster-wide pool/volume keys and re-register this node
/TopStor/etcddel.py $etcd pools --prefix
/TopStor/etcddel.py $etcd sync/pools --prefix
/TopStor/etcddel.py $etcd volume --prefix
/TopStor/etcddel.py $etcd sync/volume --prefix
/TopStor/etcdput.py $etcd mynodeip $mynodeip
/TopStor/etcdput.py $etcd mynode $myhost
/TopStor/etcdput.py $etcd leaderip $myclusterip
/TopStor/etcdput.py $etcd isprimary $isprimary
/TopStor/putEthernetPorts.py $myclusterip $leader $myhost

# On factory reset (nodestatus=reset) AND primary: initialize the admin user once
# Pattern "reset1" = nodestatus=="reset" concatenated with isprimary==1
isreset=`cat /root/nodestatus`
echo ${isreset}$isprimary | grep reset1
if [ $? -eq 0 ];
then
    echo initializing admin user
    docker exec etcdclient /TopStor/UnixsetUser.py $myclusterip `hostname` admin tmatem
    /TopStor/UnixAddGroup $etcd Everyone usersNoUser admin
    echo runningnode > /root/nodestatus
fi

# Primary seeds all sync-init entries for the cluster
#rm -rf /TopStor/key/adminfixed.gpg && cp /TopStor/factory/factoryadmin /TopStor/key/adminfixed.gpg
if [ $isprimary -eq 1 ];
then
    echo adding all sync inits as I am primary
    echo docker exec etcdclient /pace/checksyncs.py syncinit $etcd
    echo row 293 checksync init >> /root/checksync
    /pace/checksyncs.py syncinit $etcd $myhost >/dev/null & disown
fi

/TopStor/etcdput.py $etcd ready/$myhost $mynodeip


# -----------------------------------------------------------------------------
# HTTPD CONFIG PREPARATION
# Build the live httpd.conf from the template by substituting MYCLUSTER
# with the actual cluster IP. Kill any stale web/API containers first.
# -----------------------------------------------------------------------------
templhttp='/TopStor/httpd_template.conf'
rm -rf /TopStordata/httpd.conf
cp /TopStor/httpd.conf /TopStordata/
shttpdf='/TopStordata/httpd.conf'
docker rm -f httpd 2>/dev/null
docker rm -f flask 2>/dev/null
docker rm -f react-dev-ui 2>/dev/null
rm -rf $httpdf

/TopStor/ioperf.py $etcd $myhost >/dev/null & disown


# -----------------------------------------------------------------------------
# CLUSTER-WIDE READY AND ACTIVE-PARTNERS REGISTRATION
# Publishes this node's readiness and sync requests to the cluster.
# -----------------------------------------------------------------------------
echo docker exec etcdclient /TopStor/etcdput.py $myclusterip ready/$myhost $mynodeip
/TopStor/etcdput.py $myclusterip ready/$myhost $mynodeip
/pace/diskref.sh $leader $myclusterip $myhost $mynodeip
/TopStor/etcdput.py $myclusterip ActivePartners/$myhost $mynodeip
stamp=`date +%s%N`
/pace/etcddel.py $myclusterip sync/ready/Add_${myhost} --prefix
/pace/etcddel.py $myclusterip sync/ActivePartners/Add_${myhost} --prefix
/TopStor/etcdput.py $myclusterip sync/ready/Add_${myhost}_$mynodeip/request ready_$stamp
/TopStor/etcdput.py $myclusterip sync/ready/Add_${myhost}_$mynodeip/request/$leader ready_$stamp
/TopStor/etcdput.py $myclusterip sync/ActivePartners/Add_${myhost}_$mynodeip/request/$leader ready_$stamp
/TopStor/etcdput.py $myclusterip sync/ActivePartners/Add_${myhost}_$mynodeip/request ActivePartners_$stamp

echo running iscsi watchdog daemon
/TopStor/etcddel.py $myclusterip rebootme $myhost

if [ $isprimary -ne 0 ];
then
    # Primary: clear sync-ready queue and stale cluster list entries
    /pace/etcddel.py $myclusterip sync/ready/Add_${myhost} --prefix
    /pace/etcddel.py $myclusterip pools --prefix
    /pace/etcddel.py $myclusterip hosts --prefix
    /pace/etcddel.py $myclusterip vol  --prefix
    /pace/etcddel.py $myclusterip list --prefix
else
    # Secondary: nominate self as next-leader candidate
    /TopStor/etcddel.py $etcd rebootme $myhost
    /TopStor/etcdput.py $myclusterip nextlead/er $myhost
    /TopStor/etcddel.py $myclusterip sync/nextlead/Add_er_ --prefix
    /TopStor/etcdput.py $myclusterip sync/nextlead/Add_er_${myhost}/request nextlead_$stamp
    /TopStor/etcdput.py $myclusterip sync/nextlead/Add_er_${myhost}/request/$leader nextlead_$stamp
fi

# Disabled diskref sync (now handled elsewhere):
#/TopStor/etcddel.py $myclusterip sync/diskref --prefix
#/TopStor/etcdput.py $myclusterip sync/diskref/add_add_add______/request diskref_$stamp
#/pace/diskref.sh $leader $myclusterip $myhost $mynodeip >/dev/null & disown


# -----------------------------------------------------------------------------
# VERSION CHECK AND REPO SYNC
# Secondary: if its version differs from leader's, pull the correct branch.
# Primary: push current git branch to the shared repo.
# -----------------------------------------------------------------------------
if [ $isprimary -ne 1 ];
then
    leaderversion=`/TopStor/etcdget.py $myclusterip cversion/$leader | awk -F'-' '{print $1}'`
    myversion=`/TopStor/etcdget.py $myclusterip cversion/$myhost | awk -F'-' '{print $1}'`
    echo c$leaderversion | grep c$myversion
    if [ $? -ne 0 ];
    then
        /TopStor/myrepopull.sh $leaderversion
    fi
else
    BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
    /TopStor/myrepopush.sh $BRANCH_NAME & disown
fi

echo I a hhhhhhhhhhhhhhhhhhhhhhhhere

# Disabled: conditional sync (currently runs unconditionally below)
#if [ $isprimary -ne 0 ];
#then
/pace/checksyncs.py syncrequest $myclusterip $myhost >/dev/null & disown
# Disabled diskref sync:
#/TopStor/etcddel.py $myclusterip sync/diskref --prefix
#/TopStor/etcdput.py $myclusterip sync/diskref/add_add_add______/request diskref_$stamp
#fi

/TopStor/etcdput.py $etcd refreshdisown/$myhost yes
/TopStor/refreshdisown.sh > /dev/null & disown

# Disabled: alternate diskref background path
#/pace/diskref.sh $leader $leaderip $myhost $myhostip & disown

# Background daemons (all nodes)
/pace/rebootmeplslooper.sh $myclusterip $myhost >/dev/null & disown
#/TopStor/receivereplylooper.sh & disown
#/TopStor/iscsiwatchdoglooper.sh $mynodeip $myhost & disown
/pace/heartbeatlooper.sh >/dev/null & disown
#/pace/updateconfiglooper.sh $myclusterip $myhost & disown

stamp=`date +%s%N`
/TopStor/etcddel.py $myclusterip rebootwait/$myhost
/TopStor/etcddel.py $myclusterip sync/ready $myhost
/TopStor/etcdput.py $myclusterip ready/$myhost $mynodeip

# Secondary: sync ready and Active state from cluster to local etcd
if [ $isprimary -ne 1 ];
then
    /TopStor/etcdput.py $mynodeip ready/$myhost $mynodeip 2>/dev/null
    /pace/etcdsync.py $myclusterip $mynodeip ready ready 2>/dev/null
    /pace/etcdsync.py $myclusterip $mynodeip Active Active 2>/dev/null
fi

/TopStor/etcdput.py $myclusterip sync/ready/Add_${myhost}_$mynodeip/request ready_$stamp
/TopStor/etcdput.py $myclusterip sync/ready/Add_${myhost}_$mynodeip/request/$leader ready_$stamp

# Disabled initial disk change trigger (now handled by disk-change daemon):
#/pace/diskchange.sh add initial disk >/dev/null & disown

# Restore Grafana DB from known-good copy and start cluster version tracking
rm -rf /promgraf/grafana.db
cp /TopStor/grafana.db /promgraf/
echo /TopStor/getcversion.sh $myclusterip $leader $myhost >/dev/null & disown
/TopStor/getcversion.sh $myclusterip $leader $myhost >/dev/null & disown


# =============================================================================
# PRIMARY-ONLY CONTAINERS
# Only the primary node serves the web UI, API, and Prometheus stack.
# =============================================================================
if [ $isprimary -ne 0 ];
then
    echo I am hhhhhhhhhhhhhhhhhhhhhhinnhgjjjjhhhhhhhhhhhhhere

    # Render httpd.conf from template: substitute MYCLUSTER → actual cluster IP
    cp $templhttp $shttpdf
    sed -i "s/MYCLUSTERH/$myclusterip/g" $shttpdf
    sed -i "s/MYCLUSTER/$myclusterip/g" $shttpdf

    # Build React UI into /topstorweb/build_react (Vite outDir from vite.config.js).
    # Mount only the output dir — the image supplies its own React source via COPY,
    # so the legacy /topstorweb content does not overwrite the build inputs.
    echo building React UI into /topstorweb/build_react
    mkdir -p /topstorweb/build_react
    docker run --rm \
        -v /topstorweb/build_react:/app/build_react \
        quickstor-ui:latest npm run build

    # Apache httpd: serves React on 443, legacy UI on 81, proxies netdata on 19999
    echo running httpd
    docker run --rm --name httpd --hostname shttpd \
        --net bridge0 \
        -v /etc/localtime:/etc/localtime:ro \
        -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
        -p $myclusterip:19999:19999 \
        -p $myclusterip:81:81 \
        -p $myclusterip:443:443 \
        -v $shttpdf:/usr/local/apache2/conf/httpd.conf \
        -v /root/topstorwebetc:/usr/local/apache2/topstorwebetc \
        -v /topstorweb:/usr/local/apache2/htdocs/ \
        -itd moataznegm/quickstor:git

    # Flask API backend on cluster IP port 5001
    docker run -itd --rm --name flask --hostname apisrv \
        --net bridge0 \
        -v /etc/localtime:/etc/localtime:ro \
        -v /pace/:/pace \
        -v /pacedata/:/pacedata/ \
        -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
        -p $myclusterip:5001:5001 \
        -v /TopStor/:/TopStor \
        -v /TopStordata/:/TopStordata \
        moataznegm/quickstor:flask3

    # Prometheus + Grafana stack (started via helper script)
    /TopStor/promserver.sh $myclusterip
fi


# -----------------------------------------------------------------------------
# FINAL NETWORK CONFIGURATION
# Apply DNS and bond failover settings after containers are up.
# -----------------------------------------------------------------------------
mydns=`/TopStor/etcdget.py $myclusterip dnsname/$myhost`
#nmcli conn modify cmynode ipv4.dns ''     # Disabled: explicit DNS clear before set
nmcli conn modify cmynode ipv4.dns $mydns
nmcli con modify cmynode bond.options "mode=active-backup,miimon=100,fail_over_mac=1"
nmcli conn down cmynode && nmcli conn up cmynode


# =============================================================================
# PER-NODE MONITORING EXPORTERS (all nodes)
# =============================================================================

# Node exporter: exposes host-level metrics (CPU, memory, disk, network)
docker rm -f promexport
docker run -d --name promexport \
    -p $mynodeip:9100:9100 \
    -v /proc:/proc \
    -v /sys:/sys \
    prom/node-exporter

# cAdvisor: exposes per-container resource metrics
docker rm -f promcadvisor
docker run \
    --volume=/:/rootfs:ro \
    --volume=/var/run:/var/run:ro \
    --volume=/sys:/sys:ro \
    --volume=/var/lib/docker/:/var/lib/docker:ro \
    --volume=/dev/disk/:/dev/disk:ro \
    --publish=$mynodeip:9101:8080 \
    --detach=true \
    --name=promcadvisor \
    --privileged \
    --device=/dev/kmsg \
    gcr.io/cadvisor/cadvisor

# Register this node's port assignments and start the API poller daemon
/TopStor/registerports.sh $myclusterip
/pace/fapilooper.sh & disown
