#!/usr/bin/env bash
set -euo pipefail

VPN_NET="10.8.0.0/24"
WG_CONTAINER="wireguard"
WG_CONTAINER_IP="10.42.42.42"

log() {
  echo "[wireguard-route] $1"
}

# warten bis Docker läuft
if ! command -v docker >/dev/null 2>&1; then
  log "docker not available"
  exit 1
fi

# prüfen ob Container läuft
if ! docker inspect -f '{{.State.Running}}' "$WG_CONTAINER" 2>/dev/null | grep -q true; then
  log "container '$WG_CONTAINER' not running"
  exit 0
fi

# Route setzen oder ersetzen (idempotent)
log "ensuring route ${VPN_NET} via ${WG_CONTAINER_IP}"
/usr/sbin/ip route replace "$VPN_NET" via "$WG_CONTAINER_IP"

log "done"
