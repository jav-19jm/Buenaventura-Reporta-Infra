#!/usr/bin/env sh
# Ejecuta un archivo .sql contra la base del contenedor (respaldo o migración de datos)
#   ./scripts/restaurar-db.sh backups/buenaventura-20261010-120000.sql
#   ./scripts/restaurar-db.sh ../migracion-datos-supabase.sql
set -e
cd "$(dirname "$0")/.."

if [ -z "$1" ] || [ ! -f "$1" ]; then
    echo "Uso: $0 <archivo.sql>" >&2
    exit 1
fi

docker compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$1"
# Las cachés pueden tener datos del estado anterior
docker compose exec -T redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning FLUSHALL' >/dev/null
echo "Archivo aplicado: $1"
