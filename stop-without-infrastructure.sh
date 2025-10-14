#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILES=(
  "docker-compose.infrastructure.yaml"
  "docker-compose.portainer.yaml"
  "docker-compose.samba.yaml"
  "docker-compose.ncaio.yaml"
  "docker-compose.stirling.yaml"
)

NON_INFRA_SERVICES=(
  portainer
  db
  redis
  nextcloud
  backup
  ofelia
  samba
  cups
)

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
done

if [[ ${#NON_INFRA_SERVICES[@]} -eq 0 ]]; then
  echo "Keine Dienste außerhalb der Infrastruktur definiert." >&2
  exit 0
fi

echo "Stoppe Dienste (ohne Infrastruktur): ${NON_INFRA_SERVICES[*]}"
"${COMPOSE_COMMAND[@]}" \
  $(printf ' -f %q' "${COMPOSE_FILES[@]}") \
  stop "${NON_INFRA_SERVICES[@]}"

echo "Entferne gestoppte Container: ${NON_INFRA_SERVICES[*]}"
"${COMPOSE_COMMAND[@]}" \
  $(printf ' -f %q' "${COMPOSE_FILES[@]}") \
  rm -f "${NON_INFRA_SERVICES[@]}"
