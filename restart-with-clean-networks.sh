#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NETWORKS=("nextcloud-aio" "proxy")

echo "Stoppe alle Dienste, um Netzwerke zurückzusetzen..."
"${SCRIPT_DIR}/stop-all.sh" || true

for network in "${NETWORKS[@]}"; do
  if docker network inspect "$network" >/dev/null 2>&1; then
    echo "Entferne Netzwerk: $network"
    docker network rm "$network" >/dev/null || true
  fi
done

echo "Starte Dienste neu mit frisch angelegten Netzwerken..."
"${SCRIPT_DIR}/start-all.sh"
