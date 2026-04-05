#!/bin/bash
exec 3>&1
exec 1>&2
set -e

# /TopStor/reconcile_bonds.sh
# Description:
#   Reconciles bond interface assignments based on config in /TopStordata/bondconfig.
#   Hardware-aware: gracefully degrades if local NICs don't match cluster config.
#
# STDOUT: "<mynodedev> <myclusterdev> <data1dev> <data2dev>"

echo "[*] Reconciling bond assignments..." >&2

# --- Helpers ---

containsElement() {
    local match="$1"; shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

filter_local_ports() {
    local desired="$1"; shift
    local -a all=("$@") valid=()
    declare -A avail
    for p in "${all[@]}"; do avail["$p"]=1; done

    IFS='/' read -r -a desired_arr <<< "$desired"
    for p in "${desired_arr[@]}"; do
        if [[ -n "${avail[$p]}" ]]; then
            valid+=("$p")
        else
            echo "[!] Port '$p' not found on this node, ignoring." >&2
        fi
    done

    (IFS='/'; echo "${valid[*]}")
}

create_bond_if_valid() {
    local bond_name="$1" ports_str="$2"
    if [ -n "$ports_str" ]; then
        echo "[+] Creating $bond_name with: $ports_str" >&2
        /TopStor/create_bond.sh "$bond_name" "$ports_str"
        IFS='/' read -r -a ports <<< "$ports_str"
        for p in "${ports[@]}"; do ASSIGNED_PORTS_ARR+=("$p"); done
        #echo "$bond_name"
	return 0
    else
        echo "[!] $bond_name skipped: no valid NICs found." >&2
        return 1
    fi
}

# --- 1. Gather hardware ---
ALL_PORTS_ARR=($(/TopStor/listports.sh))
if [ ${#ALL_PORTS_ARR[@]} -eq 0 ]; then
    echo "[!!!] No physical NICs detected. Network setup aborted." >&2
    echo "bond0 bond0 bond0 bond0" >&3
    exit 0
fi
echo "[*] Available NICs: ${ALL_PORTS_ARR[*]}" >&2

# --- 2. Load config ---
CONFIG_FILE="/TopStordata/bondconfig"
NMPORTS_STR=""; CMPORTS_STR=""; DPORTS_STR=""; IPORTS_STR=""

if [ -f "$CONFIG_FILE" ]; then
    echo "[*] Loading bond config from $CONFIG_FILE" >&2
    source "$CONFIG_FILE"
else
    echo "[!] No config file found, assuming empty config." >&2
fi

echo "[*] Desired config:" >&2
echo "    nmports: $NMPORTS_STR" >&2
echo "    cmports: $CMPORTS_STR" >&2
echo "    dports: $DPORTS_STR" >&2
echo "    iports: $IPORTS_STR" >&2

# --- 3. Handle all-empty ---
if [ -z "$NMPORTS_STR" ] && [ -z "$CMPORTS_STR" ] && [ -z "$DPORTS_STR" ] && [ -z "$IPORTS_STR" ]; then
    echo "[*] Empty config detected — using bond0 for all roles." >&2
    ALL_PORTS_STR=$(echo "${ALL_PORTS_ARR[*]}" | tr ' ' '/')
    /TopStor/create_bond.sh bond0 "$ALL_PORTS_STR"
    echo "bond0 bond0 bond0 bond0" >&3
    exit 0
fi

# --- 4. Apply custom config ---
echo "[!] Custom config detected, bringing down existing connections..." >&2
nmcli -t -f NAME conn show | grep -Ev '^(docker0|lo|br-)' | while read -r conn; do
    nmcli conn down "$conn" 2>/dev/null || true
done

NM_BOND="nm_bond"
CM_BOND="cm_bond"
D_BOND="d_bond"
I_BOND="ibond"
DEFAULT_BOND="bond0"
ASSIGNED_PORTS_ARR=()

# Filter ports against local hardware
NM_VALID=$(filter_local_ports "$NMPORTS_STR" "${ALL_PORTS_ARR[@]}")
CM_VALID=$(filter_local_ports "$CMPORTS_STR" "${ALL_PORTS_ARR[@]}")
D_VALID=$(filter_local_ports "$DPORTS_STR" "${ALL_PORTS_ARR[@]}")
I_VALID=$(filter_local_ports "$IPORTS_STR" "${ALL_PORTS_ARR[@]}")

# --- 5. Create bonds (with identical check) ---
mynodedev=""
myclusterdev=""
data1dev=""

if create_bond_if_valid "$NM_BOND" "$NM_VALID"; then
    mynodedev=$NM_BOND
fi

if [ -n "$CM_VALID" ] && [ "$CM_VALID" == "$NM_VALID" ] && [ -n "$mynodedev" ]; then
    echo "[*] cmports identical to nmports. Re-using $mynodedev." >&2
    myclusterdev=$mynodedev
elif create_bond_if_valid "$CM_BOND" "$CM_VALID"; then
    myclusterdev=$CM_BOND
fi

if [ -n "$D_VALID" ] && [ "$D_VALID" == "$NM_VALID" ] && [ -n "$mynodedev" ]; then
    echo "[*] dports identical to nmports. Re-using $mynodedev." >&2
    data1dev=$mynodedev
elif [ -n "$D_VALID" ] && [ "$D_VALID" == "$CM_VALID" ] && [ -n "$myclusterdev" ]; then
    echo "[*] dports identical to cmports. Re-using $myclusterdev." >&2
    data1dev=$myclusterdev
elif create_bond_if_valid "$D_BOND" "$D_VALID"; then
    data1dev=$D_BOND
fi

if create_bond_if_valid "$I_BOND" "$I_VALID"; then
    echo "[+] ibond created with ports: $I_VALID" >&2
fi

data2dev=$data1dev

# --- 6. Create default bond if free NICs remain ---
REMAINING_PORTS=()
for p in "${ALL_PORTS_ARR[@]}"; do
    if ! containsElement "$p" "${ASSIGNED_PORTS_ARR[@]}"; then
        REMAINING_PORTS+=("$p")
    fi
done

DEFAULT_BOND_CREATED=false
if [ ${#REMAINING_PORTS[@]} -gt 0 ]; then
    REMAINING_PORTS_STR=$(echo "${REMAINING_PORTS[*]}" | tr ' ' '/')
    echo "[+] Configuring $DEFAULT_BOND with remaining ports: $REMAINING_PORTS_STR" >&2
    /TopStor/create_bond.sh "$DEFAULT_BOND" "$REMAINING_PORTS_STR"
    DEFAULT_BOND_CREATED=true
else
    echo "[*] No remaining NICs for $DEFAULT_BOND." >&2
fi

# --- 7. Fallback assignments (Prioritized) ---
echo "[*] Assigning fallbacks for unconfigured/failed bonds..." >&2
FALLBACK_BOND=""

# Find the "best" bond to use as a fallback.
if [ -n "$mynodedev" ]; then FALLBACK_BOND=$mynodedev;
elif [ -n "$myclusterdev" ]; then FALLBACK_BOND=$myclusterdev;
elif [ -n "$data1dev" ]; then FALLBACK_BOND=$data1dev;
elif [ "$DEFAULT_BOND_CREATED" = true ]; then FALLBACK_BOND=$DEFAULT_BOND;
else
    # Last resort: find *any* bond that exists on the system
    FALLBACK_BOND=$(nmcli -t -f NAME,TYPE connection show | grep ':bond$' | cut -d':' -f1 | head -n 1)
    if [ -z "$FALLBACK_BOND" ]; then
        echo "[!!!] CRITICAL: No bonds could be created or found. Defaulting to '$DEFAULT_BOND'." >&2
        FALLBACK_BOND="$DEFAULT_BOND" # Use the name even if creation failed
    fi
fi

echo "[*] Using '$FALLBACK_BOND' as the primary fallback device." >&2

mynodedev=${mynodedev:-$FALLBACK_BOND}
myclusterdev=${myclusterdev:-$FALLBACK_BOND}
data1dev=${data1dev:-$FALLBACK_BOND}
data2dev=${data2dev:-$data1dev} # data2dev always mirrors data1

# --- 8. Cleanup ---
if ! $DEFAULT_BOND_CREATED && [ "$FALLBACK_BOND" != "$DEFAULT_BOND" ] && \
   nmcli -t -f NAME,TYPE connection show | grep -q "^${DEFAULT_BOND}:bond$"; then
    echo "[-] Deleting unused default bond0." >&2
    nmcli connection delete "$DEFAULT_BOND" 2>/dev/null || true
fi

# --- Done ---
echo "[✓] Network reconciliation complete." >&2
echo "    Node:    $mynodedev" >&2
echo "    Cluster: $myclusterdev" >&2
echo "    Data:    $data1dev" >&2

# Output final mapping
echo "$mynodedev $myclusterdev $data1dev $data2dev" >&3

