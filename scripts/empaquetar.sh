#!/usr/bin/env bash
# Crea el ZIP de entrega excluyendo secretos, historial de Git y artefactos de compilacion.
# Uso: ./scripts/empaquetar.sh [destino.zip]
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PADRE="$(dirname "$RAIZ")"
NOMBRE="$(basename "$RAIZ")"
DESTINO="${1:-$PADRE/$NOMBRE.zip}"

if [[ -f "$RAIZ/sandbox/.env" ]]; then
  echo "Aviso: sandbox/.env existe y NO se incluira en el ZIP." >&2
fi

rm -f "$DESTINO"
cd "$PADRE"
zip -r -q "$DESTINO" "$NOMBRE" \
  -x "$NOMBRE/.git/*" \
  -x "$NOMBRE/sandbox/.env" \
  -x "$NOMBRE/**/target/*" \
  -x "$NOMBRE/**/build/*" \
  -x "$NOMBRE/**/.dart_tool/*" \
  -x "$NOMBRE/**/.pytest_cache/*" \
  -x "$NOMBRE/**/.flutter-plugins-dependencies" \
  -x "$NOMBRE/**/*.pyc" \
  -x "$NOMBRE/**/__pycache__/*"

echo "ZIP creado: $DESTINO"
if unzip -l "$DESTINO" | grep -qE '(^|/)\.env$'; then
  echo "ERROR: el ZIP contiene un archivo .env" >&2
  exit 1
fi
echo "Verificacion OK: el ZIP no contiene .env."
