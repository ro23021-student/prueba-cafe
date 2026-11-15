#!/usr/bin/env bash
# Ayudante para el segundo demonio de Docker (data-root en la SD), dedicado a sandbox_fase3.
#   ./docker-sandbox.sh up      -> monta la SD (si hace falta) y arranca containerd-sandbox + sandbox-docker
#   ./docker-sandbox.sh down    -> baja los contenedores del sandbox, para los demonios y desmonta la SD
#   ./docker-sandbox.sh status  -> estado de ambos
set -uo pipefail
MP="/media/antonio/SD_EXT4"
DH="unix:///run/sandbox-docker.sock"

case "${1:-status}" in
  up)
    if ! findmnt -rn "$MP" >/dev/null; then
      echo "[up] montando la SD..."
      sudo mount "$MP" || exit 1
    fi
    sudo systemctl start containerd-sandbox sandbox-docker || exit 1
    sleep 2
    docker -H "$DH" info 2>/dev/null | grep -m1 'Docker Root Dir' || echo "[up] no responde; ver journalctl -u sandbox-docker -n 30"
    ;;

  down)
    echo "[down] bajando contenedores del sandbox (si hubiere)..."
    # compose necesita el compose file y el nombre de proyecto correcto
    ( cd "$(dirname "$0")/../sandbox" && DOCKER_CONTEXT=sandbox docker compose --profile treatment --profile control --profile clients --profile load down --remove-orphans 2>&1 | grep -v '^$' | sed 's/^/[down] /' ) || true
    sudo systemctl stop sandbox-docker containerd-sandbox
    if findmnt -rn "$MP" >/dev/null; then
      sudo umount "$MP" && echo "[down] SD desmontada: ya puedes extraerla"
    else
      echo "[down] la SD no estaba montada"
    fi
    echo "[down] demonio principal de docker sigue funcionando (dev-setup, etc.)"
    ;;

  status)
    findmnt -rn -o FSUSED "$MP" >/dev/null || true  # silencio
    findmnt -rn "$MP" >/dev/null && echo "[SD] montada en $MP" || echo "[SD] NO montada"
    systemctl is-active -q containerd-sandbox && echo "[containerd-sandbox] activo" || echo "[containerd-sandbox] parado"
    systemctl is-active -q sandbox-docker && echo "[sandbox-docker] activo" || echo "[sandbox-docker] parado"
    if systemctl is-active -q sandbox-docker; then
      docker -H "$DH" info 2>/dev/null | grep -m1 'Docker Root Dir'
      docker -H "$DH" ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | head -10
    fi
    systemctl is-active -q docker.service && echo "[docker principal] activo (dev-setup OK)" || echo "[docker principal] parado"
    ;;
  *)
    echo "Uso: $0 {up|down|status}"
    ;;
esac
