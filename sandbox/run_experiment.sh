#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}" # usa el daemon con data-root en la SD (ver scripts/docker-sandbox.sh)
# Ejecuta una corrida del escenario E2 con client-sim (T o C0).
# Uso: ./run_experiment.sh <T|C0> <perdida_%> <dispositivos> [rep] [semilla]
# Ejemplo piloto: RUN_SECONDS=120 WARMUP_S=15 MEASURE_S=90 DRAIN_S=30 OUTAGE_PLAN=40:15 \
#                 ./run_experiment.sh T 15 10 1 42
set -euo pipefail
cd "$(dirname "$0")"

# Carga .env sin pisar las variables que el usuario ya exporto.
while IFS='=' read -r clave valor; do
  [[ -z "$clave" || "$clave" == \#* ]] && continue
  if [[ -z "${!clave+x}" ]]; then export "$clave=$valor"; fi
done < .env

ARQ="${1:?Uso: run_experiment.sh <T|C0> <perdida_%> <dispositivos> [rep] [semilla]}"
PERDIDA="${2:?Falta la perdida de paquetes}"
DISPOSITIVOS="${3:?Falta el numero de dispositivos}"
REP="${4:-1}"
SEMILLA="${5:-${SEED:-1}}"

case "$ARQ" in
  T)  PERFIL=treatment; SERVICIO=api-rust;     HOST_API=api-rust ;;
  C0) PERFIL=control;   SERVICIO=api-baseline; HOST_API=api-baseline ;;
  *) echo "Arquitectura invalida: $ARQ (use T o C0)" >&2; exit 2 ;;
esac

RUN_ID="${RUN_ID:-${ARQ}-d${DISPOSITIVOS}-l${PERDIDA}-r${REP}-$(date +%s)}"
export ARCH="$ARQ" ARCH_HOST="$HOST_API" DEVICES="$DISPOSITIVOS" REP="$REP" SEED="$SEMILLA" RUN_ID
export RUN_SECONDS="${RUN_SECONDS:-300}" WARMUP_S="${WARMUP_S:-30}" MEASURE_S="${MEASURE_S:-240}" DRAIN_S="${DRAIN_S:-120}"
export OUTAGE_MODE="${OUTAGE_MODE:-self}"
export OUTAGE_PLAN="${OUTAGE_PLAN:-60:30,180:30}"

if [[ -z "${NETEM_BASE:-}" && "$PERDIDA" != "0" ]]; then
  export NETEM_BASE="delay 50ms 10ms loss ${PERDIDA}% rate 2mbit"
fi

COMPOSE=(docker compose --profile "$PERFIL")
COMPOSE_CLIENTES=(docker compose --profile "$PERFIL" --profile clients)
LOG="results/log_${RUN_ID}.txt"
mkdir -p results

limpiar() {
  if [[ "${CLEAN:-1}" == "1" ]]; then
    docker compose --profile treatment --profile control --profile clients --profile load \
      down -v --remove-orphans >/dev/null 2>&1 || true
  fi
}

STATS="results/docker_stats_${RUN_ID}.jsonl"
STOP="results/.stop_${RUN_ID}"
STATS_PID=""
detener_stats() {
  if [[ -n "$STATS_PID" ]]; then
    touch "$STOP"
    wait "$STATS_PID" 2>/dev/null || true
    STATS_PID=""
  fi
}
trap detener_stats EXIT

echo "[run] $RUN_ID | $ARQ | perdida=${PERDIDA}% | dispositivos=$DISPOSITIVOS | semilla=$SEMILLA"
echo "[run] duracion=${RUN_SECONDS}s calentamiento=${WARMUP_S}s medicion=${MEASURE_S}s drenaje=${DRAIN_S}s"
echo "[run] CPUSET=${CPUSET:-0-1} LOAD_CPUSET=${LOAD_CPUSET:-0-1} MEM_LIMIT=${MEM_LIMIT:-2g}"

if [[ "${CLEAN:-1}" == "1" ]]; then
  limpiar
fi

echo "[run] Levantando $PERFIL..."
"${COMPOSE[@]}" up -d --build

echo "[run] Esperando /health..."
for _ in $(seq 1 90); do
  if [[ "$(curl -fs "http://localhost:${API_PORT:-8080}/health" 2>/dev/null || true)" == "ok" ]]; then break; fi
  sleep 2
done
if [[ "$(curl -fs "http://localhost:${API_PORT:-8080}/health" 2>/dev/null || true)" != "ok" ]]; then
  echo "La API no respondio /health" >&2
  "${COMPOSE[@]}" logs --tail=200 >&2 || true
  exit 1
fi

if [[ "$ARQ" == "T" ]]; then
  echo "[run] Creando usuarios CouchDB y verificando RBAC..."
  ./couchdb/create_users.sh
  ./couchdb/test_rbac.sh
fi

echo "[run] Verificando login de simulacion..."
TOKEN=$(curl -fs -X POST "http://localhost:${API_PORT:-8080}/auth/login" \
  -H 'content-type: application/json' \
  -d "{\"user\":\"sim\",\"pass\":\"$SIM_PASS\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [[ -z "$TOKEN" ]]; then
  echo "No se pudo iniciar sesion con el usuario sim" >&2
  exit 1
fi

echo "[run] Ejecutando client-sim..."
rm -f "$STOP" "$STATS"
( while [[ ! -f "$STOP" ]]; do docker stats --no-stream --format '{{json .}}' >> "$STATS" 2>/dev/null; sleep 2; done ) &
STATS_PID=$!
set +e
"${COMPOSE_CLIENTES[@]}" run --rm --build client-sim 2>&1 | tee "$LOG"
CODIGO=${PIPESTATUS[0]}
set -e
detener_stats
python3 orchestrator/metricas_docker.py --archivo "$STATS" --run-id "$RUN_ID" --salida results || true
if [[ $CODIGO -ne 0 ]]; then
  echo "client-sim termino con codigo $CODIGO. Revisa $LOG" >&2
  "${COMPOSE_CLIENTES[@]}" logs --tail=200 >&2 || true
  exit $CODIGO
fi

RESUMEN="results/resumen_${RUN_ID}.json"
if [[ ! -f "$RESUMEN" ]]; then
  echo "No se genero $RESUMEN" >&2
  exit 1
fi

GENERADOS=$(python3 -c "import json;print(int(json.load(open('$RESUMEN'))['generados_total']))")
if [[ "$GENERADOS" -le 0 ]]; then
  echo "La corrida genero 0 documentos. Se marca invalida." >&2
  exit 3
fi

echo "[run] Recolectando CPU/RAM desde Prometheus..."
read -r INICIO FIN <<EOF
$(python3 - "$RESUMEN" "$RUN_SECONDS" "$DRAIN_S" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
inicio=int(r['t0_ms']//1000)
fin=inicio+int(sys.argv[2])+int(sys.argv[3])+60
print(inicio, fin)
PY
)
EOF
python3 orchestrator/recursos.py --inicio "$INICIO" --fin "$FIN" --run-id "$RUN_ID" --salida results || true
python3 orchestrator/metricas_proceso.py --inicio "$INICIO" --fin "$FIN" --run-id "$RUN_ID" --salida results || true

"${COMPOSE_CLIENTES[@]}" logs --no-color > "results/logs_${RUN_ID}.txt" 2>&1 || true
echo "[run] Listo: $RESUMEN, docs_${RUN_ID}.csv y recursos_${RUN_ID}.json"

limpiar
