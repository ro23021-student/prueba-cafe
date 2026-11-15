# GUIA DE ENTREGA — Sandbox Fase 3 (Trazabilidad Café)

**Para equipo de 5 personas — Solo copiar y pegar**

Este documento explica exactamente qué debe hacer cada integrante, con los comandos listos para copiar y pegar.

---

## 1. Antes de empezar (todos)

Estar en la carpeta del proyecto:

```bash
cd /home/antonio/Documentos/sandbox_fase3
```

Ver el estado actual (solo lectura, no cambia nada):

```bash
git status --short
```

Debe mostrar aproximadamente:

```
 M backend-rust/src/infrastructure/couchdb.rs
 M backend-rust/src/interface/http.rs
 M sandbox/couchdb/create_users.sh
 M sandbox/couchdb/load_seed.sh
 M sandbox/couchdb/test_rbac.sh
 M sandbox/couchdb/verify_indexes.sh
 M sandbox/docker-compose.yml
 M sandbox/k6/e1_stress.js
 M sandbox/netem/apply_netem.sh
 M sandbox/netem/outage.sh
 M sandbox/orchestrator/analisis_estadistico.py
 M sandbox/run_experiment.sh
 M sandbox/run_load.sh
 M sandbox/run_plan.sh
 M sandbox/smoke_test.sh
?? sandbox/orchestrator/exportar_fase5.py
?? sandbox/orchestrator/redactar_fase5.py
?? sandbox/plan_5reps.csv
?? sandbox/plan_reducido_nuevo.csv
?? sandbox/retomar_plan.sh
```

**NUNCA subir:**
- `sandbox/results/` (datos grandes, ya en `.gitignore`)
- `sandbox/.env` (claves secretas, ya en `.gitignore`)
- `backend-rust/target/`
- `**/__pycache__/`
- `*.pyc`

---

## 2. Flujo de git (obligatorio para los 5)

Cada persona trabaja en su **propia rama**. Nadie trabaja directo en `main`.

**Paso 1 — Crear tu rama** (sustituye `<nombre>` y `<tarea>`):

```bash
git checkout -b feat/<nombre>-<tarea>
```

Ejemplos:
- `git checkout -b feat/ana-backend`
- `git checkout -b feat/luis-orquestacion`
- `git checkout -b feat/carlos-infra`
- `git checkout -b feat/elena-analisis`
- `git checkout -b feat/diego-pruebas`

**Paso 2 — Editar solo tus archivos asignados** (ver secciones 3 al 7).

**Paso 3 — Agregar solo tus archivos:**

```bash
git add <ruta-de-tus-archivos>
```

**Paso 4 — Commit con mensaje descriptivo:**

```bash
git commit -m "feat: descripcion breve de lo que hiciste"
```

**Paso 5 — Antes de subir, traer cambios de main:**

```bash
git pull --rebase origin main
```

Si hay conflictos, resueltos en tu rama.

**Paso 6 — Un líder (una sola persona) hace el merge final a main y el push:**

```bash
git checkout main
git merge feat/<nombre>-<tarea>
git push origin main
```

---

## 3. Persona 1 — Backend y base de datos

**Archivos asignados:**

```
backend-rust/src/infrastructure/couchdb.rs
backend-rust/src/interface/http.rs
sandbox/couchdb/create_users.sh
sandbox/couchdb/load_seed.sh
sandbox/couchdb/test_rbac.sh
sandbox/couchdb/verify_indexes.sh
```

**Qué revisar:**
- Que el acceso a CouchDB use una única base compartida (`trazabilidad`) con aislamiento lógico por cooperativa (claim de cooperativa del JWT, validación del backend y `validate_doc_update`).
- Que no se proponga una base física por cooperativa (ese es trabajo futuro).
- Que los scripts de CouchDB (crear usuarios, RBAC, carga semilla, verificación de índices) estén consistentes con el diseño corregido.

**Comandos para copiar y pegar:**

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-backend

git add backend-rust/src/infrastructure/couchdb.rs backend-rust/src/interface/http.rs sandbox/couchdb/create_users.sh sandbox/couchdb/load_seed.sh sandbox/couchdb/test_rbac.sh sandbox/couchdb/verify_indexes.sh

git commit -m "feat: backend y couchdb con base unica y limites de memoria corregidos"

git pull --rebase origin main
```

---

## 4. Persona 2 — Orquestación de experimentos

**Archivos asignados:**

```
sandbox/run_plan.sh
sandbox/run_experiment.sh
sandbox/run_load.sh
sandbox/smoke_test.sh
sandbox/plan_5reps.csv
sandbox/plan_reducido_nuevo.csv
sandbox/retomar_plan.sh
```

**Qué revisar:**
- `run_plan.sh` salta corridas que ya tienen `resumen_*.json` (no repetir trabajo).
- `run_experiment.sh` genera el resumen al final de cada corrida.
- Los archivos CSV de plan están presentes y con el formato correcto.
- `retomar_plan.sh` permite reanudar después de un apagado.

**Comandos para copiar y pegar:**

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-orquestacion

git add sandbox/run_plan.sh sandbox/run_experiment.sh sandbox/run_load.sh sandbox/smoke_test.sh sandbox/plan_5reps.csv sandbox/plan_reducido_nuevo.csv sandbox/retomar_plan.sh

git commit -m "feat: orquestacion de experimentos y planes de corrida"

git pull --rebase origin main
```

