#!/bin/bash
set -e

# Usage: ./create_bond.sh [bond_name] [bond_ip]
BOND_NAME="${1:-bond0}"

# Check if bond already exists
if nmcli -t -f NAME,TYPE connection show | grep -q "^${BOND_NAME}:bond$"; then
    echo "[*] Bond '$BOND_NAME' already exists. Doing nothing."
    exit 0
fi

# Dynamically find NICs starting with enp
SLAVES=($(ip -o link show | grep -Po '(?<=^\d: )enp[^\:]+' | sort -u))

if [ ${#SLAVES[@]} -eq 0 ]; then
    echo "[!] No NICs found starting with 'enp'. Exiting."
    exit 1
fi

echo "[*] Creating bond interface: $BOND_NAME"
nmcli connection add type bond con-name "$BOND_NAME" ifname "$BOND_NAME" mode active-backup || true

echo "[*] Setting bond options"
nmcli connection modify "$BOND_NAME" bond.options "mode=active-backup,miimon=100,fail_over_mac=1"

echo "[*] Adding slave interfaces: ${SLAVES[*]}"
for nic in "${SLAVES[@]}"; do
    nmcli connection add type ethernet ifname "$nic" master "$BOND_NAME" || true
done

echo "[*] Assigning IP $BOND_IP to $BOND_NAME"
nmcli connection modify "$BOND_NAME" ipv4.method disabled

echo "[*] Activating bond"
nmcli connection up "$BOND_NAME"

echo "[✓] Bond $BOND_NAME created with slaves: ${SLAVES[*]}."

