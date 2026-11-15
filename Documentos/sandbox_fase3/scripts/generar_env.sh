#!/usr/bin/env bash
# Genera sandbox/.env a partir de sandbox/.env.example con secretos aleatorios.
# Uso: ./scripts/generar_env.sh [--force]
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
EJEMPLO="$RAIZ/sandbox/.env.example"
DESTINO="$RAIZ/sandbox/.env"

if [[ -f "$DESTINO" && "${1:-}" != "--force" ]]; then
  echo "Ya existe $DESTINO. Usa --force para sobrescribirlo." >&2
  exit 1
fi

if [[ ! -f "$EJEMPLO" ]]; then
  echo "Falta $EJEMPLO" >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

while IFS= read -r linea; do
  if [[ "$linea" == *=CAMBIAR_* ]]; then
    clave="${linea%%=*}"
    valor="$(openssl rand -hex 16)"
    if [[ "$clave" == "JWT_SECRET" ]]; then
      valor="$(openssl rand -hex 32)"
    fi
    printf '%s=%s\n' "$clave" "$valor" >> "$tmp"
  else
    printf '%s\n' "$linea" >> "$tmp"
  fi
done < "$EJEMPLO"

install -m 600 "$tmp" "$DESTINO"
echo "Escrito $DESTINO con secretos nuevos."
