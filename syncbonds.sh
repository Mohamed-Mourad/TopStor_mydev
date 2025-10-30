#!/bin/bash

# This script reads bond config from etcd and writes it to /TopStordata/bondconfig.
# It compares the new config with the old one.
#
# Exit Codes:
#   0: Success, no changes detected.
#   1: Failed to fetch data or missing IP.
#  10: Success, config was updated and reboot is required.

if [ -z "$1" ]; then
    echo "Error: ETCD_IP argument is missing." >&2
    exit 1
fi

ETCD_IP="$1"
CONFIG_FILE="/TopStordata/bondconfig"
NEW_CONFIG_FILE="/TopStordata/bondconfig.new" # Temporary file for comparison
ETCDGET_CMD="/TopStor/etcdget.py"

echo "[*] Fetching new bond config from etcd at $ETCD_IP..." >&2

# --- 1. Get values from etcd ---
NMPORTS=$($ETCDGET_CMD $ETCD_IP bond/nmports 2>/dev/null)
CMPORTS=$($ETCDGET_CMD $ETCD_IP bond/cmports 2>/dev/null)
DPORTS=$($ETCDGET_CMD $ETCD_IP bond/dports 2>/dev/null)


# --- 2. Write the new config to the temporary file ---
(
    echo "NMPORTS_STR=\"$NMPORTS\""
    echo "CMPORTS_STR=\"$CMPORTS\""
    echo "DPORTS_STR=\"$DPORTS\""
) > $NEW_CONFIG_FILE

echo "[*] New config fetched to $NEW_CONFIG_FILE" >&2

# --- 3. Check if current config exists ---
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[+] No current config found ($CONFIG_FILE). Applying new config." >&2
    mv "$NEW_CONFIG_FILE" "$CONFIG_FILE"
    exit 10
fi

# --- 4. Compare new config with current config ---
echo "[*] Comparing new config with current ($CONFIG_FILE)..." >&2
if diff -q "$CONFIG_FILE" "$NEW_CONFIG_FILE" >/dev/null; then
    echo "[*] Bond config is already up-to-date." >&2
    rm "$NEW_CONFIG_FILE"
    exit 0
else
    echo "[+] New bond config detected. Updating." >&2
    mv "$NEW_CONFIG_FILE" "$CONFIG_FILE"
    echo "[!] Config updated. Signaling for reboot." >&2
    exit 10
fi

