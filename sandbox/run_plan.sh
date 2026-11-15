#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}" # usa el daemon con data-root en la SD (ver scripts/docker-sandbox.sh)
# Recorre sandbox/plan.csv y ejecuta cada corrida con run_experiment.sh.
# Uso: ./run_plan.sh [--limit N] [--arch T|C0] [--loss N] [--devices N] [--from N] [--to N] [--pilot] [--dry-run] [--yes]
set -euo pipefail
cd "$(dirname "$0")"

LIMITE=0
FILTRO_ARQ=""
FILTRO_PERDIDA=""
FILTRO_DISP=""
DESDE=""
HASTA=""
PILOTO=0
DRY=0
CONFIRMAR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMITE="$2"; shift 2 ;;
    --arch) FILTRO_ARQ="$2"; shift 2 ;;
    --loss) FILTRO_PERDIDA="$2"; shift 2 ;;
    --devices) FILTRO_DISP="$2"; shift 2 ;;
    --from) DESDE="$2"; shift 2 ;;
    --to) HASTA="$2"; shift 2 ;;
    --pilot) PILOTO=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --yes) CONFIRMAR=1; shift ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "Opcion desconocida: $1" >&2; exit 2 ;;
  esac
done

PLAN_FILE="${PLAN_FILE:-plan.csv}"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "Falta $PLAN_FILE. Genera con: python3 orchestrator/make_plan.py --seed 20261101 --reps 15 --out $PLAN_FILE" >&2
  exit 1
fi

seleccion=()
while IFS=, read -r order block rep arch loss devices run_seed; do
  [[ "$order" == "order" ]] && continue
  [[ -n "$DESDE" && "$order" -lt "$DESDE" ]] && continue
  [[ -n "$HASTA" && "$order" -gt "$HASTA" ]] && continue
  [[ -n "$FILTRO_ARQ" && "$arch" != "$FILTRO_ARQ" ]] && continue
  [[ -n "$FILTRO_PERDIDA" && "$loss" != "$FILTRO_PERDIDA" ]] && continue
  [[ -n "$FILTRO_DISP" && "$devices" != "$FILTRO_DISP" ]] && continue
  seleccion+=("$order|$arch|$loss|$devices|$rep|$run_seed")
  if [[ "$LIMITE" -gt 0 && ${#seleccion[@]} -ge "$LIMITE" ]]; then break; fi
done < "$PLAN_FILE"

if [[ ${#seleccion[@]} -eq 0 ]]; then
  echo "No hay corridas que cumplan los filtros." >&2
  exit 1
fi

echo "Corridas seleccionadas: ${#seleccion[@]}"
if [[ ${#seleccion[@]} -gt 20 && "$CONFIRMAR" != "1" && "$DRY" != "1" ]]; then
  echo "Son mas de 20 corridas. Agrega --yes para ejecutarlas o usa --limit." >&2
  exit 1
fi

if [[ "$PILOTO" == "1" ]]; then
  export RUN_SECONDS="${RUN_SECONDS:-120}" WARMUP_S="${WARMUP_S:-15}" MEASURE_S="${MEASURE_S:-90}" DRAIN_S="${DRAIN_S:-30}"
  export OUTAGE_PLAN="${OUTAGE_PLAN:-40:15}"
fi

for fila in "${seleccion[@]}"; do
  IFS='|' read -r order arch loss devices rep run_seed <<< "$fila"
  # Salta corridas que ya tienen resumen (retomar un plan sin repetir trabajo).
  if compgen -G "results/resumen_${arch}-d${devices}-l${loss}-r${rep}-*.json" > /dev/null; then
    echo "[skip] orden=$order $arch perdida=$loss dispositivos=$devices rep=$rep: ya existe resumen"
    continue
  fi
  if [[ "$DRY" == "1" ]]; then
    echo "[dry-run] orden=$order $arch perdida=$loss dispositivos=$devices rep=$rep semilla=$run_seed"
    continue
  fi
  echo "===== orden $order: $arch perdida=$loss dispositivos=$devices rep=$rep ====="
  ./run_experiment.sh "$arch" "$loss" "$devices" "$rep" "$run_seed"
done
