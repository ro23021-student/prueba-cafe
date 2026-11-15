#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}"
# Crea usuarios directos de CouchDB con roles para probar el RBAC del motor.
# Uso (desde sandbox/): ./couchdb/create_users.sh
# Requiere el perfil treatment levantado y las variables COUCH_TEC_PASS, COUCH_PROD_PASS y COUCH_AUD_PASS.
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

for v in COUCH_TEC_PASS COUCH_PROD_PASS COUCH_AUD_PASS; do
  if [[ -z "${!v:-}" ]]; then
    echo "Falta $v en .env (ver .env.example)" >&2
    exit 1
  fi
done

CURL=(docker compose --profile treatment exec -T couchdb curl -sS -u "$COUCHDB_USER:$COUCHDB_PASSWORD" -H 'content-type: application/json')
BASE=http://localhost:5984

crear() {
  local nombre="$1" clave="$2" roles="$3"
  local id="org.couchdb.user:$nombre"
  local previo rev="" cuerpo respuesta codigo
  previo=$("${CURL[@]}" "$BASE/_users/$id" 2>/dev/null || true)
  rev=$(printf '%s' "$previo" | grep -o '"_rev":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  if [[ -n "$rev" ]]; then
    cuerpo=$(printf '{"_id":"%s","_rev":"%s","name":"%s","type":"user","roles":%s,"password":"%s"}' "$id" "$rev" "$nombre" "$roles" "$clave")
  else
    cuerpo=$(printf '{"_id":"%s","name":"%s","type":"user","roles":%s,"password":"%s"}' "$id" "$nombre" "$roles" "$clave")
  fi
  respuesta=$("${CURL[@]}" -w '\nHTTP:%{http_code}' -X PUT "$BASE/_users/$id" -d "$cuerpo")
  codigo=${respuesta##*HTTP:}
  case "$codigo" in
    201|202) echo "  OK  usuario CouchDB $nombre roles=$roles" ;;
    *) echo "  FALLA usuario $nombre (HTTP $codigo): ${respuesta%$'\n'HTTP:*}" >&2; exit 1 ;;
  esac
}

echo "Creando usuarios CouchDB de prueba de RBAC..."
crear tec-c1 "$COUCH_TEC_PASS" '["tecnico","coop-C1"]'
crear prod-1 "$COUCH_PROD_PASS" '["productor"]'
crear aud-1 "$COUCH_AUD_PASS" '["auditor"]'

# Refuerza _security desde la politica versionada (idempotente).
SEGURIDAD=$(cat ../backend-rust/src/infrastructure/politicas/security.json)
respuesta=$("${CURL[@]}" -w '\nHTTP:%{http_code}' -X PUT "$BASE/trazabilidad/_security" -d "$SEGURIDAD")
codigo=${respuesta##*HTTP:}
if [[ "$codigo" != "200" && "$codigo" != "201" ]]; then
  echo "FALLA al aplicar _security (HTTP $codigo): ${respuesta%$'\n'HTTP:*}" >&2
  exit 1
fi
echo "Usuarios CouchDB y _security listos."
