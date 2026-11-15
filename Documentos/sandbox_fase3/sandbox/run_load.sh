#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}" # usa el daemon con data-root en la SD (ver scripts/docker-sandbox.sh)
# Ejecuta una prueba de carga E1 con k6 contra T o C0.
# Uso: ./run_load.sh <T|C0> [VUs] [duracion] [run_id]
# Ejemplo reducido: ./run_load.sh T 50 60s
set -euo pipefail
cd "$(dirname "$0")"

while IFS='=' read -r clave valor; do
  [[ -z "$clave" || "$clave" == \#* ]] && continue
  if [[ -z "${!clave+x}" ]]; then export "$clave=$valor"; fi
done < .env

ARQ="${1:?Uso: run_load.sh <T|C0> [VUs] [duracion] [run_id]}"
VUS="${2:-${LOAD_VUS:-500}}"
DURACION="${3:-${LOAD_DURATION:-240s}}"
RUN_ID="${4:-${RUN_ID:-load-${ARQ}-${VUS}vus-$(date +%s)}}"
SUBIDA="${RAMP_UP:-30s}"
BAJADA="${RAMP_DOWN:-30s}"

case "$ARQ" in
  T)  PERFIL=treatment; HOST_API=api-rust ;;
  C0) PERFIL=control;   HOST_API=api-baseline ;;
  *) echo "Arquitectura invalida: $ARQ (use T o C0)" >&2; exit 2 ;;
esac

export ARCH="$ARQ" ARCH_HOST="$HOST_API" RUN_ID
COMPOSE=(docker compose --profile "$PERFIL")
LOG="results/log_load_${RUN_ID}.txt"
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

echo "[load] $RUN_ID | $ARQ | VUs=$VUS | duracion=$DURACION"
if [[ "${CLEAN:-1}" == "1" ]]; then limpiar; fi

"${COMPOSE[@]}" up -d --build
echo "[load] Esperando /health..."
for _ in $(seq 1 90); do
  if [[ "$(curl -fs "http://localhost:${API_PORT:-8080}/health" 2>/dev/null || true)" == "ok" ]]; then break; fi
  sleep 2
done
if [[ "$(curl -fs "http://localhost:${API_PORT:-8080}/health" 2>/dev/null || true)" != "ok" ]]; then
  echo "La API no respondio /health" >&2
  exit 1
fi

if [[ "$ARQ" == "T" ]]; then
  ./couchdb/create_users.sh
fi

INICIO=$(date +%s)
rm -f "$STOP" "$STATS"
( while [[ ! -f "$STOP" ]]; do docker stats --no-stream --format '{{json .}}' >> "$STATS" 2>/dev/null; sleep 2; done ) &
STATS_PID=$!
ARGS_K6=(run --out "csv=/results/k6_${RUN_ID}.csv" --summary-export="/results/resumen_k6_${RUN_ID}.json")
if [[ "${K6_STRICT:-0}" != "1" ]]; then
  ARGS_K6+=(--no-thresholds)   # en pilotos, un umbral incumplido no invalida la corrida
fi
set +e
docker compose --profile "$PERFIL" --profile load run --rm \
  -e TARGET="http://${HOST_API}:8080" \
  -e LOAD_PASS="$LOAD_PASS" \
  -e VUS="$VUS" -e DURATION="$DURACION" -e RAMP_UP="$SUBIDA" -e RAMP_DOWN="$BAJADA" \
  k6 "${ARGS_K6[@]}" /scripts/e1_stress.js 2>&1 | tee "$LOG"
CODIGO=${PIPESTATUS[0]}
set -e
detener_stats
FIN=$(date +%s)
python3 orchestrator/metricas_docker.py --archivo "$STATS" --run-id "$RUN_ID" --salida results || true

python3 orchestrator/recursos.py --inicio "$INICIO" --fin "$((FIN+30))" --run-id "$RUN_ID" --salida results || true
python3 orchestrator/metricas_proceso.py --inicio "$INICIO" --fin "$((FIN+30))" --run-id "$RUN_ID" --salida results || true
"${COMPOSE[@]}" --profile load logs --no-color > "results/logs_load_${RUN_ID}.txt" 2>&1 || true
limpiar

if [[ $CODIGO -ne 0 ]]; then
  echo "k6 termino con codigo $CODIGO. Revisa $LOG y results/resumen_k6_${RUN_ID}.json" >&2
  exit $CODIGO
fi
echo "[load] Listo: results/k6_${RUN_ID}.csv y results/resumen_k6_${RUN_ID}.json"
