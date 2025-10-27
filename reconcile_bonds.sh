#!/bin/bash

#
# /TopStor/reconcile_bonds.sh
#
# Description:
#   Reconciles bond interface assignments based on config in etcd.
#   This script is intended to be called by docker_setup.sh.
#
# Arguments:
#   $1 (Cluster IP)
#   $2 (Hostname)
#   $3 (Node IP)
#
# Output (to STDOUT):
#   A single space-separated string:
#   "<mynodedev> <myclusterdev> <data1dev> <data2dev>"
#

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <myclusterip> <myhost> <mynodeip>" >&2
    echo "ERROR: Missing required arguments." >&2
    # Return default bonds on error to prevent setup failure
    echo "bond0 bond0 bond0 bond0"
    exit 1
fi

myclusterip=$1
myhost=$2
mynodeip=$3

# --- ENSURE ETCD HOST IS REACHABLE ---
echo "[*] Waiting for etcd host ($myclusterip) to be reachable..." >&2
ping -w 3 $myclusterip
while [ $? -ne 0 ];
do
        echo "    ... etcd host not reachable, retrying in 1s" >&2
        sleep 1
        ping -w 3 $myclusterip
done
echo "[*] Etcd host is reachable." >&2


# --- START RECONCILIATION LOGIC ---
echo "[*] Configured node. Reconciling bond assignments from etcd..." >&2

# Helper function to check if item is in array
# usage: containsElement "item" "${array[@]}"
containsElement () {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}


# 1. Get ALL available ports from hardware
ALL_PORTS_ARR=($(/TopStor/listports.sh))
echo "[*] All available ports on host: ${ALL_PORTS_ARR[*]}" >&2

# 2. Get desired config from etcd
NMPORTS_STR=$(/pace/etcdget.py $myclusterip bond/$myhost/nmports/$mynodeip)
CMPORTS_STR=$(/pace/etcdget.py $myclusterip bond/$myhost/cmports/$mynodeip)
DPORTS_STR=$(/pace/etcdget.py $myclusterip bond/$myhost/dports/$mynodeip)

echo "[*] Desired config from etcd:" >&2
echo "    nmports: $NMPORTS_STR" >&2
echo "    cmports: $CMPORTS_STR" >&2
echo "    dports: $DPORTS_STR" >&2

# 3. Handle etcdget failure
if [[ "$NMPORTS_STR" == "unreachable"* || "$NMPORTS_STR" == "not reachable"* ]]; then
    echo "[!] Failed to get nmports config from etcd. Assuming empty." >&2
    NMPORTS_STR=""
fi
if [[ "$CMPORTS_STR" == "unreachable"* || "$CMPORTS_STR" == "not reachable"* ]]; then
    echo "[!] Failed to get cmports config from etcd. Assuming empty." >&2
    CMPORTS_STR=""
fi
if [[ "$DPORTS_STR" == "unreachable"* || "$DPORTS_STR" == "not reachable"* ]]; then
    echo "[!] Failed to get dports config from etcd. Assuming empty." >&2
    DPORTS_STR=""
fi

# 4. Check for "All Empty" rule
if [ -z "$NMPORTS_STR" ] && [ -z "$CMPORTS_STR" ] && [ -z "$DPORTS_STR" ]; then
    echo "[*] All bond configs are empty. Using default bond0 for all." >&2
    
    mynodedev='bond0'
    myclusterdev='bond0'
    data1dev='bond0'
    data2dev='bond0'
