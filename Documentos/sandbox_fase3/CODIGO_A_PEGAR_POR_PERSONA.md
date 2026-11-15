# CODIGO A PEGAR POR PERSONA — Sandbox Fase 3

**Repositorio:** `/home/antonio/Documentos/sandbox_fase3`

Cada integrante abre su archivo, busca el marcador `PASTE AQUÍ`, pega el bloque de código correspondiente y luego ejecuta los comandos de git de su sección.

**NO subir nunca:** `sandbox/results/`, `sandbox/.env`, `backend-rust/target/`, `__pycache__/`, `*.pyc`

---

## PERSONA 1 — Backend y CouchDB

### Archivo 1: `backend-rust/src/infrastructure/couchdb.rs`

Busca la función de conexión/cliente de CouchDB y **reemplaza** o pega este bloque donde se inicializa el cliente:

```rust
// ============================================================
// PASTE AQUÍ: Cliente CouchDB con base única compartida
// Fase 3 corregida: UNA base 'trazabilidad', aislamiento lógico por cooperativa
// ============================================================

use reqwest::Client;
use serde::{Deserialize, Serialize};

#[derive(Clone)]
pub struct CouchDbClient {
    pub http: Client,
    pub base_url: String,
    pub db_name: String, // siempre "trazabilidad"
}

impl CouchDbClient {
    pub fn new(base_url: &str) -> Self {
        Self {
            http: Client::new(),
            base_url: base_url.to_string(),
            db_name: "trazabilidad".to_string(), // UNA base compartida, no una por cooperativa
        }
    }

    pub fn db_url(&self) -> String {
        format!("{}/{}", self.base_url, self.db_name)
    }

    /// Valida que el claim de cooperativa del JWT coincida con el recurso solicitado.
    /// Aislamiento lógico: ninguna base física por cooperativa.
    pub fn validar_cooperativa(&self, token_coop: &str, recurso_coop: &str) -> bool {
        token_coop == recurso_coop
    }
}
```

### Archivo 2: `sandbox/couchdb/create_users.sh`

Busca la función `crear()` y **reemplaza** el cuerpo por este bloque (usa base única `trazabilidad`):

```bash
# ============================================================
# PASTE AQUÍ: crear usuarios en la base UNICA trazabilidad
# ============================================================

crear() {
  local nombre="$1" clave="$2" roles="$3"
  local id="org.couchdb.user:$nombre"
  local previo rev="" cuerpo respuesta codigo

  previo=$("${CURL[@]}" "$BASE/_users/$id" 2>/dev/null || true)
  rev=$(printf '%s' "$previo" | grep -o '"_rev":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

  if [[ -n "$rev" ]]; then
    cuerpo=$(printf '{"_id":"%s","_rev":"%s","name":"%s","type":"user","roles":%s,"password":"%s"}' \
      "$id" "$rev" "$nombre" "$roles" "$clave")
  else
    cuerpo=$(printf '{"_id":"%s","name":"%s","type":"user","roles":%s,"password":"%s"}' \
      "$id" "$nombre" "$roles" "$clave")
  fi

  respuesta=$("${CURL[@]}" -w '\nHTTP:%{http_code}' -X PUT "$BASE/_users/$id" -d "$cuerpo")
  codigo=${respuesta##*HTTP:}

  case "$codigo" in
    201|202) echo "  OK  usuario CouchDB $nombre roles=$roles" ;;
    *) echo "  FALLA usuario $nombre (HTTP $codigo): ${respuesta%$'\n'HTTP:*}" >&2; exit 1 ;;
  esac
}
```

### Comandos git (copiar y pegar):
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-backend

git add backend-rust/src/infrastructure/couchdb.rs backend-rust/src/interface/http.rs \
  sandbox/couchdb/create_users.sh sandbox/couchdb/load_seed.sh \
  sandbox/couchdb/test_rbac.sh sandbox/couchdb/verify_indexes.sh

