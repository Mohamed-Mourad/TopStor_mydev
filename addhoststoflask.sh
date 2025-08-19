#!/bin/bash
set -e

leaderip="$1"

max_retries=5
retry_delay=10

for attempt in $(seq 1 "$max_retries"); do
    echo "Attempt $attempt of $max_retries..."

    hostname=$(/pace/etcdget.py "$leaderip" dnssearch --prefix | awk -F"'" '{print $4}')
    ip=$(/pace/etcdget.py "$leaderip" dnsname --prefix | awk -F"'" '{print $4}')

    if [[ -n "$hostname" && -n "$ip" ]]; then
        if ! grep -qE "^$ip[[:space:]]+$hostname([[:space:]]|$)" /etc/hosts; then
            tmpfile=$(mktemp)
            grep -vE "[[:space:]]$hostname([[:space:]]|$)" /etc/hosts > "$tmpfile" || true
            cat "$tmpfile" > /etc/hosts
            rm -f "$tmpfile"
            echo "$ip    $hostname" >> /etc/hosts
        fi
        exit 0
    else
        sleep "$retry_delay"
    fi
done

exit 1

