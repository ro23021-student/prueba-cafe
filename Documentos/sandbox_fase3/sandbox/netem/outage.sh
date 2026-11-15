#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}"
# Uso: outage.sh <contenedor> <duracion_s>  -> corte total (100% perdida) y restauracion
set -euo pipefail
C="$1"; D="$2"
TC="docker run --rm --net=container:${C} --cap-add=NET_ADMIN nicolaka/netshoot tc"
$TC qdisc replace dev eth0 root netem loss 100%
date +%s.%N > "./results/outage_start_$(date +%s).txt"
sleep "$D"
$TC qdisc del dev eth0 root
date +%s.%N > "./results/outage_end_$(date +%s).txt"
