// =============================================================================
// Pipeline de la infraestructura de Buenaventura Reporta
//
//   Checkout → Build → Test → Docker Build → Delivery
//
// Este repositorio no tiene código propio que compilar: su "build" es la
// configuración de Docker Compose. El pipeline la valida y, en `main`, la
// instala en /opt/buenaventura y aplica los cambios en producción.
// =============================================================================
pipeline {
  agent any

  options {
    skipDefaultCheckout()
    disableConcurrentBuilds()
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 20, unit: 'MINUTES')
  }

  environment {
    APP_DIR = '/opt/buenaventura'
    COMPOSE = 'docker compose -f docker-compose.yml -f docker-compose.prod.yml'
    // Valores ficticios: solo sirven para validar la configuración en CI
    CI_ENV  = '.env.ci'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git log -1 --format="Commit %h · %an · %s"'
      }
    }

    stage('Build') {
      // Genera la configuración final (base + producción) y la guarda como artefacto
      steps {
        sh '''
          cat > "$CI_ENV" <<'EOF'
APP_URL=https://ci.invalid
APP_KEY=base64:Y2ljaWNpY2ljaWNpY2ljaWNpY2ljaWNpY2ljaWNpY2k=
JWT_SECRET=ci
DB_DATABASE=ci
DB_USERNAME=ci
DB_PASSWORD=ci
REDIS_PASSWORD=ci
REVERB_APP_KEY=ci
REVERB_APP_SECRET=ci
ADMIN_PASSWORD=ci
EOF
          $COMPOSE --env-file "$CI_ENV" config > compose-produccion.yml
          echo "Servicios: $($COMPOSE --env-file "$CI_ENV" config --services | tr '\\n' ' ')"
        '''
        archiveArtifacts artifacts: 'compose-produccion.yml', fingerprint: true
      }
    }

    stage('Test') {
      // Comprobaciones de la configuración de producción
      steps {
        sh '''
          set -e
          json=$($COMPOSE --env-file "$CI_ENV" config --format json)

          echo "1) La configuración de producción es válida"
          $COMPOSE --env-file "$CI_ENV" config --quiet

          echo "2) Ningún servicio publica puertos en el host (solo Caddy recibe tráfico)"
          if echo "$json" | grep -q '"published"'; then echo "FALLO: hay puertos publicados"; exit 1; fi

          echo "3) El frontend está conectado a la red edge de Caddy"
          $COMPOSE --env-file "$CI_ENV" config frontend | grep -qE '^      edge:'

          echo "4) La red interna (db y redis) no tiene salida a Internet"
          echo "$json" | grep -q '"internal": true'

          echo "5) Sin secretos en .env, Compose se niega a arrancar"
          grep -v '^APP_KEY=' "$CI_ENV" > .env.incompleto
          if $COMPOSE --env-file .env.incompleto config --quiet 2>/dev/null; then echo "FALLO: arrancaría sin APP_KEY"; exit 1; fi

          echo "6) Los scripts no tienen errores de sintaxis"
          for s in scripts/*.sh; do sh -n "$s"; done

          echo "Todas las comprobaciones pasaron"
        '''
      }
    }

    stage('Docker Build') {
      // La infra no construye imágenes propias: descarga las versiones vigentes
      // de las imágenes oficiales que usa (PostgreSQL y Redis)
      steps {
        sh '$COMPOSE --env-file "$CI_ENV" pull db redis'
      }
    }

    stage('Delivery') {
      when { branch 'main' }
      steps {
        lock('despliegue-produccion') {
          sh '''
            test -f "$APP_DIR/.env" || { echo "Falta $APP_DIR/.env en el servidor"; exit 1; }

            # Instala la configuración nueva (el .env del servidor no se toca)
            cp docker-compose.yml docker-compose.prod.yml "$APP_DIR"/
            mkdir -p "$APP_DIR/scripts"
            cp scripts/*.sh "$APP_DIR/scripts/"
            chmod +x "$APP_DIR"/scripts/*.sh

            cd "$APP_DIR"
            $COMPOSE config --quiet

            if ! docker image inspect buenaventura/api:latest buenaventura/frontend:latest >/dev/null 2>&1; then
              echo "Configuración instalada. Aún no existen las imágenes de la app:"
              echo "ejecuta los pipelines de la API y del frontend en main para el primer despliegue."
              exit 0
            fi

            # Solo recrea los servicios cuya configuración cambió
            $COMPOSE up -d --remove-orphans
            ./scripts/esperar-salud.sh backend 180
            ./scripts/esperar-salud.sh frontend 90
            $COMPOSE ps
          '''
        }
      }
    }
  }

  post {
    always {
      deleteDir()
    }
  }
}
