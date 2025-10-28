#!/bin/bash

# This script reads bond config from etcd and writes it to /TopStordata/bondconfig.

if [ -z "$1" ]; then
    echo "Error: ETCD_IP argument is missing."
    exit 1
fi

ETCD_IP="$1"
CONFIG_FILE="/TopStordata/bondconfig"
ETCDGET_CMD="/TopStor/etcdget.py"

# Get values from etcd. Handle cases where the key might not exist.
NMPORTS=$($ETCDGET_CMD $ETCD_IP bond/nmports 2>/dev/null)
CMPORTS=$($ETCDGET_CMD $ETCD_IP bond/cmports 2>/dev/null)
DPORTS=$($ETCDGET_CMD $ETCD_IP bond/dports 2>/dev/null)

# Write the config file
(
    echo "NMPORTS_STR=\"$NMPORTS\""
    echo "CMPORTS_STR=\"$CMPORTS\""
    echo "DPORTS_STR=\"$DPORTS\""
) > $CONFIG_FILE

echo "Wrote bond config to $CONFIG_FILE"
