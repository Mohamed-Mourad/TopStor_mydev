#!/bin/bash
set -e
cd /TopStor/
exec 3>&1
exec 1>&2

# Usage: ./create_bond.sh [bond_name] [ports_list]
# Example: ./create_bond.sh nm_bond "enp0s3,enp0s8"
# Example: ./create_bond.sh bond0

BOND_NAME="${1:-bond0}"
PORTS_STR="$2"

if [ -z "$BOND_NAME" ]; then
    echo "[!] No bond name provided. Exiting." >&2
    exit 1
fi

# --- 1. Determine Target Slaves ---
declare -a DESIRED_SLAVES
if [ -n "$PORTS_STR" ]; then
    echo "[*] Using specified slaves: $PORTS_STR" >&2
    IFS='/' read -r -a DESIRED_SLAVES <<< "$PORTS_STR"
else
    echo "[*] No slaves specified. Using default: all ports from listports.sh" >&2
    DESIRED_SLAVES=($(/TopStor/listports.sh))
fi

if [ ${#DESIRED_SLAVES[@]} -eq 0 ]; then
    echo "[!] No slave ports provided or found for $BOND_NAME. Exiting." >&2
    exit 1
fi

echo "[*] Reconciling bond '$BOND_NAME' with desired slaves: ${DESIRED_SLAVES[*]}" >&2

# --- 2. Create bond if it doesn't exist ---
if ! nmcli -t -f NAME,TYPE connection show | grep -q "^${BOND_NAME}:bond$"; then
    echo "[+] Bond $BOND_NAME not found. Creating..." >&2
    nmcli connection add type bond con-name "$BOND_NAME" ifname "$BOND_NAME" mode active-backup || true
    nmcli connection modify "$BOND_NAME" bond.options "mode=active-backup,miimon=100,fail_over_mac=1"
    nmcli connection modify "$BOND_NAME" ipv4.method disabled
    nmcli connection modify "$BOND_NAME" ipv6.method ignore
else
    echo "[*] Bond '$BOND_NAME' already exists." >&2
fi

# --- 3. Get CURRENT slaves ---
# Use an associative array to map: [device_name]="connection_name"
declare -A CURRENT_SLAVES_MAP

if [ -f "/sys/class/net/$BOND_NAME/bonding/slaves" ]; then
    CURRENT_SLAVES=($(cat /sys/class/net/$BOND_NAME/bonding/slaves))
else
    echo "[!] Bond interface $BOND_NAME does not exist or has no slaves file." >&2
    CURRENT_SLAVES=()
fi

for iface in "${CURRENT_SLAVES[@]}"; do
    CURRENT_SLAVES_MAP["$iface"]="slave-$iface-to-$BOND_NAME"
done

echo "[*] Current slaves: ${!CURRENT_SLAVES_MAP[*]}" >&2


# Create a map for desired slaves for easy lookup
declare -A DESIRED_SLAVES_MAP
for nic in "${DESIRED_SLAVES[@]}"; do
    DESIRED_SLAVES_MAP["$nic"]=1
done

# --- 4. Remove slaves that are no longer needed ---
for nic in "${!CURRENT_SLAVES_MAP[@]}"; do
    if [[ -z "${DESIRED_SLAVES_MAP[$nic]}" ]]; then
        # This NIC is current, but not desired. Remove it.
        conn_to_delete="${CURRENT_SLAVES_MAP[$nic]}"
        echo "[-] Removing slave: $nic (connection: $conn_to_delete)" >&2
        nmcli connection delete "$conn_to_delete" || true
    fi
done

# --- 5. Add new slaves that are needed ---
for nic in "${!DESIRED_SLAVES_MAP[@]}"; do
    if [[ -z "${CURRENT_SLAVES_MAP[$nic]}" ]]; then
        # This NIC is desired, but not current. Add it.
        echo "[+] Adding new slave: $nic" >&2
        
        # Delete any *other* connection for this NIC to avoid conflicts
        #existing_conn=$(nmcli -t -f NAME,DEVICE connection show | grep ":${nic}$" | cut -d':' -f1 | head -n 1)
        #if [ -n "$existing_conn" ]; then
        #    echo "[!] Warning: $nic is configured. Deleting old connection '$existing_conn'." >&2
        #    nmcli connection delete "$existing_conn" || true
        #fi

	# Delete any connection objects that claim this nic as DEVICE (active)...
	nmcli -t -f NAME,DEVICE connection show | awk -F: -v nic="$nic" '$2==nic {print $1}' | while read -r c; do
	    echo "[!] Deleting existing connection for $nic (by DEVICE): $c" >&2
	    nmcli connection delete "$c" || true
	done
	
	nmcli -t -f NAME connection show | grep -E "^slave-${nic}-to-" | while read -r c; do
	    echo "[!] Deleting existing slave-* connection for $nic (by NAME): $c" >&2
	    nmcli connection delete "$c" || true
	done
        
        # Add the new slave connection
        nmcli connection add type ethernet con-name "slave-$nic-to-$BOND_NAME" ifname "$nic" master "$BOND_NAME"
    fi
done

# --- 6. Activate bond ---
echo "[*] Activating bond '$BOND_NAME'..." >&2
nmcli connection up "$BOND_NAME"

echo "[✓] Bond $BOND_NAME reconciled." >&2
