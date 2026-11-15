#!/usr/bin/env bash
export DOCKER_CONTEXT="${DOCKER_CONTEXT:-sandbox}"
set -uo pipefail
source .env
N="${1:-10000}"
D=$(mktemp -d)
python3 orchestrator/seed_data.py --lotes "$N" --seed 42 > "$D/seed.json"
python3 - "$D" <<'PY'
import json, sys
d = sys.argv[1]
docs = json.load(open(f"{d}/seed.json"))["docs"]
print(f"Generados {len(docs)} documentos")
for i in range(0, len(docs), 5000):
    json.dump({"docs": docs[i:i+5000]}, open(f"{d}/chunk_{i//5000:03d}.json", "w"))
PY
OK=0; ERR=0
for f in "$D"/chunk_*.json; do
  RESP=$(docker compose --profile treatment exec -T couchdb curl -s -w '\nHTTP:%{http_code}' -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
    -X POST -H 'content-type: application/json' --data-binary @- http://localhost:5984/trazabilidad/_bulk_docs < "$f")
  CODE=${RESP##*HTTP:}
  if [[ "$CODE" != "201" ]]; then echo "FALLA en $(basename $f): HTTP $CODE"; echo "${RESP:0:400}"; exit 1; fi
  OK=$((OK + $(echo "$RESP" | grep -o '"ok":true' | wc -l)))
  ERR=$((ERR + $(echo "$RESP" | grep -o '"error"' | wc -l)))
  echo "  $(basename $f): HTTP $CODE"
done
echo "Guardados: $OK   Rechazados: $ERR"
[[ $ERR -gt 0 ]] && echo "$RESP" | grep -o '"reason":"[^"]*"' | sort | uniq -c | head -3
docker compose --profile treatment exec -T couchdb curl -fs -u "$COUCHDB_USER:$COUCHDB_PASSWORD" http://localhost:5984/trazabilidad | grep -o '"doc_count":[0-9]*'
rm -rf "$D"
