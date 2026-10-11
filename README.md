# Buenaventura Reporta · Infraestructura (Docker)

Orquestación con Docker Compose de la plataforma **Buenaventura Reporta**: 4 contenedores, 2 redes y 3 volúmenes.

```
                  Navegador  ──►  http://localhost:8080
                                       │
┌─ red publica ────────────────────────┼─────────────────────────────────────┐
│   ┌──────────────────────────────────▼───┐        ┌──────────────────────┐ │
│   │ frontend  (Nginx + React)            │ /api   │ backend              │ │
│   │  • SPA                               │───────►│  Nginx → PHP-FPM     │ │
│   │  • proxy /api, /storage              │/storage│  Reverb (WebSockets) │ │
│   │  • proxy /app (WebSocket)            │  /app  │  worker de colas     │ │
│   │  ÚNICO puerto publicado              │───────►│  :8000  :8080        │ │
│   └──────────────────────────────────────┘        └─────┬────────────────┘ │
└─────────────────────────────────────────────────────────┼──────────────────┘
┌─ red interna (internal: true, sin salida a Internet) ───┼──────────────────┐
│                      ┌──────────────────────┐   ┌───────┴──────────────┐   │
│                      │ db   PostgreSQL 17   │   │ redis   Redis 7      │   │
│                      │ volumen: pgdata      │   │ volumen: redisdata   │   │
│                      └──────────────────────┘   └──────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
```

| Servicio | Imagen | Función | Puerto | Volumen |
|---|---|---|---|---|
| `frontend` | `buenaventura/frontend` (Nginx 1.27) | App React y puerta de entrada (proxy de API, archivos y WebSocket) | **`${APP_PORT}` → 80** | — |
| `backend` | `buenaventura/api` (PHP 8.2-FPM) | API Laravel, Reverb (WebSockets) y worker de colas | interno 8000 / 8080 | `storage_public` |
| `db` | `postgres:17-alpine` | Base de datos | interno 5432 | `pgdata` |
| `redis` | `redis:7-alpine` | Caché, colas y eventos de tiempo real | interno 6379 | `redisdata` |

---

## 1. Requisitos

- **Docker Desktop** (Windows/macOS) o **Docker Engine + plugin Compose** (Linux), Compose v2 o superior.
- Unos 3 GB libres en disco y unos 2 GB de RAM para Docker.
- Los tres repositorios clonados **en la misma carpeta**:

```
Buenaventura/
├── Buenaventura-Reporta-API/     # backend (Laravel)
├── Buenaventura-Reporta/         # frontend (React)
└── Buenaventura-Reporta-Infra/   # este repositorio
```

```bash
git clone https://github.com/jav-19jm/Buenaventura-Reporta-API.git
git clone https://github.com/jav-19jm/Buenaventura-Reporta.git
git clone <url-del-repositorio-infra> Buenaventura-Reporta-Infra
```

---

## 2. Puesta en marcha (local)

Todos los comandos se ejecutan **dentro de `Buenaventura-Reporta-Infra/`**.

### 2.1 Variables de entorno

```bash
# Linux / macOS / Git Bash
cp .env.example .env
./scripts/generar-secretos.sh
```

```powershell
# Windows (PowerShell)
Copy-Item .env.example .env
powershell -ExecutionPolicy Bypass -File scripts\generar-secretos.ps1
```

El script rellena los secretos vacíos y muestra la contraseña del administrador inicial:
`APP_KEY`, `JWT_SECRET`, contraseñas de PostgreSQL y Redis, claves de Reverb y `ADMIN_PASSWORD`.
Revisa también `APP_PORT`, `APP_URL` y el correo.

> `APP_URL` debe ser **exactamente** la dirección que escribes en el navegador (por defecto `http://localhost:8080`). Se usa en los enlaces de los correos y en las URLs de las imágenes.

### 2.2 Construir y levantar

```bash
docker compose up -d --build
```

El primer arranque tarda unos minutos, porque compila las extensiones de PHP y el frontend.

**Qué pasa al arrancar:**
1. `db` y `redis` arrancan y pasan su *healthcheck*.
2. Luego arranca `backend`:
   - Aplica las migraciones.
   - Si la base está vacía, crea el catálogo (entidades, categorías, insignias) y el administrador definido en `ADMIN_EMAIL` / `ADMIN_PASSWORD`.
   - Optimiza Laravel e inicia Nginx, PHP-FPM, Reverb y el worker de colas.
3. Cuando el backend está *healthy*, arranca `frontend`.

### 2.3 Verificar

```bash
docker compose ps
```

Los 4 servicios deben aparecer como `running (healthy)`, y solo `frontend` publica un puerto.

```bash
curl http://localhost:8080/healthz              # frontend → "ok"
curl http://localhost:8080/api/prueba           # API a través del proxy
curl http://localhost:8080/api/report-categories
```

Abre **<http://localhost:8080>** e inicia sesión con `ADMIN_EMAIL` y la contraseña de `ADMIN_PASSWORD` del archivo `.env`.

### 2.4 Modo desarrollo (opcional)

Publica PostgreSQL y la API solo en `127.0.0.1` (para DBeaver o Postman) y activa `APP_DEBUG`:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

| Servicio | Dirección | Credenciales |
|---|---|---|
| PostgreSQL | `127.0.0.1:5433` | `DB_USERNAME` / `DB_PASSWORD` / `DB_DATABASE` del `.env` |
| API directa | `http://127.0.0.1:8000/api` | — |

---

## 3. Comandos útiles

### Estado y logs

```bash
docker compose ps                     # estado y salud de los servicios
docker compose logs -f backend        # logs del backend (Laravel, Nginx, Reverb, worker)
docker compose logs -f frontend       # accesos al proxy
docker compose logs --tail=50 db
docker stats                          # consumo de CPU y memoria por contenedor
```