---

## 5. Persona 3 — Infraestructura, Docker y red

**Archivos asignados:**

```
sandbox/docker-compose.yml
sandbox/k6/e1_stress.js
sandbox/netem/apply_netem.sh
sandbox/netem/outage.sh
```

**Qué revisar:**
- `docker-compose.yml` con perfiles treatment, control, clients y load.
- Límites de memoria como variables (`MEM_LIMIT`, `CLIENT_MEM_LIMIT`), no valores fijos de 2 GiB.
- Scripts de netem para emulación de red y cortes.
- El contexto Docker es `default`; no se requiere el daemon dedicado (SD).

**Comandos para copiar y pegar:**

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-infra

git add sandbox/docker-compose.yml sandbox/k6/e1_stress.js sandbox/netem/apply_netem.sh sandbox/netem/outage.sh

git commit -m "feat: infraestructura docker netem y limites de memoria"

git pull --rebase origin main
```

---

## 6. Persona 4 — Análisis estadístico

**Archivos asignados:**

```
sandbox/orchestrator/analisis_estadistico.py
sandbox/orchestrator/exportar_fase5.py
sandbox/orchestrator/redactar_fase5.py
```

**Qué revisar:**
- El análisis lee `results/resumen_*.json` y genera tablas por nivel de dispositivos.
- Soporta `--run-s` para separar análisis por duración (60 s para 10 dispositivos, 300 s para 50 y 100).
- Genera salida en Markdown y JSON.

**Comandos para copiar y pegar:**

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-analisis

git add sandbox/orchestrator/analisis_estadistico.py sandbox/orchestrator/exportar_fase5.py sandbox/orchestrator/redactar_fase5.py

git commit -m "feat: analisis estadistico por nivel de dispositivos"

git pull --rebase origin main
```

---

## 7. Persona 5 — Soporte y pruebas

**Archivos asignados:**

```
sandbox/smoke_test.sh
sandbox/couchdb/verify_indexes.sh
```

Y cualquier archivo suelto que aparezca en `git status --short` y no esté asignado a otra persona.

**Qué revisar:**
- `smoke_test.sh` pasa sin errores.
- `verify_indexes.sh` verifica los índices de CouchDB.
- Nada quede sin asignar en `git status --short`.

**Comandos para copiar y pegar:**

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout -b feat/<tu-nombre>-soporte

git add sandbox/smoke_test.sh sandbox/couchdb/verify_indexes.sh

git commit -m "feat: pruebas humo y verificacion de índices couchdb"

git pull --rebase origin main
```

---

## 8. Líder — Merge final a main

Solo **UNA** persona hace esto (después de que todos hayan subido sus ramas):

```bash
cd /home/antonio/Documentos/sandbox_fase3
git checkout main
git pull origin main

# Mergear cada rama (repetir para las 5)
git merge feat/<nombre1>-backend --no-ff -m "merge: backend y couchdb"
git merge feat/<nombre2>-orquestacion --no-ff -m "merge: orquestacion de experimentos"
git merge feat/<nombre3>-infra --no-ff -m "merge: infraestructura docker"
git merge feat/<nombre4>-analisis --no-ff -m "merge: analisis estadistico"
git merge feat/<nombre5>-soporte --no-ff -m "merge: pruebas humo"

git push origin main
```

Si hay conflictos, se resuelven en `main` antes de hacer `push`.

---

## 9. Verificación final (todos)

Después del push, verificar que todo esté en `main`:

```bash
cd /home/antonio/Documentos/sandbox_fase3
git log --oneline -5
git status --short   # debe estar vacío o casi vacío
```

---

## 10. Documento separado (no va en el commit de código)

El documento de diseño va en:

```
/home/antonio/Documentos/TrabajoFase2enAdelante/Fase3_Diseno_Metodologico.docx
```

Ya contiene:
- Base CouchDB única compartida con aislamiento lógico.
- Límites de memoria corregidos (`MEM_LIMIT` / `CLIENT_MEM_LIMIT`).
- Sección de "Desviaciones del protocolo y limitaciones de ejecución".

Se entrega aparte del código, directamente al docente.

---

## Resumen rápido para cada integrante

| Persona | Rama | Carpeta principal | Comando clave |
|---------|------|-------------------|---------------|
| 1 | `feat/<nombre>-backend` | `backend-rust/src/`, `sandbox/couchdb/` | `git add backend-rust/src/ sandbox/couchdb/` |
| 2 | `feat/<nombre>-orquestacion` | `sandbox/run_plan.sh`, `sandbox/run_experiment.sh`, `sandbox/plan_*.csv` | `git add sandbox/run_plan.sh sandbox/run_experiment.sh sandbox/plan_*.csv` |
| 3 | `feat/<nombre>-infra` | `sandbox/docker-compose.yml`, `sandbox/netem/` | `git add sandbox/docker-compose.yml sandbox/netem/` |
| 4 | `feat/<nombre>-analisis` | `sandbox/orchestrator/` | `git add sandbox/orchestrator/` |
| 5 | `feat/<nombre>-soporte` | `sandbox/smoke_test.sh`, `sandbox/couchdb/verify_indexes.sh` | `git add sandbox/smoke_test.sh sandbox/couchdb/verify_indexes.sh` |

Listo. Cada uno copia sus comandos, edita sus archivos asignados, hace su commit en su rama, y un líder sube todo a `main`.