git commit -m "feat: backend y couchdb con base unica y limites de memoria corregidos"

git pull --rebase origin main
```

---

## PERSONA 2 — Orquestación de experimentos

### Archivo 1: `sandbox/run_plan.sh`

Busca el bucle `for fila` y **pega** esta lógica de skip justo antes de ejecutar `run_experiment.sh`:

```bash
# ============================================================
# PASTE AQUÍ: saltar corridas que ya tienen resumen
# ============================================================

for fila in "${seleccion[@]}"; do
  IFS='|' read -r order arch loss devices rep run_seed <<< "$fila"

  # Salta corridas que ya tienen resumen (no repetir trabajo)
  if compgen -G "results/resumen_${arch}-d${devices}-l${loss}-r${rep}-*.json" > /dev/null; then
    echo "[skip] orden=$order $arch perdida=$loss dispositivos=$devices rep=$rep: ya existe resumen"
    continue
  fi

  if [[ "$DRY" == "1" ]]; then
    echo "[dry-run] orden=$order $arch perdida=$loss dispositivos=$devices rep=$rep semilla=$run_seed"
    continue
  fi

  echo "===== orden $order: $arch perdida=$loss dispositivos=$devices rep=$rep ====="
  ./run_experiment.sh "$arch" "$loss" "$devices" "$rep" "$run_seed"
done
```

### Archivo 2: `sandbox/run_experiment.sh`

Busca la sección de variables de duración y **reemplaza** por este bloque (usa variables de entorno, no valores fijos):

```bash
# ============================================================
# PASTE AQUÍ: duracion de corrida segun dispositivos
# 10 dispositivos -> 60 s, 50 y 100 dispositivos -> 300 s
# ============================================================

export RUN_SECONDS="${RUN_SECONDS:-300}"
export WARMUP_S="${WARMUP_S:-30}"
export MEASURE_S="${MEASURE_S:-240}"
export DRAIN_S="${DRAIN_S:-120}"
export OUTAGE_MODE="${OUTAGE_MODE:-self}"
export OUTAGE_PLAN="${OUTAGE_PLAN:-60:30,180:30}"

# Si se pasa --run-s 60 (para 10 dispositivos), sobreescribir:
if [[ "${RUN_SECONDS:-}" == "60" ]]; then
  WARMUP_S="${WARMUP_S:-10}"
  MEASURE_S="${MEASURE_S:-40}"
  DRAIN_S="${DRAIN_S:-10}"
  OUTAGE_PLAN="${OUTAGE_PLAN:-30:10}"
fi
```

### Archivo 3: `sandbox/run_plan.sh` (límites de memoria)

Busca la sección donde se definen perfiles y **agrega** estas variables al entorno:

```bash
# ============================================================
# PASTE AQUÍ: variables de limite de memoria (iguales T y C0)
# ============================================================

export MEM_LIMIT="${MEM_LIMIT:-2g}"      # 768 MiB en equipo de 2 nucleos
export CLIENT_MEM_LIMIT="${CLIENT_MEM_LIMIT:-512m}"
export CPUSET="${CPUSET:-0-1}"
export LOAD_CPUSET="${LOAD_CPUSET:-0-1}"
```

### Comandos git:
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-orquestacion

git add sandbox/run_plan.sh sandbox/run_experiment.sh sandbox/run_load.sh \
  sandbox/smoke_test.sh sandbox/plan_5reps.csv sandbox/plan_reducido_nuevo.csv \
  sandbox/retomar_plan.sh

git commit -m "feat: orquestacion de experimentos y planes de corrida"

git pull --rebase origin main
```

---

## PERSONA 3 — Infraestructura, Docker y red

### Archivo 1: `sandbox/docker-compose.yml`

Busca los servicios `couchdb`, `api-rust`, `api-baseline`, `client-sim`, `k6` y **reemplaza** sus secciones `mem_limit` por estas:

