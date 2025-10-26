#!/bin/bash
set -e
cd /TopStor/

# Usage: ./create_bond.sh [bond_name] [ports_list]
# Example: ./create_bond.sh nm_bond "enp0s3,enp0s8"
# Example: ./create_bond.sh bond0

BOND_NAME="$1"
PORTS_STR="$2"

if [ -z "$BOND_NAME" ]; then
    echo "[!] No bond name provided. Exiting."
    exit 1
fi

# --- 1. Determine Target Slaves ---
declare -a DESIRED_SLAVES
if [ -n "$PORTS_STR" ]; then
    echo "[*] Using specified slaves: $PORTS_STR"
    IFS=',' read -r -a DESIRED_SLAVES <<< "$PORTS_STR"
else
    echo "[*] No slaves specified. Using default: all ports from listports.sh"
    DESIRED_SLAVES=($(/TopStor/listports.sh))
fi

if [ ${#DESIRED_SLAVES[@]} -eq 0 ]; then
    echo "[!] No slave ports provided or found for $BOND_NAME. Exiting."
    exit 1
fi

echo "[*] Reconciling bond '$BOND_NAME' with desired slaves: ${DESIRED_SLAVES[*]}"

# --- 2. Create bond if it doesn't exist ---
if ! nmcli -t -f NAME,TYPE connection show | grep -q "^${BOND_NAME}:bond$"; then
    echo "[+] Bond '$BOND_NAME' not found. Creating..."
    nmcli connection add type bond con-name "$BOND_NAME" ifname "$BOND_NAME" mode active-backup
    nmcli connection modify "$BOND_NAME" bond.options "mode=active-backup,miimon=100,fail_over_mac=1"
    nmcli connection modify "$BOND_NAME" ipv4.method disabled
    nmcli connection modify "$BOND_NAME" ipv6.method ignore
else
    echo "[*] Bond '$BOND_NAME' already exists."
fi

# --- 3. Get CURRENT slaves ---
# Use an associative array to map: [device_name]="connection_name"
declare -A CURRENT_SLAVES_MAP
while IFS=: read -r conn_name iface; do
    if [ -n "$iface" ] && [ "$iface" != "--" ]; then
        CURRENT_SLAVES_MAP["$iface"]="$conn_name"
    fi
done < <(nmcli -t -f NAME,DEVICE,MASTER connection show | grep ":${BOND_NAME}$" | cut -d: -f1,2)
echo "[*] Current slaves: ${!CURRENT_SLAVES_MAP[*]}"

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
        echo "[-] Removing slave: $nic (connection: $conn_to_delete)"
        nmcli connection delete "$conn_to_delete" || true
    fi
done

# --- 5. Add new slaves that are needed ---
for nic in "${!DESIRED_SLAVES_MAP[@]}"; do
    if [[ -z "${CURRENT_SLAVES_MAP[$nic]}" ]]; then
        # This NIC is desired, but not current. Add it.
        echo "[+] Adding new slave: $nic"
        
        # Delete any *other* connection for this NIC to avoid conflicts
        existing_conn=$(nmcli -t -f NAME,DEVICE connection show | grep ":${nic}$" | cut -d':' -f1 | head -n 1)
        if [ -n "$existing_conn" ]; then
            echo "[!] Warning: $nic is configured. Deleting old connection '$existing_conn'."
            nmcli connection delete "$existing_conn" || true
        fi
        
        # Add the new slave connection
        nmcli connection add type ethernet con-name "slave-$nic-to-$BOND_NAME" ifname "$nic" master "$BOND_NAME"
    fi
done

# --- 6. Activate bond ---
echo "[*] Activating bond '$BOND_NAME'..."
nmcli connection up "$BOND_NAME"

echo "[✓] Bond $BOND_NAME reconciled."
