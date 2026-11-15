#!/usr/bin/env bash
# Retoma las corridas E2 pendientes de plan_5reps.csv tras un apagado.
# Omite las corridas que ya tienen resumen y repite solo las incompletas.
# Uso: ./retomar_plan.sh [--foreground]
set -euo pipefail
cd "$(dirname "$0")"

FOREGROUND=0
if [[ "${1:-}" == "--foreground" ]]; then FOREGROUND=1; fi

# Contexto Docker: usa el daemon de la SD si responde; si no, el principal.
if [[ -S /run/sandbox-docker.sock ]] && docker -H unix:///run/sandbox-docker.sock info >/dev/null 2>&1; then
  export DOCKER_CONTEXT=sandbox
else
  export DOCKER_CONTEXT=default
fi
echo "[retomar] DOCKER_CONTEXT=$DOCKER_CONTEXT"

# 1) Valida resumenes; aparta los corruptos para que se repitan.
mkdir -p results/corruptos
for f in results/resumen_*.json; do
  [[ -e "$f" ]] || continue
  if ! python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$f" >/dev/null 2>&1; then
    echo "[retomar] resumen corrupto, se aparta: $f"
    mv "$f" results/corruptos/
  fi
done

# 2) Limpia contenedores/volumenes y marcas .stop viejas.
docker compose --profile treatment --profile control --profile clients --profile load \
  down -v --remove-orphans >/dev/null 2>&1 || true
rm -f results/.stop_*

# 3) Relanza la misma secuencia de pases (las corridas ya hechas se omiten solas).
CMD='PLAN_FILE=plan_5reps.csv ./run_plan.sh --loss 30 --yes
PLAN_FILE=plan_5reps.csv ./run_plan.sh --loss 5 --yes
PLAN_FILE=plan_5reps.csv ./run_plan.sh --yes'
LOG="results/plan_e2_retoma_$(date +%Y%m%d_%H%M%S).log"

if [[ "$FOREGROUND" == "1" ]]; then
  echo "[retomar] ejecutando en primer plano; log: $LOG"
  systemd-inhibit --what=sleep:idle --who=experimento --why="corridas E2" \
    bash -c "$CMD" 2>&1 | tee -a "$LOG"
else
  nohup systemd-inhibit --what=sleep:idle --who=experimento --why="corridas E2" \
    bash -c "$CMD" >>"$LOG" 2>&1 &
  echo "[retomar] lanzado en segundo plano. PID=$!"
  echo "[retomar] log: $PWD/$LOG"
  echo "[retomar] para seguir el avance: tail -f '$LOG'"
fi