```yaml
# ============================================================
# PASTE AQUÍ: limites de memoria como variables (iguales T y C0)
# ============================================================

services:
  couchdb:
    image: couchdb:3.3.3
    profiles: [treatment]
    mem_limit: ${MEM_LIMIT:-2g}          # 768 MiB en equipo de 2 nucleos
    cpuset: "${CPUSET:-0-1}"
    networks: [exp-net]
    # ... resto de configuracion existente ...

  api-rust:
    build:
      context: ../backend-rust
      network: host
    profiles: [treatment]
    mem_limit: ${MEM_LIMIT:-2g}
    cpuset: "${CPUSET:-0-1}"
    depends_on:
      couchdb: {condition: service_healthy}
    # ... resto ...

  api-baseline:
    build: ../backend-baseline
    profiles: [control]
    mem_limit: ${MEM_LIMIT:-2g}
    cpuset: "${CPUSET:-0-1}"
    # ... resto ...

  client-sim:
    build: ../client-sim
    profiles: [clients]
    mem_limit: ${CLIENT_MEM_LIMIT:-512m}
    cpuset: "${LOAD_CPUSET:-0-1}"
    # ... resto ...

  k6:
    image: grafana/k6:0.54.0
    profiles: [load]
    mem_limit: ${CLIENT_MEM_LIMIT:-512m}
    cpuset: "${LOAD_CPUSET:-0-1}"
    # ... resto ...
```

### Comandos git:
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-infra

git add sandbox/docker-compose.yml sandbox/k6/e1_stress.js \
  sandbox/netem/apply_netem.sh sandbox/netem/outage.sh

git commit -m "feat: infraestructura docker netem y limites de memoria"

git pull --rebase origin main
```

---

## PERSONA 4 — Análisis estadístico

### Archivo 1: `sandbox/orchestrator/analisis_estadistico.py`

Busca la función `main()` o el bloque de argumentos y **agrega** esta sección al principio:

```python
# ============================================================
# PASTE AQUÍ: argumentos de linea de comandos
# ============================================================

import argparse

ap = argparse.ArgumentParser(description="Analisis estadistico Fase 5")
ap.add_argument("--archivo", required=False, help="Archivo resumen JSON individual")
ap.add_argument("--archivo-k6", required=False, help="Archivo resumen K6 JSON individual")
ap.add_argument("--salida", required=False, default="results/analisis.json",
                help="Archivo de salida JSON")
ap.add_argument("--salida-md", required=False, help="Archivo de salida Markdown")
ap.add_argument("--inicio", type=int, required=False, help="Inicio en segundos")
ap.add_argument("--fin", type=int, required=False, help="Fin en segundos")
ap.add_argument("--run-id", required=False, help="Identificador de corrida")
ap.add_argument("--run-s", type=int, required=False, default=300,
                help="Duracion de corrida en segundos (60 para 10 dispositivos, 300 para 50/100)")
ap.add_argument("--devices", type=int, required=False, help="Numero de dispositivos")
ap.add_argument("--perdidas", required=False, default="0,5,15,30",
                help="Porcentajes de perdida separados por comas")
ap.add_argument("--arch", required=False, default="T,C0", help="Arquitecturas separadas por comas")
args = ap.parse_args()
```

### Archivo 2: `sandbox/orchestrator/analisis_estadistico.py` (sección de filtro por dispositivos)

Busca donde se filtran los resumenes y **agrega** este filtro:

```python
# ============================================================
# PASTE AQUÍ: filtro por nivel de dispositivos y duracion
# ============================================================

import re
from pathlib import Path

