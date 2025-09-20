#!/bin/bash
set -e

leaderip="$1"
host_to_resolve="$2"

max_retries=5
retry_delay=3

orig_resolv=$(mktemp)
cp /etc/resolv.conf "$orig_resolv"

for attempt in $(seq 1 "$max_retries"); do
    ip=$(/pace/etcdget.py "$leaderip" dnsname --prefix | awk -F"'" '{print $4}')
    
    if [[ -n "$ip" ]]; then
        break
    fi

    if [[ "$attempt" -eq "$max_retries" ]]; then
        exit 1
    fi

    sleep "$retry_delay"
done

tmpresolv=$(mktemp)
{
    head -n1 "$orig_resolv"
    echo "nameserver $ip"
    tail -n +2 "$orig_resolv"
} > "$tmpresolv"
cp "$tmpresolv" /etc/resolv.conf
rm -f "$tmpresolv"

resolved_ip=$(getent ahosts "$host_to_resolve" | awk '/^[0-9]+\.[0-9]+\.[0-9]+/{print $1; exit}')

cp "$orig_resolv" /etc/resolv.conf
rm -f "$orig_resolv"

if [[ -n "$resolved_ip" ]]; then
    echo "$resolved_ip"
    exit 0
fi

exit 1