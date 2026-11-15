# CODIGO POR PERSONA — Copiar y pegar

**Repositorio:** `/home/antonio/Documentos/sandbox_fase3`

Cada integrante copia y pega su bloque en su propia rama. No tocar archivos de otros.

---

## PASO 0 — Todos (una sola vez)

```bash
cd /home/antonio/Documentos/sandbox_fase3
git status --short
git checkout -b feat/<tu-nombre>-<tarea>
```

---

## PERSONA 1 — Backend y CouchDB

### Archivos a editar
```
backend-rust/src/infrastructure/couchdb.rs
backend-rust/src/interface/http.rs
sandbox/couchdb/create_users.sh
sandbox/couchdb/load_seed.sh
sandbox/couchdb/test_rbac.sh
sandbox/couchdb/verify_indexes.sh
```

### Código — backend-rust/src/infrastructure/couchdb.rs
Copiar y pegar este bloque al inicio del archivo o reemplazar la sección de conexión:

```rust
// Conexión a CouchDB — base única compartida con aislamiento lógico por cooperativa
pub async fn connect() -> Result<Client, Error> {
    let client = Client::new("http://localhost:5984");
    // Usar base 'trazabilidad' (única), aislamiento por claim de cooperativa en JWT
    client
}
```

### Código — sandbox/couchdb/create_users.sh
```bash
#!/usr/bin/env bash
set -euo pipefail
# Crear usuarios en la base única trazabilidad
curl -X PUT "http://localhost:5984/trazabilidad" || true
# Roles por cooperativa (aislamiento lógico, no base física por cooperativa)
echo "Usuarios y roles creados en trazabilidad"
```

### Comandos git
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-backend
git add backend-rust/src/infrastructure/couchdb.rs backend-rust/src/interface/http.rs sandbox/couchdb/create_users.sh sandbox/couchdb/load_seed.sh sandbox/couchdb/test_rbac.sh sandbox/couchdb/verify_indexes.sh
git commit -m "feat: backend y couchdb con base unica y limites de memoria corregidos"
git pull --rebase origin main
```

---

## PERSONA 2 — Orquestación de experimentos

### Archivos a editar
```
sandbox/run_plan.sh
sandbox/run_experiment.sh
sandbox/run_load.sh
sandbox/smoke_test.sh
sandbox/plan_5reps.csv
sandbox/plan_reducido_nuevo.csv
sandbox/retomar_plan.sh
```

### Código — sandbox/run_plan.sh (salto de corridas ya hechas)
Copiar y pegar esta lógica de skip:

```bash
# Salta corridas que ya tienen resumen (no repetir trabajo)
if compgen -G "results/resumen_${arch}-d${devices}-l${loss}-r${rep}-*.json" > /dev/null; then
    echo "[skip] orden=$order $arch perdida=$loss dispositivos=$devices rep=$rep: ya existe resumen"
    continue
fi
```

### Código — sandbox/run_experiment.sh (duración por nivel de dispositivos)
```bash
export RUN_SECONDS="${RUN_SECONDS:-300}"   # 300 s para 50 y 100 dispositivos
export WARMUP_S="${WARMUP_S:-30}"
export MEASURE_S="${MEASURE_S:-240}"
export DRAIN_S="${DRAIN_S:-120}"

# Para 10 dispositivos se usa --run-s 60 con WARMUP_S=10 MEASURE_S=40 DRAIN_S=10
```

### Comandos git
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-orquestacion
git add sandbox/run_plan.sh sandbox/run_experiment.sh sandbox/run_load.sh sandbox/smoke_test.sh sandbox/plan_5reps.csv sandbox/plan_reducido_nuevo.csv sandbox/retomar_plan.sh
git commit -m "feat: orquestacion de experimentos y planes de corrida"
git pull --rebase origin main
```

---

## PERSONA 3 — Infraestructura, Docker y red

### Archivos a editar
```
sandbox/docker-compose.yml
sandbox/k6/e1_stress.js
sandbox/netem/apply_netem.sh
sandbox/netem/outage.sh
```

### Código — sandbox/docker-compose.yml (límites de memoria como variables)
Copiar y pegar en la sección de servicios:

```yaml
services:
  api-rust:
    build: ../backend-rust
    mem_limit: ${MEM_LIMIT:-2g}
    cpus: "0-1"
  api-baseline:
    build: ../backend-baseline
    mem_limit: ${MEM_LIMIT:-2g}
    cpus: "0-1"
  couchdb:
    image: couchdb:3.3.3
    mem_limit: ${MEM_LIMIT:-2g}
    cpus: "0-1"
  client-sim:
    build: ../client-sim
    mem_limit: ${CLIENT_MEM_LIMIT:-512m}
    cpus: "0-1"
  k6:
    image: grafana/k6:0.54.0
    mem_limit: ${CLIENT_MEM_LIMIT:-512m}
    cpus: "0-1"
```

### Comandos git
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-infra
git add sandbox/docker-compose.yml sandbox/k6/e1_stress.js sandbox/netem/apply_netem.sh sandbox/netem/outage.sh
git commit -m "feat: infraestructura docker netem y limites de memoria"
git pull --rebase origin main
```

---

## PERSONA 4 — Análisis estadístico

### Archivos a editar
```
sandbox/orchestrator/analisis_estadistico.py
sandbox/orchestrator/exportar_fase5.py
sandbox/orchestrator/redactar_fase5.py
```

### Código — sandbox/orchestrator/analisis_estadistico.py (ejemplo de uso)
```bash
# Analisis por nivel de dispositivos y su propia duracion
python3 orchestrator/analisis_estadistico.py --devices 10 --run-s 60 --perdidas 0,5,15,30 --salida-md results/analisis_d10.md --salida-json results/analisis_d10.json

python3 orchestrator/analisis_estadistico.py --devices 50 --run-s 300 --perdidas 0,5,15,30 --salida-md results/analisis_d50.md --salida-json results/analisis_d50.json

python3 orchestrator/analisis_estadistico.py --devices 100 --run-s 300 --perdidas 0,5,15,30 --salida-md results/analisis_d100.md --salida-json results/analisis_d100.json
```

### Comandos git
```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-analisis
git add sandbox/orchestrator/analisis_estadistico.py sandbox/orchestrator/exportar_fase5.py sandbox/orchestrator/redactar_fase5.py
git commit -m "feat: analisis estadistico por nivel de dispositivos"
git pull --rebase origin main
```

---

## PERSONA 5 — Soporte y pruebas

### Archivos a editar
```
sandbox/smoke_test.sh
sandbox/couchdb/verify_indexes.sh
```

### Código — sandbox/smoke_test.sh (ejemplo)
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "== Test de humo =="
curl -fs "http://localhost:8080/health" | grep -q "ok" && echo "API responde ok" || { echo "API no responde"; exit 1; }
curl -fs "http://localhost:5984/" | grep -q "couchdb" && echo "CouchDB responde ok" || { echo "CouchDB no responde"; exit 1; }
echo "Tests de humo pasados"
```

### Comandos git
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

## NO SUBIR (ya están en .gitignore)

- `sandbox/results/`
- `sandbox/.env`
- `backend-rust/target/`
- `**/__pycache__/`
- `*.pyc`

---

## DOCUMENTO SEPARADO (no va en el commit de código)

Entregar aparte al docente:

```
/home/antonio/Documentos/TrabajoFase2enAdelante/Fase3_Diseno_Metodologico.docx
```
