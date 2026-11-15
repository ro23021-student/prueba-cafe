# Sandbox experimental (Fases 3 a 5)

Requisitos: Docker Engine/Desktop con Compose v2 y `curl`. Para las metricas estaticas se usan
opcionalmente `cargo`/`clippy` y `dart`/`flutter`; si no estan instalados, se ejecutan en CI.

## 1. Preparar el entorno

Desde la raiz del proyecto:

```bash
./scripts/generar_env.sh          # crea sandbox/.env con secretos aleatorios
cd sandbox
docker compose config >/dev/null  # valida el YAML
```

No edites ni entregues `sandbox/.env`: contiene secretos. La plantilla versionada es
`sandbox/.env.example`. Si cambias las claves de CouchDB/PostgreSQL y reutilizas volumenes viejos,
borra los volumenes antes de arrancar (`down -v`).

Variables relevantes de hardware y ejecucion:

| Variable | Uso |
|---|---|
| `CPUSET`, `MEM_LIMIT` | mismos limites para T y C0 (reproducibilidad) |
| `LOAD_CPUSET`, `CLIENT_MEM_LIMIT` | clientes y k6; sepáralos del servidor si hay 4+ nucleos |
| `PROM_MEM_LIMIT`, `CADVISOR_MEM_LIMIT` | telemetria |
| `COUCH_TEC_PASS`, `COUCH_PROD_PASS`, `COUCH_AUD_PASS` | usuarios directos de CouchDB para el RBAC |
| `RUN_SECONDS`, `WARMUP_S`, `MEASURE_S`, `DRAIN_S`, `OUTAGE_PLAN` | corrida de client-sim |
| `LOAD_VUS`, `LOAD_DURATION`, `K6_STRICT` | prueba de carga k6 (`K6_STRICT=1` para exigir umbrales) |

## 2. Arrancar, probar y apagar

```bash
docker compose --profile treatment up -d --build   # T: Rust + CouchDB
./smoke_test.sh

docker compose --profile treatment down -v

docker compose --profile control up -d --build     # C0: Flask + PostgreSQL
PROFILE=control ./smoke_test.sh
```

La prueba de humo de T incluye RBAC directo en CouchDB con `tec-c1` (solo C1), `prod-1` (solo lo
propio) y `aud-1` (solo lectura). Los scripts son `couchdb/create_users.sh` y
`couchdb/test_rbac.sh`.

Apagar todos los perfiles y borrar datos:

```bash
docker compose --profile treatment --profile control --profile clients --profile load \
  down -v --remove-orphans
```

## 3. Corridas E2 (client-sim)

El runner levanta el perfil, espera `/health`, crea usuarios/RBAC en T, ejecuta client-sim,
recolecta CPU/RAM y limpia. Aborta si se generan cero documentos.

```bash
# Piloto reducido T (2 min); en hardware de 2 nucleos usa duraciones cortas
RUN_SECONDS=120 WARMUP_S=15 MEASURE_S=90 DRAIN_S=30 OUTAGE_PLAN=40:15 \
  ./run_experiment.sh T 0 3 1 123

# Piloto equivalente C0
RUN_SECONDS=120 WARMUP_S=15 MEASURE_S=90 DRAIN_S=30 OUTAGE_PLAN=40:15 \
  ./run_experiment.sh C0 0 3 1 123
```

El plan factorial completo esta en `plan.csv` (360 corridas, semilla 20261101). Para recorrerlo:

```bash
./run_plan.sh --limit 10 --pilot --yes      # subconjunto piloto
./run_plan.sh --dry-run                     # ver orden sin ejecutar
./run_plan.sh --arch T --loss 15 --devices 10
```

La matriz completa (2 arquitecturas x 4 perdidas x 3 dispositivos x 15 repeticiones) requiere
hardware dedicado. En este equipo (2 nucleos, ~3.6 GB RAM) solo se ejecutan pilotos; no se presenta
como experimento final.

## 4. Carga E1 (k6)

```bash
# Piloto de carga reducido; K6_STRICT=0 evita que un umbral incumplido corte el piloto
K6_STRICT=0 RAMP_UP=5s RAMP_DOWN=5s ./run_load.sh T 20 30s

# Carga formal (exige umbral p95 < 15 ms)
K6_STRICT=1 ./run_load.sh T 500 240s
```

## 5. Metricas

```bash
python3 orchestrator/recursos.py --inicio <epoch> --fin <epoch> --run-id <id>
python3 orchestrator/metricas_proceso.py --inicio <epoch> --fin <epoch> --run-id <id>
python3 orchestrator/metricas_docker.py --archivo results/docker_stats_<id>.jsonl --run-id <id>
python3 orchestrator/metricas_estaticas.py            # clippy -D warnings, tamano, Dart/Flutter, build
python3 orchestrator/metricas_estaticas.py --medir-build
```

`recursos.py` consulta Prometheus/cAdvisor y filtra por proyecto/servicio de Compose, para no
mezclar contenedores de otras pilas. `metricas_proceso.py` lee `/metrics` del proceso Rust.
`metricas_docker.py` resume las muestras de `docker stats` que guardan los runners.

## 6. Servicios y puertos

| Servicio | Que es | Puerto |
|---|---|---|
| `api-rust` (T) | Rust/Axum, Clean Architecture, JWT + RBAC, `/metrics` | 8080, 9100 local |
| `couchdb` (T) | CouchDB 3.3.3, `_security` y `validate_doc_update` | 5984 local |
| `api-baseline` (C0) | Flask + gunicorn + PostgreSQL, mismo contrato REST/JWT/RBAC | 8080 |
| `client-sim` | dispositivos Dart sin interfaz (perfil `clients`) | - |
| `k6` | carga E1 (perfil `load`) | - |
| `prometheus` + `cadvisor` | CPU/RAM por contenedor, metricas internas | 9090 |

## 7. Analisis estadistico (Fase 5)

`analisis_estadistico.py` lee `results/resumen_*.json` (E2) y `results/resumen_k6_*.json` (E1) y genera las tablas:

```bash
python3 -m venv /tmp/venv-analysis
/tmp/venv-analysis/bin/pip install -r orchestrator/requirements_analisis.txt
/tmp/venv-analysis/bin/python orchestrator/analisis_estadistico.py
```

Salidas (se generan al ejecutarlo): `results/datos_fase5.csv`, `results/analisis_fase5.json` y
`results/analisis_fase5.md`.

## 8. Alcance y decisiones documentadas

- **C1 (Rust + PostgreSQL)** no se implementa: no es requisito obligatorio de las Fases 3 y 4. El
  control exigido es C0, el monolito relacional centralizado. Por eso el efecto de Rust no se separa
  del efecto del modelo documental.
- La sincronizacion del cliente es una **cola local cifrada + API Rust**, no replicacion nativa
  PouchDB/CouchDB. La Fase 4 permite esta opcion; el protocolo lo declara explicitamente.
- No se usa WorkManager ni sincronizacion en segundo plano del sistema operativo.
- En este entorno no hay SDK de Flutter; los workflows de `.github/workflows/calidad.yml` y
  `apk.yml` validan `dart analyze`, `flutter analyze` y el APK. El client-sim si se compila y
  ejecuta en Docker.
- Las corridas invalidas de 0 documentos no se conservan como evidencia; los artefactos validos
  estan en `results/`.
- La matriz completa de 360 corridas no se ejecuto: solo se corrio un subconjunto exploratorio de
  20 corridas (5.56 % del plan).
