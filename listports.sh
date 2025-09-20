#!/bin/bash
# This checks if the interface has a device directory in /sys/class/net/
for iface in $(ls /sys/class/net/); do
    if [ -d "/sys/class/net/$iface/device" ] && [ "$iface" != "lo" ]; then
        echo "$iface"
    fi
done
