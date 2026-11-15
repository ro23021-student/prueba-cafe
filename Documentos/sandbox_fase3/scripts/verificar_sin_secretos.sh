#!/usr/bin/env bash
# Verifica que el ZIP de entrega no contenga .env ni claves conocidas del entorno local.
# Uso: ./scripts/verificar_sin_secretos.sh [zip]
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="${1:-$(dirname "$RAIZ")/$(basename "$RAIZ").zip}"

if [[ ! -f "$ZIP" ]]; then
  echo "No existe $ZIP" >&2
  exit 1
fi

if unzip -l "$ZIP" | grep -qE '(^|/)\.env$'; then
  echo "ERROR: $ZIP contiene un .env" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unzip -q "$ZIP" -d "$tmp"

if [[ -f "$RAIZ/sandbox/.env" ]]; then
  while IFS='=' read -r clave valor; do
    [[ -z "$clave" || "$clave" == \#* ]] && continue
    [[ "${clave,,}" == *pass* || "${clave,,}" == *secret* ]] || continue
    [[ -n "$valor" ]] || continue
    if grep -RqsF -- "$valor" "$tmp"; then
      echo "ERROR: el valor de $clave aparece en el ZIP." >&2
      exit 1
    fi
  done < "$RAIZ/sandbox/.env"
fi

echo "Verificacion OK: $ZIP no contiene .env ni valores secretos del entorno."
