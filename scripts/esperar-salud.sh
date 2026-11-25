#!/usr/bin/env sh
# Espera a que un servicio de producción quede "healthy" (lo usan los pipelines).
#   ./scripts/esperar-salud.sh <servicio> [segundos]
# Sale con 0 si queda healthy y con 1 si queda unhealthy o se agota el tiempo.
set -u
cd "$(dirname "$0")/.."

servicio="$1"
limite="${2:-120}"
compose="docker compose -f docker-compose.yml -f docker-compose.prod.yml"
t=0

while [ "$t" -lt "$limite" ]; do
  id=$($compose ps -q "$servicio" 2>/dev/null)
  if [ -n "$id" ]; then
    estado=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id")
    case "$estado" in
      healthy)   echo "$servicio: healthy (${t}s)"; exit 0 ;;
      unhealthy) echo "$servicio: unhealthy"; exit 1 ;;
    esac
    echo "$servicio: $estado (${t}s)..."
  else
    echo "$servicio: aún sin contenedor (${t}s)..."
  fi
  sleep 5
  t=$((t + 5))
done

echo "$servicio no quedó healthy en ${limite}s"
exit 1
