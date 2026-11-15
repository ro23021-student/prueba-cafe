#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}"
# Uso: apply_netem.sh <contenedor> <perdida_%> [retardo_ms] [jitter_ms] [tasa]
#   ej: apply_netem.sh trazabilidad-sandbox-client-sim-1 15 50 10 2mbit
# Aplica tc netem sobre eth0 (egress) en el netns del contenedor. Ejecutarlo
# en el cliente Y en el servidor para degradar ambos sentidos.
set -euo pipefail
C="$1"; LOSS="${2:-0}"; DELAY="${3:-0}"; JIT="${4:-0}"; RATE="${5:-}"
TC="docker run --rm --net=container:${C} --cap-add=NET_ADMIN nicolaka/netshoot tc"
$TC qdisc del dev eth0 root 2>/dev/null || true
if [[ "$LOSS" == "0" && "$DELAY" == "0" && -z "$RATE" ]]; then echo "[netem] $C: sin degradacion"; exit 0; fi
ARGS="delay ${DELAY}ms ${JIT}ms loss ${LOSS}%"
[[ -n "$RATE" ]] && ARGS="$ARGS rate ${RATE}"
$TC qdisc add dev eth0 root netem $ARGS
echo "[netem] $C: $ARGS"
