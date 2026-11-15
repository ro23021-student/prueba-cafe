# ENTREGA — Sandbox Fase 3 (Trazabilidad Café)

## 1. Qué se entrega

| Elemento | Ruta | Notas |
|----------|------|-------|
| Código del sandbox | `/home/antonio/Documentos/sandbox_fase3` | Repositorio git, commiteado y pusheado |
| Documento de diseño | `/home/antonio/Documentos/TrabajoFase2enAdelante/Fase3_Diseno_Metodologico.docx` | Incluye sección de desviaciones del protocolo |
| Resultados (no se suben al repo) | `sandbox/results/` | Ya están en `.gitignore` |

## 2. Contenido del documento `Fase3_Diseno_Metodologico.docx`

Ya está listo en la carpeta `TrabajoFase2enAdelante/`. Incluye:
- Base de datos CouchDB única compartida (`trazabilidad`) con aislamiento lógico por cooperativa (JWT + backend + `validate_doc_update`).
- Límites de memoria configurables: `MEM_LIMIT` (768 MiB API/BD), `CLIENT_MEM_LIMIT` (512 MiB clientes/k6), idénticos entre T y C0.
- **Nueva sección:** "Desviaciones del protocolo y limitaciones de ejecución" (explica las 31 corridas apartadas, las duraciones 60s vs 300s, y el TFS = 0%).

## 3. Cómo preparar el repositorio para entregar

Ejecutar desde `/home/antonio/Documentos/sandbox_fase3`:

```bash
# Ver estado actual
git status --short

# Agregar solo archivos del proyecto (results/ y .env están en .gitignore, NO se suben)
git add backend-rust/src/infrastructure/couchdb.rs backend-rust/src/interface/http.rs \
  sandbox/couchdb/create_users.sh sandbox/couchdb/load_seed.sh sandbox/couchdb/test_rbac.sh \
  sandbox/couchdb/verify_indexes.sh sandbox/docker-compose.yml sandbox/k6/e1_stress.js \
  sandbox/netem/apply_netem.sh sandbox/netem/outage.sh sandbox/orchestrator/analisis_estadistico.py \
  sandbox/run_experiment.sh sandbox/run_load.sh sandbox/run_plan.sh sandbox/smoke_test.sh \
  sandbox/orchestrator/exportar_fase5.py sandbox/orchestrator/redactar_fase5.py \
  sandbox/plan_5reps.csv sandbox/plan_reducido_nuevo.csv sandbox/retomar_plan.sh

# Revisar qué se va a commitear
git status --short

# Commit
git commit -m "Fase 3: diseño CouchDB único, límites de memoria corregidos y reanudación de plan E2"

# Subir a GitHub (opcional si el docente lo revisa ahí)
git push origin main
```

## 4. Reparto para 5 personas (solo código)

| Persona | Encargado de | Archivos |
|---------|-------------|----------|
| 1 | Backend y base de datos | `backend-rust/src/`, `sandbox/couchdb/*.sh` |
| 2 | Orquestación de experimentos | `sandbox/run_plan.sh`, `sandbox/run_experiment.sh`, `sandbox/run_load.sh`, `sandbox/smoke_test.sh`, `sandbox/plan_*.csv`, `sandbox/retomar_plan.sh` |
| 3 | Infraestructura, Docker y red | `sandbox/docker-compose.yml`, `sandbox/k6/e1_stress.js`, `sandbox/netem/*.sh` |
| 4 | Análisis estadístico | `sandbox/orchestrator/analisis_estadistico.py`, `sandbox/orchestrator/exportar_fase5.py`, `sandbox/orchestrator/redactar_fase5.py` |
| 5 | Soporte y pruebas | `sandbox/smoke_test.sh`, `sandbox/couchdb/verify_indexes.sh`, cualquier archivo suelto de `git status --short` |

## 5. Flujo de git (equipo de 5)

1. Cada uno crea su rama: `git checkout -b feat/<nombre>-<tarea>`
2. Nadie comitea directo a `main`.
3. Commits pequeños y descriptivos: `feat: ...`, `fix: ...`, `docs: ...`
4. Antes de unir: `git pull --rebase origin main` y resolver conflictos en la rama propia.
5. Un líder hace los merges a `main` y el `push` final.

## 6. Cómo ejecutar el plan (si el docente quiere reproducir)

Desde `sandbox_fase3`:

```bash
# Verificar que no hay contenedores previos
docker ps

# Ejecutar plan completo (las corridas ya hechas se saltan automáticamente)
PLAN_FILE=plan_5reps.csv ./run_plan.sh --yes

# O ejecutar solo una parte
PLAN_FILE=plan_5reps.csv ./run_plan.sh --devices 100 --loss 30 --yes
```

## 7. Análisis estadístico (opcional, para completar)

```bash
cd ~/Documentos/sandbox_fase3/sandbox
python3 orchestrator/analisis_estadistico.py --devices 10 --run-s 60 --perdidas 0,5,15,30
python3 orchestrator/analisis_estadistico.py --devices 50 --run-s 300 --perdidas 0,5,15,30
python3 orchestrator/analisis_estadistico.py --devices 100 --run-s 300 --perdidas 0,5,15,30
```

---

Copia esto a un archivo `ENTREGA.md` dentro de `sandbox_fase3` o envíalo por separado a tus compañeros. Si necesitas que ajuste alguna parte, dímelo.
