#!/bin/bash
set -e

TARGET_IP="10.42.42.42"
TARGET_NET="10.8.0.0/24"

# Maximal 12 Versuche, jeweils 5 Sekunden Pause
for i in {1..12}; do
    if ping -c1 -W1 "$TARGET_IP" >/dev/null 2>&1; then
        /usr/sbin/ip route replace "$TARGET_NET" via "$TARGET_IP"
        exit 0
    fi
    sleep 5
done

echo "wireguard container at $TARGET_IP not reachable" >&2
exit 1
