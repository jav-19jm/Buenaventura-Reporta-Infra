#!/usr/bin/env sh
# Respaldo de PostgreSQL en backups/<fecha>.sql (formato SQL plano)
#   ./scripts/respaldar-db.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p backups

archivo="backups/buenaventura-$(date +%Y%m%d-%H%M%S).sql"
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean --if-exists' > "$archivo"
echo "Respaldo creado: $archivo"
