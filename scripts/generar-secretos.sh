#!/usr/bin/env sh
# Rellena en .env los secretos que estén vacíos (APP_KEY, JWT_SECRET, claves de
# Reverb y contraseñas). No toca los valores que ya existan.
#   ./scripts/generar-secretos.sh
set -e

cd "$(dirname "$0")/.."

[ -f .env ] || cp .env.example .env

aleatorio() { openssl rand -hex "$1"; }

asignar() {
    clave="$1"; valor="$2"
    if grep -qE "^${clave}=$" .env; then
        # sed -i compatible con GNU y BSD
        sed -i.bak "s|^${clave}=$|${clave}=${valor}|" .env && rm -f .env.bak
        echo "  ${clave} generado"
    fi
}

echo "Generando secretos en .env..."
asignar APP_KEY "base64:$(openssl rand -base64 32)"
asignar JWT_SECRET "$(aleatorio 32)"
asignar DB_PASSWORD "$(aleatorio 16)"
asignar REDIS_PASSWORD "$(aleatorio 16)"
asignar REVERB_APP_KEY "$(aleatorio 10)"
asignar REVERB_APP_SECRET "$(aleatorio 20)"
asignar ADMIN_PASSWORD "$(aleatorio 6)"

echo "Listo. Contraseña del administrador inicial:"
grep "^ADMIN_PASSWORD=" .env
