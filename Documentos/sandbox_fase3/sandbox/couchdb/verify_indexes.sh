#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}"
# Comprueba que las consultas usan los indices Mango y compara con una consulta SIN indice.
set -euo pipefail
source .env
Q() { docker compose --profile treatment exec -T couchdb curl -fs -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
        -X POST -H 'content-type: application/json' "http://localhost:5984/trazabilidad/$1" -d "$2"; }
mostrar() { # $1=titulo $2=json de _find
  echo "== $1"
  echo "   $(echo "$2" | grep -o '"total_docs_examined":[0-9]*')  $(echo "$2" | grep -o '"total_keys_examined":[0-9]*')  $(echo "$2" | grep -o '"execution_time_ms":[0-9.]*')"
}
LOTE='{"selector":{"type":"evento_lote","lote_id":"L-000123","ts":{"$gte":0}},"use_index":"idx_lote_ts","execution_stats":true,"limit":200}'
COOP='{"selector":{"type":"evento_lote","cooperativa_id":"COOP-05","ts":{"$gte":1760000000}},"use_index":"idx_coop_ts","execution_stats":true,"limit":50}'
SIN='{"selector":{"type":"evento_lote","owner":"prod-0042"},"execution_stats":true,"limit":200}'
echo "Indice elegido por CouchDB (_explain):"
for q in "$LOTE" "$COOP" "$SIN"; do Q _explain "$q" | grep -o '"index":{[^}]*' | grep -o '"name":"[^"]*"' | head -1; done
mostrar "Por lote (con indice idx_lote_ts)" "$(Q _find "$LOTE")"
mostrar "Por cooperativa y fecha (con indice idx_coop_ts)" "$(Q _find "$COOP")"
mostrar "Por productor (SIN indice: escaneo completo)" "$(Q _find "$SIN")"
