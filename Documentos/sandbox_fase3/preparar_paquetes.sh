#!/usr/bin/env bash
# Prepara UN PAQUETE POR PERSONA (persona1.zip ... persona5.zip) con sus archivos y sus commits ya escritos.
# No modifica tu carpeta de trabajo: trabaja sobre una copia limpia.
#
# Uso:
#   1. Deja este archivo junto al README.md de la raiz del proyecto.
#   2. bash preparar_paquetes.sh
#   3. Entrega a cada persona su zip de ~/paquetes-equipo/ (persona1.zip ... persona5.zip).
set -euo pipefail

SRC="${SRC:-$HOME/Documentos/sandbox_fase3}"   # tu carpeta de trabajo (no se modifica)
OUT="${OUT:-$HOME/paquetes-equipo}"              # donde quedan los paquetes
AQUI="$(cd "$(dirname "$0")" && pwd)"
STAGE="$OUT/_base"

[[ -d "$SRC/.git" ]] || { echo "No encuentro el repositorio en $SRC" >&2; exit 1; }
[[ ! -e "$OUT" ]] || { echo "Ya existe $OUT. Borralo o cambia OUT." >&2; exit 1; }

echo "== 1) Copia limpia del proyecto"
mkdir -p "$STAGE"
LISTA="$(mktemp)"; trap 'rm -f "$LISTA"' EXIT
git -C "$SRC" ls-files -co --exclude-standard \
  | grep -v -E '(^|/)(nohup\.out|.*\.(log|pid|patch|zip|docx|pdf|bak))$' \
  | grep -v -E '^scripts/docker-sandbox\.sh$' \
  | while IFS= read -r f; do [[ -f "$SRC/$f" ]] && printf '%s\n' "$f"; done > "$LISTA"
tar -C "$SRC" -cf - -T "$LISTA" | tar -C "$STAGE" -xf -
echo "   $(wc -l < "$LISTA") archivos"

echo "== 2) Contexto de Docker por defecto (para que funcione en cualquier equipo)"
grep -rIl 'DOCKER_CONTEXT:-sandbox' "$STAGE" 2>/dev/null | while IFS= read -r f; do
  sed -i -E 's/DOCKER_CONTEXT:-sandbox/DOCKER_CONTEXT:-default/; s/ *# usa el daemon con data-root en la SD.*$//' "$f"
done
if grep -rIq 'DOCKER_CONTEXT:-sandbox' "$STAGE"; then echo "Quedaron referencias a 'sandbox'." >&2; exit 1; fi
if [[ -f "$AQUI/README.md" ]]; then cp "$AQUI/README.md" "$STAGE/README.md"
else echo "   AVISO: no hay README.md junto al script."; fi