### Entrar a un contenedor

```bash
docker compose exec backend sh                  # shell del backend
docker compose exec backend php artisan about   # resumen de Laravel (drivers, caché, colas)
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker compose exec redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning'
```

### Laravel dentro del contenedor

```bash
docker compose exec backend php artisan migrate:status
docker compose exec backend php artisan queue:failed           # trabajos fallidos de la cola
docker compose exec backend supervisorctl status               # php-fpm, nginx, reverb, queue
docker compose exec backend php artisan optimize:clear         # limpiar cachés de Laravel
```

### Pruebas automatizadas (92 pruebas del backend)

```bash
docker compose --profile test run --rm backend-test
```

Construye la etapa `test` del Dockerfile (con dependencias de desarrollo) y ejecuta PHPUnit con SQLite en memoria. No toca la base real.

### Reconstruir después de cambiar código

```bash
docker compose up -d --build backend     # solo el backend
docker compose up -d --build frontend    # solo el frontend
docker compose up -d --build             # todo
```

### Detener y limpiar

```bash
docker compose stop                      # detener sin borrar nada
docker compose down                      # eliminar contenedores y redes (los DATOS se conservan)
docker compose down -v                   # ⚠ también elimina los volúmenes: base de datos, Redis e imágenes subidas
docker image prune -f                    # borrar imágenes huérfanas de builds anteriores
```

---

## 4. Datos

### Respaldar y restaurar PostgreSQL

```bash
./scripts/respaldar-db.sh                                   # crea backups/buenaventura-<fecha>.sql
./scripts/restaurar-db.sh backups/buenaventura-<fecha>.sql  # aplica un respaldo
```

### Cargar los datos históricos de Supabase

El script `migracion-datos-supabase.sql` **reemplaza todos los datos** por los del respaldo de Supabase. Contiene datos personales, así que **no se versiona**.

```bash
./scripts/restaurar-db.sh ../migracion-datos-supabase.sql
```

En Windows sin Git Bash:

```powershell
Get-Content ..\migracion-datos-supabase.sql -Raw | docker compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker compose exec redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning FLUSHALL'
```

---

## 5. Tiempo real (WebSockets)

Laravel Reverb corre dentro del contenedor `backend` (puerto interno 8080). El navegador se conecta a `ws://localhost:8080/app/<REVERB_APP_KEY>`, es decir, al mismo host de la app, y el Nginx del frontend reenvía la conexión.

| Canal | Tipo | Evento | Uso |
|---|---|---|---|
| `usuario.{id}` | privado | `notificacion.creada` | Campana de notificaciones |
| `avisos` | público | `aviso.general` | Noticias y servicios nuevos (avisos masivos) |
| `reporte.{id}` | privado | `chat.actualizado` | Chat de seguimiento del reporte |

Los canales privados se autorizan con el token JWT en `POST /api/broadcasting/auth`. Los eventos se encolan en Redis y los envía el worker, así que no frenan las peticiones. Si el WebSocket se cae, el frontend sigue funcionando con consultas periódicas.

**Comprobar que funciona:**
1. Abre la app en dos navegadores distintos, por ejemplo el ciudadano en uno y el admin en otro.
2. Escribe en el chat de un reporte o publica una noticia: el otro lo recibe sin recargar.
3. En las herramientas de desarrollo (pestaña *Network* → *WS*) se ve la conexión `/app/...` abierta.

```bash
docker compose logs -f backend | grep -i reverb
```

---

## 6. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Bind for 0.0.0.0:8080 failed: port is already allocated` | Otro programa usa el puerto | Cambia `APP_PORT` (y `APP_URL`) en `.env` |
| `Falta APP_KEY en .env` (u otra variable) | `.env` incompleto | Ejecuta el script de secretos |
| `backend` queda `unhealthy` | Error al migrar o al conectar con db/redis | `docker compose logs backend` |
| Imágenes o enlaces de correo con la URL equivocada | `APP_URL` no coincide con la del navegador | Corrige `APP_URL` y `docker compose up -d backend` |
| `exec /usr/local/bin/entrypoint: no such file or directory` | El script quedó con finales de línea CRLF | `git config core.autocrlf input`, vuelve a clonar y reconstruye |
| El WebSocket no conecta | Clave distinta entre frontend y backend | Tras cambiar `REVERB_APP_KEY`, reconstruye el frontend: `docker compose up -d --build frontend` |
| Los correos no llegan | `MAIL_MAILER=log` (valor por defecto) | Aparecen en `docker compose logs backend`; para enviarlos usa SMTP |

---

## 7. Decisiones de diseño

- **Un solo puerto expuesto.** El frontend hace de *reverse proxy*. Navegador, API y WebSocket comparten el mismo origen, así que no hay CORS ni hay que recompilar el frontend por entorno.
- **Red `interna` aislada** (`internal: true`). PostgreSQL y Redis no tienen salida a Internet ni son alcanzables desde el frontend. El backend está en ambas redes, por lo que sí puede enviar correos.
- **Imágenes multi-etapa y livianas** (Alpine). El backend corre como `www-data`, sin root, y las imágenes no contienen secretos: todo entra por variables de entorno.
- **Healthchecks y `depends_on: service_healthy`.** Cada servicio arranca cuando sus dependencias están realmente listas.
- **Límites de memoria:** db 256 MB, redis 128 MB, backend 512 MB y frontend 64 MB, pensando en un servidor pequeño.
- **Redis con `noeviction`.** Nunca descarta datos por falta de memoria, porque la cola de trabajos vive ahí.
- **Siembra solo en base vacía.** Reiniciar un contenedor no revierte los cambios hechos desde el panel de administración.