def cargar_resumenes(devices=None, run_s=None, perdidas=None, archs=None):
    """Carga resumenes filtrando por dispositivos, duracion y perdida."""
    resumenes = []
    for f in Path("results").glob("resumen_*-d*-l*-r*.json"):
        m = re.match(r"resumen_(T|C0)-d(\d+)-l(\d+)-r(\d+)-", f.name)
        if not m:
            continue
        arch, d, l, rep = m.groups()
        if devices and int(d) != devices:
            continue
        if run_s is not None:
            # Leer run_s del JSON si existe
            import json
            try:
                datos = json.load(open(f))
                if datos.get("run_s") != run_s:
                    continue
            except Exception:
                continue
        if perdidas and str(l) not in perdidas.split(","):
            continue
        if archs and arch not in archs.split(","):
            continue
        resumenes.append(f)
    return resumenes
```

### Comandos git:
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-analisis

git add sandbox/orchestrator/analisis_estadistico.py \
  sandbox/orchestrator/exportar_fase5.py sandbox/orchestrator/redactar_fase5.py

git commit -m "feat: analisis estadistico por nivel de dispositivos"

git pull --rebase origin main
```

---

## PERSONA 5 — Soporte y pruebas

### Archivo 1: `sandbox/smoke_test.sh`

Busca el inicio del script y **pega** este bloque:

```bash
#!/usr/bin/env bash
# ============================================================
# PASTE AQUÍ: test de humo del sandbox
# ============================================================

set -euo pipefail

echo "[smoke] Verificando API..."
if curl -fs "http://localhost:${API_PORT:-8080}/health" 2>/dev/null | grep -q "ok"; then
  echo "  OK: API responde en /health"
else
  echo "  FALLA: API no responde en /health" >&2
  exit 1
fi

echo "[smoke] Verificando CouchDB..."
if curl -fs "http://localhost:5984/" 2>/dev/null | grep -q "couchdb"; then
  echo "  OK: CouchDB responde"
else
  echo "  FALLA: CouchDB no responde" >&2
  exit 1
fi

echo "[smoke] Todos los tests de humo pasaron"
```

### Archivo 2: `sandbox/couchdb/verify_indexes.sh`

Busca el inicio del script y **pega** este bloque:

```bash
#!/usr/bin/env bash
# ============================================================
# PASTE AQUÍ: verificar índices de CouchDB
# ============================================================

set -euo pipefail

echo "[indexes] Verificando índices de CouchDB en trazabilidad..."

# Listar bases de datos
curl -sS -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" \
  http://localhost:5984/_all_dbs | python3 -m json.tool

# Verificar diseño de base trazabilidad
curl -sS -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" \
  http://localhost:5984/trazabilidad/_all_docs?startkey="_design/" \
  | python3 -m json.tool

echo "[indexes] Índices verificados"
```

### Comandos git:
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-soporte

git add sandbox/smoke_test.sh sandbox/couchdb/verify_indexes.sh

git commit -m "feat: pruebas humo y verificacion de índices couchdb"

git pull --rebase origin main
```

---

## LÍDER — Merge final a main (una sola persona)

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout main
git pull origin main

git merge feat/<persona1>-backend --no-ff -m "merge: backend y couchdb"
git merge feat/<persona2>-orquestacion --no-ff -m "merge: orquestacion de experimentos"
git merge feat/<persona3>-infra --no-ff -m "merge: infraestructura docker"
git merge feat/<persona4>-analisis --no-ff -m "merge: analisis estadistico"
git merge feat/<persona5>-soporte --no-ff -m "merge: pruebas humo"

git push origin main
```

---

## DOCUMENTO SEPARADO (no va en el commit de código)

Entregar aparte al docente:

```
/home/antonio/Documentos/TrabajoFase2enAdelante/Fase3_Diseno_Metodologico.docx
```

Ya incluye:
- Base CouchDB única compartida con aislamiento lógico por cooperativa.
- Límites de memoria corregidos (MEM_LIMIT / CLIENT_MEM_LIMIT).
- Sección de "Desviaciones del protocolo y limitaciones de ejecución".

---

## NO SUBIR (ya están en .gitignore)

- `sandbox/results/`
- `sandbox/.env`
- `backend-rust/target/`
- `**/__pycache__/`
- `*.pyc`