echo "== 3) Comprobando que no haya secretos"
[[ ! -e "$STAGE/sandbox/.env" ]] || { echo "ERROR: hay sandbox/.env" >&2; exit 1; }
if [[ -f "$SRC/sandbox/.env" ]]; then
  while IFS='=' read -r clave valor; do
    [[ "$clave" =~ (PASS|SECRET) && ${#valor} -ge 8 ]] || continue
    if grep -rIlF -- "$valor" "$STAGE" >/dev/null 2>&1; then echo "ERROR: $clave aparece en la copia." >&2; exit 1; fi
  done < "$SRC/sandbox/.env"
fi
echo "   sin secretos"

AREAS=("" "Backend en Rust" "Nucleo Dart y simulador de clientes" "App Flutter, control C0 y CI" \
       "Infraestructura del sandbox" "Orquestador, analisis y documentacion")
VERIF=("" \
 "cd backend-rust && cargo test" \
 "cd cliente/trazabilidad_core && dart pub get && dart test   (y lo mismo en client-sim)" \
 "cd backend-baseline && pip install -r requirements.txt && pytest tests" \
 "cd sandbox && docker compose config > /dev/null && echo compose valido" \
 "python3 -m pytest sandbox/orchestrator/tests")
declare -a COUNT=(0 0 0 0 0 0)
PK=0

empezar() {   # empezar <n>
  PK="$1"
  mkdir -p "$OUT/persona$PK"
  cat > "$OUT/persona$PK/commits.sh" <<'EOF'
#!/usr/bin/env bash
# Ejecutar en la RAIZ del repositorio clonado, despues de descomprimir el paquete aqui.
set -euo pipefail
[[ -d .git ]] || { echo "Ejecuta esto en la raiz del repositorio (donde esta la carpeta .git)." >&2; exit 1; }
[[ -n "$(git config user.name)" && -n "$(git config user.email)" ]] || {
  echo "Configura primero tu identidad:" >&2
  echo '  git config user.name  "Tu Nombre"' >&2
  echo '  git config user.email "correo-de-tu-cuenta-de-github@ejemplo.com"' >&2
  exit 1; }
echo "Commits como: $(git config user.name) <$(git config user.email)>"
EOF
}

cm() {        # cm "mensaje" ruta...   (copia las rutas al paquete y escribe el commit en commits.sh)
  local msg="$1"; shift
  local ex=() p
  for p in "$@"; do [[ -e "$STAGE/$p" ]] && ex+=("$p"); done
  [[ ${#ex[@]} -gt 0 ]] || { echo "   (sin archivos) $msg"; return; }
  for p in "${ex[@]}"; do
    mkdir -p "$OUT/persona$PK/$(dirname "$p")"
    cp -a "$STAGE/$p" "$OUT/persona$PK/$(dirname "$p")/"
  done
  {
    printf 'git add --'; printf " '%s'" "${ex[@]}"; printf '\n'
    printf 'git commit -q -m "%s" && echo "  OK: %s"\n\n' "$msg" "$msg"
  } >> "$OUT/persona$PK/commits.sh"
  COUNT[$PK]=$(( ${COUNT[$PK]} + 1 ))
}

echo "== 4) Armando los paquetes"
# ---------- Persona 1 ----------
empezar 1
cm "chore: estructura inicial del repositorio, .gitignore, .dockerignore y README general" .gitignore .dockerignore README.md
cm "build(backend): proyecto Rust, dependencias y Dockerfile" backend-rust/Cargo.toml backend-rust/Cargo.lock backend-rust/Dockerfile
cm "feat(domain): evento de lote, sesion y errores de dominio" backend-rust/src/domain
cm "feat(application): puertos, casos de uso y autenticacion" backend-rust/src/application
cm "feat(infrastructure): repositorio CouchDB con Reqwest y Mango, JWT, telemetria y politicas RBAC" backend-rust/src/infrastructure backend-rust/src/config.rs
cm "feat(interface): API REST con Axum, middleware de sesion y arranque" backend-rust/src/interface backend-rust/src/lib.rs backend-rust/src/main.rs
cm "test(backend): pruebas de integracion de la pasarela y de las metricas" backend-rust/tests
# ---------- Persona 2 ----------
empezar 2
cm "feat(cliente-core): modelo de evento y cliente HTTP con JWT" cliente/trazabilidad_core/lib/src/evento_lote.dart cliente/trazabilidad_core/lib/src/api_cliente.dart
cm "feat(cliente-core): cola local cifrada AES-256-GCM y motor de sincronizacion offline-first" cliente/trazabilidad_core/lib cliente/trazabilidad_core/pubspec.yaml cliente/trazabilidad_core/pubspec.lock cliente/trazabilidad_core/analysis_options.yaml
cm "test(cliente-core): pruebas del almacen cifrado, la API y la sincronizacion" cliente/trazabilidad_core/test
cm "feat(client-sim): simulador de dispositivos Dart con red degradada para el escenario E2" client-sim/bin client-sim/lib client-sim/pubspec.yaml client-sim/pubspec.lock client-sim/analysis_options.yaml client-sim/Dockerfile client-sim/README.md
cm "test(client-sim): pruebas de configuracion, metricas y simulacion" client-sim/test
# ---------- Persona 3 ----------
empezar 3
cm "feat(app): estado global, boveda de claves y ajustes" cliente/trazabilidad_app/lib/main.dart cliente/trazabilidad_app/lib/estado_app.dart cliente/trazabilidad_app/lib/boveda.dart cliente/trazabilidad_app/lib/ajustes.dart cliente/trazabilidad_app/pubspec.yaml cliente/trazabilidad_app/pubspec.lock cliente/trazabilidad_app/analysis_options.yaml
cm "feat(app): pantallas de inicio, registro, lotes y sincronizacion" cliente/trazabilidad_app/lib/pantallas
cm "docs(app): guia de uso de la app y firma de depuracion para CI" cliente/trazabilidad_app/README.md cliente/trazabilidad_app/ci
cm "feat(control): monolito Flask + PostgreSQL (C0) con el mismo contrato REST" backend-baseline/app.py backend-baseline/gunicorn.conf.py backend-baseline/requirements.txt backend-baseline/Dockerfile backend-baseline/.dockerignore
cm "test(control): pruebas del monolito C0" backend-baseline/tests
cm "ci: flujos de calidad (Rust, Dart, Flutter), APK y client-sim" .github
# ---------- Persona 4 ----------
empezar 4
cm "feat(sandbox): docker-compose con perfiles treatment, control, clients y load" sandbox/docker-compose.yml sandbox/docker-compose.override.yml sandbox/.env.example
cm "feat(sandbox): configuracion de CouchDB, usuarios, semilla, indices y prueba de RBAC" sandbox/couchdb
cm "feat(sandbox): emulacion de red con tc/netem y cortes de conexion" sandbox/netem
cm "feat(sandbox): prueba de carga E1 con k6 y telemetria con Prometheus" sandbox/k6 sandbox/prometheus
cm "test(sandbox): prueba de humo con login, RBAC e idempotencia" sandbox/smoke_test.sh
# ---------- Persona 5 ----------
empezar 5
cm "feat(orquestador): plan factorial aleatorizado, datos sinteticos y planes de corridas" sandbox/orchestrator/make_plan.py sandbox/orchestrator/seed_data.py sandbox/plan.csv sandbox/plan_5reps.csv sandbox/plan_reducido_nuevo.csv
cm "feat(orquestador): runners de corridas E2 y de carga E1, y reanudacion del plan" sandbox/run_experiment.sh sandbox/run_load.sh sandbox/run_plan.sh sandbox/retomar_plan.sh
cm "feat(metricas): recoleccion de recursos, proceso, docker y metricas estaticas" sandbox/orchestrator/recursos.py sandbox/orchestrator/metricas_docker.py sandbox/orchestrator/metricas_proceso.py sandbox/orchestrator/metricas_estaticas.py sandbox/orchestrator/tests
cm "feat(analisis): analisis estadistico de la Fase 5 y de E1" sandbox/orchestrator/analisis_estadistico.py sandbox/orchestrator/analisis_e1.py sandbox/orchestrator/exportar_fase5.py sandbox/orchestrator/redactar_fase5.py sandbox/orchestrator/requirements_analisis.txt
cm "chore(scripts): generacion del .env y verificacion de secretos" scripts
cm "docs: guia del sandbox, variables de entorno y ejecucion de experimentos" sandbox/README.md

echo "== 5) Comprobando que no quede ningun archivo sin asignar"
( cd "$STAGE" && find . -type f | sed 's|^\./||' | sort ) > "$OUT/_todos.txt"
( cd "$OUT" && for n in 1 2 3 4 5; do ( cd persona$n && find . -type f ! -name commits.sh ! -name LEEME.txt | sed 's|^\./||' ); done | sort -u ) > "$OUT/_asignados.txt"
SIN="$(comm -23 "$OUT/_todos.txt" "$OUT/_asignados.txt")"
if [[ -n "$SIN" ]]; then
  echo "   Archivos sin asignar (se anaden a la persona 5):"; echo "$SIN" | sed 's/^/     /'
  PK=5
  mapfile -t RESTO <<< "$SIN"
  cm "chore: archivos restantes del proyecto" "${RESTO[@]}"
else echo "   todo asignado"; fi

echo "== 6) Instrucciones y zips"
for n in 1 2 3 4 5; do
  D="$OUT/persona$n"
  cat >> "$D/commits.sh" <<'EOF'
echo
echo "Tus commits:"; git log --oneline --author="$(git config user.email)" | head -20
EOF
  if [[ $n == 1 ]]; then
    PASO_A="  A) Persona 1 (primera): crea en GitHub un repositorio VACIO (sin README ni .gitignore; publico, o anade al docente
     como colaborador) y despues:
        mkdir proyecto && cd proyecto && git init -b main
        git remote add origin <URL_DEL_REPOSITORIO_VACIO>"
    PASO_D="        git push -u origin main"
  else
    PASO_A="  A) Espera a que la persona 1 haya subido. Luego:
        git clone <URL_DEL_REPOSITORIO> proyecto && cd proyecto"
    PASO_D="        git pull --rebase origin main
        git push origin main"
  fi
  cat > "$D/LEEME.txt" <<EOF
PERSONA $n - ${AREAS[$n]}
=========================================================
Tienes ${COUNT[$n]} commits que subir. Este paquete trae tus archivos y el script que hace los commits.

ANTES DE EMPEZAR (una sola vez)
  1. Instala git y entra a tu cuenta de GitHub.
  2. Configura tu identidad con el MISMO correo de tu cuenta de GitHub (si no, no se te atribuyen los commits):
        git config --global user.name  "Tu Nombre"
        git config --global user.email "tu-correo-de-github@ejemplo.com"

ORDEN DE SUBIDA
  La persona 1 sube primero: crea el repositorio y deja la base (README, .gitignore, .dockerignore).
  Las demas suben despues, en cualquier orden.

PASOS
${PASO_A}
  B) Descomprime este paquete DENTRO de la carpeta del repositorio, de modo que las carpetas queden en la raiz:
        unzip -o ../persona$n.zip -d .
     (en Windows: extraer aqui, sobre la carpeta del repositorio)
  C) Ejecuta los commits:
        bash commits.sh
  D) Borra los archivos auxiliares y sube:
        rm commits.sh LEEME.txt
${PASO_D}
  E) Comprueba en GitHub que tus commits aparecen con tu cuenta.

VERIFICA TU PARTE (opcional, recomendado)
  ${VERIF[$n]}

NO SUBAS: sandbox/.env, sandbox/results/, target/, build/, .dart_tool/ ni otros proyectos.
EOF
  python3 -I - "$D" "$OUT/persona$n.zip" <<'PY'
import os, sys, zipfile
raiz, destino = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(destino, "w", zipfile.ZIP_DEFLATED) as z:
    for d, _, fs in os.walk(raiz):
        for f in sorted(fs):
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, raiz))
PY
done
rm -f "$OUT/_todos.txt" "$OUT/_asignados.txt"

echo; echo "== Listo. Entrega a cada persona su zip:"
for n in 1 2 3 4 5; do printf '   persona%s.zip  (%s commits, %s)  %s\n' "$n" "${COUNT[$n]}" "${AREAS[$n]}" "$(du -h "$OUT/persona$n.zip" | cut -f1)"; done
echo "   Carpeta: $OUT"
