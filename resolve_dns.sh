#!/bin/bash

# Check if hostname argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <hostname>"
    echo "Example: $0 cifsd.test"
    exit 1
fi

hostname="$1"

# Run getent ahosts and extract the first IPv4 address
first_ipv4=$(getent ahosts "$hostname" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | awk '{print $1}')

# Check if we found an IPv4 address
if [ -z "$first_ipv4" ]; then
    echo "No IPv4 address found for $hostname"
    exit 1
fi

echo "$first_ipv4"
