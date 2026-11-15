#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}" # usa el daemon con data-root en la SD (ver scripts/docker-sandbox.sh)
# Prueba de humo del sandbox. Uso:  ./smoke_test.sh            (perfil treatment, Rust + CouchDB)
#                                   PROFILE=control ./smoke_test.sh   (C0: monolito + PostgreSQL)
# Requiere: docker compose, curl, .env creado a partir de .env.example
set -uo pipefail
source .env
PROFILE=${PROFILE:-treatment}
API=http://localhost:8080
DC="docker compose --profile $PROFILE"
ok(){ echo "  OK  $1"; }; fail(){ echo "  FALLA  $1"; exit 1; }
for v in LOAD_PASS AUDIT_PASS PROD_PASS SIM_PASS; do [[ -n "${!v:-}" ]] || fail "falta $v en .env (ver .env.example)"; done
J='content-type: application/json'
login(){ curl -s -X POST $API/auth/login -H "$J" -d "{\"user\":\"$1\",\"pass\":\"$2\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'; }

echo "0) Esperando a la API (hasta 60 s)"
for i in $(seq 1 30); do [[ "$(curl -fs $API/health 2>/dev/null)" == "ok" ]] && break; sleep 2; done
echo "1) API viva";                [[ "$(curl -fs $API/health 2>/dev/null)" == "ok" ]] && ok "/health" || fail "/health"
echo "2) Sin token (401)";         c=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/v1/eventos -H "$J" -d '{"lote_id":"X"}'); [[ $c == 401 ]] && ok "exige JWT" || fail "codigo $c"
echo "3) Login incorrecto (401)";  c=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/auth/login -H "$J" -d '{"user":"load","pass":"mala"}'); [[ $c == 401 ]] && ok "rechazado" || fail "codigo $c"
TOK=$(login load "$LOAD_PASS"); [[ -n "$TOK" ]] && ok "login load (tecnico)" || fail "no se obtuvo token"
AUTH="authorization: Bearer $TOK"
echo "4) Evento invalido (422)";   c=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/v1/eventos -H "$J" -H "$AUTH" -d '{"lote_id":"X"}'); [[ $c == 422 ]] && ok "rechazado" || fail "codigo $c"
TS=$(date +%s)
DOC="{\"type\":\"evento_lote\",\"lote_id\":\"SMOKE-$TS\",\"cooperativa_id\":\"C1\",\"etapa\":\"recoleccion\",\"ts\":$TS,\"owner\":\"smoke\",\"peso_kg\":40}"
echo "5) Evento valido (201)";     c=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/v1/eventos -H "$J" -H "$AUTH" -d "$DOC"); [[ $c == 201 ]] && ok "creado" || fail "codigo $c"
echo "6) Reintento idempotente";   c=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/v1/eventos -H "$J" -H "$AUTH" -d "$DOC"); [[ $c == 200 ]] && ok "duplicado detectado" || fail "codigo $c"
echo "7) Lectura del lote";        out=$(curl -s $API/v1/lotes/SMOKE-$TS -H "$AUTH"); [[ "$out" == *"SMOKE-$TS"* ]] && ok "lote devuelto" || fail "respuesta: $out"
echo "8) RBAC: auditor no escribe (403)"; AUD=$(login auditor "$AUDIT_PASS"); c=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/v1/eventos -H "$J" -H "authorization: Bearer $AUD" -d "$DOC"); [[ $c == 403 ]] && ok "solo lectura" || fail "codigo $c"
echo "9) RBAC: auditor si lee";    out=$(curl -s $API/v1/lotes/SMOKE-$TS -H "authorization: Bearer $AUD"); [[ "$out" == *"SMOKE-$TS"* ]] && ok "lectura permitida" || fail "respuesta: $out"
echo "10) RBAC: productor solo escribe lo suyo (403)"; PRO=$(login productor "$PROD_PASS"); c=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/v1/eventos -H "$J" -H "authorization: Bearer $PRO" -d "$DOC"); [[ $c == 403 ]] && ok "owner ajeno bloqueado" || fail "codigo $c"
if [[ $PROFILE == treatment ]]; then
  # CouchDB no publica puertos al anfitrion: se consulta desde dentro de su contenedor.
  echo "11) Documento en CouchDB";   out=$($DC exec -T couchdb curl -fs -u "$COUCHDB_USER:$COUCHDB_PASSWORD" "http://localhost:5984/trazabilidad/SMOKE-$TS:$TS" 2>&1); [[ "$out" == *"SMOKE-$TS"* ]] && ok "persistido" || fail "no esta: $out"
  echo "12) CouchDB sin credenciales (401)"; c=$($DC exec -T couchdb curl -s -o /dev/null -w '%{http_code}' http://localhost:5984/trazabilidad); [[ $c == 401 ]] && ok "acceso anonimo bloqueado" || fail "codigo $c"
  echo "13) Metricas del backend";   m=$(curl -fs http://localhost:9100/metrics 2>&1); [[ "$m" == *"http_request_duration_seconds"* && "$m" == *"db_tx_duration_seconds"* && "$m" == *"process_threads"* ]] && ok "/metrics expone latencia, transacciones e hilos" || fail "faltan metricas"
  echo "14) Metricas de CouchDB";    m=$($DC exec -T couchdb curl -fs http://localhost:17986/_node/_local/_prometheus 2>&1 | head -c 2000); [[ "$m" == *"couchdb_"* ]] && ok "endpoint Prometheus de CouchDB" || fail "sin metricas de CouchDB: $m"
  echo "15) RBAC directo en CouchDB"; ./couchdb/create_users.sh >/dev/null && ./couchdb/test_rbac.sh && ok "roles CouchDB" || fail "RBAC directo de CouchDB"
else
  echo "11) Fila en PostgreSQL";     out=$($DC exec -T postgres psql -U postgres -d trazabilidad -tAc "SELECT id FROM eventos WHERE id='SMOKE-$TS:$TS'" 2>&1); [[ "$out" == *"SMOKE-$TS"* ]] && ok "persistido" || fail "no esta: $out"
fi
echo "Todo correcto."
