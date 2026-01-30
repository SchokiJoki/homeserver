#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILES=(

  "docker-compose.infrastructure.yaml"
  "docker-compose.wg.yaml"
  "docker-compose.portainer.yaml"
  "docker-compose.samba.yaml"
  "docker-compose.ncaio.yaml"
  "docker-compose.stirling.yaml"
  "docker-compose.assistant.yaml"
  "docker-compose.passbolt.yaml"
  "docker-compose.authentik.yaml"
  "docker-compose.scrutiny.yaml"
  "docker-compose.paperless.yaml"
  "docker-compose.mail.yaml"
)

STATIC_IPV4_FILES=()
OTHER_FILES=()
REQUIRED_NETWORKS=("nextcloud-aio" "proxy")

if docker compose version >/dev/null 2>&1; then
  COMPOSE_COMMAND=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_COMMAND=(docker-compose)
else
  echo "Weder 'docker compose' noch 'docker-compose' ist verfügbar." >&2
  exit 1
fi

for file in "${COMPOSE_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Fehlende Compose-Datei: $file" >&2
    exit 1
  fi
  if grep -Eq 'ipv4_address|subnet' "$file"; then
    STATIC_IPV4_FILES+=("$file")
  else
    OTHER_FILES+=("$file")
  fi
done

COMPOSE_FILES=("${STATIC_IPV4_FILES[@]}" "${OTHER_FILES[@]}")

for network in "${REQUIRED_NETWORKS[@]}"; do
  if ! docker network inspect "$network" >/dev/null 2>&1; then
    echo "Erstelle fehlendes Docker-Netzwerk: $network"
    docker network create "$network" >/dev/null
  fi
done

echo "Starte alle Dienste aus: ${COMPOSE_FILES[*]}"
"${COMPOSE_COMMAND[@]}" \
  $(printf ' -f %q' "${COMPOSE_FILES[@]}") \
  up -d
