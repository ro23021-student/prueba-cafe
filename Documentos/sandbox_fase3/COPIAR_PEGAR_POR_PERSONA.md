# COPIAR Y PEGAR — Por integrante del equipo

## Repositorio: `/home/antonio/Documentos/sandbox_fase3`

Cada persona copia y pega sus bloques en orden. No modificar archivos de otros.

---

## PASO 0 — Todos (ejecutar una vez)

```bash
cd /home/antonio/Documentos/sandbox_fase3
git status --short
```

---

## PERSONA 1 — Backend y CouchDB

**Archivos:**
- `backend-rust/src/infrastructure/couchdb.rs`
- `backend-rust/src/interface/http.rs`
- `sandbox/couchdb/create_users.sh`
- `sandbox/couchdb/load_seed.sh`
- `sandbox/couchdb/test_rbac.sh`
- `sandbox/couchdb/verify_indexes.sh`

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/persona1-backend
git add backend-rust/src/infrastructure/couchdb.rs backend-rust/src/interface/http.rs sandbox/couchdb/create_users.sh sandbox/couchdb/load_seed.sh sandbox/couchdb/test_rbac.sh sandbox/couchdb/verify_indexes.sh
git commit -m "feat: backend y couchdb con base unica y limites de memoria corregidos"
git pull --rebase origin main
```

---

## PERSONA 2 — Orquestación de experimentos

**Archivos:**
- `sandbox/run_plan.sh`
- `sandbox/run_experiment.sh`
- `sandbox/run_load.sh`
- `sandbox/smoke_test.sh`
- `sandbox/plan_5reps.csv`
- `sandbox/plan_reducido_nuevo.csv`
- `sandbox/retomar_plan.sh`

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/persona2-orquestacion
git add sandbox/run_plan.sh sandbox/run_experiment.sh sandbox/run_load.sh sandbox/smoke_test.sh sandbox/plan_5reps.csv sandbox/plan_reducido_nuevo.csv sandbox/retomar_plan.sh
git commit -m "feat: orquestacion de experimentos y planes de corrida"
git pull --rebase origin main
```

---

## PERSONA 3 — Infraestructura, Docker y red

**Archivos:**
- `sandbox/docker-compose.yml`
- `sandbox/k6/e1_stress.js`
- `sandbox/netem/apply_netem.sh`
- `sandbox/netem/outage.sh`

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/persona3-infra
git add sandbox/docker-compose.yml sandbox/k6/e1_stress.js sandbox/netem/apply_netem.sh sandbox/netem/outage.sh
git commit -m "feat: infraestructura docker netem y limites de memoria"
git pull --rebase origin main
```

---

## PERSONA 4 — Análisis estadístico

**Archivos:**
- `sandbox/orchestrator/analisis_estadistico.py`
- `sandbox/orchestrator/exportar_fase5.py`
- `sandbox/orchestrator/redactar_fase5.py`

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/persona4-analisis
git add sandbox/orchestrator/analisis_estadistico.py sandbox/orchestrator/exportar_fase5.py sandbox/orchestrator/redactar_fase5.py
git commit -m "feat: analisis estadistico por nivel de dispositivos"
git pull --rebase origin main
```

---

## PERSONA 5 — Soporte y pruebas

**Archivos:**
- `sandbox/smoke_test.sh`
- `sandbox/couchdb/verify_indexes.sh`
- Cualquier archivo suelto de `git status --short`

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/persona5-soporte
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
git merge feat/persona1-backend --no-ff -m "merge: backend y couchdb"
git merge feat/persona2-orquestacion --no-ff -m "merge: orquestacion de experimentos"
git merge feat/persona3-infra --no-ff -m "merge: infraestructura docker"
git merge feat/persona4-analisis --no-ff -m "merge: analisis estadistico"
git merge feat/persona5-soporte --no-ff -m "merge: pruebas humo"
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

## DOCUMENTO SEPARADO (no va en el commit)

Entregar aparte al docente:

```
/home/antonio/Documentos/TrabajoFase2enAdelante/Fase3_Diseno_Metodologico.docx
```
