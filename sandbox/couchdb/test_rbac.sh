#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}"
# Prueba el RBAC directamente contra CouchDB con los usuarios creados por create_users.sh.
# Uso (desde sandbox/): ./couchdb/test_rbac.sh
set -euo pipefail

cd "$(dirname "$0")/.."
source .env
BASE=http://localhost:5984
DB=trazabilidad
CURL=(docker compose --profile treatment exec -T couchdb curl -sS -H 'content-type: application/json')

admin() { "${CURL[@]}" -u "$COUCHDB_USER:$COUCHDB_PASSWORD" "$@"; }
como()  { local u="$1" p="$2"; shift 2; "${CURL[@]}" -u "$u:$p" "$@"; }
estado() { local r="$1"; printf '%s' "$r" | tail -1; }
cuerpo() { local r="$1"; printf '%s' "$r" | sed '$d'; }

# Asegura la base y la politica.
admin -o /dev/null -X PUT "$BASE/$DB" || true
SEGURIDAD=$(cat ../backend-rust/src/infrastructure/politicas/security.json)
admin -o /dev/null -X PUT "$BASE/$DB/_security" -d "$SEGURIDAD" || true

fallos=0
comprobar() {
  local descripcion="$1" esperado="$2" obtenido="$3"
  if [[ "$obtenido" == "$esperado" ]]; then
    echo "  OK  $descripcion (HTTP $obtenido)"
  else
    echo "  FALLA $descripcion: esperaba $esperado, obtuvo $obtenido" >&2
    fallos=$((fallos+1))
  fi
}

ts=$(date +%s)
doc_c1="{\"_id\":\"RBAC-C1-$ts\",\"type\":\"evento_lote\",\"lote_id\":\"RBAC-C1-$ts\",\"cooperativa_id\":\"C1\",\"etapa\":\"recoleccion\",\"ts\":$ts,\"owner\":\"tec-c1\"}"
doc_c2="{\"_id\":\"RBAC-C2-$ts\",\"type\":\"evento_lote\",\"lote_id\":\"RBAC-C2-$ts\",\"cooperativa_id\":\"C2\",\"etapa\":\"recoleccion\",\"ts\":$((ts+1)),\"owner\":\"tec-c1\"}"
doc_prod="{\"_id\":\"RBAC-P-$ts\",\"type\":\"evento_lote\",\"lote_id\":\"RBAC-P-$ts\",\"cooperativa_id\":\"C1\",\"etapa\":\"recoleccion\",\"ts\":$((ts+2)),\"owner\":\"prod-1\"}"
doc_ajeno="{\"_id\":\"RBAC-A-$ts\",\"type\":\"evento_lote\",\"lote_id\":\"RBAC-A-$ts\",\"cooperativa_id\":\"C1\",\"etapa\":\"recoleccion\",\"ts\":$((ts+3)),\"owner\":\"otro\"}"

echo "RBAC directo en CouchDB"
comprobar "anonimo no entra" 401 "$(estado "$("${CURL[@]}" -o /dev/null -w '\n%{http_code}' "$BASE/$DB")")"
comprobar "auditor lee" 200 "$(estado "$(como aud-1 "$COUCH_AUD_PASS" -o /dev/null -w '\n%{http_code}' "$BASE/$DB")")"
comprobar "auditor no escribe" 403 "$(estado "$(como aud-1 "$COUCH_AUD_PASS" -o /dev/null -w '\n%{http_code}' -X POST "$BASE/$DB" -d "$doc_c1")")"
comprobar "tecnico C1 escribe C1" 201 "$(estado "$(como tec-c1 "$COUCH_TEC_PASS" -o /dev/null -w '\n%{http_code}' -X POST "$BASE/$DB" -d "$doc_c1")")"
comprobar "tecnico C1 no escribe C2" 403 "$(estado "$(como tec-c1 "$COUCH_TEC_PASS" -o /dev/null -w '\n%{http_code}' -X POST "$BASE/$DB" -d "$doc_c2")")"
comprobar "productor escribe lo propio" 201 "$(estado "$(como prod-1 "$COUCH_PROD_PASS" -o /dev/null -w '\n%{http_code}' -X POST "$BASE/$DB" -d "$doc_prod")")"
comprobar "productor no escribe lo ajeno" 403 "$(estado "$(como prod-1 "$COUCH_PROD_PASS" -o /dev/null -w '\n%{http_code}' -X POST "$BASE/$DB" -d "$doc_ajeno")")"

if [[ $fallos -ne 0 ]]; then
  echo "RBAC CouchDB: $fallos fallo(s)." >&2
  exit 1
fi
echo "RBAC CouchDB: todo correcto."