else
    echo "[!] Custom config found. Taking down network connections..." >&2
    nmcli conn down mynode 2>/dev/null || true
    nmcli conn down mycluster 2>/dev/null || true
    nmcli conn down bond0 2>/dev/null || true
    nmcli conn down nm_bond 2>/dev/null || true
    nmcli conn down cm_bond 2>/dev/null || true
    nmcli conn down d_bond 2>/dev/null || true

    echo "[*] Custom bond config found. Applying..." >&2
 
    NM_BOND="nm_bond"
    CM_BOND="cm_bond"
    D_BOND="d_bond"
    DEFAULT_BOND="bond0"

    # Track all ports that get assigned to a *custom* bond
    ASSIGNED_PORTS_ARR=()

    # --- Process nmports ---
    if [ -n "$NMPORTS_STR" ]; then
        echo "[+] Configuring $NM_BOND with: $NMPORTS_STR" >&2
        /TopStor/create_bond.sh "$NM_BOND" "$NMPORTS_STR"
        mynodedev=$NM_BOND
        # Add to assigned list
        IFS=',' read -r -a ports <<< "$NMPORTS_STR"
        for port in "${ports[@]}"; do ASSIGNED_PORTS_ARR+=("$port"); done
    else
        mynodedev=$DEFAULT_BOND # Will use bond0 by default
    fi

    # --- Process cmports ---
    if [ -n "$CMPORTS_STR" ]; then
        if [ "$CMPORTS_STR" == "$NMPORTS_STR" ]; then
            echo "[*] cmports is same as nmports. Re-using $NM_BOND." >&2
            myclusterdev=$NM_BOND
        else
            echo "[+] Configuring $CM_BOND with: $CMPORTS_STR" >&2
            /TopStor/create_bond.sh "$CM_BOND" "$CMPORTS_STR"
            myclusterdev=$CM_BOND
            IFS=',' read -r -a ports <<< "$CMPORTS_STR"
            for port in "${ports[@]}"; do ASSIGNED_PORTS_ARR+=("$port"); done
        fi
    else
        myclusterdev=$DEFAULT_BOND # Will use bond0 by default
    fi

    # --- Process dports ---
    if [ -n "$DPORTS_STR" ]; then
        if [ "$DPORTS_STR" == "$NMPORTS_STR" ]; then
            echo "[*] dports is same as nmports. Re-using $NM_BOND." >&2
            data1dev=$NM_BOND
            data2dev=$NM_BOND
        elif [ "$DPORTS_STR" == "$CMPORTS_STR" ]; then
            echo "[*] dports is same as cmports. Re-using $CM_BOND." >&2
            data1dev=$CM_BOND
            data2dev=$CM_BOND
        else
            echo "[+] Configuring $D_BOND with: $DPORTS_STR" >&2
            /TopStor/create_bond.sh "$D_BOND" "$DPORTS_STR"
            data1dev=$D_BOND
            data2dev=$D_BOND
            IFS=',' read -r -a ports <<< "$DPORTS_STR"
            for port in "${ports[@]}"; do ASSIGNED_PORTS_ARR+=("$port"); done
        fi
    else
        data1dev=$DEFAULT_BOND # Will use bond0 by default
        data2dev=$DEFAULT_BOND
    fi

    # --- Process Remaining Ports ---
    REMAINING_PORTS_ARR=()
    for port in "${ALL_PORTS_ARR[@]}"; do
        if ! containsElement "$port" "${ASSIGNED_PORTS_ARR[@]}"; then
            REMAINING_PORTS_ARR+=("$port")
        fi
    done

    if [ ${#REMAINING_PORTS_ARR[@]} -eq 0 ]; then
        # SUB-RULE: No remaining ports.
        echo "[!] No remaining ports found." >&2
        # Find a fallback bond for any unassigned categories
        FALLBACK_BOND=""
        if [ -n "$NMPORTS_STR" ]; then FALLBACK_BOND=$NM_BOND;
        elif [ -n "$CMPORTS_STR" ]; then FALLBACK_BOND=$CM_BOND;
        elif [ -n "$DPORTS_STR" ]; then FALLBACK_BOND=$D_BOND;
        fi
    
        # Handle edge case where all ports are assigned but one of the configs was empty
        if [ -z "$FALLBACK_BOND" ]; then
             echo "[!] No fallback bond found, defaulting to nm_bond" >&2
             FALLBACK_BOND=$NM_BOND
        fi

        echo "[!] Using $FALLBACK_BOND as fallback for empty assignments." >&2
    
        if [ -z "$NMPORTS_STR" ]; then mynodedev=$FALLBACK_BOND; fi
        if [ -z "$CMPORTS_STR" ]; then myclusterdev=$FALLBACK_BOND; fi
        if [ -z "$DPORTS_STR" ]; then data1dev=$FALLBACK_BOND; data2dev=$FALLBACK_BOND; fi
    
        # Delete the default bond0 if it exists, it's not needed
        if nmcli -t -f NAME,TYPE connection show | grep -q "^${DEFAULT_BOND}:bond$"; then
            echo "[-] Deleting unused default $DEFAULT_BOND." >&2
            nmcli connection delete "$DEFAULT_BOND" 2>/dev/null || true
        fi
    else
        # SUB-RULE: Remaining ports exist.
        REMAINING_PORTS_STR=$(echo "${REMAINING_PORTS_ARR[*]}" | tr ' ' ',')
        echo "[+] Configuring $DEFAULT_BOND with all remaining ports: $REMAINING_PORTS_STR" >&2
        /TopStor/create_bond.sh "$DEFAULT_BOND" "$REMAINING_PORTS_STR"
        # Any var still set to DEFAULT_BOND ('bond0') is now correctly configured.
    fi
fi

echo "[✓] Network reconciliation complete." >&2
echo "    Node device:    $mynodedev" >&2
echo "    Cluster device: $myclusterdev" >&2
echo "    Data device:    $data1dev" >&2

# --- FINAL OUTPUT ---
# This is the *only* line that should print to STDOUT.
# It returns the determined values to the calling script.
echo "$mynodedev $myclusterdev $data1dev $data2dev"
